$ErrorActionPreference = "Stop"

# Legacy platform-specific entrypoint. Keep behavior centralized in git-guard.cjs.
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$nodeGuard = Join-Path $scriptDir "git-guard.cjs"
$inputJson = [Console]::In.ReadToEnd()

if (-not (Test-Path -LiteralPath $nodeGuard)) {
    exit 0
}

$nodeCommand = Get-Command node -ErrorAction SilentlyContinue
if ($null -eq $nodeCommand) {
    exit 0
}

$inputJson | & $nodeCommand.Source $nodeGuard
exit $LASTEXITCODE
