[CmdletBinding()]
param([switch]$DryRun)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PackageDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $PackageDir 'lib.ps1')

$CodexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME '.codex' }
$SkillDir = Join-Path $CodexHome 'skills/whole-task-control'
$AgentsFile = Join-Path $CodexHome 'AGENTS.md'
$BackupRoot = Join-Path $CodexHome 'backups/whole-task-control'
$LastBackupFile = Join-Path $CodexHome 'whole-task-control-last-backup'
$ManagedMarker = Join-Path $SkillDir $WtcManagedFile

Assert-WtcWindowsPathBudget $CodexHome

if ((Test-Path -LiteralPath $AgentsFile) -and -not (Test-Path -LiteralPath $AgentsFile -PathType Leaf)) {
    throw '卸载停止：AGENTS.md 已存在但不是普通文件。未修改任何文件。'
}

if (-not (Test-WtcMarkers $AgentsFile)) {
    throw '卸载停止：AGENTS.md 中的标记缺失、重复或顺序错误。未修改任何文件。'
}
$ManagedSkill = Test-Path -LiteralPath $ManagedMarker -PathType Leaf

if ($DryRun) {
    Write-Host '预览：将移除 AGENTS.md 中的 Whole Task Control 规则块。'
    if ($ManagedSkill) { Write-Host "将移除受管理技能：$SkillDir" }
    if ((Test-Path -LiteralPath $SkillDir) -and -not $ManagedSkill) { Write-Host '同名技能不受本安装器管理，将保留。' }
    Write-Host '预览完成：没有修改任何文件。'
    exit 0
}

New-Item -ItemType Directory -Force -Path $CodexHome, $BackupRoot | Out-Null
$StageDir = Join-Path $CodexHome ('.whole-task-control-uninstall.' + [Guid]::NewGuid().ToString('N'))
$StageAgents = Join-Path $StageDir 'AGENTS.md'
$BackupDir = New-WtcBackupDir $BackupRoot 'uninstall'
$CommitStarted = $false
$Committed = $false

try {
    New-Item -ItemType Directory -Force -Path $StageDir | Out-Null
    $stripped = Get-WtcStrippedText $AgentsFile
    $KeepAgents = $stripped.Length -gt 0
    if ($KeepAgents) { Write-WtcText $StageAgents $stripped }

    Save-WtcSnapshot $BackupDir 'uninstall' $AgentsFile $SkillDir
    Save-WtcSnapshotPointer $BackupDir $LastBackupFile
    $CommitStarted = $true

    if ($ManagedSkill -and (Test-Path -LiteralPath $SkillDir)) { Remove-Item -LiteralPath $SkillDir -Recurse -Force }
    if ($KeepAgents) {
        if (Test-Path -LiteralPath $AgentsFile) { Remove-Item -LiteralPath $AgentsFile -Force }
        Move-Item -LiteralPath $StageAgents -Destination $AgentsFile
    } elseif (Test-Path -LiteralPath $AgentsFile) {
        Remove-Item -LiteralPath $AgentsFile -Force
    }
    Set-WtcLastBackup $CodexHome $BackupDir
    $Committed = $true
} catch {
    if ($CommitStarted -and -not $Committed -and (Test-Path -LiteralPath $BackupDir -PathType Container)) {
        Restore-WtcSnapshot $BackupDir $AgentsFile $SkillDir
        Restore-WtcPointer $BackupDir $LastBackupFile
    }
    throw
} finally {
    if (Test-Path -LiteralPath $StageDir) { Remove-Item -LiteralPath $StageDir -Recurse -Force }
}

Write-Host "卸载完成。卸载前状态备份：$BackupDir"
Write-Host '如需恢复，运行：./restore.ps1'
