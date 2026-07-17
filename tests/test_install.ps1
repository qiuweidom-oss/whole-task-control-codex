[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PackageDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Install = Join-Path $PackageDir 'install.ps1'
$Uninstall = Join-Path $PackageDir 'uninstall.ps1'
$Restore = Join-Path $PackageDir 'restore.ps1'
$BeginMarker = '<!-- WHOLE-TASK-CONTROL BEGIN (Codex root only) -->'
$EndMarker = '<!-- WHOLE-TASK-CONTROL END -->'
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Fail-Test {
    param([string]$Message)
    throw "FAIL: $Message"
}

function Write-TestText {
    param([string]$Path, [string]$Text)
    $parent = Split-Path -Parent $Path
    if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    [System.IO.File]::WriteAllText($Path, $Text, $Utf8NoBom)
}

function Assert-File {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { Fail-Test "missing file: $Path" }
}

function Assert-Contains {
    param([string]$Path, [string]$Expected)
    if (-not ([System.IO.File]::ReadAllText($Path).Contains($Expected))) { Fail-Test "$Path does not contain: $Expected" }
}

function Assert-NotContains {
    param([string]$Path, [string]$Unexpected)
    if ([System.IO.File]::ReadAllText($Path).Contains($Unexpected)) { Fail-Test "$Path unexpectedly contains: $Unexpected" }
}

function Assert-Equal {
    param($Actual, $Expected, [string]$Message)
    if ($Actual -ne $Expected) { Fail-Test "$Message; expected=$Expected actual=$Actual" }
}

function Invoke-Quiet {
    param([scriptblock]$Action)
    & $Action *> $null
}

function Expect-Failure {
    param([scriptblock]$Action, [string]$Message)
    $failed = $false
    try { & $Action *> $null } catch { $failed = $true }
    if (-not $failed) { Fail-Test $Message }
}

function New-TestCodexHome {
    param([string]$Root, [string]$Name)
    $path = Join-Path $Root $Name
    New-Item -ItemType Directory -Force -Path $path | Out-Null
    return $path
}

function Assert-Utf8Bom {
    param([string]$Path)
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -lt 3 -or $bytes[0] -ne 0xEF -or $bytes[1] -ne 0xBB -or $bytes[2] -ne 0xBF) {
        Fail-Test "$Path is not UTF-8 BOM encoded"
    }
}

$TestRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('wtc211-' + [Guid]::NewGuid().ToString('N').Substring(0, 12))
$OriginalCodexHome = $env:CODEX_HOME
New-Item -ItemType Directory -Force -Path $TestRoot | Out-Null

