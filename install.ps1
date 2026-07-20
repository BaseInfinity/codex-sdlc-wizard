param(
    [ValidateSet("mixed", "maximum")]
    [string]$ModelProfile = "maximum"
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$minimumGpt56CodexVersion = [version]"0.144.0"

function Assert-Gpt56CodexVersion {
    $codexExecutable = if ($env:CODEX_SDLC_CODEX_BIN) { $env:CODEX_SDLC_CODEX_BIN } else { "codex" }
    $codexCommand = Get-Command $codexExecutable -CommandType Application -ErrorAction SilentlyContinue
    if ($null -eq $codexCommand) {
        throw "GPT-5.6 profiles require Codex CLI $minimumGpt56CodexVersion or newer (Codex CLI is not installed or is unavailable: $codexExecutable).`nUpdate with: npm install -g @openai/codex@latest"
    }

    try {
        $versionOutput = @(& $codexCommand.Source --version 2>&1)
        $versionStatus = $LASTEXITCODE
    } catch {
        throw "GPT-5.6 profiles require Codex CLI $minimumGpt56CodexVersion or newer (the configured Codex binary could not report its version: $codexExecutable).`nUpdate with: npm install -g @openai/codex@latest"
    }

    if ($versionStatus -ne 0) {
        throw "GPT-5.6 profiles require Codex CLI $minimumGpt56CodexVersion or newer (the configured Codex binary could not report its version: $codexExecutable).`nUpdate with: npm install -g @openai/codex@latest"
    }

    $versionMatch = [regex]::Match(($versionOutput -join "`n"), '(?im)^\s*(?:OpenAI\s+)?Codex(?:-CLI)?\s+v?(?<major>\d+)\.(?<minor>\d+)\.(?<patch>\d+)(?<prerelease>-[0-9A-Za-z.-]+)?(?:\s|$)')
    $parsedVersion = if ($versionMatch.Success) {
        [version]("{0}.{1}.{2}" -f $versionMatch.Groups["major"].Value, $versionMatch.Groups["minor"].Value, $versionMatch.Groups["patch"].Value)
    } else {
        $null
    }
    $isMinimumPrerelease = $null -ne $parsedVersion -and $parsedVersion -eq $minimumGpt56CodexVersion -and $versionMatch.Groups["prerelease"].Success
    if ($null -eq $parsedVersion -or $parsedVersion -lt $minimumGpt56CodexVersion -or $isMinimumPrerelease) {
        $foundVersion = if ($versionMatch.Success) {
            $versionMatch.Groups["major"].Value + "." + $versionMatch.Groups["minor"].Value + "." + $versionMatch.Groups["patch"].Value + $versionMatch.Groups["prerelease"].Value
        } else {
            "an unparseable version"
        }
        throw "GPT-5.6 profiles require Codex CLI $minimumGpt56CodexVersion or newer (found $foundVersion).`nUpdate with: npm install -g @openai/codex@latest"
    }
}

function Install-AgentsBaseline {
    param(
        [string]$Source,
        [ValidateSet("mixed", "maximum")]
        [string]$Profile
    )

    if (Test-Path -LiteralPath "AGENTS.md") {
        Write-Host "AGENTS.md already exists - skipping (review manually)"
        return
    }

    $reasoningBaseline = if ($Profile -eq "mixed") { "medium" } else { "high" }
    $content = Get-Content -LiteralPath $Source -Raw
    $content = $content.Replace("{{MODEL_PROFILE}}", $Profile).Replace("{{REASONING_BASELINE}}", $reasoningBaseline)
    Set-Content -LiteralPath "AGENTS.md" -Value $content -NoNewline
    Write-Host "Created AGENTS.md"
}

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
                model = "gpt-5.6-terra"
                effort = "medium"
                review = "gpt-5.6-sol"
            }
        }
        "maximum" {
            @{
                model = "gpt-5.6-sol"
                effort = "high"
                review = "gpt-5.6-sol"
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
                $output.Add("hooks = true")
                $insertedHooks = $true
            }

            $inFeatures = $Matches[1].Trim() -eq "features"
            if ($inFeatures) {
                $sawFeatures = $true
                $insertedHooks = $false
            }

            $output.Add($line)

            if ($inFeatures) {
                $output.Add("hooks = true")
                $insertedHooks = $true
            }
            continue
        }

        if ($inFeatures -and $line -match '^\s*(codex_hooks|hooks)\s*=') {
            continue
        }

        $output.Add($line)
    }

    if ($inFeatures -and -not $insertedHooks) {
        $output.Add("hooks = true")
    }

    if (-not $sawFeatures) {
        if ($output.Count -gt 0 -and $output[$output.Count - 1] -ne "") {
            $output.Add("")
        }
        $output.Add("[features]")
        $output.Add("hooks = true")
    }

    Set-Content -LiteralPath $ConfigPath -Value (($output -join "`r`n") + "`r`n") -NoNewline
}

