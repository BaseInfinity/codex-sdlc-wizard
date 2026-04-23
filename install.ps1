$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

function Copy-IfMissing {
    param(
        [string]$Source,
        [string]$Destination,
        [string]$Label
    )

    if (-not (Test-Path -LiteralPath $Destination)) {
        Copy-Item -LiteralPath $Source -Destination $Destination
        Write-Host "Created $Label"
    } else {
        Write-Host "$Label already exists - skipping (review manually)"
    }
}

function Install-Skills {
    param(
        [string]$SourceRoot
    )

    $codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME ".codex" }
    $skillsRoot = Join-Path $codexHome "skills"
    $skillsBackupRoot = Join-Path $codexHome "backups\skills"
    $sourceSkillsRoot = Join-Path $SourceRoot "skills"
    New-Item -ItemType Directory -Path $skillsRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $skillsBackupRoot -Force | Out-Null

    Get-ChildItem -LiteralPath $sourceSkillsRoot -Directory | ForEach-Object {
        $skillName = $_.Name
        $installedSkillPath = Join-Path $skillsRoot $skillName

        if (Test-Path -LiteralPath $installedSkillPath) {
            $timestamp = Get-Date -Format "yyyyMMddHHmmss"
            $backupPath = Join-Path $skillsBackupRoot "$skillName.bak.$timestamp"
            Copy-Item -LiteralPath $installedSkillPath -Destination $backupPath -Recurse
            Remove-Item -LiteralPath $installedSkillPath -Recurse -Force
            Write-Host "Backed up existing Codex skill: $skillName"
        }

        Copy-Item -LiteralPath $_.FullName -Destination $skillsRoot -Recurse
        Write-Host "Installed Codex skill: $skillName"
    }
}

Write-Host "Installing SDLC Wizard for Codex CLI..."

Copy-IfMissing -Source (Join-Path $scriptDir "AGENTS.md") -Destination "AGENTS.md" -Label "AGENTS.md"
Copy-IfMissing -Source (Join-Path $scriptDir "SDLC-LOOP.md") -Destination "SDLC-LOOP.md" -Label "SDLC-LOOP.md"
Copy-IfMissing -Source (Join-Path $scriptDir "START-SDLC.md") -Destination "START-SDLC.md" -Label "START-SDLC.md"
Copy-IfMissing -Source (Join-Path $scriptDir "PROVE-IT.md") -Destination "PROVE-IT.md" -Label "PROVE-IT.md"
Copy-IfMissing -Source (Join-Path $scriptDir "start-sdlc.ps1") -Destination "start-sdlc.ps1" -Label "start-sdlc.ps1"
Install-Skills -SourceRoot $scriptDir

New-Item -ItemType Directory -Path ".codex" -Force | Out-Null
New-Item -ItemType Directory -Path ".codex\hooks" -Force | Out-Null

$configPath = ".codex\config.toml"
if (Test-Path -LiteralPath $configPath) {
    $config = Get-Content -LiteralPath $configPath -Raw
    $activeLines = ($config -split "`r?`n") | Where-Object { $_ -notmatch '^\s*#' }

    if ($activeLines -match 'codex_hooks\s*=\s*false') {
        $updated = [regex]::Replace($config, '(^[^#\r\n]*codex_hooks\s*=\s*)false', '$1true', [System.Text.RegularExpressions.RegexOptions]::Multiline)
        Set-Content -LiteralPath $configPath -Value $updated -NoNewline
        Write-Host "Set codex_hooks = true in existing config.toml"
    } elseif ($activeLines -match 'codex_hooks\s*=\s*true') {
        Write-Host "config.toml already has codex_hooks = true - skipping"
    } elseif ($config -match '^\[features\]') {
        $updated = [regex]::Replace($config, '^\[features\]\r?\n', "[features]`r`ncodex_hooks = true`r`n", [System.Text.RegularExpressions.RegexOptions]::Multiline)
        Set-Content -LiteralPath $configPath -Value $updated -NoNewline
        Write-Host "Added codex_hooks = true to existing [features] table"
    } else {
        $suffix = if ($config.EndsWith("`n")) { "" } else { "`r`n" }
        Set-Content -LiteralPath $configPath -Value ($config + $suffix + "[features]`r`ncodex_hooks = true`r`n") -NoNewline
        Write-Host "Added [features] codex_hooks = true to config.toml"
    }
} else {
    Copy-Item -LiteralPath (Join-Path $scriptDir ".codex\config.toml") -Destination $configPath
    Write-Host "Created .codex/config.toml"
}

$hooksPath = ".codex\hooks.json"
if (Test-Path -LiteralPath $hooksPath) {
    $timestamp = Get-Date -Format "yyyyMMddHHmmss"
    Copy-Item -LiteralPath $hooksPath -Destination ".codex\hooks.json.bak.$timestamp"
    Write-Host "Backed up existing hooks.json"
}

Copy-Item -LiteralPath (Join-Path $scriptDir ".codex\windows-hooks.json") -Destination $hooksPath
Copy-Item -LiteralPath (Join-Path $scriptDir ".codex\hooks\git-guard.ps1") -Destination ".codex\hooks\git-guard.ps1"
Copy-Item -LiteralPath (Join-Path $scriptDir ".codex\hooks\session-start.ps1") -Destination ".codex\hooks\session-start.ps1"

Write-Host "Installed .codex/hooks.json (Windows PowerShell hooks)"
Write-Host "Installed PowerShell hook scripts"
Write-Host ""
Write-Host "SDLC Wizard for Codex installed."
Write-Host "Recommended: use full access during setup, environment repair, and auth-heavy workflows."
Write-Host "Codex does not have a native /sdlc command. Use the installed skills plus START-SDLC.md and SDLC-LOOP.md as the honest equivalent."
Write-Host "Restart Codex to pick up the new skills, then use /skills and invoke `$codex-sdlc, `$setup-wizard, `$update-wizard, or `$feedback."
Write-Host "Run 'codex' to start a session with SDLC enforcement."