try {
    foreach ($file in @('install.ps1', 'uninstall.ps1', 'restore.ps1', 'lib.ps1')) {
        Assert-Utf8Bom (Join-Path $PackageDir $file)
    }

    $clean = New-TestCodexHome $TestRoot 'clean codex'
    $env:CODEX_HOME = $clean
    Invoke-Quiet { & $Install }
    $cleanAgents = Join-Path $clean 'AGENTS.md'
    $cleanSkill = Join-Path $clean 'skills/whole-task-control/SKILL.md'
    Assert-File $cleanSkill
    Assert-Contains $cleanAgents $BeginMarker
    Assert-Contains $cleanAgents '自包含、低风险、单步'
    $firstHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $cleanAgents).Hash
    Invoke-Quiet { & $Install }
    Assert-Equal (Get-FileHash -Algorithm SHA256 -LiteralPath $cleanAgents).Hash $firstHash 'repeat install changed AGENTS.md'

    $coexist = New-TestCodexHome $TestRoot 'coexist'
    Write-TestText (Join-Path $coexist 'AGENTS.md') ("EXISTING-RULE" + [Environment]::NewLine)
    $env:CODEX_HOME = $coexist
    Invoke-Quiet { & $Install }
    Assert-Contains (Join-Path $coexist 'AGENTS.md') 'EXISTING-RULE'

    $reversed = New-TestCodexHome $TestRoot 'reversed'
    $reversedAgents = Join-Path $reversed 'AGENTS.md'
    Write-TestText $reversedAgents ("KEEP`n$EndMarker`nMIDDLE`n$BeginMarker`nAFTER`n")
    $reversedHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $reversedAgents).Hash
    $env:CODEX_HOME = $reversed
    Expect-Failure { & $Install } 'reversed markers unexpectedly installed'
    Assert-Equal (Get-FileHash -Algorithm SHA256 -LiteralPath $reversedAgents).Hash $reversedHash 'reversed markers mutated AGENTS.md'
    if (Test-Path -LiteralPath (Join-Path $reversed 'skills/whole-task-control')) { Fail-Test 'reversed marker failure half-installed skill' }

    $custom = New-TestCodexHome $TestRoot 'custom'
    $customSkill = Join-Path $custom 'skills/whole-task-control/SKILL.md'
    Write-TestText $customSkill ("CUSTOM-SKILL" + [Environment]::NewLine)
    Write-TestText (Join-Path $custom 'AGENTS.md') ("CUSTOM-AGENTS" + [Environment]::NewLine)
    $env:CODEX_HOME = $custom
    Expect-Failure { & $Install } 'custom skill was overwritten without -Replace'
    Assert-Contains $customSkill 'CUSTOM-SKILL'
    Invoke-Quiet { & $Install -Replace }
    $backupDir = ([System.IO.File]::ReadAllText((Join-Path $custom 'whole-task-control-last-backup'))).Trim()
    Assert-Contains (Join-Path $backupDir 'whole-task-control-original/SKILL.md') 'CUSTOM-SKILL'

    $dry = New-TestCodexHome $TestRoot 'dry'
    $dryAgents = Join-Path $dry 'AGENTS.md'
    Write-TestText $dryAgents ("DRY-KEEP" + [Environment]::NewLine)
    $dryHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $dryAgents).Hash
    $env:CODEX_HOME = $dry
    Invoke-Quiet { & $Install -DryRun }
    Assert-Equal (Get-FileHash -Algorithm SHA256 -LiteralPath $dryAgents).Hash $dryHash 'dry run mutated AGENTS.md'
    if (Test-Path -LiteralPath (Join-Path $dry 'skills/whole-task-control')) { Fail-Test 'dry run installed skill' }

    $uninstallHome = New-TestCodexHome $TestRoot 'uninstall'
    $uninstallAgents = Join-Path $uninstallHome 'AGENTS.md'
    Write-TestText $uninstallAgents ("ORIGINAL-RULE" + [Environment]::NewLine)
    $env:CODEX_HOME = $uninstallHome
    Invoke-Quiet { & $Install }
    [System.IO.File]::AppendAllText($uninstallAgents, "LATER-RULE" + [Environment]::NewLine, $Utf8NoBom)
    Invoke-Quiet { & $Uninstall }
    Assert-Contains $uninstallAgents 'ORIGINAL-RULE'
    Assert-Contains $uninstallAgents 'LATER-RULE'
    Assert-NotContains $uninstallAgents $BeginMarker
    if (Test-Path -LiteralPath (Join-Path $uninstallHome 'skills/whole-task-control')) { Fail-Test 'uninstall left managed skill' }

    $restoreHome = New-TestCodexHome $TestRoot 'restore'
    $restoreAgents = Join-Path $restoreHome 'AGENTS.md'
    $restoreSkill = Join-Path $restoreHome 'skills/whole-task-control/SKILL.md'
    Write-TestText $restoreAgents ("RESTORE-ORIGINAL-AGENTS" + [Environment]::NewLine)
    Write-TestText $restoreSkill ("RESTORE-ORIGINAL-SKILL" + [Environment]::NewLine)
    $env:CODEX_HOME = $restoreHome
    Invoke-Quiet { & $Install -Replace }
    [System.IO.File]::AppendAllText($restoreAgents, "POST-INSTALL-CHANGE" + [Environment]::NewLine, $Utf8NoBom)
    Invoke-Quiet { & $Restore }
    Assert-Contains $restoreAgents 'RESTORE-ORIGINAL-AGENTS'
    Assert-NotContains $restoreAgents 'POST-INSTALL-CHANGE'
    Assert-Contains $restoreSkill 'RESTORE-ORIGINAL-SKILL'

    if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
        $env:CODEX_HOME = Join-Path $TestRoot ('deep-' + ('x' * 180))
        Expect-Failure { & $Install -DryRun } 'deep Windows CODEX_HOME passed path preflight'
        if (Test-Path -LiteralPath $env:CODEX_HOME) { Fail-Test 'deep path preflight modified filesystem' }
    }

    Write-Output 'ALL_V211_POWERSHELL_TESTS_PASSED'
} finally {
    $env:CODEX_HOME = $OriginalCodexHome
    if (Test-Path -LiteralPath $TestRoot) { Remove-Item -LiteralPath $TestRoot -Recurse -Force }
}
