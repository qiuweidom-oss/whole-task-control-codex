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

Assert-WtcWindowsPathBudget $CodexHome

if (-not (Test-Path -LiteralPath $LastBackupFile -PathType Leaf)) { throw '恢复停止：没有找到最近备份指针。' }
$BackupDir = ([System.IO.File]::ReadAllText($LastBackupFile)).Trim()
$backupFull = [System.IO.Path]::GetFullPath($BackupDir)
$rootFull = [System.IO.Path]::GetFullPath($BackupRoot).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
$requiredPrefix = $rootFull + [System.IO.Path]::DirectorySeparatorChar
if (-not $backupFull.StartsWith($requiredPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw '恢复停止：备份路径不属于 Whole Task Control 备份目录。'
}
foreach ($required in @('agents-existed', 'skill-existed', 'operation')) {
    if (-not (Test-Path -LiteralPath (Join-Path $BackupDir $required) -PathType Leaf)) { throw "恢复停止：备份不完整，缺少 $required。" }
}
$AgentsExisted = ([System.IO.File]::ReadAllText((Join-Path $BackupDir 'agents-existed'))).Trim()
$SkillExisted = ([System.IO.File]::ReadAllText((Join-Path $BackupDir 'skill-existed'))).Trim()
if ($AgentsExisted -eq '1' -and -not (Test-Path -LiteralPath (Join-Path $BackupDir 'AGENTS.md') -PathType Leaf)) { throw '恢复停止：备份缺少 AGENTS.md。' }
if ($SkillExisted -eq '1' -and -not (Test-Path -LiteralPath (Join-Path $BackupDir 'whole-task-control-original') -PathType Container)) { throw '恢复停止：备份缺少原技能。' }

if ($DryRun) {
    Write-Host "预览：将恢复备份 $BackupDir"
    Write-Host '当前状态会先创建一份新的安全备份。'
    Write-Host '预览完成：没有修改任何文件。'
    exit 0
}

New-Item -ItemType Directory -Force -Path $CodexHome, $BackupRoot | Out-Null
$StageDir = Join-Path $CodexHome ('.whole-task-control-restore.' + [Guid]::NewGuid().ToString('N'))
$SafetyBackup = New-WtcBackupDir $BackupRoot 'before-restore'
$CommitStarted = $false
$Committed = $false

try {
    New-Item -ItemType Directory -Force -Path $StageDir | Out-Null
    if ($AgentsExisted -eq '1') { Copy-Item -LiteralPath (Join-Path $BackupDir 'AGENTS.md') -Destination (Join-Path $StageDir 'AGENTS.md') }
    if ($SkillExisted -eq '1') { Copy-Item -LiteralPath (Join-Path $BackupDir 'whole-task-control-original') -Destination (Join-Path $StageDir 'skill') -Recurse }

    Save-WtcSnapshot $SafetyBackup 'before-restore' $AgentsFile $SkillDir
    Save-WtcSnapshotPointer $SafetyBackup $LastBackupFile
    $CommitStarted = $true

    if (Test-Path -LiteralPath $SkillDir) { Remove-Item -LiteralPath $SkillDir -Recurse -Force }
    if ($SkillExisted -eq '1') {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $SkillDir) | Out-Null
        Move-Item -LiteralPath (Join-Path $StageDir 'skill') -Destination $SkillDir
    }
    if ($AgentsExisted -eq '1') {
        if (Test-Path -LiteralPath $AgentsFile) { Remove-Item -LiteralPath $AgentsFile -Force }
        Move-Item -LiteralPath (Join-Path $StageDir 'AGENTS.md') -Destination $AgentsFile
    } elseif (Test-Path -LiteralPath $AgentsFile) {
        Remove-Item -LiteralPath $AgentsFile -Force
    }
    Set-WtcLastBackup $CodexHome $SafetyBackup
    $Committed = $true
} catch {
    if ($CommitStarted -and -not $Committed -and (Test-Path -LiteralPath $SafetyBackup -PathType Container)) {
        Restore-WtcSnapshot $SafetyBackup $AgentsFile $SkillDir
        Restore-WtcPointer $SafetyBackup $LastBackupFile
    }
    throw
} finally {
    if (Test-Path -LiteralPath $StageDir) { Remove-Item -LiteralPath $StageDir -Recurse -Force }
}

Write-Host "恢复完成：$BackupDir"
Write-Host "恢复前状态另存为：$SafetyBackup"
