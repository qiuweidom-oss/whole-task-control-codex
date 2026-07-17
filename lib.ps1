$WtcBeginMarker = '<!-- WHOLE-TASK-CONTROL BEGIN (Codex root only) -->'
$WtcEndMarker = '<!-- WHOLE-TASK-CONTROL END -->'
$WtcManagedFile = '.managed-by-whole-task-control'
$WtcUtf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Assert-WtcWindowsPathBudget {
    param([string]$CodexHome)
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { return }

    $backupRoot = Join-Path $CodexHome 'backups/whole-task-control'
    $sampleBackup = Join-Path $backupRoot '20991231-235959-2147483647-before-restore-12345678'
    $probes = @(
        (Join-Path $sampleBackup 'whole-task-control-original/agents/openai.yaml'),
        (Join-Path $CodexHome '.whole-task-control-stage.12345678901234567890123456789012/skill/agents/openai.yaml'),
        (Join-Path $CodexHome 'skills/whole-task-control/agents/openai.yaml')
    )

    $skillDir = Join-Path $CodexHome 'skills/whole-task-control'
    if (Test-Path -LiteralPath $skillDir -PathType Container) {
        foreach ($item in Get-ChildItem -LiteralPath $skillDir -Recurse -Force) {
            $relative = $item.FullName.Substring($skillDir.Length).TrimStart('\', '/')
            $probes += Join-Path (Join-Path $sampleBackup 'whole-task-control-original') $relative
        }
    }

    foreach ($probe in $probes) {
        $fullPath = [System.IO.Path]::GetFullPath($probe)
        if ($fullPath.Length -ge 240) {
            throw "Windows 路径过深，无法安全创建暂存或备份文件。请使用较短的 CODEX_HOME；当前预检路径长度为 $($fullPath.Length)。"
        }
    }
}

function Write-WtcText {
    param([string]$Path, [string]$Text)
    [System.IO.File]::WriteAllText($Path, $Text, $WtcUtf8NoBom)
}

function Test-WtcMarkers {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $true }

    $beginCount = 0
    $endCount = 0
    $state = 0
    $bad = $false
    foreach ($line in [System.IO.File]::ReadAllLines($Path)) {
        if ($line -eq $WtcBeginMarker) {
            $beginCount++
            if ($state -ne 0 -or $beginCount -gt 1) { $bad = $true }
            $state = 1
            continue
        }
        if ($line -eq $WtcEndMarker) {
            $endCount++
            if ($state -ne 1 -or $endCount -gt 1) { $bad = $true }
            $state = 2
        }
    }
    return (-not $bad -and $beginCount -eq $endCount -and $beginCount -le 1 -and ($beginCount -eq 0 -or $state -eq 2))
}

function Get-WtcStrippedText {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return '' }

    $output = New-Object 'System.Collections.Generic.List[string]'
    $skipping = $false
    foreach ($line in [System.IO.File]::ReadAllLines($Path)) {
        if ($line -eq $WtcBeginMarker) { $skipping = $true; continue }
        if ($line -eq $WtcEndMarker) { $skipping = $false; continue }
        if (-not $skipping) { $output.Add($line) }
    }
    if ($output.Count -eq 0) { return '' }
    return (($output -join [Environment]::NewLine) + [Environment]::NewLine)
}

function Get-WtcRenderedRule {
    param([string]$TemplatePath, [string]$SkillPath)
    $output = New-Object 'System.Collections.Generic.List[string]'
    foreach ($line in [System.IO.File]::ReadAllLines($TemplatePath)) {
        if ($line -eq '__WHOLE_TASK_CONTROL_SKILL_PATH_LINE__') {
            $output.Add('- 触发后完整读取：`' + $SkillPath + '`。')
        } else {
            $output.Add($line)
        }
    }
    return (($output -join [Environment]::NewLine) + [Environment]::NewLine)
}

function New-WtcBackupDir {
    param([string]$BackupRoot, [string]$Operation)
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    return (Join-Path $BackupRoot ($stamp + '-' + $PID + '-' + $Operation + '-' + [Guid]::NewGuid().ToString('N').Substring(0, 8)))
}

