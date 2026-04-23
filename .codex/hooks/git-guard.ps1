$ErrorActionPreference = "Stop"

$inputJson = [Console]::In.ReadToEnd()
if ([string]::IsNullOrWhiteSpace($inputJson)) {
    exit 0
}

try {
    $payload = $inputJson | ConvertFrom-Json -ErrorAction Stop
} catch {
    exit 0
}

$commandText = ""
if ($null -ne $payload.tool_input -and $null -ne $payload.tool_input.command) {
    $commandText = [string]$payload.tool_input.command
}

if ($commandText -match '(^|\s)git\s+commit(\s|$)') {
    [Console]::Out.Write('{"decision":"block","reason":"TDD CHECK: Did you run tests before committing? Run your full test suite first. ALL tests must pass."}')
    exit 0
}

if ($commandText -match '(^|\s)git\s+push(\s|$)') {
    [Console]::Out.Write('{"decision":"block","reason":"REVIEW CHECK: Did you self-review your changes and run all tests before pushing?"}')
    exit 0
}
