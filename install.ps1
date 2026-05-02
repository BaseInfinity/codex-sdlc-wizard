param(
    [ValidateSet("mixed", "maximum")]
    [string]$ModelProfile = "mixed"
)

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

    $legacySkillPath = Join-Path $skillsRoot "codex-sdlc"
    if (Test-Path -LiteralPath $legacySkillPath) {
        $timestamp = Get-Date -Format "yyyyMMddHHmmss"
        $backupPath = Join-Path $skillsBackupRoot "codex-sdlc.bak.$timestamp"
        Copy-Item -LiteralPath $legacySkillPath -Destination $backupPath -Recurse
        Remove-Item -LiteralPath $legacySkillPath -Recurse -Force
        Write-Host "Removed legacy Codex skill: codex-sdlc (canonical: sdlc)"
    }
}

function Merge-CodexModelConfig {
    param(
        [string]$ConfigPath,
        [ValidateSet("mixed", "maximum")]
        [string]$Profile
    )

    $profileConfig = switch ($Profile) {
        "mixed" {
            @{
                model = "gpt-5.4-mini"
                effort = "xhigh"
                review = "gpt-5.5"
            }
        }
        "maximum" {
            @{
                model = "gpt-5.5"
                effort = "xhigh"
                review = $null
            }
        }
    }

    $configDir = Split-Path -Parent $ConfigPath
    New-Item -ItemType Directory -Path $configDir -Force | Out-Null

    $content = if (Test-Path -LiteralPath $ConfigPath) {
        Get-Content -LiteralPath $ConfigPath -Raw
    } else {
        ""
    }

    $lines = @()
    if ($content.Length -gt 0) {
        $normalized = ($content -replace "`r`n", "`n") -replace "`r", "`n"
        $lines = @($normalized -split "`n")
        if ($lines.Count -gt 0 -and $lines[$lines.Count - 1] -eq "") {
            if ($lines.Count -eq 1) {
                $lines = @()
            } else {
                $lines = @($lines[0..($lines.Count - 2)])
            }
        }
    }

    $stripped = New-Object System.Collections.Generic.List[string]
    $tableName = $null
    foreach ($line in $lines) {
        if ($line -match '^\s*\[([^\]]+)\]\s*(#.*)?$') {
            $tableName = $Matches[1].Trim()
            $stripped.Add($line)
            continue
        }

        if ($null -eq $tableName -and $line -match '^\s*(model|model_reasoning_effort|review_model)\s*=') {
            continue
        }

        $stripped.Add($line)
    }

    $profileLines = New-Object System.Collections.Generic.List[string]
    $profileLines.Add("model = `"$($profileConfig.model)`"")
    $profileLines.Add("model_reasoning_effort = `"$($profileConfig.effort)`"")
    if ($profileConfig.review) {
        $profileLines.Add("review_model = `"$($profileConfig.review)`"")
    }

    $firstTableIndex = -1
    for ($i = 0; $i -lt $stripped.Count; $i++) {
        if ($stripped[$i] -match '^\s*\[[^\]]+\]\s*(#.*)?$') {
            $firstTableIndex = $i
            break
        }
    }

    $withProfile = New-Object System.Collections.Generic.List[string]
    if ($firstTableIndex -eq -1) {
        foreach ($line in $stripped) { $withProfile.Add($line) }
        if ($withProfile.Count -gt 0 -and $withProfile[$withProfile.Count - 1] -ne "") {
            $withProfile.Add("")
        }
        foreach ($line in $profileLines) { $withProfile.Add($line) }
    } else {
        for ($i = 0; $i -lt $firstTableIndex; $i++) {
            $withProfile.Add($stripped[$i])
        }
        if ($withProfile.Count -gt 0 -and $withProfile[$withProfile.Count - 1] -ne "") {
            $withProfile.Add("")
        }
        foreach ($line in $profileLines) { $withProfile.Add($line) }
        $withProfile.Add("")
        for ($i = $firstTableIndex; $i -lt $stripped.Count; $i++) {
            $withProfile.Add($stripped[$i])
        }
    }

    $output = New-Object System.Collections.Generic.List[string]
    $inFeatures = $false
    $sawFeatures = $false
    $insertedHooks = $false

    foreach ($line in $withProfile) {
        if ($line -match '^\s*\[([^\]]+)\]\s*(#.*)?$') {
            if ($inFeatures -and -not $insertedHooks) {
                $output.Add("codex_hooks = true")
                $insertedHooks = $true
            }

            $inFeatures = $Matches[1].Trim() -eq "features"
            if ($inFeatures) {
                $sawFeatures = $true
                $insertedHooks = $false
            }

            $output.Add($line)

            if ($inFeatures) {
                $output.Add("codex_hooks = true")
                $insertedHooks = $true
            }
            continue
        }

        if ($inFeatures -and $line -match '^\s*codex_hooks\s*=') {
            continue
        }

        $output.Add($line)
    }

    if ($inFeatures -and -not $insertedHooks) {
        $output.Add("codex_hooks = true")
    }

    if (-not $sawFeatures) {
        if ($output.Count -gt 0 -and $output[$output.Count - 1] -ne "") {
            $output.Add("")
        }
        $output.Add("[features]")
        $output.Add("codex_hooks = true")
    }

    Set-Content -LiteralPath $ConfigPath -Value (($output -join "`r`n") + "`r`n") -NoNewline
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
Merge-CodexModelConfig -ConfigPath $configPath -Profile $ModelProfile
Write-Host "Merged repo-local Codex config for model profile '$ModelProfile'"

$hooksPath = ".codex\hooks.json"
if (Test-Path -LiteralPath $hooksPath) {
    $timestamp = Get-Date -Format "yyyyMMddHHmmss"
    Copy-Item -LiteralPath $hooksPath -Destination ".codex\hooks.json.bak.$timestamp"
    Write-Host "Backed up existing hooks.json"
}

Copy-Item -LiteralPath (Join-Path $scriptDir ".codex\windows-hooks.json") -Destination $hooksPath
Copy-Item -LiteralPath (Join-Path $scriptDir ".codex\hooks\git-guard.js") -Destination ".codex\hooks\git-guard.js"
Copy-Item -LiteralPath (Join-Path $scriptDir ".codex\hooks\session-start.js") -Destination ".codex\hooks\session-start.js"
Copy-Item -LiteralPath (Join-Path $scriptDir ".codex\hooks\git-guard.ps1") -Destination ".codex\hooks\git-guard.ps1"
Copy-Item -LiteralPath (Join-Path $scriptDir ".codex\hooks\session-start.ps1") -Destination ".codex\hooks\session-start.ps1"

Write-Host "Installed .codex/hooks.json (universal Node hooks)"
Write-Host "Installed Node and PowerShell hook scripts"
Write-Host ""
Write-Host "SDLC Wizard for Codex installed."
$startModel = if ($ModelProfile -eq "maximum") { "gpt-5.5" } else { "gpt-5.4-mini" }
$startReasoning = "xhigh"
Write-Host "Recommended start: 'codex --full-auto' for low-friction SDLC inside the repo guardrails."
Write-Host "Use plain 'codex' instead if you want more manual confirmation."
Write-Host "Fresh-session note: if you ran this from inside an existing Codex session, exit and reopen Codex in this repo so repo-local config, hooks, and skills load."
Write-Host "Start new with selected profile: codex --full-auto -m $startModel -c 'model_reasoning_effort=`"$startReasoning`"'"
Write-Host "Resume with selected profile: codex resume --full-auto -m $startModel -c 'model_reasoning_effort=`"$startReasoning`"'"
Write-Host "If resume warns it came back with a different model, resume explicitly with: codex resume --full-auto -m gpt-5.5 -c 'model_reasoning_effort=`"xhigh`"'"
Write-Host "Recommended: use full access during setup, environment repair, and auth-heavy workflows."
Write-Host "Wrote repo-local .codex/config.toml model keys for this profile; mixed is wizard policy, not a native Codex mode."
Write-Host "Codex loads project config only after the repo is trusted, and trusted project config overrides your user-level ~/.codex/config.toml."
Write-Host "Codex does not have a native /sdlc command. Use the installed skills plus START-SDLC.md and SDLC-LOOP.md as the honest equivalent."
Write-Host "After restart, use /skills and invoke `$sdlc, `$setup-wizard, `$update-wizard, or `$feedback."
