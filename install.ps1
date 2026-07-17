[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$Replace
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PackageDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $PackageDir 'lib.ps1')

$SourceDir = Join-Path $PackageDir 'whole-task-control'
$RuleTemplate = Join-Path $PackageDir 'global-rule.txt'
$VersionFile = Join-Path $PackageDir 'VERSION'
$CodexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME '.codex' }
$SkillDir = Join-Path $CodexHome 'skills/whole-task-control'
$AgentsFile = Join-Path $CodexHome 'AGENTS.md'
$BackupRoot = Join-Path $CodexHome 'backups/whole-task-control'
$LastBackupFile = Join-Path $CodexHome 'whole-task-control-last-backup'
$FirstBackupFile = Join-Path $CodexHome 'AGENTS.md.before-whole-task-control'

Assert-WtcWindowsPathBudget $CodexHome

foreach ($required in @(
    (Join-Path $SourceDir 'SKILL.md'),
    (Join-Path $SourceDir 'agents/openai.yaml'),
    $RuleTemplate,
    $VersionFile
)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "安装包不完整：缺少 $required"
    }
}

if ((Test-Path -LiteralPath $AgentsFile) -and -not (Test-Path -LiteralPath $AgentsFile -PathType Leaf)) {
    throw '安装停止：AGENTS.md 已存在但不是普通文件。未修改任何文件。'
}

if (-not (Test-WtcMarkers $AgentsFile)) {
    throw '安装停止：AGENTS.md 中的 Whole Task Control 标记缺失、重复或顺序错误。未修改任何文件。'
}

$ManagedMarker = Join-Path $SkillDir $WtcManagedFile
if ((Test-Path -LiteralPath $SkillDir) -and -not (Test-Path -LiteralPath $ManagedMarker -PathType Leaf) -and -not $Replace) {
    throw '安装停止：发现未受本安装器管理的同名技能。确认替换时请使用 -Replace。未修改任何文件。'
}

if ($DryRun) {
    $version = ([System.IO.File]::ReadAllText($VersionFile)).Trim()
    Write-Host "预览：将安装 Whole Task Control $version"
    Write-Host "技能目录：$SkillDir"
    Write-Host "全局规则：$AgentsFile"
    if (Test-Path -LiteralPath $SkillDir) { Write-Host '现有技能将备份后更新。' } else { Write-Host '将创建新技能。' }
    Write-Host '预览完成：没有修改任何文件。'
    exit 0
}

New-Item -ItemType Directory -Force -Path $CodexHome, (Join-Path $CodexHome 'skills'), $BackupRoot | Out-Null
$StageDir = Join-Path $CodexHome ('.whole-task-control-stage.' + [Guid]::NewGuid().ToString('N'))
$StageSkill = Join-Path $StageDir 'skill'
$StageAgents = Join-Path $StageDir 'AGENTS.md'
$StageFirstBackup = Join-Path $StageDir 'AGENTS.md.before-whole-task-control'
$BackupDir = New-WtcBackupDir $BackupRoot 'install'
$CommitStarted = $false
$Committed = $false
$FirstBackupCreated = $false

try {
    New-Item -ItemType Directory -Force -Path $StageDir | Out-Null
    Copy-Item -LiteralPath $SourceDir -Destination $StageSkill -Recurse
    Copy-Item -LiteralPath $VersionFile -Destination (Join-Path $StageSkill $WtcManagedFile)

    $agentsText = (Get-WtcStrippedText $AgentsFile) + (Get-WtcRenderedRule $RuleTemplate (Join-Path $SkillDir 'SKILL.md'))
    Write-WtcText $StageAgents $agentsText
    if (-not (Test-WtcMarkers $StageAgents)) { throw '生成的 AGENTS.md 标记校验失败。' }
    if ((Get-Item -LiteralPath (Join-Path $StageSkill 'SKILL.md')).Length -eq 0) { throw '生成的技能文件为空。' }

    if ((Test-Path -LiteralPath $AgentsFile -PathType Leaf) -and -not (Test-Path -LiteralPath $FirstBackupFile)) {
        Copy-Item -LiteralPath $AgentsFile -Destination $StageFirstBackup
    }

    Save-WtcSnapshot $BackupDir 'install' $AgentsFile $SkillDir
    Save-WtcSnapshotPointer $BackupDir $LastBackupFile
    $CommitStarted = $true

    if (Test-Path -LiteralPath $SkillDir) { Remove-Item -LiteralPath $SkillDir -Recurse -Force }
    Move-Item -LiteralPath $StageSkill -Destination $SkillDir
    if (Test-Path -LiteralPath $AgentsFile) { Remove-Item -LiteralPath $AgentsFile -Force }
    Move-Item -LiteralPath $StageAgents -Destination $AgentsFile
    if (Test-Path -LiteralPath $StageFirstBackup -PathType Leaf) {
        Move-Item -LiteralPath $StageFirstBackup -Destination $FirstBackupFile
        $FirstBackupCreated = $true
    }
    Set-WtcLastBackup $CodexHome $BackupDir
    $Committed = $true
} catch {
    if ($CommitStarted -and -not $Committed -and (Test-Path -LiteralPath $BackupDir -PathType Container)) {
        Restore-WtcSnapshot $BackupDir $AgentsFile $SkillDir
        Restore-WtcPointer $BackupDir $LastBackupFile
        if ($FirstBackupCreated -and (Test-Path -LiteralPath $FirstBackupFile)) {
            Remove-Item -LiteralPath $FirstBackupFile -Force
        }
    }
    throw
} finally {
    if (Test-Path -LiteralPath $StageDir) { Remove-Item -LiteralPath $StageDir -Recurse -Force }
}

if (-not (Test-WtcMarkers $AgentsFile)) { throw '安装后标记校验失败。' }
Write-Host "安装完成：$SkillDir"
Write-Host "原状态备份：$BackupDir"
Write-Host 'Claude Code 未被读取或修改。新建 Codex 任务或重启 Codex 后生效。'
