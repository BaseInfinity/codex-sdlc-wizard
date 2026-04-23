$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath "AGENTS.md")) {
    [Console]::Out.Write('{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"WARNING: No AGENTS.md found. SDLC enforcement requires AGENTS.md. Run install.ps1 or install.sh to set it up."}}')
}