function Write-ModelProfile {
    param(
        [ValidateSet("mixed", "maximum")]
        [string]$Profile
    )

    New-Item -ItemType Directory -Path ".codex-sdlc" -Force | Out-Null
    $metadata = [ordered]@{
        schema_version = 2
        selected_profile = $Profile
        profiles = [ordered]@{
            mixed = [ordered]@{
                main_model = "gpt-5.6-terra"
                main_reasoning = "medium"
                review_model = "gpt-5.6-sol"
                review_reasoning = "high"
                review_effort_source = "explicit command override"
                review_command = "codex -c 'model_reasoning_effort=`"high`"' review"
                tradeoff = "Experimental explicit opt-in efficiency profile for measured, bounded work; not the normal quality-first driver."
            }
            maximum = [ordered]@{
                main_model = "gpt-5.6-sol"
                main_reasoning = "high"
                review_model = "gpt-5.6-sol"
                review_reasoning = "high"
                review_effort_source = "profile baseline"
                review_command = "codex review"
                tradeoff = "Default quality-first profile with Sol high as the standing root driver."
            }
        }
        policy = [ordered]@{
            high_confidence_threshold_percent = 95
            default_profile = "maximum"
            default_driver = "gpt-5.6-sol"
            default_reasoning = "high"
            low_confidence_rule = "Research more first. If confidence stays below 95%, escalate the difficult slice or review to xhigh."
            reasoning_effort_rule = "Use Sol high as the normal root driver for meaningful SDLC work. Escalate only difficult or high-risk slices to xhigh."
            mixed_profile_rule = "Mixed is experimental and requires explicit opt-in. Preserve an existing explicit selection, but do not select it automatically."
            review_effort_rule = "review_model selects the review model only. Mixed reviews must explicitly override model_reasoning_effort to high."
            lightweight_rule = "Use Terra or Luna only for bounded support work when the task and verification boundary make the tradeoff explicit."
            escalation_rule = "Max is single-task reasoning; Ultra is subagent-backed parallel work. Most tasks do not need either, and neither is a default wizard profile."
        }
    }

    $metadata | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath ".codex-sdlc\model-profile.json"
    Write-Host "Wrote .codex-sdlc/model-profile.json ($Profile)"
}

Assert-Gpt56CodexVersion

Write-Host "Installing SDLC Wizard for Codex CLI..."

Install-AgentsBaseline -Source (Join-Path $scriptDir "templates\AGENTS.baseline.md") -Profile $ModelProfile
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
Write-ModelProfile -Profile $ModelProfile

$hooksPath = ".codex\hooks.json"
if (Test-Path -LiteralPath $hooksPath) {
    $timestamp = Get-Date -Format "yyyyMMddHHmmss"
    Copy-Item -LiteralPath $hooksPath -Destination ".codex\hooks.json.bak.$timestamp"
    Write-Host "Backed up existing hooks.json"
}

Copy-Item -LiteralPath (Join-Path $scriptDir ".codex\windows-hooks.json") -Destination $hooksPath
Copy-Item -LiteralPath (Join-Path $scriptDir ".codex\hooks\git-guard.cjs") -Destination ".codex\hooks\git-guard.cjs"
Copy-Item -LiteralPath (Join-Path $scriptDir ".codex\hooks\session-start.cjs") -Destination ".codex\hooks\session-start.cjs"
Copy-Item -LiteralPath (Join-Path $scriptDir ".codex\hooks\compact-guard.cjs") -Destination ".codex\hooks\compact-guard.cjs"
Copy-Item -LiteralPath (Join-Path $scriptDir ".codex\hooks\git-guard.ps1") -Destination ".codex\hooks\git-guard.ps1"
Copy-Item -LiteralPath (Join-Path $scriptDir ".codex\hooks\session-start.ps1") -Destination ".codex\hooks\session-start.ps1"
Remove-Item -LiteralPath ".codex\hooks\git-guard.js", ".codex\hooks\session-start.js" -ErrorAction SilentlyContinue

Write-Host "Installed .codex/hooks.json (universal Node hooks)"
Write-Host "Installed Node and PowerShell hook scripts"
Write-Host ""
Write-Host "SDLC Wizard for Codex installed."
$startModel = if ($ModelProfile -eq "maximum") { "gpt-5.6-sol" } else { "gpt-5.6-terra" }
$startReasoning = if ($ModelProfile -eq "maximum") { "high" } else { "medium" }
Write-Host "Recommended start: codex -m $startModel -c 'model_reasoning_effort=`"$startReasoning`"'"
Write-Host "Use plain 'codex' instead if you want to rely on trusted repo-local config."
Write-Host "Fresh-session note: if you ran this from inside an existing Codex session, exit and reopen Codex in this repo so repo-local config, hooks, and skills load."
Write-Host "Hook review note: if Codex says hooks need review, open /hooks after restart and review pending repo hooks before relying on enforcement."
Write-Host "Start new with selected profile: codex -m $startModel -c 'model_reasoning_effort=`"$startReasoning`"'"
Write-Host "Resume with selected profile: codex resume -m $startModel -c 'model_reasoning_effort=`"$startReasoning`"'"
Write-Host "If resume warns it came back with a different model, resume explicitly with: codex resume -m gpt-5.6-sol -c 'model_reasoning_effort=`"high`"'"
Write-Host "If you normally use yolo-style sessions, use the canonical full-trust Codex flag:"
Write-Host "  codex --dangerously-bypass-approvals-and-sandbox -m $startModel -c 'model_reasoning_effort=`"$startReasoning`"'"
Write-Host "  codex resume --dangerously-bypass-approvals-and-sandbox -m $startModel -c 'model_reasoning_effort=`"$startReasoning`"'"
Write-Host "Codex may accept --yolo as shorthand; this wizard prints the canonical full-trust flag."
Write-Host "Full-auto is not full-trust: full-trust bypasses sandbox and approval prompts."
Write-Host "Full-trust warning: only use that variant in repos you fully trust."
Write-Host "Recommended: use full access during setup, environment repair, and auth-heavy workflows."
Write-Host "Model profile policy: Sol high is the default normal driver for meaningful SDLC work."
Write-Host "Mixed is an experimental explicit opt-in using Terra medium plus Sol review for measured speed, latency, or token-efficiency trials; invoke review with an explicit high effort override."
Write-Host "Reasoning effort policy: keep Sol high as the standing root driver; escalate only difficult or high-risk slices to xhigh."
Write-Host "Escalation policy: Max is single-task reasoning; Ultra is subagent-backed parallel work. Most tasks do not need either, and neither is a default wizard profile."
Write-Host "Wrote repo-local .codex/config.toml model keys for this profile; mixed is experimental wizard policy, not a native Codex mode."
Write-Host "Codex loads project config only after the repo is trusted, and trusted project config overrides your user-level ~/.codex/config.toml."
Write-Host "Codex does not have a native /sdlc command. Use `$sdlc plus START-SDLC.md and SDLC-LOOP.md as the honest equivalent."
Write-Host "After restart, use `$sdlc as the public workflow. Setup/update/feedback helpers are installed for Codex support, not as extra repo-scoped lifecycle entrypoints."