function Save-WtcSnapshot {
    param(
        [string]$BackupDir,
        [string]$Operation,
        [string]$AgentsFile,
        [string]$SkillDir
    )
    New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
    Write-WtcText (Join-Path $BackupDir 'operation') ($Operation + [Environment]::NewLine)
    if (Test-Path -LiteralPath $AgentsFile -PathType Leaf) {
        Copy-Item -LiteralPath $AgentsFile -Destination (Join-Path $BackupDir 'AGENTS.md')
        Write-WtcText (Join-Path $BackupDir 'agents-existed') ('1' + [Environment]::NewLine)
    } else {
        Write-WtcText (Join-Path $BackupDir 'agents-existed') ('0' + [Environment]::NewLine)
    }
    if (Test-Path -LiteralPath $SkillDir -PathType Container) {
        Copy-Item -LiteralPath $SkillDir -Destination (Join-Path $BackupDir 'whole-task-control-original') -Recurse
        Write-WtcText (Join-Path $BackupDir 'skill-existed') ('1' + [Environment]::NewLine)
    } else {
        Write-WtcText (Join-Path $BackupDir 'skill-existed') ('0' + [Environment]::NewLine)
    }
}

function Save-WtcSnapshotPointer {
    param([string]$BackupDir, [string]$PointerFile)
    if (Test-Path -LiteralPath $PointerFile -PathType Leaf) {
        Copy-Item -LiteralPath $PointerFile -Destination (Join-Path $BackupDir 'last-backup-pointer')
        Write-WtcText (Join-Path $BackupDir 'pointer-existed') ('1' + [Environment]::NewLine)
    } else {
        Write-WtcText (Join-Path $BackupDir 'pointer-existed') ('0' + [Environment]::NewLine)
    }
}

function Restore-WtcSnapshot {
    param([string]$BackupDir, [string]$AgentsFile, [string]$SkillDir)
    $agentsExisted = ([System.IO.File]::ReadAllText((Join-Path $BackupDir 'agents-existed'))).Trim()
    $skillExisted = ([System.IO.File]::ReadAllText((Join-Path $BackupDir 'skill-existed'))).Trim()

    if (Test-Path -LiteralPath $SkillDir) { Remove-Item -LiteralPath $SkillDir -Recurse -Force }
    if ($skillExisted -eq '1') {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $SkillDir) | Out-Null
        Copy-Item -LiteralPath (Join-Path $BackupDir 'whole-task-control-original') -Destination $SkillDir -Recurse
    }
    if ($agentsExisted -eq '1') {
        Copy-Item -LiteralPath (Join-Path $BackupDir 'AGENTS.md') -Destination $AgentsFile -Force
    } elseif (Test-Path -LiteralPath $AgentsFile) {
        Remove-Item -LiteralPath $AgentsFile -Force
    }
}

function Restore-WtcPointer {
    param([string]$BackupDir, [string]$PointerFile)
    $stateFile = Join-Path $BackupDir 'pointer-existed'
    if (-not (Test-Path -LiteralPath $stateFile -PathType Leaf)) { return }
    $pointerExisted = ([System.IO.File]::ReadAllText($stateFile)).Trim()
    if ($pointerExisted -eq '1') {
        Copy-Item -LiteralPath (Join-Path $BackupDir 'last-backup-pointer') -Destination $PointerFile -Force
    } elseif (Test-Path -LiteralPath $PointerFile) {
        Remove-Item -LiteralPath $PointerFile -Force
    }
}

function Set-WtcLastBackup {
    param([string]$CodexHome, [string]$BackupDir)
    $pointerFile = Join-Path $CodexHome 'whole-task-control-last-backup'
    $temporary = Join-Path $CodexHome ('.whole-task-control-last-backup.' + [Guid]::NewGuid().ToString('N'))
    Write-WtcText $temporary ($BackupDir + [Environment]::NewLine)
    if (Test-Path -LiteralPath $pointerFile) { Remove-Item -LiteralPath $pointerFile -Force }
    Move-Item -LiteralPath $temporary -Destination $pointerFile
}
