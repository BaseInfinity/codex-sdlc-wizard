#!/bin/bash
# Test Codex SDLC Adapter - platform-aware behavior, payload format, config, install

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$SCRIPT_DIR/.."
HOOKS_DIR="$REPO_DIR/.codex/hooks"
ACTIVE_HOOKS_FILE="$REPO_DIR/.codex/hooks.json"
UNIVERSAL_PRETOOL_SCRIPT="$HOOKS_DIR/git-guard.cjs"
UNIVERSAL_SESSION_SCRIPT="$HOOKS_DIR/session-start.cjs"
UNIVERSAL_COMPACT_SCRIPT="$HOOKS_DIR/compact-guard.cjs"
FABLE_REVIEW_SCRIPT="$HOOKS_DIR/fable-review.cjs"
PASSED=0
FAILED=0

case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) IS_WINDOWS=true ;;
    *) IS_WINDOWS=false ;;
esac

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() {
    echo -e "${GREEN}PASS${NC}: $1"
    PASSED=$((PASSED + 1))
}

fail() {
    echo -e "${RED}FAIL${NC}: $1"
    FAILED=$((FAILED + 1))
}

run_json_hook() {
    local payload="$1"
    local script_path="$2"

    if [ "$IS_WINDOWS" = "true" ]; then
        local win_path
        win_path=$(cygpath -w "$script_path")
        printf '%s' "$payload" | powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$win_path" 2>/dev/null
    else
        printf '%s' "$payload" | "$script_path" 2>/dev/null
    fi
}

run_session_hook() {
    local tmpdir="$1"
    local script_path="$2"

    if [ "$IS_WINDOWS" = "true" ]; then
        local win_path
        local win_tmp
        win_path=$(cygpath -w "$script_path")
        win_tmp=$(cygpath -w "$tmpdir")
        powershell.exe -NoProfile -Command "Set-Location '$win_tmp'; & '$win_path'" 2>/dev/null
    else
        (cd "$tmpdir" && "$script_path" 2>/dev/null)
    fi
}

run_node_json_hook() {
    local payload="$1"
    local script_path="$2"

    printf '%s' "$payload" | node "$script_path" 2>/dev/null
}

run_node_session_hook() {
    local tmpdir="$1"
    local script_path="$2"

    (cd "$tmpdir" && node "$script_path" 2>/dev/null)
}

payload_for_compact() {
    HOOK_EVENT="$1" TRIGGER_TEXT="${2:-auto}" CWD_TEXT="${3:-$PWD}" node -e 'process.stdout.write(JSON.stringify({
      cwd: process.env.CWD_TEXT,
      hook_event_name: process.env.HOOK_EVENT,
      model: "gpt-5.6-sol",
      session_id: "session-test",
      transcript_path: null,
      trigger: process.env.TRIGGER_TEXT,
      turn_id: "turn-test"
    }));'
}

run_hook_status() {
    local payload="$1"
    local script_path="$2"

    if [ "$IS_WINDOWS" = "true" ]; then
        local win_path
        win_path=$(cygpath -w "$script_path")
        printf '%s' "$payload" | powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$win_path" >/dev/null 2>&1
    else
        printf '%s' "$payload" | "$script_path" >/dev/null 2>&1
    fi
}

run_node_hook_status() {
    local payload="$1"
    local script_path="$2"

    printf '%s' "$payload" | node "$script_path" >/dev/null 2>&1
}

payload_for_command() {
    MSYS_NO_PATHCONV=1 COMMAND_TEXT="$1" node -e 'process.stdout.write(JSON.stringify({ tool_input: { command: process.env.COMMAND_TEXT } }));'
}

payload_for_command_with_workdir() {
    local workdir_text="$2"
    if [ "$IS_WINDOWS" = "true" ]; then
        workdir_text=$(cygpath -w "$workdir_text")
    fi
    MSYS_NO_PATHCONV=1 COMMAND_TEXT="$1" WORKDIR_TEXT="$workdir_text" node -e 'process.stdout.write(JSON.stringify({ tool_input: { command: process.env.COMMAND_TEXT, workdir: process.env.WORKDIR_TEXT } }));'
}

native_command_path() {
    if [ "$IS_WINDOWS" = "true" ]; then
        cygpath -w "$1"
    else
        printf '%s' "$1"
    fi
}

deep_nested_eval_command() {
    COMMAND_TEXT="git push origin main" node -e '
        let command = process.env.COMMAND_TEXT;
        for (let index = 0; index < 6; index += 1) {
            command = `eval ${JSON.stringify(command)}`;
        }
        process.stdout.write(command);
    '
}

echo "=== Codex SDLC Adapter Tests ==="
echo ""

write_fake_pester_module() {
    local module_root="$1"
    mkdir -p "$module_root/Pester"
    cat > "$module_root/Pester/Pester.psm1" <<'EOF'
function Invoke-Pester {
    param(
        [object]$Path,
        [object]$ExcludeTag,
        [switch]$EnableExit,
        [switch]$CI
    )
}
Export-ModuleMember -Function Invoke-Pester
EOF
}

if [ "$IS_WINDOWS" = "true" ]; then
    PRETOOL_SCRIPT="$HOOKS_DIR/git-guard.ps1"
    SESSION_SCRIPT="$HOOKS_DIR/session-start.ps1"
    HOOKS_FILE="$REPO_DIR/.codex/windows-hooks.json"
    EXPECTED_HELPER="start-sdlc.ps1"
else
    PRETOOL_SCRIPT="$HOOKS_DIR/bash-guard.sh"
    SESSION_SCRIPT="$HOOKS_DIR/session-start.sh"
    HOOKS_FILE="$REPO_DIR/.codex/unix-hooks.json"
    EXPECTED_HELPER="start-sdlc.sh"
fi

test_pretool_blocks_commit() {
    local output
    output=$(run_json_hook '{"tool_input":{"command":"git commit -m '\''test'\''"}}' "$PRETOOL_SCRIPT")
    if echo "$output" | grep -q '"decision":"block"' \
        && echo "$output" | grep -qi 'hard manual checkpoint' \
        && ! echo "$output" | grep -qi 'Did you run tests'; then
        pass "pre-tool hook blocks git commit"
    else
        fail "pre-tool hook did not block git commit (output: $output)"
    fi
}

test_pretool_blocks_push() {
    local output
    output=$(run_json_hook '{"tool_input":{"command":"git push origin main"}}' "$PRETOOL_SCRIPT")
    if echo "$output" | grep -q '"decision":"block"' \
        && echo "$output" | grep -qi 'hard manual checkpoint' \
        && ! echo "$output" | grep -qi 'Did you self-review'; then
        pass "pre-tool hook blocks git push"
    else
        fail "pre-tool hook did not block git push (output: $output)"
    fi
}

test_universal_pretool_allows_commit_with_fresh_proof() {
    local ws
    local output
    local option_output
    local assignment_output

    ws=$(mktemp -d)
    mkdir -p "$ws/.codex/hooks"
    cp "$UNIVERSAL_PRETOOL_SCRIPT" "$ws/.codex/hooks/git-guard.cjs"

    (
        cd "$ws" || exit 1
        git init -q
        printf '%s\n' "proof-target" > app.txt
        git add app.txt
        node .codex/hooks/git-guard.cjs prove --reviewed --check "true" >/dev/null
    )

    output=$(cd "$ws" && run_node_json_hook "$(payload_for_command "git commit -m test")" ".codex/hooks/git-guard.cjs")
    option_output=$(cd "$ws" && run_node_json_hook "$(payload_for_command "git --no-pager commit -m test")" ".codex/hooks/git-guard.cjs")
    assignment_output=$(cd "$ws" && run_node_json_hook "$(payload_for_command "FOO=bar git commit -m test")" ".codex/hooks/git-guard.cjs")
    rm -rf "$ws"

    if [ -z "$output" ] && [ -z "$option_output" ] && [ -z "$assignment_output" ]; then
        pass "universal pre-tool hook preserves current-repo commit forms with fresh SDLC proof"
    else
        fail "universal pre-tool hook blocked a current-repo commit form despite fresh proof (plain: $output; option: $option_output; assignment: $assignment_output)"
    fi
}

test_universal_proof_runs_powershell_manifest_commands_in_pwsh() {
    if [ "$IS_WINDOWS" != "true" ]; then
        pass "PowerShell proof dispatch regression is Windows-only"
        return
    fi
    if ! command -v pwsh >/dev/null 2>&1; then
        fail "Windows PowerShell proof dispatch regression requires pwsh"
        return
    fi

    local ws module_root marker output status win_module_root win_marker valid=true
    ws=$(mktemp -d)
    module_root="$ws/modules"
    marker="$ws/powershell-proof.txt"
    mkdir -p "$ws/.codex/hooks" "$ws/.codex-sdlc" "$module_root/Pester"
    cp "$UNIVERSAL_PRETOOL_SCRIPT" "$ws/.codex/hooks/git-guard.cjs"
    cat > "$module_root/Pester/Pester.psm1" <<'EOF'
function Invoke-Pester {
    param([string]$Path, [switch]$EnableExit)
    Set-Content -LiteralPath $env:CODEX_SDLC_TEST_MARKER -Value "$($PSVersionTable.PSEdition)|$Path|$EnableExit"
}
Export-ModuleMember -Function Invoke-Pester
EOF
    cat > "$ws/.codex-sdlc/manifest.json" <<'EOF'
{
  "scan": {
    "language": "PowerShell",
    "test_command": "Invoke-Pester -Path tests -EnableExit"
  }
}
EOF
    printf '%s\n' 'proof-target' > "$ws/app.txt"
    (cd "$ws" && git init -q && git add app.txt)
    win_module_root=$(cygpath -w "$module_root")
    win_marker=$(cygpath -w "$marker")

    set +e
    output=$(cd "$ws" && CODEX_SDLC_TEST_MARKER="$win_marker" PSModulePath="$win_module_root;$PSModulePath" \
        node .codex/hooks/git-guard.cjs prove --reviewed 2>&1)
    status=$?
    set -e

    [ "$status" -eq 0 ] || valid=false
    grep -Fxq 'Core|tests|True' "$marker" 2>/dev/null || valid=false
    echo "$output" | grep -Fq 'Running SDLC proof check: Invoke-Pester -Path tests -EnableExit' || valid=false
    echo "$output" | grep -Fq 'Wrote SDLC proof:' || valid=false
    rm -f "$ws/.git/codex-sdlc/proof.json"
    cat > "$ws/.codex-sdlc/manifest.json" <<'EOF'
{
  "scan": {
    "language": "PowerShell",
    "test_command": "Invoke-Pester -Path tests"
  }
}
EOF
    set +e
    output=$(cd "$ws" && CODEX_SDLC_TEST_MARKER="$win_marker" PSModulePath="$win_module_root;$PSModulePath" \
        node .codex/hooks/git-guard.cjs prove --reviewed 2>&1)
    status=$?
    set -e
    [ "$status" -eq 2 ] || valid=false
    echo "$output" | grep -Fqi 'Unsafe Pester proof command' || valid=false
    [ ! -e "$ws/.git/codex-sdlc/proof.json" ] || valid=false
    rm -rf "$ws"

    if [ "$valid" = "true" ]; then
        pass "universal proof runs PowerShell manifest commands through pwsh instead of cmd.exe"
    else
        printf '%s\n' "$output" >&2
        fail "universal proof sent a PowerShell manifest command to the wrong interpreter"
    fi
}

test_universal_proof_rejects_shell_prefixed_powershell_hosts() {
    local ws fakebin command output status valid=true
    local -a commands
    ws=$(mktemp -d)
    fakebin=$(mktemp -d)
    mkdir -p "$ws/.codex/hooks" "$ws/.codex-sdlc"
    cp "$UNIVERSAL_PRETOOL_SCRIPT" "$ws/.codex/hooks/git-guard.cjs"
    if [ "$IS_WINDOWS" = "true" ]; then
        cat > "$fakebin/pwsh.cmd" <<'EOF'
@echo off
if "%CODEX_SDLC_VALIDATE_ONLY%"=="1" exit /b 2
echo Tests Passed: 0, Failed: 1 1>&2
exit /b 0
EOF
    else
        cat > "$fakebin/pwsh" <<'EOF'
#!/bin/sh
[ "$CODEX_SDLC_VALIDATE_ONLY" = "1" ] && exit 2
echo 'Tests Passed: 0, Failed: 1' >&2
exit 0
EOF
        chmod +x "$fakebin/pwsh"
    fi
    printf '%s\n' 'proof-target' > "$ws/app.txt"
    (cd "$ws" && git init -q && git add app.txt)

    commands=(
        'echo setup && pwsh -Command "Invoke-Pester -Path tests"'
        'bash -c '\''pwsh -Command "Invoke-Pester -Path tests"'\'''
        'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -Command "Invoke-Pester -Path tests"'
        'cmd.exe /c po^wershell.exe -NoProfile -Command "Invoke-Pester -Path tests"'
        'po^wershell.exe -NoProfile -Command "Invoke-Pester -Path tests"'
        'eval '\''pwsh -NoProfile -Command "Invoke-Pester -Path tests"'\'''
        'printf '\''%s\n'\'' '\''pwsh -NoProfile -Command "Invoke-Pester -Path tests"'\'' | sh'
    )
    for command in "${commands[@]}"; do
        TEST_COMMAND="$command" node -e '
const fs = require("fs");
fs.writeFileSync(process.argv[1], JSON.stringify({
  scan: { language: "JavaScript", test_command: process.env.TEST_COMMAND },
}));
' "$ws/.codex-sdlc/manifest.json"
        rm -f "$ws/.git/codex-sdlc/proof.json"

        set +e
        output=$(cd "$ws" && PATH="$fakebin:$PATH" node .codex/hooks/git-guard.cjs prove --reviewed 2>&1)
        status=$?
        set -e

        if [ "$status" -ne 2 ] || [ -e "$ws/.git/codex-sdlc/proof.json" ]; then
            printf 'wrapped PowerShell proof was accepted: %s\n%s\n' "$command" "$output" >&2
            valid=false
        fi
    done
    rm -rf "$ws" "$fakebin"

    if [ "$valid" = "true" ]; then
        pass "universal proof rejects PowerShell hosts after shell prefixes"
    else
        printf '%s\n' "$output" >&2
        fail "universal proof stamped a shell-prefixed bare Pester command"
    fi
}

test_universal_proof_preserves_powershell_names_as_data() {
    local ws fakebin output status query_output query_status stdin_output stdin_status powershell_output powershell_status valid=true
    ws=$(mktemp -d)
    fakebin=$(mktemp -d)
    mkdir -p "$ws/.codex/hooks" "$ws/.codex-sdlc" "$ws/tests"
    cp "$UNIVERSAL_PRETOOL_SCRIPT" "$ws/.codex/hooks/git-guard.cjs"
    cat > "$ws/.codex-sdlc/manifest.json" <<'EOF'
{
  "scan": {
    "language": "JavaScript",
    "test_command": "printf '%s\\n' powershell pwsh"
  }
}
EOF
    printf '%s\n' 'proof-target' > "$ws/app.txt"
    printf '%s\n' '#!/bin/sh' 'exit 0' > "$ws/tests/run.sh"
    (cd "$ws" && git init -q && git add app.txt)

    set +e
    output=$(cd "$ws" && node .codex/hooks/git-guard.cjs prove --reviewed 2>&1)
    status=$?
    set -e

    [ "$status" -eq 0 ] || valid=false
    echo "$output" | grep -Fq 'powershell' || valid=false
    echo "$output" | grep -Fq 'pwsh' || valid=false
    [ -e "$ws/.git/codex-sdlc/proof.json" ] || valid=false

    rm -f "$ws/.git/codex-sdlc/proof.json"
    cat > "$ws/.codex-sdlc/manifest.json" <<'EOF'
{
  "scan": {
    "language": "PowerShell",
    "test_command": "'pwsh' | Select-String pwsh"
  }
}
EOF
    if ! command -v pwsh >/dev/null 2>&1 && ! command -v powershell.exe >/dev/null 2>&1; then
        printf '%s\n' '#!/bin/sh' 'exit 0' > "$fakebin/pwsh"
        chmod +x "$fakebin/pwsh"
    fi
    set +e
    powershell_output=$(cd "$ws" && PATH="$fakebin:$PATH" node .codex/hooks/git-guard.cjs prove --reviewed 2>&1)
    powershell_status=$?
    set -e
    [ "$powershell_status" -eq 0 ] || valid=false
    echo "$powershell_output" | grep -Fq 'Wrote SDLC proof:' || valid=false
    [ -e "$ws/.git/codex-sdlc/proof.json" ] || valid=false

    rm -f "$ws/.git/codex-sdlc/proof.json"
    cat > "$ws/.codex-sdlc/manifest.json" <<'EOF'
{
  "scan": {
    "language": "JavaScript",
    "test_command": "command -v pwsh >/dev/null || true"
  }
}
EOF
    set +e
    query_output=$(cd "$ws" && PATH="$fakebin:$PATH" node .codex/hooks/git-guard.cjs prove --reviewed 2>&1)
    query_status=$?
    set -e
    [ "$query_status" -eq 0 ] || valid=false
    echo "$query_output" | grep -Fq 'Wrote SDLC proof:' || valid=false
    [ -e "$ws/.git/codex-sdlc/proof.json" ] || valid=false

    rm -f "$ws/.git/codex-sdlc/proof.json"
    cat > "$ws/.codex-sdlc/manifest.json" <<'EOF'
{
  "scan": {
    "language": "JavaScript",
    "test_command": "bash < tests/run.sh"
  }
}
EOF
    set +e
    stdin_output=$(cd "$ws" && node .codex/hooks/git-guard.cjs prove --reviewed 2>&1)
    stdin_status=$?
    set -e
    [ "$stdin_status" -eq 0 ] || valid=false
    echo "$stdin_output" | grep -Fq 'Wrote SDLC proof:' || valid=false
    [ -e "$ws/.git/codex-sdlc/proof.json" ] || valid=false
    rm -rf "$ws" "$fakebin"

    if [ "$valid" = "true" ]; then
        pass "universal proof preserves PowerShell host names used only as data"
    else
        printf '%s\n' "$output" >&2
        fail "universal proof misclassified a PowerShell host name used as data"
    fi
}

test_universal_proof_rejects_pester_without_exit_propagation() {
    local ws fakebin command output status valid=true
    local -a multiline_commands
    ws=$(mktemp -d)
    fakebin=$(mktemp -d)
    mkdir -p "$ws/.codex/hooks" "$ws/.codex-sdlc"
    cp "$UNIVERSAL_PRETOOL_SCRIPT" "$ws/.codex/hooks/git-guard.cjs"
    grep -Fq 'Explicit pwsh/powershell wrappers are not allowed' \
        "$ws/.codex/hooks/git-guard.cjs" || valid=false
    if grep -Fq 'cmd.exe wrappers around PowerShell are not allowed' \
        "$ws/.codex/hooks/git-guard.cjs"; then
        valid=false
    fi
    grep -Fq "ParameterName -in @('EnableExit', 'CI')" \
        "$ws/.codex/hooks/git-guard.cjs" || valid=false
    grep -Fq 'Where-Object { $_.Extent.Text -match' \
        "$ws/.codex/hooks/git-guard.cjs" || valid=false
    grep -Fq "'pwsh-preview'" "$ws/.codex/hooks/git-guard.cjs" || valid=false
    grep -Fq "'powershell-preview'" "$ws/.codex/hooks/git-guard.cjs" || valid=false
    grep -Fq 'EncodedCommand' \
        "$ws/.codex/hooks/git-guard.cjs" || valid=false
    grep -Fq "'Set-Alias', 'New-Alias'" \
        "$ws/.codex/hooks/git-guard.cjs" || valid=false
    grep -Fq "'bash', 'dash'" \
        "$ws/.codex/hooks/git-guard.cjs" || valid=false
    grep -Fq "'Start-Job'" \
        "$ws/.codex/hooks/git-guard.cjs" || valid=false
    grep -Fq "Properties['Background']" \
        "$ws/.codex/hooks/git-guard.cjs" || valid=false
    printf '%s\n' 'proof-target' > "$ws/app.txt"
    (cd "$ws" && git init -q && git add app.txt)
    if ! command -v pwsh >/dev/null 2>&1 && ! command -v powershell.exe >/dev/null 2>&1; then
        cat > "$fakebin/pwsh" <<'EOF'
#!/bin/sh
if [ "$CODEX_SDLC_VALIDATE_ONLY" = "1" ]; then
    echo 'Unsafe PowerShell proof command: test validator rejected command.' >&2
    exit 2
fi
exit 0
EOF
        chmod +x "$fakebin/pwsh"
    fi

    while IFS= read -r command; do
        TEST_COMMAND="$command" node -e '
const fs = require("fs");
fs.writeFileSync(process.argv[1], JSON.stringify({
  scan: { language: "PowerShell", test_command: process.env.TEST_COMMAND },
}));
' "$ws/.codex-sdlc/manifest.json"
        rm -f "$ws/.git/codex-sdlc/proof.json"

        set +e
        output=$(cd "$ws" && PATH="$fakebin:$PATH" node .codex/hooks/git-guard.cjs prove --reviewed 2>&1)
        status=$?
        set -e

        if [ "$status" -ne 2 ] \
            || ! echo "$output" | grep -Fqi 'Unsafe' \
            || [ -e "$ws/.git/codex-sdlc/proof.json" ]; then
            printf 'unsafe Pester case was accepted: %s\n' "$command" >&2
            valid=false
        fi
    done <<'EOF'
Invoke-Pester -Path tests
$result = Invoke-Pester -Path tests
Invoke-Pester -Path unit; Invoke-Pester -Path integration -EnableExit
Invoke-Pester -Path tests # TODO: add -EnableExit
Invoke-Pester -Path tests <# TODO: add -EnableExit #>
Invoke-Pester -Path tests -Output "Remember -EnableExit next time"
Invoke-Pester -Path tests -CI:$false
pwsh -Command "Invoke-Pester -Path tests"
pwsh -Command Invoke-Pester -Path tests
pwsh '-Command' 'Invoke-Pester -Path tests'
pwsh '-c' 'Invoke-Pester -Path tests'
"pwsh" -Command "Invoke-Pester -Path tests"
& "pwsh" -Command "Invoke-Pester -Path tests"
pwsh -EncodedCommand SQBuAHYAbwBrAGUALQBQAGUAcwB0AGUAcgA=
powershell.exe -EncodedCommand SQBuAHYAbwBrAGUALQBQAGUAcwB0AGUAcgA=
powershell-preview -Command "Invoke-Pester -Path tests"
pwsh-preview -Command "Invoke-Pester -Path tests"
cmd.exe /c powershell.exe -Command "Invoke-Pester -Path tests"
Write-Output "$(Invoke-Pester -Path tests)"
& "Invoke-Pester" -Path tests
Invoke-`Pester -Path tests
Pester\Invoke-Pester -Path tests
Write-Output C#; Invoke-Pester -Path tests
Invoke-Pester -Path (Get-Tests -EnableExit)
Write-Output "$(if ($true) { Invoke-Pester -Path tests })"
pwsh -Command 'Write-Output ''setup''; Invoke-Pester -Path tests'
$p = 'Invoke-Pester'; & $p -Path tests
. Invoke-Pester -Path tests
Invoke-Pester -Path tests -ExcludeTag `-EnableExit
$payload = 'Invoke-Pester -Path tests'; pwsh -Command $payload
$payload = 'Invoke-Pester -Path tests'; Invoke-Expression $payload
iex 'Invoke-Pester -Path tests'
Import-Module Pester; Set-Alias Run-Tests Invoke-Pester; Run-Tests -Path tests
Start-Process pwsh -ArgumentList '-Command','Invoke-Pester -Path tests'
Start-Job { Invoke-Pester -Path tests -CI } | Wait-Job | Receive-Job
Invoke-Pester -Path tests -CI &
EOF

    multiline_commands=(
        $'& `\n\'Invoke-Pester\' -Path tests'
        $'$note = @\'\nit\'s text\n\'@\nInvoke-Pester -Path tests'
    )
    for command in "${multiline_commands[@]}"; do
        TEST_COMMAND="$command" node -e '
const fs = require("fs");
fs.writeFileSync(process.argv[1], JSON.stringify({
  scan: { language: "PowerShell", test_command: process.env.TEST_COMMAND },
}));
' "$ws/.codex-sdlc/manifest.json"
        rm -f "$ws/.git/codex-sdlc/proof.json"

        set +e
        output=$(cd "$ws" && PATH="$fakebin:$PATH" node .codex/hooks/git-guard.cjs prove --reviewed 2>&1)
        status=$?
        set -e

        if [ "$status" -ne 2 ] \
            || ! echo "$output" | grep -Fqi 'Unsafe' \
            || [ -e "$ws/.git/codex-sdlc/proof.json" ]; then
            printf 'unsafe multiline Pester case was accepted: %s\n' "$command" >&2
            valid=false
        fi
    done
    rm -rf "$ws" "$fakebin"

    if [ "$valid" = "true" ]; then
        pass "universal proof rejects Pester commands that can mask failed tests"
    else
        printf '%s\n' "$output" >&2
        fail "universal proof accepted Pester without explicit failed-test exit propagation"
    fi
}

test_universal_proof_accepts_pester_switch_after_quoted_separators() {
    local ws fakebin module_root test_psmodule_path command output status valid=true
    local -a multiline_commands
    ws=$(mktemp -d)
    fakebin=$(mktemp -d)
    mkdir -p "$ws/.codex/hooks" "$ws/.codex-sdlc"
    cp "$UNIVERSAL_PRETOOL_SCRIPT" "$ws/.codex/hooks/git-guard.cjs"
    printf '%s\n' 'proof-target' > "$ws/app.txt"
    (cd "$ws" && git init -q && git add app.txt)
    if command -v pwsh >/dev/null 2>&1 || command -v powershell.exe >/dev/null 2>&1; then
        module_root="$ws/modules"
        write_fake_pester_module "$module_root"
        if [ "$IS_WINDOWS" = "true" ]; then
            test_psmodule_path="$(cygpath -w "$module_root");$PSModulePath"
        else
            test_psmodule_path="$module_root${PSModulePath:+:$PSModulePath}"
        fi
    else
        cat > "$fakebin/pwsh" <<'EOF'
#!/bin/sh
exit 0
EOF
        chmod +x "$fakebin/pwsh"
        test_psmodule_path="${PSModulePath:-}"
    fi

    while IFS= read -r command; do
        TEST_COMMAND="$command" node -e '
const fs = require("fs");
fs.writeFileSync(process.argv[1], JSON.stringify({
  scan: { language: "PowerShell", test_command: process.env.TEST_COMMAND },
}));
' "$ws/.codex-sdlc/manifest.json"
        rm -f "$ws/.git/codex-sdlc/proof.json"

        set +e
        output=$(cd "$ws" && PSModulePath="$test_psmodule_path" PATH="$fakebin:$PATH" \
            node .codex/hooks/git-guard.cjs prove --reviewed 2>&1)
        status=$?
        set -e

        if [ "$status" -ne 0 ] \
            || ! echo "$output" | grep -Fq 'Wrote SDLC proof:' \
            || [ ! -e "$ws/.git/codex-sdlc/proof.json" ]; then
            printf 'safe Pester case was rejected: %s\n%s\n' "$command" "$output" >&2
            valid=false
        fi
    done <<'EOF'
Invoke-Pester -Path "C:\R&D\tests" -EnableExit
Invoke-Pester -Path 'C:\R|D\tests' -EnableExit
(Invoke-Pester -Path tests -EnableExit)
Invoke-Pester -Path 'Invoke-Pester.Tests.ps1' -EnableExit
Pester\Invoke-Pester -Path tests -EnableExit
Invoke-Pester -Path tests -CI
Invoke-Pester -Path tests -CI:$false -EnableExit
Write-Output Invoke-Pester
Write-Output '$(Invoke-Pester -Path tests)'
Write-Output "$(Invoke-Pester -Path (Join-Path . tests) -EnableExit)"
Write-Output "literal `$(Invoke-Pester -Path tests)"; Invoke-Pester -Path tests -EnableExit
& { Invoke-Pester -Path tests -EnableExit }
EOF

    multiline_commands=(
        $'Invoke-Pester -Path tests `\n -EnableExit'
    )
    for command in "${multiline_commands[@]}"; do
        TEST_COMMAND="$command" node -e '
const fs = require("fs");
fs.writeFileSync(process.argv[1], JSON.stringify({
  scan: { language: "PowerShell", test_command: process.env.TEST_COMMAND },
}));
' "$ws/.codex-sdlc/manifest.json"
        rm -f "$ws/.git/codex-sdlc/proof.json"

        set +e
        output=$(cd "$ws" && PSModulePath="$test_psmodule_path" PATH="$fakebin:$PATH" \
            node .codex/hooks/git-guard.cjs prove --reviewed 2>&1)
        status=$?
        set -e

        if [ "$status" -ne 0 ] \
            || ! echo "$output" | grep -Fq 'Wrote SDLC proof:' \
            || [ ! -e "$ws/.git/codex-sdlc/proof.json" ]; then
            printf 'safe multiline Pester case was rejected: %s\n%s\n' "$command" "$output" >&2
            valid=false
        fi
    done
    rm -rf "$ws" "$fakebin"

    if [ "$valid" = "true" ]; then
        pass "universal proof accepts Pester failure propagation after quoted separators"
    else
        printf '%s\n' "$output" >&2
        fail "universal proof rejected a valid Pester command containing quoted separators"
    fi
}

test_universal_proof_validates_explicit_powershell_host_wrappers() {
    local ws fakebin output status valid=true
    ws=$(mktemp -d)
    fakebin=$(mktemp -d)
    mkdir -p "$ws/.codex/hooks"
    cp "$UNIVERSAL_PRETOOL_SCRIPT" "$ws/.codex/hooks/git-guard.cjs"
    printf '%s\n' 'proof-target' > "$ws/app.txt"
    (cd "$ws" && git init -q && git add app.txt)
    if ! command -v pwsh >/dev/null 2>&1 && ! command -v powershell.exe >/dev/null 2>&1; then
        cat > "$fakebin/pwsh" <<'EOF'
#!/bin/sh
if [ "$CODEX_SDLC_VALIDATE_ONLY" = "1" ]; then
    echo 'Unsafe Pester proof command: test validator rejected command.' >&2
    exit 2
fi
exit 0
EOF
        chmod +x "$fakebin/pwsh"
    fi

    set +e
    output=$(cd "$ws" && PATH="$fakebin:$PATH" node .codex/hooks/git-guard.cjs prove --reviewed \
        --check 'pwsh -Command "Invoke-Pester -Path tests"' 2>&1)
    status=$?
    set -e

    [ "$status" -eq 2 ] || valid=false
    echo "$output" | grep -Fqi 'Unsafe' || valid=false
    [ ! -e "$ws/.git/codex-sdlc/proof.json" ] || valid=false
    rm -rf "$ws" "$fakebin"

    if [ "$valid" = "true" ]; then
        pass "universal proof validates explicit PowerShell host wrappers"
    else
        printf '%s\n' "$output" >&2
        fail "universal proof bypassed validation for an explicit PowerShell host wrapper"
    fi
}

test_universal_proof_checks_every_pester_entry_from_zero_depth() {
    local ws fakebin module_root test_psmodule_path output status valid=true
    ws=$(mktemp -d)
    fakebin=$(mktemp -d)
    mkdir -p "$ws/.codex/hooks"
    cp "$UNIVERSAL_PRETOOL_SCRIPT" "$ws/.codex/hooks/git-guard.cjs"
    printf '%s\n' 'proof-target' > "$ws/app.txt"
    (cd "$ws" && git init -q && git add app.txt)
    if command -v pwsh >/dev/null 2>&1 || command -v powershell.exe >/dev/null 2>&1; then
        module_root="$ws/modules"
        write_fake_pester_module "$module_root"
        if [ "$IS_WINDOWS" = "true" ]; then
            test_psmodule_path="$(cygpath -w "$module_root");$PSModulePath"
        else
            test_psmodule_path="$module_root${PSModulePath:+:$PSModulePath}"
        fi
    else
        cat > "$fakebin/pwsh" <<'EOF'
#!/bin/sh
exit 0
EOF
        chmod +x "$fakebin/pwsh"
        test_psmodule_path="${PSModulePath:-}"
    fi

    set +e
    output=$(cd "$ws" && PSModulePath="$test_psmodule_path" PATH="$fakebin:$PATH" \
        node .codex/hooks/git-guard.cjs prove --reviewed \
        --check true --check true --check true --check true --check true \
        --check true --check true --check true --check true \
        --check "Invoke-Pester -Path tests -EnableExit" 2>&1)
    status=$?
    set -e

    [ "$status" -eq 0 ] || valid=false
    echo "$output" | grep -Fq 'Wrote SDLC proof:' || valid=false
    [ -e "$ws/.git/codex-sdlc/proof.json" ] || valid=false
    rm -rf "$ws" "$fakebin"

    if [ "$valid" = "true" ]; then
        pass "universal proof validates every Pester check from recursion depth zero"
    else
        printf '%s\n' "$output" >&2
        fail "universal proof leaked the Array.find callback index into Pester recursion depth"
    fi
}

test_universal_proof_ignores_placeholder_manifest_commands() {
    local ws fakebin output status valid=true
    ws=$(mktemp -d)
    fakebin=$(mktemp -d)
    mkdir -p "$ws/.codex/hooks" "$ws/.codex-sdlc"
    cp "$UNIVERSAL_PRETOOL_SCRIPT" "$ws/.codex/hooks/git-guard.cjs"
    cat > "$ws/.codex-sdlc/manifest.json" <<'EOF'
{
  "scan": {
    "test_command": "none configured",
    "lint_command": "\"  NOT   APPLICABLE  \".",
    "typecheck_command": "<todo>;",
    "build_command": "--"
  }
}
EOF
    if [ "$IS_WINDOWS" = "true" ]; then
        cat > "$fakebin/none.cmd" <<'EOF'
@echo off
echo PLACEHOLDER_COMMAND_EXECUTED
EOF
    else
        cat > "$fakebin/none" <<'EOF'
#!/bin/sh
echo PLACEHOLDER_COMMAND_EXECUTED
EOF
        chmod +x "$fakebin/none"
    fi
    (cd "$ws" && git init -q)

    set +e
    output=$(cd "$ws" && PATH="$fakebin:$PATH" node .codex/hooks/git-guard.cjs prove --reviewed 2>&1)
    status=$?
    set -e

    [ "$status" -eq 2 ] || valid=false
    echo "$output" | grep -Fq 'No proof checks configured. Pass --check <command> or run setup first.' || valid=false
    echo "$output" | grep -Fq 'Running SDLC proof check:' && valid=false
    echo "$output" | grep -Fq 'PLACEHOLDER_COMMAND_EXECUTED' && valid=false
    rm -rf "$ws" "$fakebin"

    if [ "$valid" = "true" ]; then
        pass "universal proof treats placeholder manifest commands as unconfigured without executing them"
    else
        printf '%s\n' "$output" >&2
        fail "universal proof executed a placeholder manifest command"
    fi
}

test_universal_proof_preserves_commands_that_begin_with_none() {
    local ws fakebin output status valid=true
    ws=$(mktemp -d)
    fakebin=$(mktemp -d)
    mkdir -p "$ws/.codex/hooks" "$ws/.codex-sdlc"
    cp "$UNIVERSAL_PRETOOL_SCRIPT" "$ws/.codex/hooks/git-guard.cjs"
    cat > "$ws/.codex-sdlc/manifest.json" <<'EOF'
{
  "scan": {
    "test_command": "none-cli --version"
  }
}
EOF
    if [ "$IS_WINDOWS" = "true" ]; then
        cat > "$fakebin/none-cli.cmd" <<'EOF'
@echo off
echo none-cli regression sentinel
EOF
    else
        cat > "$fakebin/none-cli" <<'EOF'
#!/bin/sh
echo none-cli regression sentinel
EOF
        cat > "$fakebin/pwsh" <<'EOF'
#!/bin/sh
[ "$CODEX_SDLC_VALIDATE_ONLY" = "1" ] && exit 0
[ "$1" = "-NoProfile" ] || exit 97
[ "$2" = "-EncodedCommand" ] || exit 98
decoded=$(node -e 'process.stdout.write(Buffer.from(process.argv[1], "base64").toString("utf16le"))' "$3")
exec sh -c "$decoded"
EOF
        chmod +x "$fakebin/none-cli" "$fakebin/pwsh"
    fi
    printf '%s\n' 'proof-target' > "$ws/app.txt"
    (cd "$ws" && git init -q && git add app.txt)

    set +e
    output=$(cd "$ws" && PATH="$fakebin:$PATH" node .codex/hooks/git-guard.cjs prove --reviewed 2>&1)
    status=$?
    set -e

    [ "$status" -eq 0 ] || valid=false
    echo "$output" | grep -Fq 'Running SDLC proof check: none-cli --version' || valid=false
    echo "$output" | grep -Fq 'none-cli regression sentinel' || valid=false
    echo "$output" | grep -Fq 'Wrote SDLC proof:' || valid=false
    rm -rf "$ws" "$fakebin"

    if [ "$valid" = "true" ]; then
        pass "universal proof preserves genuine commands that begin with none"
    else
        printf '%s\n' "$output" >&2
        fail "universal proof swallowed a genuine command that begins with none"
    fi
}

test_universal_pretool_blocks_stale_proof() {
    local ws
    local output

    ws=$(mktemp -d)
    mkdir -p "$ws/.codex/hooks"
    cp "$UNIVERSAL_PRETOOL_SCRIPT" "$ws/.codex/hooks/git-guard.cjs"

    (
        cd "$ws" || exit 1
        git init -q
        printf '%s\n' "proof-target" > app.txt
        git add app.txt
        node .codex/hooks/git-guard.cjs prove --reviewed --check "true" >/dev/null
        printf '%s\n' "changed-after-proof" >> app.txt
    )

    output=$(cd "$ws" && run_node_json_hook "$(payload_for_command "git commit -m test")" ".codex/hooks/git-guard.cjs")
    rm -rf "$ws"

    if echo "$output" | grep -q '"decision":"block"' \
        && echo "$output" | grep -qi 'proof is stale'; then
        pass "universal pre-tool hook blocks git commit when SDLC proof is stale"
    else
        fail "universal pre-tool hook did not report stale proof (output: $output)"
    fi
}

test_universal_pretool_blocks_cross_repo_proof_reuse() {
    local trusted_ws
    local target_ws
    local output

    trusted_ws=$(mktemp -d)
    target_ws=$(mktemp -d)
    mkdir -p "$trusted_ws/.codex/hooks"
    cp "$UNIVERSAL_PRETOOL_SCRIPT" "$trusted_ws/.codex/hooks/git-guard.cjs"

    (
        cd "$trusted_ws" || exit 1
        git init -q
        printf '%s\n' "trusted-proof" > app.txt
        git add app.txt
        node .codex/hooks/git-guard.cjs prove --reviewed --check "true" >/dev/null
    )

    (
        cd "$target_ws" || exit 1
        git init -q
        printf '%s\n' "target-change" > app.txt
        git add app.txt
        node "$trusted_ws/.codex/hooks/git-guard.cjs" prove --reviewed --check "true" >/dev/null
    )

    output=$(cd "$trusted_ws" && run_node_json_hook "$(payload_for_command "git -C $target_ws commit -m test")" ".codex/hooks/git-guard.cjs")
    rm -rf "$trusted_ws" "$target_ws"

    if echo "$output" | grep -q '"decision":"block"' \
        && echo "$output" | grep -qi 'target repo'; then
        pass "universal pre-tool hook blocks cross-repo SDLC proof reuse"
    else
        fail "universal pre-tool hook allowed cross-repo proof reuse (output: $output)"
    fi
}

test_universal_pretool_blocks_cd_proof_reuse() {
    local trusted_ws
    local target_ws
    local output

    trusted_ws=$(mktemp -d)
    target_ws=$(mktemp -d)
    mkdir -p "$trusted_ws/.codex/hooks"
    cp "$UNIVERSAL_PRETOOL_SCRIPT" "$trusted_ws/.codex/hooks/git-guard.cjs"

    (
        cd "$trusted_ws" || exit 1
        git init -q
        printf '%s\n' "trusted-proof" > app.txt
        git add app.txt
        node .codex/hooks/git-guard.cjs prove --reviewed --check "true" >/dev/null
    )

    (
        cd "$target_ws" || exit 1
        git init -q
        printf '%s\n' "target-change" > app.txt
        git add app.txt
    )

    output=$(cd "$trusted_ws" && run_node_json_hook "$(payload_for_command "cd $target_ws && git commit -m test")" ".codex/hooks/git-guard.cjs")
    rm -rf "$trusted_ws" "$target_ws"

    if echo "$output" | grep -q '"decision":"block"' \
        && echo "$output" | grep -qi 'target repo'; then
        pass "universal pre-tool hook blocks cd-based SDLC proof reuse"
    else
        fail "universal pre-tool hook allowed cd-based proof reuse (output: $output)"
    fi
}

test_universal_pretool_blocks_git_env_proof_reuse() {
    local trusted_ws
    local target_ws
    local output

    trusted_ws=$(mktemp -d)
    target_ws=$(mktemp -d)
    mkdir -p "$trusted_ws/.codex/hooks"
    cp "$UNIVERSAL_PRETOOL_SCRIPT" "$trusted_ws/.codex/hooks/git-guard.cjs"

    (
        cd "$trusted_ws" || exit 1
        git init -q
        printf '%s\n' "trusted-proof" > app.txt
        git add app.txt
        node .codex/hooks/git-guard.cjs prove --reviewed --check "true" >/dev/null
    )

    (
        cd "$target_ws" || exit 1
        git init -q
        printf '%s\n' "target-change" > app.txt
        git add app.txt
    )

    output=$(cd "$trusted_ws" && run_node_json_hook "$(payload_for_command "GIT_DIR=$target_ws/.git GIT_WORK_TREE=$target_ws git commit -m test")" ".codex/hooks/git-guard.cjs")
    rm -rf "$trusted_ws" "$target_ws"

    if echo "$output" | grep -q '"decision":"block"' \
        && echo "$output" | grep -qi 'target repo'; then
        pass "universal pre-tool hook blocks GIT_DIR/GIT_WORK_TREE SDLC proof reuse"
    else
        fail "universal pre-tool hook allowed GIT_DIR/GIT_WORK_TREE proof reuse (output: $output)"
    fi
}

test_universal_pretool_blocks_exported_git_env_proof_reuse() {
    local trusted_ws
    local target_ws
    local output

    trusted_ws=$(mktemp -d)
    target_ws=$(mktemp -d)
    mkdir -p "$trusted_ws/.codex/hooks"
    cp "$UNIVERSAL_PRETOOL_SCRIPT" "$trusted_ws/.codex/hooks/git-guard.cjs"

    (
        cd "$trusted_ws" || exit 1
        git init -q
        printf '%s\n' "trusted-proof" > app.txt
        git add app.txt
        node .codex/hooks/git-guard.cjs prove --reviewed --check "true" >/dev/null
    )

    (
        cd "$target_ws" || exit 1
        git init -q
        printf '%s\n' "target-change" > app.txt
        git add app.txt
    )

    output=$(cd "$trusted_ws" && run_node_json_hook "$(payload_for_command "export GIT_DIR=$target_ws/.git GIT_WORK_TREE=$target_ws; git commit -m test")" ".codex/hooks/git-guard.cjs")
    rm -rf "$trusted_ws" "$target_ws"

    if echo "$output" | grep -q '"decision":"block"' \
        && echo "$output" | grep -qi 'target repo'; then
        pass "universal pre-tool hook blocks exported GIT_DIR/GIT_WORK_TREE SDLC proof reuse"
    else
        fail "universal pre-tool hook allowed exported GIT_DIR/GIT_WORK_TREE proof reuse (output: $output)"
    fi
}

test_universal_pretool_blocks_auto_exported_git_env_proof_reuse() {
    local trusted_ws
    local target_ws
    local output

    trusted_ws=$(mktemp -d)
    target_ws=$(mktemp -d)
    mkdir -p "$trusted_ws/.codex/hooks"
    cp "$UNIVERSAL_PRETOOL_SCRIPT" "$trusted_ws/.codex/hooks/git-guard.cjs"

    (
        cd "$trusted_ws" || exit 1
        git init -q
        printf '%s\n' "trusted-proof" > app.txt
        git add app.txt
        node .codex/hooks/git-guard.cjs prove --reviewed --check "true" >/dev/null
    )

    (
        cd "$target_ws" || exit 1
        git init -q
        printf '%s\n' "target-change" > app.txt
        git add app.txt
    )

    output=$(cd "$trusted_ws" && run_node_json_hook "$(payload_for_command "set -a; GIT_DIR=$target_ws/.git GIT_WORK_TREE=$target_ws; git commit -m test")" ".codex/hooks/git-guard.cjs")
    rm -rf "$trusted_ws" "$target_ws"

    if echo "$output" | grep -q '"decision":"block"' \
        && echo "$output" | grep -qi 'target repo'; then
        pass "universal pre-tool hook blocks auto-exported GIT_DIR/GIT_WORK_TREE SDLC proof reuse"
    else
        fail "universal pre-tool hook allowed auto-exported GIT_DIR/GIT_WORK_TREE proof reuse (output: $output)"
    fi
}

test_universal_pretool_blocks_workdir_proof_reuse() {
    local trusted_ws
    local target_ws
    local output

    trusted_ws=$(mktemp -d)
    target_ws=$(mktemp -d)
    mkdir -p "$trusted_ws/.codex/hooks"
    cp "$UNIVERSAL_PRETOOL_SCRIPT" "$trusted_ws/.codex/hooks/git-guard.cjs"

    (
        cd "$trusted_ws" || exit 1
        git init -q
        printf '%s\n' "trusted-proof" > app.txt
        git add app.txt
        node .codex/hooks/git-guard.cjs prove --reviewed --check "true" >/dev/null
    )

    (
        cd "$target_ws" || exit 1
        git init -q
        printf '%s\n' "target-change" > app.txt
        git add app.txt
    )

    output=$(cd "$trusted_ws" && run_node_json_hook "$(payload_for_command_with_workdir "git commit -m test" "$target_ws")" ".codex/hooks/git-guard.cjs")
    rm -rf "$trusted_ws" "$target_ws"

    if echo "$output" | grep -q '"decision":"block"' \
        && echo "$output" | grep -qi 'proof is missing'; then
        pass "universal pre-tool hook checks proof against Bash workdir"
    else
        fail "universal pre-tool hook reused process-cwd proof for Bash workdir (output: $output)"
    fi
}

test_universal_pretool_allows_workdir_with_fresh_proof() {
    local trusted_ws
    local target_ws
    local output

    trusted_ws=$(mktemp -d)
    target_ws=$(mktemp -d)
    mkdir -p "$trusted_ws/.codex/hooks"
    cp "$UNIVERSAL_PRETOOL_SCRIPT" "$trusted_ws/.codex/hooks/git-guard.cjs"

    (
        cd "$trusted_ws" || exit 1
        git init -q
    )

    (
        cd "$target_ws" || exit 1
        git init -q
        printf '%s\n' "target-proof" > app.txt
        git add app.txt
        node "$trusted_ws/.codex/hooks/git-guard.cjs" prove --reviewed --check "true" >/dev/null
    )

    output=$(cd "$trusted_ws" && run_node_json_hook "$(payload_for_command_with_workdir "git commit -m test" "$target_ws")" ".codex/hooks/git-guard.cjs")
    rm -rf "$trusted_ws" "$target_ws"

    if [ -z "$output" ]; then
        pass "universal pre-tool hook allows Bash workdir with fresh SDLC proof"
    else
        fail "universal pre-tool hook blocked Bash workdir despite fresh proof (output: $output)"
    fi
}

test_universal_pretool_allows_linked_worktree_with_fresh_proof() {
    local trusted_ws
    local linked_parent
    local linked_ws
    local linked_command_path
    local commit_output
    local push_output
    local option_output
    local config_output
    local newline_output
    local terminator_output
    local heredoc_command
    local heredoc_output
    local null_device="/dev/null"
    local msys_output=""

    trusted_ws=$(mktemp -d)
    linked_parent=$(mktemp -d)
    linked_ws="$linked_parent/linked worktree"
    linked_command_path=$(native_command_path "$linked_ws")
    if [ "$IS_WINDOWS" = "true" ]; then
        null_device="NUL"
    fi
    mkdir -p "$trusted_ws/.codex/hooks"
    cp "$UNIVERSAL_PRETOOL_SCRIPT" "$trusted_ws/.codex/hooks/git-guard.cjs"

    (
        cd "$trusted_ws" || exit 1
        git init -q
        git config user.name "Codex SDLC Test"
        git config user.email "codex-sdlc@example.invalid"
        printf '%s\n' "baseline" > app.txt
        git add app.txt
        git commit -qm "baseline"
        git worktree add -q -b linked-proof "$linked_ws"
    )

    (
        cd "$linked_ws" || exit 1
        printf '%s\n' "linked-worktree-change" >> app.txt
        git add app.txt
        node "$trusted_ws/.codex/hooks/git-guard.cjs" prove --reviewed --check "true" >/dev/null
    )

    commit_output=$(cd "$trusted_ws" && run_node_json_hook "$(payload_for_command "git -C \"$linked_command_path\" commit -m test")" ".codex/hooks/git-guard.cjs")
    push_output=$(cd "$trusted_ws" && run_node_json_hook "$(payload_for_command "git -C \"$linked_command_path\" push origin HEAD")" ".codex/hooks/git-guard.cjs")
    option_output=$(cd "$trusted_ws" && run_node_json_hook "$(payload_for_command "git --no-pager -C \"$linked_command_path\" commit -m test")" ".codex/hooks/git-guard.cjs")
    config_output=$(cd "$trusted_ws" && run_node_json_hook "$(payload_for_command "git -C \"$linked_command_path\" -c core.hooksPath=$null_device -c core.fsmonitor=false -c commit.gpgSign=false commit -m test")" ".codex/hooks/git-guard.cjs")
    newline_output=$(cd "$trusted_ws" && run_node_json_hook "$(payload_for_command "$(printf 'git -C \"%s\" commit -m test\r\n' "$linked_command_path")")" ".codex/hooks/git-guard.cjs")
    terminator_output=$(cd "$trusted_ws" && run_node_json_hook "$(payload_for_command "git -C \"$linked_command_path\" commit -m test;")" ".codex/hooks/git-guard.cjs")
    heredoc_command=$(printf "git -C \"%s\" commit -F - <<'EOF'\nmessage\nEOF\n" "$linked_command_path")
    heredoc_output=$(cd "$trusted_ws" && run_node_json_hook "$(payload_for_command "$heredoc_command")" ".codex/hooks/git-guard.cjs")
    if [ "$IS_WINDOWS" = "true" ]; then
        msys_output=$(cd "$trusted_ws" && run_node_json_hook "$(payload_for_command "git -C \"$(cygpath -u "$linked_ws")\" commit -m test")" ".codex/hooks/git-guard.cjs")
    fi
    git -C "$trusted_ws" worktree remove --force "$linked_ws" >/dev/null 2>&1
    rm -rf "$trusted_ws" "$linked_parent"

    if [ -z "$commit_output" ] && [ -z "$push_output" ] \
        && [ -z "$option_output" ] && [ -z "$config_output" ] \
        && [ -z "$newline_output" ] && [ -z "$terminator_output" ] \
        && [ -z "$heredoc_output" ] \
        && [ -z "$msys_output" ]; then
        pass "universal pre-tool hook allows linked-worktree commit and push with fresh target proof"
    else
        fail "universal pre-tool hook blocked a linked worktree despite fresh proof (commit: $commit_output; push: $push_output; option: $option_output; config: $config_output; newline: $newline_output; terminator: $terminator_output; heredoc: $heredoc_output; MSYS: $msys_output)"
    fi
}

test_universal_pretool_supports_git_without_path_format() {
    local trusted_ws
    local linked_parent
    local linked_ws
    local linked_command_path
    local fakebin
    local real_git
    local output

    if [ "$IS_WINDOWS" = "true" ]; then
        pass "legacy Git path-format fallback coverage is Unix-only"
        return
    fi

    trusted_ws=$(mktemp -d)
    linked_parent=$(mktemp -d)
    linked_ws="$linked_parent/linked worktree"
    linked_command_path=$(native_command_path "$linked_ws")
    fakebin="$linked_parent/fakebin"
    real_git=$(command -v git)
    mkdir -p "$trusted_ws/.codex/hooks" "$fakebin"
    cp "$UNIVERSAL_PRETOOL_SCRIPT" "$trusted_ws/.codex/hooks/git-guard.cjs"
    printf '%s\n' \
        '#!/bin/sh' \
        'for argument in "$@"; do' \
        '    if [ "$argument" = "--path-format=absolute" ]; then' \
        '        echo "unknown option: --path-format=absolute" >&2' \
        '        exit 129' \
        '    fi' \
        'done' \
        'exec "$REAL_GIT" "$@"' > "$fakebin/git"
    chmod +x "$fakebin/git"

    (
        cd "$trusted_ws" || exit 1
        git init -q
        git config user.name "Codex SDLC Test"
        git config user.email "codex-sdlc@example.invalid"
        printf '%s\n' "baseline" > app.txt
        git add app.txt
        git commit -qm "baseline"
        git worktree add -q -b linked-proof "$linked_ws"
    )
    (
        cd "$linked_ws" || exit 1
        printf '%s\n' "linked-worktree-change" >> app.txt
        git add app.txt
        node "$trusted_ws/.codex/hooks/git-guard.cjs" prove --reviewed --check "true" >/dev/null
    )

    output=$(cd "$trusted_ws" && PATH="$fakebin:$PATH" REAL_GIT="$real_git" run_node_json_hook "$(payload_for_command "git -C \"$linked_command_path\" commit -m test")" ".codex/hooks/git-guard.cjs")
    git -C "$trusted_ws" worktree remove --force "$linked_ws" >/dev/null 2>&1
    rm -rf "$trusted_ws" "$linked_parent"

    if [ -z "$output" ]; then
        pass "universal pre-tool hook supports Git without --path-format"
    else
        fail "universal pre-tool hook requires Git 2.31 path formatting (output: $output)"
    fi
}

test_universal_pretool_reports_git_context_inspection_failure() {
    local trusted_ws
    local linked_parent
    local linked_ws
    local linked_command_path
    local fakebin
    local real_git
    local output

    if [ "$IS_WINDOWS" = "true" ]; then
        pass "Git context timeout diagnostic coverage is Unix-only"
        return
    fi

    trusted_ws=$(mktemp -d)
    linked_parent=$(mktemp -d)
    linked_ws="$linked_parent/linked worktree"
    linked_command_path=$(native_command_path "$linked_ws")
    fakebin="$linked_parent/fakebin"
    real_git=$(command -v git)
    mkdir -p "$trusted_ws/.codex/hooks" "$fakebin"
    cp "$UNIVERSAL_PRETOOL_SCRIPT" "$trusted_ws/.codex/hooks/git-guard.cjs"
    printf '%s\n' \
        '#!/bin/sh' \
        'for argument in "$@"; do' \
        '    if [ "$argument" = "rev-parse" ]; then' \
        '        sleep 3' \
        '        exit 1' \
        '    fi' \
        'done' \
        'exec "$REAL_GIT" "$@"' > "$fakebin/git"
    chmod +x "$fakebin/git"

    (
        cd "$trusted_ws" || exit 1
        git init -q
        git config user.name "Codex SDLC Test"
        git config user.email "codex-sdlc@example.invalid"
        printf '%s\n' "baseline" > app.txt
        git add app.txt
        git commit -qm "baseline"
        git worktree add -q -b linked-proof "$linked_ws"
    )
    (
        cd "$linked_ws" || exit 1
        printf '%s\n' "linked-worktree-change" >> app.txt
        git add app.txt
        node "$trusted_ws/.codex/hooks/git-guard.cjs" prove --reviewed --check "true" >/dev/null
    )

    output=$(cd "$trusted_ws" && PATH="$fakebin:$PATH" REAL_GIT="$real_git" run_node_json_hook "$(payload_for_command "git -C \"$linked_command_path\" commit -m test")" ".codex/hooks/git-guard.cjs")
    git -C "$trusted_ws" worktree remove --force "$linked_ws" >/dev/null 2>&1
    rm -rf "$trusted_ws" "$linked_parent"

    if echo "$output" | grep -q '"decision":"block"' \
        && echo "$output" | grep -qi 'cannot inspect target Git context'; then
        pass "universal pre-tool hook reports Git context inspection failures"
    else
        fail "universal pre-tool hook misreported an inspection failure as another repo (output: $output)"
    fi
}

test_universal_pretool_preserves_builtin_git_action_precedence() {
    local trusted_ws
    local linked_parent
    local linked_ws
    local linked_command_path
    local commit_output
    local push_output
    local status_output
    local browser_output
    local browser_marker
    local browser_script
    local viewer_output
    local viewer_marker
    local probe_output
    local probe_marker
    local alias_failure_output
    local failing_git_dir
    local failing_git
    local fake_git
    local real_git

    trusted_ws=$(mktemp -d)
    linked_parent=$(mktemp -d)
    linked_ws="$linked_parent/linked worktree"
    linked_command_path=$(native_command_path "$linked_ws")
    browser_marker="$linked_parent/browser-opened"
    browser_script="$linked_parent/browser"
    viewer_marker="$linked_parent/man-viewer-ran"
    probe_marker="$linked_parent/help-probe-unpinned"
    failing_git_dir="$linked_parent/failing-git"
    failing_git="$failing_git_dir/git"
    fake_git="$linked_parent/git"
    real_git=$(command -v git)
    printf '%s\n' '#!/bin/sh' ': > "$BROWSER_MARKER"' > "$browser_script"
    chmod +x "$browser_script"
    printf '%s\n' \
        '#!/bin/sh' \
        'for argument in "$@"; do' \
        '    if [ "$argument" = "help.format=man" ]; then' \
        '        exec "$REAL_GIT" "$@"' \
        '    fi' \
        'done' \
        'case " $* " in' \
        '    *" help --exclude-guides "*) : > "$PROBE_MARKER"; exit 0 ;;' \
        'esac' \
        'exec "$REAL_GIT" "$@"' > "$fake_git"
    chmod +x "$fake_git"
    mkdir -p "$failing_git_dir"
    printf '%s\n' \
        '#!/bin/sh' \
        'case " $* " in' \
        '    *" config --null --get-regexp "*) exit 2 ;;' \
        'esac' \
        'exec "$REAL_GIT" "$@"' > "$failing_git"
    chmod +x "$failing_git"
    mkdir -p "$trusted_ws/.codex/hooks"
    cp "$UNIVERSAL_PRETOOL_SCRIPT" "$trusted_ws/.codex/hooks/git-guard.cjs"

    (
        cd "$trusted_ws" || exit 1
        git init -q
        git config user.name "Codex SDLC Test"
        git config user.email "codex-sdlc@example.invalid"
        printf '%s\n' "baseline" > app.txt
        git add app.txt
        git commit -qm "baseline"
        git worktree add -q -b linked-proof "$linked_ws"
    )

    (
        cd "$linked_ws" || exit 1
        printf '%s\n' "linked-worktree-change" >> app.txt
        git add app.txt
        git config alias.commit push
        git config alias.push commit
        git config alias.status push
        git config alias.c commit
        node "$trusted_ws/.codex/hooks/git-guard.cjs" prove --reviewed --check "true" >/dev/null
    )

    commit_output=$(cd "$trusted_ws" && run_node_json_hook "$(payload_for_command "git -C \"$linked_command_path\" commit -m test")" ".codex/hooks/git-guard.cjs")
    push_output=$(cd "$trusted_ws" && run_node_json_hook "$(payload_for_command "git -C \"$linked_command_path\" push origin HEAD")" ".codex/hooks/git-guard.cjs")
    status_output=$(cd "$trusted_ws" && run_node_json_hook "$(payload_for_command "git -C \"$linked_command_path\" status --short")" ".codex/hooks/git-guard.cjs")
    browser_output=$(cd "$trusted_ws" && BROWSER_MARKER="$browser_marker" run_node_json_hook "$(payload_for_command "git -C \"$linked_command_path\" -c help.format=web -c web.browser=codex-sdlc -c browser.codex-sdlc.path=\"$browser_script\" status --short")" ".codex/hooks/git-guard.cjs")
    viewer_output=$(cd "$trusted_ws" && run_node_json_hook "$(payload_for_command "git -C \"$linked_command_path\" -c man.viewer=unsafe -c \"man.unsafe.cmd=: > '$viewer_marker'\" status --short")" ".codex/hooks/git-guard.cjs")
    probe_output=$(cd "$trusted_ws" && PATH="$linked_parent:$PATH" REAL_GIT="$real_git" PROBE_MARKER="$probe_marker" run_node_json_hook "$(payload_for_command "git -C \"$linked_command_path\" status --short")" ".codex/hooks/git-guard.cjs")
    alias_failure_output=$(cd "$trusted_ws" && PATH="$failing_git_dir:$PATH" REAL_GIT="$real_git" run_node_json_hook "$(payload_for_command "git -C \"$linked_command_path\" c -m test")" ".codex/hooks/git-guard.cjs")
    git -C "$trusted_ws" worktree remove --force "$linked_ws" >/dev/null 2>&1

    if [ -z "$commit_output" ] && [ -z "$push_output" ] && [ -z "$status_output" ] \
        && [ -z "$browser_output" ] \
        && [ ! -e "$browser_marker" ] \
        && [ -z "$viewer_output" ] && [ ! -e "$viewer_marker" ] \
        && [ -z "$probe_output" ] && [ ! -e "$probe_marker" ] \
        && echo "$alias_failure_output" | grep -q '"decision":"block"' \
        && echo "$alias_failure_output" | grep -qi 'inspect.*alias'; then
        pass "universal pre-tool hook gives Git built-ins precedence over aliases"
    else
        fail "universal pre-tool hook let aliases override Git commands, launched configured help, or failed open (commit: $commit_output; push: $push_output; status: $status_output; configured help: $browser_output; browser opened: $([ -e "$browser_marker" ] && echo yes || echo no); viewer: $viewer_output; viewer ran: $([ -e "$viewer_marker" ] && echo yes || echo no); probe: $probe_output; unpinned: $([ -e "$probe_marker" ] && echo yes || echo no); alias failure: $alias_failure_output)"
    fi
    rm -rf "$trusted_ws" "$linked_parent"
}

test_universal_pretool_allows_inert_inherited_git_settings() {
    local ws
    local count_output
    local no_system_output
    local discovery_output
    local ceiling_output
    local global_null_output
    local system_null_output
    local global_file_output
    local system_file_output
    local parameters_output
    local alternates_output
    local command_count_output
    local command_no_system_output
    local command_discovery_output
    local command_ceiling_output
    local command_global_null_output
    local command_system_null_output
    local inherited_same_git_dir_output
    local inherited_same_index_output
    local current_index
    local null_device="/dev/null"

    if [ "$IS_WINDOWS" = "true" ]; then
        null_device="NUL"
    fi

    ws=$(mktemp -d)
    mkdir -p "$ws/.codex/hooks"
    cp "$UNIVERSAL_PRETOOL_SCRIPT" "$ws/.codex/hooks/git-guard.cjs"
    printf '%s\n' '[user]' '    name = Codex SDLC Test' > "$ws/global.config"
    printf '%s\n' '[user]' '    email = codex-sdlc@example.invalid' > "$ws/system.config"
    mkdir -p "$ws/alternate-objects"

    (
        cd "$ws" || exit 1
        git init -q
        printf '%s\n' "fresh-proof" > app.txt
        git add app.txt
        node .codex/hooks/git-guard.cjs prove --reviewed --check "true" >/dev/null
    )

    count_output=$(cd "$ws" && GIT_CONFIG_COUNT=0 run_node_json_hook "$(payload_for_command "git commit -m test")" ".codex/hooks/git-guard.cjs")
    no_system_output=$(cd "$ws" && GIT_CONFIG_NOSYSTEM=1 run_node_json_hook "$(payload_for_command "git commit -m test")" ".codex/hooks/git-guard.cjs")
    discovery_output=$(cd "$ws" && GIT_DISCOVERY_ACROSS_FILESYSTEM=0 run_node_json_hook "$(payload_for_command "git commit -m test")" ".codex/hooks/git-guard.cjs")
    ceiling_output=$(cd "$ws" && GIT_CEILING_DIRECTORIES="$(dirname "$ws")" run_node_json_hook "$(payload_for_command "git commit -m test")" ".codex/hooks/git-guard.cjs")
    global_null_output=$(cd "$ws" && GIT_CONFIG_GLOBAL="$null_device" run_node_json_hook "$(payload_for_command "git commit -m test")" ".codex/hooks/git-guard.cjs")
    system_null_output=$(cd "$ws" && GIT_CONFIG_SYSTEM="$null_device" run_node_json_hook "$(payload_for_command "git commit -m test")" ".codex/hooks/git-guard.cjs")
    global_file_output=$(cd "$ws" && GIT_CONFIG_GLOBAL="$ws/global.config" run_node_json_hook "$(payload_for_command "git commit -m test")" ".codex/hooks/git-guard.cjs")
    system_file_output=$(cd "$ws" && GIT_CONFIG_SYSTEM="$ws/system.config" run_node_json_hook "$(payload_for_command "git commit -m test")" ".codex/hooks/git-guard.cjs")
    parameters_output=$(cd "$ws" && GIT_CONFIG_PARAMETERS="'user.name=Codex SDLC Test'" run_node_json_hook "$(payload_for_command "git commit -m test")" ".codex/hooks/git-guard.cjs")
    alternates_output=$(cd "$ws" && GIT_ALTERNATE_OBJECT_DIRECTORIES="$ws/alternate-objects" run_node_json_hook "$(payload_for_command "git commit -m test")" ".codex/hooks/git-guard.cjs")
    command_count_output=$(cd "$ws" && run_node_json_hook "$(payload_for_command "GIT_CONFIG_COUNT=0 git commit -m test")" ".codex/hooks/git-guard.cjs")
    command_no_system_output=$(cd "$ws" && run_node_json_hook "$(payload_for_command "GIT_CONFIG_NOSYSTEM=1 git commit -m test")" ".codex/hooks/git-guard.cjs")
    command_discovery_output=$(cd "$ws" && run_node_json_hook "$(payload_for_command "GIT_DISCOVERY_ACROSS_FILESYSTEM=0 git commit -m test")" ".codex/hooks/git-guard.cjs")
    command_ceiling_output=$(cd "$ws" && run_node_json_hook "$(payload_for_command "GIT_CEILING_DIRECTORIES=\"$(dirname "$ws")\" git commit -m test")" ".codex/hooks/git-guard.cjs")
    command_global_null_output=$(cd "$ws" && run_node_json_hook "$(payload_for_command "GIT_CONFIG_GLOBAL=$null_device git commit -m test")" ".codex/hooks/git-guard.cjs")
    command_system_null_output=$(cd "$ws" && run_node_json_hook "$(payload_for_command "GIT_CONFIG_SYSTEM=$null_device git commit -m test")" ".codex/hooks/git-guard.cjs")
    current_index=$(git -C "$ws" rev-parse --git-path index)
    inherited_same_git_dir_output=$(cd "$ws" && GIT_DIR=.git run_node_json_hook "$(payload_for_command "git commit -m test")" ".codex/hooks/git-guard.cjs")
    inherited_same_index_output=$(cd "$ws" && GIT_INDEX_FILE="$current_index" run_node_json_hook "$(payload_for_command "git commit -m test")" ".codex/hooks/git-guard.cjs")
    rm -rf "$ws"

    if [ -z "$count_output" ] && [ -z "$no_system_output" ] && [ -z "$discovery_output" ] && [ -z "$ceiling_output" ] \
        && [ -z "$global_null_output" ] && [ -z "$system_null_output" ] \
        && [ -z "$global_file_output" ] && [ -z "$system_file_output" ] \
        && [ -z "$parameters_output" ] && [ -z "$alternates_output" ] \
        && [ -z "$command_count_output" ] && [ -z "$command_no_system_output" ] \
        && [ -z "$command_discovery_output" ] && [ -z "$command_ceiling_output" ] \
        && [ -z "$command_global_null_output" ] && [ -z "$command_system_null_output" ] \
        && [ -z "$inherited_same_git_dir_output" ] && [ -z "$inherited_same_index_output" ]; then
        pass "universal pre-tool hook allows inert inherited Git settings"
    else
        fail "universal pre-tool hook blocked inert or same-repository Git settings (inherited count: $count_output; inherited no-system: $no_system_output; inherited discovery: $discovery_output; inherited ceiling: $ceiling_output; inherited global null: $global_null_output; inherited system null: $system_null_output; global file: $global_file_output; system file: $system_file_output; parameters: $parameters_output; alternates: $alternates_output; command count: $command_count_output; command no-system: $command_no_system_output; command discovery: $command_discovery_output; command ceiling: $command_ceiling_output; command global null: $command_global_null_output; command system null: $command_system_null_output; same GIT_DIR: $inherited_same_git_dir_output; same index: $inherited_same_index_output)"
    fi
}

test_universal_pretool_allows_same_context_git_dir_without_index() {
    local ws
    local output

    ws=$(mktemp -d)
    mkdir -p "$ws/.codex/hooks"
    cp "$UNIVERSAL_PRETOOL_SCRIPT" "$ws/.codex/hooks/git-guard.cjs"

    (
        cd "$ws" || exit 1
        git init -q
        node .codex/hooks/git-guard.cjs prove --reviewed --check "true" >/dev/null
    )

    output=$(cd "$ws" && GIT_DIR=.git run_node_json_hook "$(payload_for_command "git commit --allow-empty -m test")" ".codex/hooks/git-guard.cjs")
    rm -rf "$ws"

    if [ -z "$output" ]; then
        pass "universal pre-tool hook allows a same-context GIT_DIR before the index exists"
    else
        fail "universal pre-tool hook rejected a same-context GIT_DIR in an index-free repo (output: $output)"
    fi
}

test_universal_pretool_blocks_inherited_linked_worktree_rebinding() {
    local ws
    local linked_parent
    local first_ws
    local second_ws
    local first_command_path
    local second_git_dir
    local output

    ws=$(mktemp -d)
    linked_parent=$(mktemp -d)
    first_ws="$linked_parent/first"
    second_ws="$linked_parent/second"
    first_command_path=$(native_command_path "$first_ws")
    mkdir -p "$ws/.codex/hooks"
    cp "$UNIVERSAL_PRETOOL_SCRIPT" "$ws/.codex/hooks/git-guard.cjs"

    (
        cd "$ws" || exit 1
        git init -q
        git config user.name "Codex SDLC Test"
        git config user.email "codex-sdlc@example.invalid"
        printf '%s\n' "baseline" > app.txt
        git add app.txt
        git commit -qm "baseline"
        git worktree add -q -b first-proof "$first_ws"
        git worktree add -q -b second-proof "$second_ws"
    )

    (
        cd "$second_ws" || exit 1
        printf '%s\n' "second-worktree-change" >> app.txt
        git add app.txt
        node "$ws/.codex/hooks/git-guard.cjs" prove --reviewed --check "true" >/dev/null
    )
    (
        cd "$first_ws" || exit 1
        printf '%s\n' "second-worktree-change" >> app.txt
        git add app.txt
    )
    second_git_dir=$(git -C "$second_ws" rev-parse --absolute-git-dir)

    output=$(cd "$ws" && GIT_DIR="$second_git_dir" run_node_json_hook "$(payload_for_command "git -C \"$first_command_path\" commit -m bypass")" ".codex/hooks/git-guard.cjs")
    git -C "$ws" worktree remove --force "$first_ws" >/dev/null 2>&1
    git -C "$ws" worktree remove --force "$second_ws" >/dev/null 2>&1
    rm -rf "$ws" "$linked_parent"

    if echo "$output" | grep -q '"decision":"block"' \
        && echo "$output" | grep -q 'GIT_DIR'; then
        pass "universal pre-tool hook binds inherited Git overrides to one worktree"
    else
        fail "universal pre-tool hook reused proof across linked worktrees through inherited GIT_DIR (output: $output)"
    fi
}

test_universal_pretool_blocks_inherited_config_worktree_proof_rebinding() {
    local trusted_ws
    local linked_parent
    local linked_ws
    local linked_command_path
    local unrelated_ws
    local fakebin
    local real_git
    local output

    trusted_ws=$(mktemp -d)
    linked_parent=$(mktemp -d)
    linked_ws="$linked_parent/linked worktree"
    linked_command_path=$(native_command_path "$linked_ws")
    unrelated_ws=$(mktemp -d)
    fakebin="$linked_parent/fakebin"
    real_git=$(command -v git)
    mkdir -p "$trusted_ws/.codex/hooks" "$fakebin"
    cp "$UNIVERSAL_PRETOOL_SCRIPT" "$trusted_ws/.codex/hooks/git-guard.cjs"
    printf '%s\n' \
        '#!/bin/sh' \
        'has_rev_parse=false' \
        'has_show_toplevel=false' \
        'has_index_path=false' \
        'previous=""' \
        'for argument in "$@"; do' \
        '    [ "$argument" = "rev-parse" ] && has_rev_parse=true' \
        '    [ "$argument" = "--show-toplevel" ] && has_show_toplevel=true' \
        '    [ "$previous" = "--git-path" ] && [ "$argument" = "index" ] && has_index_path=true' \
        '    previous="$argument"' \
        'done' \
        'if [ "${GIT_CONFIG_COUNT:-}" = "1" ] && [ "$has_rev_parse" = "true" ] && [ "$has_show_toplevel" = "true" ]; then' \
        '    if [ "$has_index_path" = "true" ]; then' \
        '        "$REAL_GIT" "$@" | awk -v target="$REDIRECT_WORKTREE" '\''NR == 3 { $0 = target } { print }'\''' \
        '        exit ${PIPESTATUS:-0}' \
        '    fi' \
        '    printf "%s\n" "$REDIRECT_WORKTREE"' \
        '    exit 0' \
        'fi' \
        'exec "$REAL_GIT" "$@"' > "$fakebin/git"
    chmod +x "$fakebin/git"

    (
        cd "$trusted_ws" || exit 1
        git init -q
        git config user.name "Codex SDLC Test"
        git config user.email "codex-sdlc@example.invalid"
        printf '%s\n' "trusted-baseline" > app.txt
        git add app.txt
        git commit -qm "baseline"
        git worktree add -q -b linked-proof "$linked_ws"
    )
    (
        cd "$linked_ws" || exit 1
        printf '%s\n' "linked-worktree-change" >> app.txt
        git add app.txt
    )
    (
        cd "$unrelated_ws" || exit 1
        git init -q
        git config user.name "Codex SDLC Test"
        git config user.email "codex-sdlc@example.invalid"
        printf '%s\n' "unrelated-proof" > app.txt
        git add app.txt
        node "$trusted_ws/.codex/hooks/git-guard.cjs" prove --reviewed --check "true" >/dev/null
    )

    output=$(cd "$trusted_ws" \
        && PATH="$fakebin:$PATH" \
            REAL_GIT="$real_git" \
            REDIRECT_WORKTREE="$unrelated_ws" \
            GIT_CONFIG_COUNT=1 \
            GIT_CONFIG_KEY_0=core.worktree \
            GIT_CONFIG_VALUE_0="$unrelated_ws" \
            run_node_json_hook "$(payload_for_command "git -C \"$linked_command_path\" commit -m bypass")" ".codex/hooks/git-guard.cjs")
    git -C "$trusted_ws" worktree remove --force "$linked_ws" >/dev/null 2>&1
    rm -rf "$trusted_ws" "$linked_parent" "$unrelated_ws"

    if echo "$output" | grep -q '"decision":"block"' \
        && echo "$output" | grep -q 'GIT_CONFIG_COUNT'; then
        pass "universal pre-tool hook binds inherited Git config to the inspected worktree"
    else
        fail "universal pre-tool hook reused unrelated proof through inherited core.worktree (output: $output)"
    fi
}

test_universal_pretool_preserves_case_sensitive_worktree_identity() {
    local ws
    local linked_parent
    local upper_ws
    local lower_ws
    local upper_command_path
    local lower_git_dir
    local simulated_guard
    local output
    local context_source

    context_source=$(sed -n '/^function physicalGitContext(/,/^}/p' "$UNIVERSAL_PRETOOL_SCRIPT")
    if echo "$context_source" | grep -q 'toLowerCase' \
        || ! echo "$context_source" | grep -q 'statSync'; then
        fail "universal pre-tool hook must compare filesystem identity without unconditional case folding"
        return
    fi

    ws=$(mktemp -d)
    linked_parent=$(mktemp -d)
    upper_ws="$linked_parent/Worktree"
    lower_ws="$linked_parent/worktree"
    mkdir "$upper_ws"
    if ! mkdir "$lower_ws" 2>/dev/null; then
        rm -rf "$ws" "$linked_parent"
        pass "case-sensitive worktree identity coverage skipped on case-insensitive volume"
        return
    fi
    rmdir "$upper_ws" "$lower_ws"

    upper_command_path=$(native_command_path "$upper_ws")
    simulated_guard="$ws/git-guard-darwin.cjs"
    {
        printf '%s\n' 'Object.defineProperty(process, "platform", { value: "darwin" });'
        sed '1d' "$UNIVERSAL_PRETOOL_SCRIPT"
    } > "$simulated_guard"
    mkdir -p "$ws/.codex/hooks"
    cp "$UNIVERSAL_PRETOOL_SCRIPT" "$ws/.codex/hooks/git-guard.cjs"

    (
        cd "$ws" || exit 1
        git init -q
        git config user.name "Codex SDLC Test"
        git config user.email "codex-sdlc@example.invalid"
        printf '%s\n' "baseline" > app.txt
        git add app.txt
        git commit -qm "baseline"
        git worktree add -q -b upper-proof "$upper_ws"
        git worktree add -q -b lower-proof "$lower_ws"
    )

    for target in "$upper_ws" "$lower_ws"; do
        (
            cd "$target" || exit 1
            printf '%s\n' "same-change" >> app.txt
            git add app.txt
        )
    done
    (
        cd "$lower_ws" || exit 1
        node "$ws/.codex/hooks/git-guard.cjs" prove --reviewed --check "true" >/dev/null
    )
    lower_git_dir=$(git -C "$lower_ws" rev-parse --absolute-git-dir)

    output=$(cd "$ws" && GIT_DIR="$lower_git_dir" run_node_json_hook "$(payload_for_command "git -C \"$upper_command_path\" commit -m bypass")" "$simulated_guard")
    git -C "$ws" worktree remove --force "$upper_ws" >/dev/null 2>&1
    git -C "$ws" worktree remove --force "$lower_ws" >/dev/null 2>&1
    rm -rf "$ws" "$linked_parent"

    if echo "$output" | grep -q '"decision":"block"' \
        && echo "$output" | grep -q 'GIT_DIR'; then
        pass "universal pre-tool hook preserves case-sensitive worktree identity"
    else
        fail "universal pre-tool hook folded distinct case-sensitive worktree identities together (output: $output)"
    fi
}

test_universal_pretool_allows_case_variant_linked_worktree_context() {
    local trusted_ws
    local linked_parent
    local linked_ws
    local linked_command_path
    local case_variant_ws
    local case_variant_linked_ws
    local output
    local target_output

    if [ "$IS_WINDOWS" = "true" ] || [ "$(uname -s)" != "Darwin" ]; then
        pass "linked-worktree case-variant path coverage is macOS-only"
        return
    fi

    trusted_ws=$(mktemp -d /private/tmp/Codex-SDLC-Case.XXXXXX)
    linked_parent=$(mktemp -d)
    linked_ws="$linked_parent/linked worktree"
    linked_command_path=$(native_command_path "$linked_ws")
    case_variant_ws=$(printf '%s' "$trusted_ws" | tr '[:upper:]' '[:lower:]')
    case_variant_linked_ws=$(printf '%s' "$linked_ws" | tr '[:upper:]' '[:lower:]')
    mkdir -p "$trusted_ws/.codex/hooks"
    cp "$UNIVERSAL_PRETOOL_SCRIPT" "$trusted_ws/.codex/hooks/git-guard.cjs"

    (
        cd "$trusted_ws" || exit 1
        git init -q
        git config user.name "Codex SDLC Test"
        git config user.email "codex-sdlc@example.invalid"
        printf '%s\n' "baseline" > app.txt
        git add app.txt
        git commit -qm "baseline"
        git worktree add -q -b linked-proof "$linked_ws"
    )

    if ! git -C "$case_variant_ws" rev-parse --show-toplevel >/dev/null 2>&1; then
        git -C "$trusted_ws" worktree remove --force "$linked_ws" >/dev/null 2>&1
        rm -rf "$trusted_ws" "$linked_parent"
        pass "linked-worktree case-variant path coverage skipped on case-sensitive macOS volume"
        return
    fi

    (
        cd "$linked_ws" || exit 1
        printf '%s\n' "linked-worktree-change" >> app.txt
        git add app.txt
        node "$trusted_ws/.codex/hooks/git-guard.cjs" prove --reviewed --check "true" >/dev/null
    )

    output=$(cd "$trusted_ws" && run_node_json_hook "$(payload_for_command_with_workdir "git -C \"$linked_command_path\" commit -m test" "$case_variant_ws")" ".codex/hooks/git-guard.cjs")
    target_output=$(cd "$trusted_ws" && run_node_json_hook "$(payload_for_command "git -C \"$case_variant_linked_ws\" commit -m test")" ".codex/hooks/git-guard.cjs")
    git -C "$trusted_ws" worktree remove --force "$linked_ws" >/dev/null 2>&1
    rm -rf "$trusted_ws" "$linked_parent"

    if [ -z "$output" ] && [ -z "$target_output" ]; then
        pass "universal pre-tool hook canonicalizes case-variant macOS worktree paths"
    else
        fail "universal pre-tool hook rejected a case-variant path to the same linked-worktree repository (workdir: $output; target: $target_output)"
    fi
}

test_universal_pretool_blocks_case_variant_windows_git_env() {
    local ws
    local simulated_guard
    local output
    local inert_output

    ws=$(mktemp -d)
    simulated_guard="$ws/git-guard-windows.cjs"
    {
        printf '%s\n' 'Object.defineProperty(process, "platform", { value: "win32" });'
        sed '1d' "$UNIVERSAL_PRETOOL_SCRIPT"
    } > "$simulated_guard"
    mkdir -p "$ws/repo/.codex/hooks" "$ws/alternate"
    cp "$UNIVERSAL_PRETOOL_SCRIPT" "$ws/repo/.codex/hooks/git-guard.cjs"

    (
        cd "$ws/repo" || exit 1
        git init -q
        printf '%s\n' "fresh-proof" > app.txt
        git add app.txt
        node .codex/hooks/git-guard.cjs prove --reviewed --check "true" >/dev/null
    )

    output=$(cd "$ws/repo" && git_dir="$ws/alternate" run_node_json_hook "$(payload_for_command "git commit -m test")" "$simulated_guard")
    inert_output=$(cd "$ws/repo" && run_node_json_hook "$(payload_for_command "git_config_count=0 git_config_key_0=core.hooksPath git_config_value_0=/tmp/ignored git commit -m test")" "$simulated_guard")
    rm -rf "$ws"

    if echo "$output" | grep -q '"decision":"block"' \
        && echo "$output" | grep -q 'GIT_DIR' \
        && [ -z "$inert_output" ]; then
        pass "universal pre-tool hook normalizes case-insensitive Windows Git environment names"
    else
        fail "universal pre-tool hook mishandled case-variant Windows Git environment settings (override: $output; inert: $inert_output)"
    fi
}

test_universal_pretool_blocks_windows_cmd_path_expansion() {
    local ws
    local linked_ws
    local unrelated_ws
    local simulated_guard
    local output

    ws=$(mktemp -d)
    linked_ws="$ws/%TARGET%"
    unrelated_ws=$(mktemp -d)
    simulated_guard="$ws/git-guard-windows.cjs"
    {
        printf '%s\n' 'Object.defineProperty(process, "platform", { value: "win32" });'
        sed '1d' "$UNIVERSAL_PRETOOL_SCRIPT"
    } > "$simulated_guard"
    mkdir -p "$ws/.codex/hooks"
    cp "$UNIVERSAL_PRETOOL_SCRIPT" "$ws/.codex/hooks/git-guard.cjs"

    (
        cd "$ws" || exit 1
        git init -q
        git config user.name "Codex SDLC Test"
        git config user.email "codex-sdlc@example.invalid"
        printf '%s\n' "baseline" > app.txt
        git add app.txt
        git commit -qm "baseline"
        git worktree add -q -b literal-cmd-path "$linked_ws"
    )
    (
        cd "$linked_ws" || exit 1
        printf '%s\n' "linked-worktree-change" >> app.txt
        git add app.txt
        node "$ws/.codex/hooks/git-guard.cjs" prove --reviewed --check "true" >/dev/null
    )
    (
        cd "$unrelated_ws" || exit 1
        git init -q
        printf '%s\n' "unrelated-change" > app.txt
        git add app.txt
    )

    output=$(cd "$ws" && TARGET="$unrelated_ws" run_node_json_hook "$(payload_for_command 'git -C "%TARGET%" commit -m bypass')" "$simulated_guard")
    git -C "$ws" worktree remove --force "$linked_ws" >/dev/null 2>&1
    rm -rf "$ws" "$unrelated_ws"

    if echo "$output" | grep -q '"decision":"block"' \
        && echo "$output" | grep -qi 'target repo'; then
        pass "universal pre-tool hook blocks cmd.exe expansion in linked-worktree paths"
    else
        fail "universal pre-tool hook validated a literal path that cmd.exe can retarget (output: $output)"
    fi
}

test_universal_pretool_blocks_symlink_parent_directory_rebinding() {
    local trusted_ws
    local linked_parent
    local linked_ws
    local unrelated_ws
    local output
    local linked_output
    local single_operand_output

    if [ "$IS_WINDOWS" = "true" ]; then
        pass "universal pre-tool hook symlink traversal coverage is POSIX-only"
        return
    fi

    trusted_ws=$(mktemp -d)
    linked_parent=$(mktemp -d)
    linked_ws="$linked_parent/linked worktree"
    unrelated_ws=$(mktemp -d)
    mkdir -p "$trusted_ws/.codex/hooks" "$unrelated_ws/child"
    cp "$UNIVERSAL_PRETOOL_SCRIPT" "$trusted_ws/.codex/hooks/git-guard.cjs"

    (
        cd "$trusted_ws" || exit 1
        git init -q
        git config user.name "Codex SDLC Test"
        git config user.email "codex-sdlc@example.invalid"
        printf '%s\n' "trusted" > app.txt
        git add app.txt
        git commit -qm "baseline"
        git worktree add -q -b linked-proof "$linked_ws"
        ln -s "$linked_ws" linked-alias
        ln -s "$unrelated_ws/child" escape-link
        printf '%s\n' "trusted-change" >> app.txt
        git add app.txt
        node .codex/hooks/git-guard.cjs prove --reviewed --check "true" >/dev/null
    )

    (
        cd "$linked_ws" || exit 1
        printf '%s\n' "linked-worktree-change" >> app.txt
        git add app.txt
        node "$trusted_ws/.codex/hooks/git-guard.cjs" prove --reviewed --check "true" >/dev/null
    )

    (
        cd "$unrelated_ws" || exit 1
        git init -q
        git config user.name "Codex SDLC Test"
        git config user.email "codex-sdlc@example.invalid"
        printf '%s\n' "unrelated" > app.txt
        git add app.txt
        git commit -qm "baseline"
        printf '%s\n' "unrelated-change" >> app.txt
        git add app.txt
    )

    output=$(cd "$trusted_ws" && run_node_json_hook "$(payload_for_command "git -C escape-link -C .. commit -m bypass")" ".codex/hooks/git-guard.cjs")
    single_operand_output=$(cd "$trusted_ws" && run_node_json_hook "$(payload_for_command "git -C escape-link/.. commit -m bypass")" ".codex/hooks/git-guard.cjs")
    linked_output=$(cd "$trusted_ws" && run_node_json_hook "$(payload_for_command "git -C linked-alias commit -m bypass")" ".codex/hooks/git-guard.cjs")
    git -C "$trusted_ws" worktree remove --force "$linked_ws" >/dev/null 2>&1
    rm -rf "$trusted_ws" "$linked_parent" "$unrelated_ws"

    if echo "$output" | grep -q '"decision":"block"' \
        && echo "$output" | grep -qi 'target repo' \
        && echo "$single_operand_output" | grep -q '"decision":"block"' \
        && echo "$single_operand_output" | grep -qi 'target repo' \
        && echo "$linked_output" | grep -q '"decision":"block"' \
        && echo "$linked_output" | grep -qi 'target repo'; then
        pass "universal pre-tool hook blocks symlinked linked-worktree targets and resolves chained -C operands"
    else
        fail "universal pre-tool hook allowed symlink target rebinding (chained traversal: $output; single-operand traversal: $single_operand_output; linked alias: $linked_output)"
    fi
}

test_universal_pretool_blocks_linked_worktree_without_fresh_proof() {
    local trusted_ws
    local linked_parent
    local linked_ws
    local linked_command_path
    local missing_output
    local compound_output
    local background_output
    local stale_output

    trusted_ws=$(mktemp -d)
    linked_parent=$(mktemp -d)
    linked_ws="$linked_parent/linked worktree"
    linked_command_path=$(native_command_path "$linked_ws")
    mkdir -p "$trusted_ws/.codex/hooks"
    cp "$UNIVERSAL_PRETOOL_SCRIPT" "$trusted_ws/.codex/hooks/git-guard.cjs"

    (
        cd "$trusted_ws" || exit 1
        git init -q
        git config user.name "Codex SDLC Test"
        git config user.email "codex-sdlc@example.invalid"
        printf '%s\n' "baseline" > app.txt
        git add app.txt
        git commit -qm "baseline"
        git worktree add -q -b linked-proof "$linked_ws"
    )

    missing_output=$(cd "$trusted_ws" && run_node_json_hook "$(payload_for_command "git -C \"$linked_command_path\" commit -m test")" ".codex/hooks/git-guard.cjs")

    (
        cd "$linked_ws" || exit 1
        printf '%s\n' "proof-target" >> app.txt
        git add app.txt
        node "$trusted_ws/.codex/hooks/git-guard.cjs" prove --reviewed --check "true" >/dev/null
    )

    compound_output=$(cd "$trusted_ws" && run_node_json_hook "$(payload_for_command "git -C \"$linked_command_path\" status >/dev/null && sh -c 'git commit -m bypass'")" ".codex/hooks/git-guard.cjs")
    background_output=$(cd "$trusted_ws" && run_node_json_hook "$(payload_for_command "git -C \"$linked_command_path\" commit -m test &")" ".codex/hooks/git-guard.cjs")
    printf '%s\n' "changed-after-proof" >> "$linked_ws/app.txt"
    stale_output=$(cd "$trusted_ws" && run_node_json_hook "$(payload_for_command "git -C \"$linked_command_path\" push origin HEAD")" ".codex/hooks/git-guard.cjs")
    git -C "$trusted_ws" worktree remove --force "$linked_ws" >/dev/null 2>&1
    rm -rf "$trusted_ws" "$linked_parent"

    if echo "$missing_output" | grep -q '"decision":"block"' \
        && echo "$missing_output" | grep -qi 'proof is missing' \
        && echo "$compound_output" | grep -q '"decision":"block"' \
        && echo "$compound_output" | grep -qi 'target repo' \
        && echo "$background_output" | grep -q '"decision":"block"' \
        && echo "$background_output" | grep -qi 'target repo' \
        && echo "$stale_output" | grep -q '"decision":"block"' \
        && echo "$stale_output" | grep -qi 'proof is stale'; then
        pass "universal pre-tool hook binds linked-worktree proof to a direct commit or push"
    else
        fail "universal pre-tool hook mishandled linked-worktree proof binding (missing: $missing_output; compound: $compound_output; background: $background_output; stale: $stale_output)"
    fi
}

test_universal_pretool_blocks_wrapper_directory_proof_rebinding() {
    local trusted_ws
    local linked_ws
    local other_parent
    local other_ws
    local linked_command_path
    local other_parent_command_path
    local linked_object_dir
    local output
    local login_output
    local long_login_output
    local env_path_output
    local assignment_path_output
    local executable_path_output
    local nohup_output
    local index_output
    local namespace_output
    local inherited_object_output
    local alias_output
    local include_alias_output
    local invalid_null_output
    local invalid_null_device="NUL"

    trusted_ws=$(mktemp -d)
    linked_ws="$trusted_ws/linked worktree"
    other_parent=$(mktemp -d)
    other_ws="$other_parent/linked worktree"
    linked_command_path=$(native_command_path "$linked_ws")
    other_parent_command_path=$(native_command_path "$other_parent")
    if [ "$IS_WINDOWS" = "true" ]; then
        invalid_null_device="/dev/null"
    fi
    mkdir -p "$trusted_ws/.codex/hooks" "$other_ws"
    cp "$UNIVERSAL_PRETOOL_SCRIPT" "$trusted_ws/.codex/hooks/git-guard.cjs"

    (
        cd "$trusted_ws" || exit 1
        git init -q
        git config user.name "Codex SDLC Test"
        git config user.email "codex-sdlc@example.invalid"
        printf '%s\n' "baseline" > app.txt
        git add app.txt
        git commit -qm "baseline"
        git worktree add -q -b linked-proof "$linked_ws"
    )

    (
        cd "$linked_ws" || exit 1
        printf '%s\n' "linked-worktree-change" >> app.txt
        git add app.txt
        node "$trusted_ws/.codex/hooks/git-guard.cjs" prove --reviewed --check "true" >/dev/null
    )
    linked_object_dir=$(git -C "$linked_ws" rev-parse --git-path objects)
    git -C "$linked_ws" config alias.c commit
    printf '%s\n' '[alias]' '    hidden = commit' > "$other_parent/aliases.config"

    (
        cd "$other_ws" || exit 1
        git init -q
        git config user.name "Codex SDLC Test"
        git config user.email "codex-sdlc@example.invalid"
        printf '%s\n' "unrelated-change" > app.txt
        git add app.txt
    )

    output=$(cd "$trusted_ws" && run_node_json_hook "$(payload_for_command "env -C \"$other_parent_command_path\" git -C \"linked worktree\" commit -m bypass")" ".codex/hooks/git-guard.cjs")
    login_output=$(cd "$trusted_ws" && run_node_json_hook "$(payload_for_command "sudo -i git -C \"linked worktree\" commit -m bypass")" ".codex/hooks/git-guard.cjs")
    long_login_output=$(cd "$trusted_ws" && run_node_json_hook "$(payload_for_command "sudo --login git -C \"linked worktree\" commit -m bypass")" ".codex/hooks/git-guard.cjs")
    env_path_output=$(cd "$trusted_ws" && run_node_json_hook "$(payload_for_command "env PATH=/tmp/fake git -C \"linked worktree\" commit -m bypass")" ".codex/hooks/git-guard.cjs")
    assignment_path_output=$(cd "$trusted_ws" && run_node_json_hook "$(payload_for_command "PATH=/tmp/fake git -C \"linked worktree\" commit -m bypass")" ".codex/hooks/git-guard.cjs")
    executable_path_output=$(cd "$trusted_ws" && run_node_json_hook "$(payload_for_command "/tmp/fake/git -C \"linked worktree\" commit -m bypass")" ".codex/hooks/git-guard.cjs")
    nohup_output=$(cd "$trusted_ws" && run_node_json_hook "$(payload_for_command "nohup git -C \"linked worktree\" commit -m bypass")" ".codex/hooks/git-guard.cjs")
    index_output=$(cd "$trusted_ws" && run_node_json_hook "$(payload_for_command "GIT_INDEX_FILE=/tmp/alternate-index git -C \"linked worktree\" commit -m bypass")" ".codex/hooks/git-guard.cjs")
    namespace_output=$(cd "$trusted_ws" && run_node_json_hook "$(payload_for_command "GIT_NAMESPACE=alternate git -C \"linked worktree\" push origin HEAD")" ".codex/hooks/git-guard.cjs")
    inherited_object_output=$(cd "$trusted_ws" && GIT_OBJECT_DIRECTORY="$linked_object_dir" run_node_json_hook "$(payload_for_command "git -C \"linked worktree\" commit -m bypass")" ".codex/hooks/git-guard.cjs")
    alias_output=$(cd "$trusted_ws" && run_node_json_hook "$(payload_for_command "git -C \"linked worktree\" c -m bypass")" ".codex/hooks/git-guard.cjs")
    include_alias_output=$(cd "$trusted_ws" && run_node_json_hook "$(payload_for_command "git -C \"linked worktree\" -c include.path=\"$other_parent_command_path/aliases.config\" hidden -m bypass")" ".codex/hooks/git-guard.cjs")
    invalid_null_output=$(cd "$trusted_ws" && run_node_json_hook "$(payload_for_command "git -C \"linked worktree\" -c core.hooksPath=$invalid_null_device commit -m bypass")" ".codex/hooks/git-guard.cjs")
    git -C "$trusted_ws" worktree remove --force "$linked_ws" >/dev/null 2>&1
    rm -rf "$trusted_ws" "$other_parent"

    if echo "$output" | grep -q '"decision":"block"' \
        && echo "$output" | grep -qi 'target repo' \
        && echo "$login_output" | grep -q '"decision":"block"' \
        && echo "$login_output" | grep -qi 'target repo' \
        && echo "$long_login_output" | grep -q '"decision":"block"' \
        && echo "$long_login_output" | grep -qi 'target repo' \
        && echo "$env_path_output" | grep -q '"decision":"block"' \
        && echo "$env_path_output" | grep -qi 'target repo' \
        && echo "$assignment_path_output" | grep -q '"decision":"block"' \
        && echo "$assignment_path_output" | grep -qi 'target repo' \
        && echo "$executable_path_output" | grep -q '"decision":"block"' \
        && echo "$executable_path_output" | grep -qi 'target repo' \
        && echo "$nohup_output" | grep -q '"decision":"block"' \
        && echo "$nohup_output" | grep -qi 'target repo' \
        && echo "$index_output" | grep -q '"decision":"block"' \
        && echo "$index_output" | grep -qi 'target repo' \
        && echo "$namespace_output" | grep -q '"decision":"block"' \
        && echo "$namespace_output" | grep -qi 'target repo' \
        && echo "$inherited_object_output" | grep -q '"decision":"block"' \
        && echo "$inherited_object_output" | grep -q 'GIT_OBJECT_DIRECTORY' \
        && echo "$alias_output" | grep -q '"decision":"block"' \
        && echo "$alias_output" | grep -qi 'target repo' \
        && echo "$include_alias_output" | grep -q '"decision":"block"' \
        && echo "$include_alias_output" | grep -qi 'target repo' \
        && echo "$invalid_null_output" | grep -q '"decision":"block"' \
        && echo "$invalid_null_output" | grep -qi 'target repo'; then
        pass "universal pre-tool hook blocks wrapper directory proof rebinding"
    else
        fail "universal pre-tool hook allowed wrapper or repository-context proof rebinding (linked: $linked_command_path; chdir: $output; login: $login_output; long login: $long_login_output; env PATH: $env_path_output; assignment PATH: $assignment_path_output; executable path: $executable_path_output; nohup: $nohup_output; index: $index_output; namespace: $namespace_output; inherited object dir: $inherited_object_output; alias: $alias_output; include alias: $include_alias_output; invalid null: $invalid_null_output)"
    fi
}

test_universal_pretool_blocks_shell_alias_proof_rebinding() {
    local trusted_ws
    local linked_parent
    local linked_ws
    local literal_ws
    local other_ws
    local linked_command_path
    local other_command_path
    local output
    local process_substitution_output
    local substitution_output
    local variable_output

    trusted_ws=$(mktemp -d)
    linked_parent=$(mktemp -d)
    linked_ws="$linked_parent/linked worktree"
    literal_ws="$trusted_ws/\$TARGET"
    other_ws=$(mktemp -d)
    linked_command_path=$(native_command_path "$linked_ws")
    other_command_path=$(native_command_path "$other_ws")
    mkdir -p "$trusted_ws/.codex/hooks"
    cp "$UNIVERSAL_PRETOOL_SCRIPT" "$trusted_ws/.codex/hooks/git-guard.cjs"

    (
        cd "$trusted_ws" || exit 1
        git init -q
        git config user.name "Codex SDLC Test"
        git config user.email "codex-sdlc@example.invalid"
        printf '%s\n' "baseline" > app.txt
        git add app.txt
        git commit -qm "baseline"
        git worktree add -q -b linked-proof "$linked_ws"
        git worktree add -q -b literal-proof "$literal_ws"
    )

    (
        cd "$linked_ws" || exit 1
        printf '%s\n' "linked-worktree-change" >> app.txt
        git add app.txt
        node "$trusted_ws/.codex/hooks/git-guard.cjs" prove --reviewed --check "true" >/dev/null
    )

    (
        cd "$literal_ws" || exit 1
        printf '%s\n' "literal-worktree-change" >> app.txt
        git add app.txt
        node "$trusted_ws/.codex/hooks/git-guard.cjs" prove --reviewed --check "true" >/dev/null
    )

    (
        cd "$other_ws" || exit 1
        git init -q
        git config user.name "Codex SDLC Test"
        git config user.email "codex-sdlc@example.invalid"
        printf '%s\n' "unrelated-change" > app.txt
        git add app.txt
    )

    output=$(cd "$trusted_ws" && run_node_json_hook "$(payload_for_command "git -C \"$linked_command_path\" -c alias.c='!unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR; git -C \"$other_command_path\" commit -m bypass' c")" ".codex/hooks/git-guard.cjs")
    substitution_output=$(cd "$trusted_ws" && run_node_json_hook "$(payload_for_command "git -C \"$linked_command_path\" commit -m \"\$(git -C \"$other_command_path\" commit -m bypass)\"")" ".codex/hooks/git-guard.cjs")
    process_substitution_output=$(cd "$trusted_ws" && run_node_json_hook "$(payload_for_command "git -C \"$linked_command_path\" commit -F <(git -C \"$other_command_path\" commit -m bypass)")" ".codex/hooks/git-guard.cjs")
    variable_output=$(cd "$trusted_ws" && TARGET="$other_command_path" run_node_json_hook "$(payload_for_command 'git -C $TARGET commit -m bypass')" ".codex/hooks/git-guard.cjs")
    git -C "$trusted_ws" worktree remove --force "$linked_ws" >/dev/null 2>&1
    git -C "$trusted_ws" worktree remove --force "$literal_ws" >/dev/null 2>&1
    rm -rf "$trusted_ws" "$linked_parent" "$other_ws"

    if echo "$output" | grep -q '"decision":"block"' \
        && echo "$output" | grep -qi 'target repo' \
        && echo "$substitution_output" | grep -q '"decision":"block"' \
        && echo "$substitution_output" | grep -qi 'target repo' \
        && echo "$process_substitution_output" | grep -q '"decision":"block"' \
        && echo "$process_substitution_output" | grep -qi 'target repo' \
        && echo "$variable_output" | grep -q '"decision":"block"' \
        && echo "$variable_output" | grep -qi 'target repo'; then
        pass "universal pre-tool hook blocks indirect proof rebinding"
    else
        fail "universal pre-tool hook allowed indirect proof rebinding (alias: $output; substitution: $substitution_output; process substitution: $process_substitution_output; variable: $variable_output)"
    fi
}

test_pretool_blocks_git_after_shell_prefixes() {
    local commands=(
        "npm test && git commit -m test"
        "cd repo; git push origin main"
        "AFTERHOURS_SKIP=1 git push origin main"
        "A[0]=x git push origin main"
        "A[0]+=x git commit -m test"
        "npm test & git push origin main"
        "(git commit -m test)"
        "sudo git commit -m test"
        "if git push origin main; then echo ok; fi"
        "for x in y; do git commit -m test; done"
        $'npm test\ngit push origin main'
        "env -u FOO git push origin main"
        'env -iS "git push origin main"'
        'env -iu FOO -S "git push origin main"'
        "sudo -u root git commit -m test"
        "sudo -HEu root git push origin main"
        "sudo -u >out root git commit -m test"
        "sudo -r sysadm_r git push origin main"
        "sudo -t sysadm_t git commit -m test"
        "sudo --role sysadm_r git push origin main"
        "sudo --type sysadm_t git commit -m test"
        'sudo -Eu root bash -c "git push origin main"'
        "if false; then :; else git push origin main; fi"
        "elif git push origin main; then echo ok; fi"
        "{ git push origin main; }"
        "FOO+=bar git commit -m test"
        ">/tmp/out git push origin main"
        "2>err git commit -m test"
        "git push>/tmp/out origin main"
        "git commit>/tmp/out -m test"
        "git push origin main # --help"
        "git commit -m test # --help"
        "git push -- --help"
        "git push origin -- --help"
        "git commit -- --help"
        "git commit -m --help"
        "git commit -F --help"
        "git commit --message --help"
        "git push origin --receive-pack --help main"
        "git push origin --repo --help main"
        "git>/tmp/out push origin main"
        "git</tmp/in commit -F -"
        "git push&>/tmp/out"
        'git --exec-path "$(git --exec-path)" push'
        'echo "$( git push origin main)"'
        "nice git push origin main"
        "nice -n 10 git commit -m test"
        "stdbuf -oL git push origin main"
        "unbuffer git push origin main"
        "arch -x86_64 git push origin main"
        "script -q /dev/null git push origin main"
        "script -c 'git push origin main' /dev/null"
        'script --command "git commit -m test" /dev/null'
        "ssh-agent git push origin main"
        "ssh-agent bash -c 'git commit -m test'"
        'su -c "git push origin main"'
        "su --session-command 'git push origin main'"
        "su --session-command='git commit -m test'"
        "doas git push origin main"
        "chrt -r 1 git push origin main"
        "taskset -c 0 git push origin main"
        "ionice -c2 git push origin main"
        $'npm test && \\\n git push origin main'
        $'git \\\n push origin main'
        "2>&1 git push origin main"
        ">&2 git commit -m test"
        "git >& 2 push origin main"
        "git 2>& 1 commit -m test"
        "env -S git push origin main"
        'env -S "git commit -m test"'
        'env -S "-- git push origin main"'
        'env -S "-i git push origin main"'
        'env -S "--ignore-environment git push origin main"'
        'env -S "-u FOO git push origin main"'
        'env -S "-C /tmp git push origin main"'
        "env -P /usr/bin git push origin main"
        "env -a fake git push origin main"
        "env --argv0 fake git commit -m test"
        "env -u >out FOO git push origin main"
        "env -P >out /usr/bin git push origin main"
        "exec -a git git push origin main"
        "noglob git push origin main"
        "noglob git commit -m test"
        'eval "git push origin main"'
        'eval -- "git push origin main"'
        'bash -c "git push origin main"'
        'bash -c -- "git push origin main"'
        "cmd /c git push origin main"
        "CMD /C git push origin main"
        "cmd /c call git push origin main"
        "cmd /c CALL git commit -m test"
        "cmd /c start git push origin main"
        'cmd /c start "title" git push origin main'
        'cmd /c start /b "title" git commit -m test'
        "cmd.exe /c git commit -m test"
        'powershell -Command "git push origin main"'
        'PowerShell -Command "git push origin main"'
        'powershell -Command "start git push origin main"'
        'powershell -Command "Start-Process git -ArgumentList push,origin,main"'
        "powershell -EncodedCommand ZwBpAHQAIABwAHUAcwBoACAAbwByAGkAZwBpAG4AIABtAGEAaQBuAA=="
        "pwsh -e ZwBpAHQAIABjAG8AbQBtAGkAdAAgAC0AbQAgAHQAZQBzAHQA"
        'powershell.exe -NoProfile -Command "git commit -m test"'
        'pwsh -c "git push origin main"'
        'PwSh -c "git commit -m test"'
        'zsh --emulate sh -c "git push origin main"'
        'fish --command="git push origin main"'
        'fish --init-command="git push origin main"'
        'fish -C "git push origin main"'
        'sh -c -- "git commit -m test"'
        "sh -c 'git \"\$@\"' sh push origin main"
        "bash -c 'exec git \"\${@}\"' bash push origin main"
        "bash -c 'sh -c \"\$*\"' bash git push origin main"
        "bash -c 'exec git \"\$@\"' bash push origin main"
        "bash -c 'git \"\$1\" origin main' bash push"
        "bash -c 'git \"\${@:1:1}\" origin main' bash push"
        "bash -c 'git \"\${*:1:1}\" origin main' bash push"
        "trap 'git push origin main' EXIT"
        "bash -c 'trap \"git push origin main\" EXIT'"
        'bash -c '\''eval -- "git push origin main"'\'''
        'bash -c >out "git push origin main"'
        'bash -O >out extglob -c "git push origin main"'
        "case main in main) git push origin main;; esac"
        "case main in main) git commit -m test;; esac"
        "git >/tmp/out push origin main"
        "git 2>err commit -m test"
        "git -C >out repo push origin main"
        "git --git-dir >out .git push origin main"
        'git -c >out alias.p=push p'
        $'# <<EOF\ngit push origin main'
        $'# <<\'EOF\'\ngit push origin main\nEOF'
        $'# cat <<EOF\ngit commit -m test\nEOF'
        $'cat <<EOF # <<NEVER\nsafe\nEOF\ngit push origin main'
        $'bash <<EOF\ngit push origin main\nEOF'
        $'sh <<EOF\ngit commit -m test\nEOF'
        $'bash <<\'EOF\'\ngit push origin main\nEOF'
        $'cat <<\\EOF\nsafe\nEOF\ngit push origin main'
        $'cat <<EOF > /tmp/run.sh\ngit push origin main\nEOF\nbash /tmp/run.sh'
        $'cat <<\'EOF\' >/tmp/run.sh\ngit commit -m test\nEOF\nsh /tmp/run.sh'
        $'cat <<EOF > /tmp/run.sh\ngit push origin main\nEOF\n. /tmp/run.sh'
        $'cat <<EOF > /tmp/run.sh\ngit commit -m test\nEOF\nsource /tmp/run.sh'
        $'cat <<EOF &> /tmp/run.sh\ngit push origin main\nEOF\nbash /tmp/run.sh'
        $'cat <<EOF &>> /tmp/run.sh\ngit commit -m test\nEOF\nsh /tmp/run.sh'
        $'cat <<EOF > run.sh\ngit push origin main\nEOF\nbash ./run.sh'
        $'cat <<\'E\\OF\' > run.sh\ngit push origin main\nE\\OF\nbash ./run.sh'
        $'cat <<EOF > run.sh && chmod +x run.sh\ngit push origin main\nEOF\nbash ./run.sh'
        $'cat > run.sh <<EOF\ngit commit -m test\nEOF\nchmod +x run.sh && ./run.sh'
        $'cat > run.sh <<EOF && chmod +x run.sh && ./run.sh\ngit push origin main\nEOF'
        $'cat > run.sh <<\'EOF\'\ngit "$@"\nEOF\nbash run.sh push origin main'
        $'cat > run.sh <<\'EOF\'\ngit "$1" origin main\nEOF\nbash run.sh push'
        $'cat > run.sh <<EOF\ngit push origin main\nEOF\nbash < run.sh'
        $'cat > run.sh <<EOF\ngit commit -m test\nEOF\nsh 0< run.sh'
        "echo git push origin main > run.sh && bash run.sh"
        "printf 'git commit -m test\n' > run.sh && sh run.sh"
        "printf 'git push origin main\n' | tee run.sh >/dev/null && bash run.sh"
        $'cat <<EOF | tee run.sh >/dev/null\ngit push origin main\nEOF\nbash run.sh'
        $'tee >/dev/null run.sh <<\'EOF\'\ngit commit -m test\nEOF\nsh run.sh'
        $'tee >/tmp/run.sh <<EOF\ngit push origin main\nEOF\nbash /tmp/run.sh'
        $'tee > /tmp/run.sh <<EOF\ngit commit -m test\nEOF\nsh /tmp/run.sh'
        $'cat <<END-OF >/dev/null\nsafe\nEND-OF\ngit push origin main'
        "timeout 30 git push origin main"
        "timeout 30 git commit -m test"
        "flock /tmp/codex-sdlc-test.lock git push origin main"
        "flock -n /tmp/codex-sdlc-test.lock git commit -m test"
        "/usr/bin/env git push origin main"
        "/bin/env git commit -m test"
        "/usr/bin/sudo git push origin main"
        "runuser -u root -- git push origin main"
        "runuser --user root -- git commit -m test"
        "/usr/bin/nohup git push origin main"
        "/usr/bin/time git push origin main"
        "/usr/bin/timeout 30 git commit -m test"
        "/usr/bin/nice git push origin main"
        "/usr/bin/git push origin main"
        "Git.exe push origin main"
        "git.exe push origin main"
        "git.exe commit -m test"
        "/mingw64/bin/git.exe commit -m test"
        '"C:/Program Files/Git/cmd/git.exe" push origin main'
        "find . -exec git push origin main \\;"
        "find . -exec /usr/bin/git commit -m test \\;"
        "find . -exec sh -c 'git push origin main' \\;"
        "xargs git push origin main"
        "xargs -i git push {}"
        "xargs --replace git commit -m test"
        "xargs -e git push origin main"
        "xargs --eof git push origin main"
        "xargs git <<< push"
        "xargs -I{} git {} <<< push"
        "watch git push origin main"
        "watch -x git push origin main"
        "watch --exec git push origin main"
        "watch --no-title git commit -m test"
        "parallel git push ::: origin main"
        "parallel -k git push ::: origin main"
        "parallel --keep-order git push ::: origin main"
        "parallel --results out git push ::: origin main"
        "parallel --tagstring tag git push ::: origin main"
        "parallel -C , git push ::: origin main"
        "parallel --colsep , git commit -m test ::: x"
        "parallel -u git commit -m test ::: x"
        "parallel git ::: push"
        "parallel git {} ::: push"
        "git submodule foreach git push origin main"
        "git submodule foreach git commit -m test"
        "git -C repo submodule foreach git push origin main"
        "git submodule foreach 'git push origin main'"
        "git lfs push origin main"
        "git lfs push origin main # --help"
        "git lfs -c lfs.dialtimeout=1 push origin main"
        "git subtree push --prefix dist origin gh-pages"
        "git subtree push --prefix dist origin gh-pages # --help"
        "git subtree --prefix dist push origin gh-pages"
        'git -c alias.p="!git push origin main" p'
        "git -c alias.p='!git \"\$1\" origin main' p push"
        'git -c alias.c="!git commit -m test" c'
        "git -c alias.p='!\$@' p git push origin main"
        "git -c alias.p='!sh -c \"\$@\"' p git push origin main"
        "git -c alias.p='!eval \"\$@\"' p 'git push origin main'"
        "git -c alias.p='!git \"\${@}\"' p push origin main"
        "git -c alias.p='!trap \"git push origin main\" EXIT' p"
        "ALIAS=push git --config-env=alias.p=ALIAS p origin main"
        "ALIAS=commit git --config-env=alias.c=ALIAS c -m test"
        "git -c alias.p='!f() { git \"\$@\"; }; f' p push origin main"
        "git -c alias.p='!f() { exec git \"\$@\"; }; f' p push origin main"
        'git -c alias.p=push p'
        'git -c alias.c=commit c'
        'git -c alias.p="push origin main" p'
        'git -c alias.p=push -c alias.q=p q origin main'
        'git -c alias.c=commit -c alias.q=c q -m test'
        'git -c alias.p="!git push origin main" p -h'
        'git -c alias.c="!git commit -m test" c -h'
        '/usr/bin/env -S "git push origin main"'
        'sudo /usr/bin/env -S "git push origin main"'
        'sudo bash -c "git push origin main"'
        'sudo eval "git push origin main"'
        'eval "$(echo git push origin main)"'
        $'eval "$(cat <<\'EOF\'\ngit push origin main\nEOF\n)"'
        'bash -c "$(echo git push origin main)"'
        '$(echo -e git\\x20push) origin main'
        '$(echo git; echo push) origin main'
        'eval "$(echo -e git\\x20push origin main)"'
        'bash -c "$(echo -e git\\x20push origin main)"'
        "zsh -c 'nocorrect git push origin main'"
        '$(echo git push origin main)'
        '$(printf "git\x20push") origin main'
        $'$(cat <<EOF\ngit push origin main\nEOF\n)'
        '$(echo git) push origin main'
        '$(printf %s git) commit -m test'
        'g$(printf it) push origin main'
        'g$(echo it) com$(printf mit) -m test'
        'git p$(printf ush) origin main'
        'git pu$(echo sh) origin main'
        'git com$(printf mit) -m test'
        'git "$(printf push)" origin main'
        'git p`printf ush` origin main'
        'g`printf it` push origin main'
        'bash -c "$(echo git) push origin main"'
        'eval "$(echo git) commit -m test"'
        'eval "$(printf '\''%q '\'' git push origin main)"'
        "bash -c \"\$(printf git; printf ' push origin main')\""
        "eval \"\$(echo -n git; echo ' commit -m test')\""
        "bash -c \"\$(printf 'git push origin main' | cat)\""
        "eval \"\$(printf 'git commit -m test' | tee /dev/null)\""
        "printf -- 'git push origin main\n' | bash"
        "printf -- 'push\n' | xargs git"
        "printf 'push\\0' | xargs -0 git"
        "printf 'push,' | xargs -d, git"
        '`echo git commit -m test`'
        'echo "$(case x in x) echo ok;; esac; git push origin main)"'
        'echo "$( (echo ok); git push origin main )"'
        'bash -c "$( (echo echo ok); echo git push origin main )"'
        $'bash -c "$(cat <<EOF\ngit push origin main\nEOF\n)"'
        $'sh -c "$(cat <<EOF\ngit commit -m test\nEOF\n)"'
        "function f { git push origin main; }; f"
        'function f() { git "$@"; }; f push origin main'
        'f() { git "$@"; }; f push origin main'
        'f() { command git "$@"; }; f push origin main'
        'f() { git "$1" origin main; }; f push'
        "coproc git push origin main"
        "setsid git push origin main"
        'bash >out -c "git push origin main"'
        'bash -O extglob -c "git push origin main"'
        "eval \$'git push origin main'"
        "eval \$'git\\x20push origin main'"
        "bash -c \$'git push origin main'"
        "bash -c \$'git\\040commit -m test'"
        "printf 'git push origin main\n' | bash"
        "printf 'git push origin main\n' |& bash"
        "echo git push origin main |& sh"
        "echo -e \"git\\x20push origin main\" | bash"
        "printf \"git\\x20push origin main\n\" | bash"
        "printf 'git push origin main\n' | cat | bash"
        "printf 'git push origin main\n' | tee /dev/null | bash"
        "printf 'git push origin main\n' | env -S \"bash -s\""
        $'cat <<EOF | xargs -I{} sh -c \'{}\'\ngit push origin main\nEOF'
        "printf 'git push origin main\n' | xargs -I{} sh -c '{}'"
        "printf 'git push origin main\n' | xargs -I{} bash -c '{}'"
        "echo git push origin main | xargs -I{} sh -c '{}'"
        $'echo ok\nxargs git <<EOF\npush\nEOF'
        $'echo ok\ncat <<EOF | xargs git\npush\nEOF'
        "parallel ::: 'git push origin main'"
        "parallel --jobs 1 ::: 'git commit -m test'"
        "flock -n -c 'git push origin main' /tmp/lock"
        "flock --command='git commit -m test' /tmp/lock"
        "su -c'git push origin main'"
        "script -c'git commit -m test' /dev/null"
        "echo git push origin main | tee >(bash)"
        "printf 'git push origin main\n' | tee >(bash)"
        "printf 'git push origin main\n' | cat > >(bash)"
        "cat > >(bash) <<< 'git push origin main'"
        "tee >(bash) <<< 'git push origin main'"
        "printf 'git push origin main\n' 2>&1 > >(bash)"
        "printf 'git push origin main\n' >| >(bash)"
        "printf 'git push origin main\n' | bash -c 'bash'"
        "bash -c 'source /dev/stdin' <<< 'git commit -m test'"
        "printf '%s ' git push origin main | bash"
        "printf 'git commit -m test\n' | sh"
        "printf '%s\n' 'git push origin main' | bash"
        "printf '%s %s %s %s\n' git commit -m test | sh"
        "echo git push origin main | bash"
        "echo git push origin main | sh -s -- arg"
        "printf '%s\n' 'git commit -m test' | bash -s arg"
        "bash <<< 'git push origin main'"
        'bash <<<$(echo git push origin main)'
        "env -S \"bash -s\" <<< 'git commit -m test'"
        "sh <<< \$'git commit -m test'"
        "<<< 'git push origin main' cat | bash"
        "bash -s arg <<< 'git push origin main'"
        "sh -s -- arg <<< \$'git commit -m test'"
        "bash /dev/fd/3 3<<< 'git push origin main'"
        "source /dev/fd/7 7<<< 'git commit -m test'"
        "bash <(echo git push origin main)"
        "bash <> <(echo git push origin main)"
        "bash 0<> <(echo git push origin main)"
        "sh <(printf 'git commit -m test\n')"
        "bash <(printf 'git push origin main\n' | cat)"
        "source <(printf 'git commit -m test\n' | tee /dev/null)"
        "bash < <(echo git push origin main)"
        "source <(echo git push origin main)"
        ". <(echo git commit -m test)"
        "/opt/homebrew/bin/bash <(echo git push origin main)"
        "env /usr/local/bin/bash <(echo git push origin main)"
        "sudo -u root bash <(echo git push origin main)"
        "env -u FOO bash <(echo git push origin main)"
        "env -P /usr/bin bash <(echo git push origin main)"
        "time -f %e bash <(echo git push origin main)"
        "cat <(git push origin main)"
        "cat <( git push origin main )"
        "cat >(git commit -m test)"
        "diff <(echo ok) <(git push origin main)"
        "echo \`git push origin main\`"
        "echo \` git push origin main\`"
        $'cat <<EOF | bash\ngit push origin main\nEOF'
        $'cat <<EOF | sh\ngit commit -m test\nEOF'
        $'cat <<EOF | /usr/bin/sudo /bin/bash\ngit push origin main\nEOF'
        $'cat <<EOF | env bash\ngit push origin main\nEOF'
        $'cat <<EOF | env -S "bash"\ngit push origin main\nEOF'
        $'tee /tmp/run.sh >/dev/null <<\'EOF\'\ngit push origin main\nEOF\nbash /tmp/run.sh'
        $'cat <<EOF > >(bash)\ngit push origin main\nEOF'
        "echo git push origin main > >(bash)"
        $'cat <<EOF 1> >(sh)\ngit commit -m test\nEOF'
        $'cat <<EOF\n$(git push origin main)\nEOF'
    )
    local failures=""
    local command
    local output

    for command in "${commands[@]}"; do
        output=$(run_json_hook "$(payload_for_command "$command")" "$PRETOOL_SCRIPT")
        if ! echo "$output" | grep -q '"decision":"block"'; then
            failures="${failures} [$command => $output]"
        fi
    done

    if [ -z "$failures" ]; then
        pass "pre-tool hook blocks git commit/push after shell prefixes"
    else
        fail "pre-tool hook allowed shell-prefix git commands:$failures"
    fi
}

test_pretool_allows_safe_command() {
    local output
    output=$(run_json_hook '{"tool_input":{"command":"git diff"}}' "$PRETOOL_SCRIPT")
    if [ -z "$output" ]; then
        pass "pre-tool hook allows safe commands"
    else
        fail "pre-tool hook unexpectedly blocked safe command (output: $output)"
    fi
}

test_pretool_reads_command_field() {
    local output
    output=$(run_json_hook '{"tool_input":{"command":"echo hello","file_path":"git commit -m test"}}' "$PRETOOL_SCRIPT")
    if [ -z "$output" ]; then
        pass "pre-tool hook reads tool_input.command"
    else
        fail "pre-tool hook incorrectly read file_path"
    fi
}

test_pretool_allows_non_git_command_mentions() {
    local issue_command
    local helper_echo_command
    local print_command
    local quoted_heredoc_command
    local git_global_help_command
    local git_help_command
    local git_push_help_command
    local git_alias_push_help_command
    local git_alias_commit_help_command
    local git_help_command_substitution
    local git_push_help_command_substitution
    local git_push_late_help_command
    local git_commit_late_help_command
    local git_lfs_push_help_command
    local git_subtree_push_help_command
    local quoted_python_heredoc_command
    local safe_process_substitution_after_shell_command
    local safe_process_substitution_inside_shell_payload
    local output1
    local output2
    local output3
    local output4
    local output5
    local output6
    local output7
    local output8
    local output9
    local output10
    local output11
    local output12
    local output13
    local output14
    local output15
    local output16
    local output17
    local output18
    local output19

    issue_command=$'gh issue create --title bug --body "$(cat <<EOF\ngit commit -m test should not block here\nEOF\n)"'
    helper_echo_command="find . -exec echo git push origin main \\;"
    print_command="printf %s git push origin main"
    quoted_heredoc_command=$'cat <<\'EOF\'\n$(git push origin main)\nEOF'
    git_global_help_command="git --help push"
    git_help_command="git help push"
    git_push_help_command="git push --help"
    git_alias_push_help_command="git -c alias.p=push p --help"
    git_alias_commit_help_command="git -c alias.c=commit c -h"
    git_help_command_substitution='bash -c "$(git help push)"'
    git_push_help_command_substitution='eval "$(git push --help)"'
    git_push_late_help_command="git push origin --help"
    git_commit_late_help_command="git commit -m test --help"
    git_lfs_push_help_command="git lfs push --help"
    git_lfs_global_help_command="git lfs --help push"
    git_subtree_push_help_command="git subtree push --help"
    quoted_python_heredoc_command=$'python <<\'EOF\'\n$(git push origin main)\nEOF'
    safe_process_substitution_after_shell_command='bash -c "true"; cat <(echo git push origin main)'
    safe_process_substitution_inside_shell_payload='bash -c "cat <(echo git push origin main)"'
    output1=$(run_json_hook "$(payload_for_command "$issue_command")" "$PRETOOL_SCRIPT")
    output2=$(run_json_hook "$(payload_for_command "$print_command")" "$PRETOOL_SCRIPT")
    output3=$(run_json_hook "$(payload_for_command "$helper_echo_command")" "$PRETOOL_SCRIPT")
    output4=$(run_json_hook "$(payload_for_command "$quoted_heredoc_command")" "$PRETOOL_SCRIPT")
    output5=$(run_json_hook "$(payload_for_command "$git_global_help_command")" "$PRETOOL_SCRIPT")
    output6=$(run_json_hook "$(payload_for_command "$git_help_command")" "$PRETOOL_SCRIPT")
    output7=$(run_json_hook "$(payload_for_command "$git_push_help_command")" "$PRETOOL_SCRIPT")
    output8=$(run_json_hook "$(payload_for_command "$quoted_python_heredoc_command")" "$PRETOOL_SCRIPT")
    output9=$(run_json_hook "$(payload_for_command "$git_alias_push_help_command")" "$PRETOOL_SCRIPT")
    output10=$(run_json_hook "$(payload_for_command "$git_alias_commit_help_command")" "$PRETOOL_SCRIPT")
    output11=$(run_json_hook "$(payload_for_command "$git_help_command_substitution")" "$PRETOOL_SCRIPT")
    output12=$(run_json_hook "$(payload_for_command "$git_push_help_command_substitution")" "$PRETOOL_SCRIPT")
    output13=$(run_json_hook "$(payload_for_command "$git_push_late_help_command")" "$PRETOOL_SCRIPT")
    output14=$(run_json_hook "$(payload_for_command "$git_commit_late_help_command")" "$PRETOOL_SCRIPT")
    output15=$(run_json_hook "$(payload_for_command "$git_lfs_push_help_command")" "$PRETOOL_SCRIPT")
    output16=$(run_json_hook "$(payload_for_command "$git_subtree_push_help_command")" "$PRETOOL_SCRIPT")
    output17=$(run_json_hook "$(payload_for_command "$git_lfs_global_help_command")" "$PRETOOL_SCRIPT")
    output18=$(run_json_hook "$(payload_for_command "$safe_process_substitution_after_shell_command")" "$PRETOOL_SCRIPT")
    output19=$(run_json_hook "$(payload_for_command "$safe_process_substitution_inside_shell_payload")" "$PRETOOL_SCRIPT")

    if [ -z "$output1$output2$output3$output4$output5$output6$output7$output8$output9$output10$output11$output12$output13$output14$output15$output16$output17$output18$output19" ]; then
        pass "pre-tool hook allows non-git commands that mention git commit/push"
    else
        fail "pre-tool hook blocked non-git command text (output1: $output1 output2: $output2 output3: $output3 output4: $output4 output5: $output5 output6: $output6 output7: $output7 output8: $output8 output9: $output9 output10: $output10 output11: $output11 output12: $output12 output13: $output13 output14: $output14 output15: $output15 output16: $output16 output17: $output17 output18: $output18 output19: $output19)"
    fi
}

test_pretool_does_not_crash_on_non_git_prototype_words() {
    if run_hook_status "$(payload_for_command "toString -x git push origin main")" "$PRETOOL_SCRIPT" \
        && run_hook_status "$(payload_for_command "echo \$'\\UFFFFFFFF'")" "$PRETOOL_SCRIPT"; then
        pass "pre-tool hook does not crash on non-git prototype words"
    else
        fail "pre-tool hook crashed on non-git prototype words"
    fi
}

test_pretool_blocks_deep_wrapper_recursion() {
    local command
    local output
    command=$(deep_nested_eval_command)
    output=$(run_json_hook "$(payload_for_command "$command")" "$PRETOOL_SCRIPT")

    if echo "$output" | grep -q '"decision":"block"'; then
        pass "pre-tool hook blocks deep wrapper recursion"
    else
        fail "pre-tool hook allowed deep wrapper recursion (output: $output)"
    fi
}

test_session_warns_missing() {
    local tmpdir
    tmpdir=$(mktemp -d)
    local output
    output=$(run_session_hook "$tmpdir" "$SESSION_SCRIPT")
    rm -rf "$tmpdir"
    if echo "$output" | grep -q '"additionalContext"'; then
        pass "session hook warns when AGENTS.md is missing"
    else
        fail "session hook did not warn when AGENTS.md was missing"
    fi
}

test_session_silent_when_present() {
    local tmpdir
    tmpdir=$(mktemp -d)
    touch "$tmpdir/AGENTS.md"
    local output
    output=$(run_session_hook "$tmpdir" "$SESSION_SCRIPT")
    rm -rf "$tmpdir"
    if [ -z "$output" ]; then
        pass "session hook is silent when AGENTS.md exists"
    else
        fail "session hook produced output when AGENTS.md exists"
    fi
}

test_universal_pretool_blocks_commit() {
    local output
    output=$(run_node_json_hook '{"tool_input":{"command":"git commit -m '\''test'\''"}}' "$UNIVERSAL_PRETOOL_SCRIPT")
    if echo "$output" | grep -q '"decision":"block"'; then
        pass "universal pre-tool hook blocks git commit"
    else
        fail "universal pre-tool hook did not block git commit (output: $output)"
    fi
}

test_universal_pretool_blocks_git_after_shell_prefixes() {
    local commands=(
        "npm test && git commit -m test"
        "cd repo; git push origin main"
        "AFTERHOURS_SKIP=1 git push origin main"
        "A[0]=x git push origin main"
        "A[0]+=x git commit -m test"
        "npm test & git push origin main"
        "(git commit -m test)"
        "sudo git commit -m test"
        "if git push origin main; then echo ok; fi"
        "for x in y; do git commit -m test; done"
        $'npm test\ngit push origin main'
        "env -u FOO git push origin main"
        'env -iS "git push origin main"'
        'env -iu FOO -S "git push origin main"'
        "sudo -u root git commit -m test"
        "sudo -HEu root git push origin main"
        "sudo -u >out root git commit -m test"
        "sudo -r sysadm_r git push origin main"
        "sudo -t sysadm_t git commit -m test"
        "sudo --role sysadm_r git push origin main"
        "sudo --type sysadm_t git commit -m test"
        'sudo -Eu root bash -c "git push origin main"'
        "if false; then :; else git push origin main; fi"
        "elif git push origin main; then echo ok; fi"
        "{ git push origin main; }"
        "FOO+=bar git commit -m test"
        ">/tmp/out git push origin main"
        "2>err git commit -m test"
        "git push>/tmp/out origin main"
        "git commit>/tmp/out -m test"
        "git push origin main # --help"
        "git commit -m test # --help"
        "git push -- --help"
        "git push origin -- --help"
        "git commit -- --help"
        "git commit -m --help"
        "git commit -F --help"
        "git commit --message --help"
        "git push origin --receive-pack --help main"
        "git push origin --repo --help main"
        "git>/tmp/out push origin main"
        "git</tmp/in commit -F -"
        "git push&>/tmp/out"
        'git --exec-path "$(git --exec-path)" push'
        'echo "$( git push origin main)"'
        "nice git push origin main"
        "nice -n 10 git commit -m test"
        "stdbuf -oL git push origin main"
        "unbuffer git push origin main"
        "arch -x86_64 git push origin main"
        "script -q /dev/null git push origin main"
        "script -c 'git push origin main' /dev/null"
        'script --command "git commit -m test" /dev/null'
        "ssh-agent git push origin main"
        "ssh-agent bash -c 'git commit -m test'"
        'su -c "git push origin main"'
        "su --session-command 'git push origin main'"
        "su --session-command='git commit -m test'"
        "doas git push origin main"
        "chrt -r 1 git push origin main"
        "taskset -c 0 git push origin main"
        "ionice -c2 git push origin main"
        $'npm test && \\\n git push origin main'
        $'git \\\n push origin main'
        "2>&1 git push origin main"
        ">&2 git commit -m test"
        "git >& 2 push origin main"
        "git 2>& 1 commit -m test"
        "env -S git push origin main"
        'env -S "git commit -m test"'
        'env -S "-- git push origin main"'
        'env -S "-i git push origin main"'
        'env -S "--ignore-environment git push origin main"'
        'env -S "-u FOO git push origin main"'
        'env -S "-C /tmp git push origin main"'
        "env -P /usr/bin git push origin main"
        "env -a fake git push origin main"
        "env --argv0 fake git commit -m test"
        "env -u >out FOO git push origin main"
        "env -P >out /usr/bin git push origin main"
        "exec -a git git push origin main"
        "noglob git push origin main"
        "noglob git commit -m test"
        'eval "git push origin main"'
        'eval -- "git push origin main"'
        'bash -c "git push origin main"'
        'bash -c -- "git push origin main"'
        "cmd /c git push origin main"
        "CMD /C git push origin main"
        "cmd /c call git push origin main"
        "cmd /c CALL git commit -m test"
        "cmd /c start git push origin main"
        'cmd /c start "title" git push origin main'
        'cmd /c start /b "title" git commit -m test'
        "cmd.exe /c git commit -m test"
        'powershell -Command "git push origin main"'
        'PowerShell -Command "git push origin main"'
        'powershell -Command "start git push origin main"'
        'powershell -Command "Start-Process git -ArgumentList push,origin,main"'
        "powershell -EncodedCommand ZwBpAHQAIABwAHUAcwBoACAAbwByAGkAZwBpAG4AIABtAGEAaQBuAA=="
        "pwsh -e ZwBpAHQAIABjAG8AbQBtAGkAdAAgAC0AbQAgAHQAZQBzAHQA"
        'powershell.exe -NoProfile -Command "git commit -m test"'
        'pwsh -c "git push origin main"'
        'PwSh -c "git commit -m test"'
        'zsh --emulate sh -c "git push origin main"'
        'fish --command="git push origin main"'
        'fish --init-command="git push origin main"'
        'fish -C "git push origin main"'
        'sh -c -- "git commit -m test"'
        "sh -c 'git \"\$@\"' sh push origin main"
        "bash -c 'exec git \"\${@}\"' bash push origin main"
        "bash -c 'sh -c \"\$*\"' bash git push origin main"
        "bash -c 'exec git \"\$@\"' bash push origin main"
        "bash -c 'git \"\$1\" origin main' bash push"
        "bash -c 'git \"\${@:1:1}\" origin main' bash push"
        "bash -c 'git \"\${*:1:1}\" origin main' bash push"
        "trap 'git push origin main' EXIT"
        "bash -c 'trap \"git push origin main\" EXIT'"
        'bash -c '\''eval -- "git push origin main"'\'''
        'bash -c >out "git push origin main"'
        'bash -O >out extglob -c "git push origin main"'
        "case main in main) git push origin main;; esac"
        "case main in main) git commit -m test;; esac"
        "git >/tmp/out push origin main"
        "git 2>err commit -m test"
        "git -C >out repo push origin main"
        "git --git-dir >out .git push origin main"
        'git -c >out alias.p=push p'
        $'# <<EOF\ngit push origin main'
        $'# <<\'EOF\'\ngit push origin main\nEOF'
        $'# cat <<EOF\ngit commit -m test\nEOF'
        $'cat <<EOF # <<NEVER\nsafe\nEOF\ngit push origin main'
        $'bash <<EOF\ngit push origin main\nEOF'
        $'sh <<EOF\ngit commit -m test\nEOF'
        $'bash <<\'EOF\'\ngit push origin main\nEOF'
        $'cat <<\\EOF\nsafe\nEOF\ngit push origin main'
        $'cat <<EOF > /tmp/run.sh\ngit push origin main\nEOF\nbash /tmp/run.sh'
        $'cat <<\'EOF\' >/tmp/run.sh\ngit commit -m test\nEOF\nsh /tmp/run.sh'
        $'cat <<EOF > /tmp/run.sh\ngit push origin main\nEOF\n. /tmp/run.sh'
        $'cat <<EOF > /tmp/run.sh\ngit commit -m test\nEOF\nsource /tmp/run.sh'
        $'cat <<EOF &> /tmp/run.sh\ngit push origin main\nEOF\nbash /tmp/run.sh'
        $'cat <<EOF &>> /tmp/run.sh\ngit commit -m test\nEOF\nsh /tmp/run.sh'
        $'cat <<EOF > run.sh\ngit push origin main\nEOF\nbash ./run.sh'
        $'cat <<\'E\\OF\' > run.sh\ngit push origin main\nE\\OF\nbash ./run.sh'
        $'cat <<EOF > run.sh && chmod +x run.sh\ngit push origin main\nEOF\nbash ./run.sh'
        $'cat > run.sh <<EOF\ngit commit -m test\nEOF\nchmod +x run.sh && ./run.sh'
        $'cat > run.sh <<EOF && chmod +x run.sh && ./run.sh\ngit push origin main\nEOF'
        $'cat > run.sh <<\'EOF\'\ngit "$@"\nEOF\nbash run.sh push origin main'
        $'cat > run.sh <<\'EOF\'\ngit "$1" origin main\nEOF\nbash run.sh push'
        $'cat > run.sh <<EOF\ngit push origin main\nEOF\nbash < run.sh'
        $'cat > run.sh <<EOF\ngit commit -m test\nEOF\nsh 0< run.sh'
        "echo git push origin main > run.sh && bash run.sh"
        "printf 'git commit -m test\n' > run.sh && sh run.sh"
        "printf 'git push origin main\n' | tee run.sh >/dev/null && bash run.sh"
        $'cat <<EOF | tee run.sh >/dev/null\ngit push origin main\nEOF\nbash run.sh'
        $'tee >/dev/null run.sh <<\'EOF\'\ngit commit -m test\nEOF\nsh run.sh'
        $'tee >/tmp/run.sh <<EOF\ngit push origin main\nEOF\nbash /tmp/run.sh'
        $'tee > /tmp/run.sh <<EOF\ngit commit -m test\nEOF\nsh /tmp/run.sh'
        $'cat <<END-OF >/dev/null\nsafe\nEND-OF\ngit push origin main'
        "timeout 30 git push origin main"
        "timeout 30 git commit -m test"
        "flock /tmp/codex-sdlc-test.lock git push origin main"
        "flock -n /tmp/codex-sdlc-test.lock git commit -m test"
        "/usr/bin/env git push origin main"
        "/bin/env git commit -m test"
        "/usr/bin/sudo git push origin main"
        "runuser -u root -- git push origin main"
        "runuser --user root -- git commit -m test"
        "/usr/bin/nohup git push origin main"
        "/usr/bin/time git push origin main"
        "/usr/bin/timeout 30 git commit -m test"
        "/usr/bin/nice git push origin main"
        "/usr/bin/git push origin main"
        "Git.exe push origin main"
        "git.exe push origin main"
        "git.exe commit -m test"
        "/mingw64/bin/git.exe commit -m test"
        '"C:/Program Files/Git/cmd/git.exe" push origin main'
        "find . -exec git push origin main \\;"
        "find . -exec /usr/bin/git commit -m test \\;"
        "find . -exec sh -c 'git push origin main' \\;"
        "xargs git push origin main"
        "xargs -i git push {}"
        "xargs --replace git commit -m test"
        "xargs -e git push origin main"
        "xargs --eof git push origin main"
        "xargs git <<< push"
        "xargs -I{} git {} <<< push"
        "watch git push origin main"
        "watch -x git push origin main"
        "watch --exec git push origin main"
        "watch --no-title git commit -m test"
        "parallel git push ::: origin main"
        "parallel -k git push ::: origin main"
        "parallel --keep-order git push ::: origin main"
        "parallel --results out git push ::: origin main"
        "parallel --tagstring tag git push ::: origin main"
        "parallel -C , git push ::: origin main"
        "parallel --colsep , git commit -m test ::: x"
        "parallel -u git commit -m test ::: x"
        "parallel git ::: push"
        "parallel git {} ::: push"
        "git submodule foreach git push origin main"
        "git submodule foreach git commit -m test"
        "git -C repo submodule foreach git push origin main"
        "git submodule foreach 'git push origin main'"
        "git lfs push origin main"
        "git lfs push origin main # --help"
        "git lfs -c lfs.dialtimeout=1 push origin main"
        "git subtree push --prefix dist origin gh-pages"
        "git subtree push --prefix dist origin gh-pages # --help"
        "git subtree --prefix dist push origin gh-pages"
        'git -c alias.p="!git push origin main" p'
        "git -c alias.p='!git \"\$1\" origin main' p push"
        'git -c alias.c="!git commit -m test" c'
        "git -c alias.p='!\$@' p git push origin main"
        "git -c alias.p='!sh -c \"\$@\"' p git push origin main"
        "git -c alias.p='!eval \"\$@\"' p 'git push origin main'"
        "git -c alias.p='!git \"\${@}\"' p push origin main"
        "git -c alias.p='!trap \"git push origin main\" EXIT' p"
        "ALIAS=push git --config-env=alias.p=ALIAS p origin main"
        "ALIAS=commit git --config-env=alias.c=ALIAS c -m test"
        "git -c alias.p='!f() { git \"\$@\"; }; f' p push origin main"
        "git -c alias.p='!f() { exec git \"\$@\"; }; f' p push origin main"
        'git -c alias.p=push p'
        'git -c alias.c=commit c'
        'git -c alias.p="push origin main" p'
        'git -c alias.p=push -c alias.q=p q origin main'
        'git -c alias.c=commit -c alias.q=c q -m test'
        'git -c alias.p="!git push origin main" p -h'
        'git -c alias.c="!git commit -m test" c -h'
        '/usr/bin/env -S "git push origin main"'
        'sudo /usr/bin/env -S "git push origin main"'
        'sudo bash -c "git push origin main"'
        'sudo eval "git push origin main"'
        'eval "$(echo git push origin main)"'
        $'eval "$(cat <<\'EOF\'\ngit push origin main\nEOF\n)"'
        'bash -c "$(echo git push origin main)"'
        '$(echo -e git\\x20push) origin main'
        '$(echo git; echo push) origin main'
        'eval "$(echo -e git\\x20push origin main)"'
        'bash -c "$(echo -e git\\x20push origin main)"'
        "zsh -c 'nocorrect git push origin main'"
        '$(echo git push origin main)'
        '$(printf "git\x20push") origin main'
        $'$(cat <<EOF\ngit push origin main\nEOF\n)'
        '$(echo git) push origin main'
        '$(printf %s git) commit -m test'
        'g$(printf it) push origin main'
        'g$(echo it) com$(printf mit) -m test'
        'git p$(printf ush) origin main'
        'git pu$(echo sh) origin main'
        'git com$(printf mit) -m test'
        'git "$(printf push)" origin main'
        'git p`printf ush` origin main'
        'g`printf it` push origin main'
        'bash -c "$(echo git) push origin main"'
        'eval "$(echo git) commit -m test"'
        'eval "$(printf '\''%q '\'' git push origin main)"'
        "bash -c \"\$(printf git; printf ' push origin main')\""
        "eval \"\$(echo -n git; echo ' commit -m test')\""
        "bash -c \"\$(printf 'git push origin main' | cat)\""
        "eval \"\$(printf 'git commit -m test' | tee /dev/null)\""
        "printf -- 'git push origin main\n' | bash"
        "printf -- 'push\n' | xargs git"
        "printf 'push\\0' | xargs -0 git"
        "printf 'push,' | xargs -d, git"
        '`echo git commit -m test`'
        'echo "$(case x in x) echo ok;; esac; git push origin main)"'
        'echo "$( (echo ok); git push origin main )"'
        'bash -c "$( (echo echo ok); echo git push origin main )"'
        $'bash -c "$(cat <<EOF\ngit push origin main\nEOF\n)"'
        $'sh -c "$(cat <<EOF\ngit commit -m test\nEOF\n)"'
        "function f { git push origin main; }; f"
        'function f() { git "$@"; }; f push origin main'
        'f() { git "$@"; }; f push origin main'
        'f() { command git "$@"; }; f push origin main'
        'f() { git "$1" origin main; }; f push'
        "coproc git push origin main"
        "setsid git push origin main"
        'bash >out -c "git push origin main"'
        'bash -O extglob -c "git push origin main"'
        "eval \$'git push origin main'"
        "eval \$'git\\x20push origin main'"
        "bash -c \$'git push origin main'"
        "bash -c \$'git\\040commit -m test'"
        "printf 'git push origin main\n' | bash"
        "printf 'git push origin main\n' |& bash"
        "echo git push origin main |& sh"
        "echo -e \"git\\x20push origin main\" | bash"
        "printf \"git\\x20push origin main\n\" | bash"
        "printf 'git push origin main\n' | cat | bash"
        "printf 'git push origin main\n' | tee /dev/null | bash"
        "printf 'git push origin main\n' | env -S \"bash -s\""
        $'cat <<EOF | xargs -I{} sh -c \'{}\'\ngit push origin main\nEOF'
        "printf 'git push origin main\n' | xargs -I{} sh -c '{}'"
        "printf 'git push origin main\n' | xargs -I{} bash -c '{}'"
        "echo git push origin main | xargs -I{} sh -c '{}'"
        $'echo ok\nxargs git <<EOF\npush\nEOF'
        $'echo ok\ncat <<EOF | xargs git\npush\nEOF'
        "parallel ::: 'git push origin main'"
        "parallel --jobs 1 ::: 'git commit -m test'"
        "flock -n -c 'git push origin main' /tmp/lock"
        "flock --command='git commit -m test' /tmp/lock"
        "su -c'git push origin main'"
        "script -c'git commit -m test' /dev/null"
        "echo git push origin main | tee >(bash)"
        "printf 'git push origin main\n' | tee >(bash)"
        "printf 'git push origin main\n' | cat > >(bash)"
        "cat > >(bash) <<< 'git push origin main'"
        "tee >(bash) <<< 'git push origin main'"
        "printf 'git push origin main\n' 2>&1 > >(bash)"
        "printf 'git push origin main\n' >| >(bash)"
        "printf 'git push origin main\n' | bash -c 'bash'"
        "bash -c 'source /dev/stdin' <<< 'git commit -m test'"
        "printf '%s ' git push origin main | bash"
        "printf 'git commit -m test\n' | sh"
        "printf '%s\n' 'git push origin main' | bash"
        "printf '%s %s %s %s\n' git commit -m test | sh"
        "echo git push origin main | bash"
        "echo git push origin main | sh -s -- arg"
        "printf '%s\n' 'git commit -m test' | bash -s arg"
        "bash <<< 'git push origin main'"
        'bash <<<$(echo git push origin main)'
        "env -S \"bash -s\" <<< 'git commit -m test'"
        "sh <<< \$'git commit -m test'"
        "<<< 'git push origin main' cat | bash"
        "bash -s arg <<< 'git push origin main'"
        "sh -s -- arg <<< \$'git commit -m test'"
        "bash /dev/fd/3 3<<< 'git push origin main'"
        "source /dev/fd/7 7<<< 'git commit -m test'"
        "bash <(echo git push origin main)"
        "bash <> <(echo git push origin main)"
        "bash 0<> <(echo git push origin main)"
        "sh <(printf 'git commit -m test\n')"
        "bash <(printf 'git push origin main\n' | cat)"
        "source <(printf 'git commit -m test\n' | tee /dev/null)"
        "bash < <(echo git push origin main)"
        "source <(echo git push origin main)"
        ". <(echo git commit -m test)"
        "/opt/homebrew/bin/bash <(echo git push origin main)"
        "env /usr/local/bin/bash <(echo git push origin main)"
        "sudo -u root bash <(echo git push origin main)"
        "env -u FOO bash <(echo git push origin main)"
        "env -P /usr/bin bash <(echo git push origin main)"
        "time -f %e bash <(echo git push origin main)"
        "cat <(git push origin main)"
        "cat <( git push origin main )"
        "cat >(git commit -m test)"
        "diff <(echo ok) <(git push origin main)"
        "echo \`git push origin main\`"
        "echo \` git push origin main\`"
        $'cat <<EOF | bash\ngit push origin main\nEOF'
        $'cat <<EOF | sh\ngit commit -m test\nEOF'
        $'cat <<EOF | /usr/bin/sudo /bin/bash\ngit push origin main\nEOF'
        $'cat <<EOF | env bash\ngit push origin main\nEOF'
        $'cat <<EOF | env -S "bash"\ngit push origin main\nEOF'
        $'tee /tmp/run.sh >/dev/null <<\'EOF\'\ngit push origin main\nEOF\nbash /tmp/run.sh'
        $'cat <<EOF > >(bash)\ngit push origin main\nEOF'
        "echo git push origin main > >(bash)"
        $'cat <<EOF 1> >(sh)\ngit commit -m test\nEOF'
        $'cat <<EOF\n$(git push origin main)\nEOF'
    )
    local failures=""
    local command
    local output

    for command in "${commands[@]}"; do
        output=$(run_node_json_hook "$(payload_for_command "$command")" "$UNIVERSAL_PRETOOL_SCRIPT")
        if ! echo "$output" | grep -q '"decision":"block"'; then
            failures="${failures} [$command => $output]"
        fi
    done

    if [ -z "$failures" ]; then
        pass "universal pre-tool hook blocks git commit/push after shell prefixes"
    else
        fail "universal pre-tool hook allowed shell-prefix git commands:$failures"
    fi
}

test_universal_pretool_allows_non_git_command_mentions() {
    local issue_command
    local helper_echo_command
    local print_command
    local quoted_heredoc_command
    local git_global_help_command
    local git_help_command
    local git_push_help_command
    local git_alias_push_help_command
    local git_alias_commit_help_command
    local git_help_command_substitution
    local git_push_help_command_substitution
    local git_push_late_help_command
    local git_commit_late_help_command
    local git_lfs_push_help_command
    local git_subtree_push_help_command
    local quoted_python_heredoc_command
    local safe_process_substitution_after_shell_command
    local safe_process_substitution_inside_shell_payload
    local output1
    local output2
    local output3
    local output4
    local output5
    local output6
    local output7
    local output8
    local output9
    local output10
    local output11
    local output12
    local output13
    local output14
    local output15
    local output16
    local output17
    local output18
    local output19

    issue_command=$'gh issue create --title bug --body "$(cat <<EOF\ngit commit -m test should not block here\nEOF\n)"'
    helper_echo_command="find . -exec echo git push origin main \\;"
    print_command="printf %s git push origin main"
    quoted_heredoc_command=$'cat <<\'EOF\'\n$(git push origin main)\nEOF'
    git_global_help_command="git --help push"
    git_help_command="git help push"
    git_push_help_command="git push --help"
    git_alias_push_help_command="git -c alias.p=push p --help"
    git_alias_commit_help_command="git -c alias.c=commit c -h"
    git_help_command_substitution='bash -c "$(git help push)"'
    git_push_help_command_substitution='eval "$(git push --help)"'
    git_push_late_help_command="git push origin --help"
    git_commit_late_help_command="git commit -m test --help"
    git_lfs_push_help_command="git lfs push --help"
    git_lfs_global_help_command="git lfs --help push"
    git_subtree_push_help_command="git subtree push --help"
    quoted_python_heredoc_command=$'python <<\'EOF\'\n$(git push origin main)\nEOF'
    safe_process_substitution_after_shell_command='bash -c "true"; cat <(echo git push origin main)'
    safe_process_substitution_inside_shell_payload='bash -c "cat <(echo git push origin main)"'
    output1=$(run_node_json_hook "$(payload_for_command "$issue_command")" "$UNIVERSAL_PRETOOL_SCRIPT")
    output2=$(run_node_json_hook "$(payload_for_command "$print_command")" "$UNIVERSAL_PRETOOL_SCRIPT")
    output3=$(run_node_json_hook "$(payload_for_command "$helper_echo_command")" "$UNIVERSAL_PRETOOL_SCRIPT")
    output4=$(run_node_json_hook "$(payload_for_command "$quoted_heredoc_command")" "$UNIVERSAL_PRETOOL_SCRIPT")
    output5=$(run_node_json_hook "$(payload_for_command "$git_global_help_command")" "$UNIVERSAL_PRETOOL_SCRIPT")
    output6=$(run_node_json_hook "$(payload_for_command "$git_help_command")" "$UNIVERSAL_PRETOOL_SCRIPT")
    output7=$(run_node_json_hook "$(payload_for_command "$git_push_help_command")" "$UNIVERSAL_PRETOOL_SCRIPT")
    output8=$(run_node_json_hook "$(payload_for_command "$quoted_python_heredoc_command")" "$UNIVERSAL_PRETOOL_SCRIPT")
    output9=$(run_node_json_hook "$(payload_for_command "$git_alias_push_help_command")" "$UNIVERSAL_PRETOOL_SCRIPT")
    output10=$(run_node_json_hook "$(payload_for_command "$git_alias_commit_help_command")" "$UNIVERSAL_PRETOOL_SCRIPT")
    output11=$(run_node_json_hook "$(payload_for_command "$git_help_command_substitution")" "$UNIVERSAL_PRETOOL_SCRIPT")
    output12=$(run_node_json_hook "$(payload_for_command "$git_push_help_command_substitution")" "$UNIVERSAL_PRETOOL_SCRIPT")
    output13=$(run_node_json_hook "$(payload_for_command "$git_push_late_help_command")" "$UNIVERSAL_PRETOOL_SCRIPT")
    output14=$(run_node_json_hook "$(payload_for_command "$git_commit_late_help_command")" "$UNIVERSAL_PRETOOL_SCRIPT")
    output15=$(run_node_json_hook "$(payload_for_command "$git_lfs_push_help_command")" "$UNIVERSAL_PRETOOL_SCRIPT")
    output16=$(run_node_json_hook "$(payload_for_command "$git_subtree_push_help_command")" "$UNIVERSAL_PRETOOL_SCRIPT")
    output17=$(run_node_json_hook "$(payload_for_command "$git_lfs_global_help_command")" "$UNIVERSAL_PRETOOL_SCRIPT")
    output18=$(run_node_json_hook "$(payload_for_command "$safe_process_substitution_after_shell_command")" "$UNIVERSAL_PRETOOL_SCRIPT")
    output19=$(run_node_json_hook "$(payload_for_command "$safe_process_substitution_inside_shell_payload")" "$UNIVERSAL_PRETOOL_SCRIPT")

    if [ -z "$output1$output2$output3$output4$output5$output6$output7$output8$output9$output10$output11$output12$output13$output14$output15$output16$output17$output18$output19" ]; then
        pass "universal pre-tool hook allows non-git commands that mention git commit/push"
    else
        fail "universal pre-tool hook blocked non-git command text (output1: $output1 output2: $output2 output3: $output3 output4: $output4 output5: $output5 output6: $output6 output7: $output7 output8: $output8 output9: $output9 output10: $output10 output11: $output11 output12: $output12 output13: $output13 output14: $output14 output15: $output15 output16: $output16 output17: $output17 output18: $output18 output19: $output19)"
    fi
}

test_universal_pretool_does_not_crash_on_non_git_prototype_words() {
    if run_node_hook_status "$(payload_for_command "toString -x git push origin main")" "$UNIVERSAL_PRETOOL_SCRIPT" \
        && run_node_hook_status "$(payload_for_command "echo \$'\\UFFFFFFFF'")" "$UNIVERSAL_PRETOOL_SCRIPT"; then
        pass "universal pre-tool hook does not crash on non-git prototype words"
    else
        fail "universal pre-tool hook crashed on non-git prototype words"
    fi
}

test_universal_pretool_blocks_deep_wrapper_recursion() {
    local command
    local output
    command=$(deep_nested_eval_command)
    output=$(run_node_json_hook "$(payload_for_command "$command")" "$UNIVERSAL_PRETOOL_SCRIPT")

    if echo "$output" | grep -q '"decision":"block"'; then
        pass "universal pre-tool hook blocks deep wrapper recursion"
    else
        fail "universal pre-tool hook allowed deep wrapper recursion (output: $output)"
    fi
}

test_universal_session_warns_missing() {
    local tmpdir
    tmpdir=$(mktemp -d)
    local output
    output=$(run_node_session_hook "$tmpdir" "$UNIVERSAL_SESSION_SCRIPT")
    rm -rf "$tmpdir"
    if echo "$output" | grep -q '"additionalContext"'; then
        pass "universal session hook warns when AGENTS.md is missing"
    else
        fail "universal session hook did not warn when AGENTS.md was missing"
    fi
}

test_universal_compact_guard_emits_lifecycle_context() {
    local tmpdir output

    tmpdir=$(mktemp -d)
    (
        cd "$tmpdir" || exit 1
        git init -q
        printf '%s\n' "work in progress" > app.txt
    )

    output=$(run_node_json_hook "$(payload_for_compact PreCompact auto "$tmpdir")" "$UNIVERSAL_COMPACT_SCRIPT")
    rm -rf "$tmpdir"

    if echo "$output" | grep -q '"continue":true' \
        && echo "$output" | grep -q 'systemMessage' \
        && echo "$output" | grep -q 'SDLC compact guard' \
        && echo "$output" | grep -q 'dirty worktree'; then
        pass "universal compact guard emits SDLC lifecycle context before compaction"
    else
        fail "universal compact guard did not emit expected PreCompact context (output: $output)"
    fi
}

test_universal_compact_guard_handles_post_compact() {
    local tmpdir output

    tmpdir=$(mktemp -d)
    output=$(run_node_json_hook "$(payload_for_compact PostCompact manual "$tmpdir")" "$UNIVERSAL_COMPACT_SCRIPT")
    rm -rf "$tmpdir"

    if echo "$output" | grep -q '"continue":true' \
        && echo "$output" | grep -q 'PostCompact' \
        && echo "$output" | grep -q 'reread'; then
        pass "universal compact guard emits post-compact recovery context"
    else
        fail "universal compact guard did not emit expected PostCompact context (output: $output)"
    fi
}

test_universal_node_hooks_work_in_type_module_repos() {
    local tmpdir
    local session_command
    local pretool_command
    local session_output
    local pretool_output
    local all_passed=true

    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.codex/hooks"
    cp "$ACTIVE_HOOKS_FILE" "$tmpdir/.codex/hooks.json"
    cp "$HOOKS_DIR"/git-guard.* "$tmpdir/.codex/hooks/" 2>/dev/null || true
    cp "$HOOKS_DIR"/session-start.* "$tmpdir/.codex/hooks/" 2>/dev/null || true
    cp "$HOOKS_DIR"/compact-guard.* "$tmpdir/.codex/hooks/" 2>/dev/null || true
    printf '%s\n' '{"type":"module"}' > "$tmpdir/package.json"

    session_command=$(node -e 'const config = require(process.argv[1]); process.stdout.write(config.hooks.SessionStart[0].hooks[0].command);' "$tmpdir/.codex/hooks.json")
    pretool_command=$(node -e 'const config = require(process.argv[1]); process.stdout.write(config.hooks.PreToolUse[0].hooks[0].command);' "$tmpdir/.codex/hooks.json")
    compact_command=$(node -e 'const config = require(process.argv[1]); process.stdout.write(config.hooks.PreCompact[0].hooks[0].command);' "$tmpdir/.codex/hooks.json")

    echo "$session_command" | grep -q '\.cjs' || all_passed=false
    echo "$pretool_command" | grep -q '\.cjs' || all_passed=false
    echo "$compact_command" | grep -q '\.cjs' || all_passed=false

    session_output=$(cd "$tmpdir" && sh -c "$session_command" 2>&1) || all_passed=false
    pretool_output=$(cd "$tmpdir" && printf '%s' '{"tool_input":{"command":"git commit -m test"}}' | sh -c "$pretool_command" 2>&1) || all_passed=false
    compact_output=$(cd "$tmpdir" && printf '%s' "$(payload_for_compact PreCompact auto "$tmpdir")" | sh -c "$compact_command" 2>&1) || all_passed=false

    echo "$session_output" | grep -q '"additionalContext"' || all_passed=false
    echo "$pretool_output" | grep -q '"decision":"block"' || all_passed=false
    echo "$compact_output" | grep -q '"continue":true' || all_passed=false
    echo "$session_output$pretool_output$compact_output" | grep -q 'require is not defined' && all_passed=false

    rm -rf "$tmpdir"

    if [ "$all_passed" = "true" ]; then
        pass "universal Node hooks work in type=module repos"
    else
        fail "universal Node hooks fail in type=module repos"
    fi
}

test_hooks_json_matcher() {
    local matcher
    matcher=$(grep -o '"matcher":[[:space:]]*"[^"]*"' "$HOOKS_FILE" | head -1 | sed 's/.*"matcher":[[:space:]]*"\([^"]*\)"/\1/')
    if [ "$matcher" = "^Bash\$" ]; then
        pass "hook matcher is ^Bash$"
    else
        fail "hook matcher is '$matcher'"
    fi
}

test_hooks_json_valid() {
    if grep -q '"PreToolUse"' "$HOOKS_FILE" \
        && grep -q '"SessionStart"' "$HOOKS_FILE" \
        && grep -q '"PreCompact"' "$HOOKS_FILE" \
        && grep -q '"PostCompact"' "$HOOKS_FILE" \
        && grep -q 'node \.codex/hooks/compact-guard\.cjs' "$HOOKS_FILE" \
        && ! grep -q '"PermissionRequest"' "$HOOKS_FILE" \
        && ! grep -q '"PostToolUse"' "$HOOKS_FILE" \
        && ! grep -q '"UserPromptSubmit"' "$HOOKS_FILE"; then
        pass "hook config uses the current compact lifecycle hooks without over-wiring noisy events"
    else
        fail "hook config does not match the current compact-aware quiet hook set"
    fi
}

test_live_hooks_file_uses_universal_node_hooks() {
    if grep -q 'node \.codex/hooks/git-guard\.cjs' "$ACTIVE_HOOKS_FILE" \
        && grep -q 'node \.codex/hooks/session-start\.cjs' "$ACTIVE_HOOKS_FILE" \
        && grep -q 'node \.codex/hooks/compact-guard\.cjs' "$ACTIVE_HOOKS_FILE" \
        && ! grep -q 'powershell\.exe' "$ACTIVE_HOOKS_FILE" \
        && ! grep -q 'bash-guard\.sh' "$ACTIVE_HOOKS_FILE" \
        && ! grep -q 'session-start\.sh' "$ACTIVE_HOOKS_FILE"; then
        pass "live hooks.json uses universal Node hook entrypoints"
    else
        fail "live hooks.json still uses platform-specific hook commands"
    fi
}

test_live_hooks_file_is_windows_safe() {
    if [ "$IS_WINDOWS" != "true" ]; then
        return
    fi

    if grep -q 'node \.codex/hooks/git-guard\.cjs' "$ACTIVE_HOOKS_FILE" \
        && grep -q 'node \.codex/hooks/session-start\.cjs' "$ACTIVE_HOOKS_FILE" \
        && grep -q 'node \.codex/hooks/compact-guard\.cjs' "$ACTIVE_HOOKS_FILE" \
        && ! grep -q 'powershell\.exe' "$ACTIVE_HOOKS_FILE" \
        && ! grep -q '\.sh' "$ACTIVE_HOOKS_FILE"; then
        pass "live hooks.json uses universal Node hooks on Windows"
    else
        fail "live hooks.json still points at platform-specific hooks on Windows"
    fi
}

test_config_enables_hooks() {
    if grep -q '^hooks = true' "$REPO_DIR/.codex/config.toml" 2>/dev/null \
        && ! grep -v '^[[:space:]]*#' "$REPO_DIR/.codex/config.toml" | grep -q '^codex_hooks\s*='; then
        pass "config.toml enables codex hooks with the current feature flag"
    else
        fail "config.toml missing hooks = true or still has active codex_hooks"
    fi
}

test_install_preserves_agents_md() {
    local tmpdir output
    tmpdir=$(mktemp -d)
    echo "CUSTOM AGENTS CONTENT" > "$tmpdir/AGENTS.md"
    output=$(cd "$tmpdir" && CODEX_HOME="$tmpdir/.codex-home" bash "$REPO_DIR/install.sh" 2>&1)
    local content
    content=$(cat "$tmpdir/AGENTS.md")
    rm -rf "$tmpdir"
    if [ "$content" = "CUSTOM AGENTS CONTENT" ] \
        && echo "$output" | grep -Fq 'AGENTS.md is user-owned or customized - preserving it' \
        && ! echo "$output" | grep -Fq 'AGENTS.md already exists - skipping (review manually)'; then
        pass "install.sh preserves and accurately reports customized AGENTS.md"
    else
        fail "install.sh overwrote or ambiguously reported customized AGENTS.md"
    fi
}

test_install_reports_current_agents_baseline() {
    local tmpdir output
    tmpdir=$(mktemp -d)
    sed \
        -e 's|{{MODEL_PROFILE}}|maximum|g' \
        -e 's|{{REASONING_BASELINE}}|high|g' \
        "$REPO_DIR/templates/AGENTS.baseline.md" > "$tmpdir/AGENTS.md"

    output=$(cd "$tmpdir" && CODEX_HOME="$tmpdir/.codex-home" bash "$REPO_DIR/install.sh" 2>&1)
    rm -rf "$tmpdir"

    if echo "$output" | grep -Fq 'AGENTS.md already matches the wizard baseline - keeping it' \
        && ! echo "$output" | grep -Fq 'AGENTS.md already exists - skipping (review manually)'; then
        pass "install.sh distinguishes an already-current AGENTS.md baseline"
    else
        fail "install.sh did not identify an already-current AGENTS.md baseline"
    fi
}

test_install_omits_inactive_prompt_hook() {
    local tmpdir custom_tmpdir
    tmpdir=$(mktemp -d)
    custom_tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.codex/hooks" "$custom_tmpdir/.codex/hooks"
    for target in "$tmpdir/.codex/hooks/sdlc-prompt-check.sh" "$custom_tmpdir/.codex/hooks/sdlc-prompt-check.sh"; do
        printf '%s\n' \
            '#!/bin/bash' \
            "cat << 'EOF'" \
            'SDLC BASELINE:' \
            '1. Plan before coding — state confidence level' \
            '2. TDD: Write failing test FIRST, then implement' \
            '3. ALL tests must pass before commit' \
            '4. Self-review before presenting to user' \
            'EOF' > "$target"
    done
    printf '%s\n' '# user customization' >> "$custom_tmpdir/.codex/hooks/sdlc-prompt-check.sh"

    (cd "$tmpdir" && CODEX_HOME="$tmpdir/.codex-home" bash "$REPO_DIR/install.sh" >/dev/null 2>&1)
    (cd "$custom_tmpdir" && CODEX_HOME="$custom_tmpdir/.codex-home" bash "$REPO_DIR/install.sh" >/dev/null 2>&1)

    local valid=true
    [ ! -e "$REPO_DIR/.codex/hooks/sdlc-prompt-check.sh" ] || valid=false
    [ ! -e "$tmpdir/.codex/hooks/sdlc-prompt-check.sh" ] || valid=false
    grep -Fq '# user customization' "$custom_tmpdir/.codex/hooks/sdlc-prompt-check.sh" || valid=false
    grep -Fq 'sdlc-prompt-check.sh' "$REPO_DIR/install.sh" && valid=false
    grep -Fq 'remove-retired-files.cjs' "$REPO_DIR/install.sh" || valid=false
    grep -Fq 'remove-retired-files.cjs' "$REPO_DIR/install.ps1" || valid=false
    grep -Fq 'remove-retired-files.cjs' "$REPO_DIR/update.sh" || valid=false
    rm -rf "$tmpdir" "$custom_tmpdir"

    if [ "$valid" = "true" ]; then
        pass "installers remove only the unchanged retired prompt hook"
    else
        fail "installers retained the wizard-owned prompt hook or removed a customization"
    fi
}

test_installers_share_agents_ownership_messages() {
    local valid=true
    for installer in "$REPO_DIR/install.sh" "$REPO_DIR/install.ps1"; do
        grep -Fq 'CODEX_SDLC_SETUP_GENERATED_AGENTS' "$installer" || valid=false
        grep -Fq 'AGENTS.md generated earlier in this setup - keeping it' "$installer" || valid=false
        grep -Fq 'AGENTS.md already matches the wizard baseline - keeping it' "$installer" || valid=false
        grep -Fq 'AGENTS.md is wizard-managed - keeping it; profile guidance will be refreshed if needed' "$installer" || valid=false
        grep -Fq 'AGENTS.md is user-owned or customized - preserving it' "$installer" || valid=false
    done
    grep -Fq ') -ceq $content)' "$REPO_DIR/install.ps1" || valid=false

    if [ "$valid" = "true" ]; then
        pass "shell and PowerShell installers share explicit AGENTS.md ownership messages"
    else
        fail "shell and PowerShell installers do not share AGENTS.md ownership semantics"
    fi
}

test_install_creates_sdlc_docs() {
    local tmpdir
    tmpdir=$(mktemp -d)
    (cd "$tmpdir" && CODEX_HOME="$tmpdir/.codex-home" bash "$REPO_DIR/install.sh" >/dev/null 2>&1)

    local all_present=true
    for f in "SDLC-LOOP.md" "START-SDLC.md" "PROVE-IT.md" "$EXPECTED_HELPER"; do
        if [ ! -f "$tmpdir/$f" ]; then
            all_present=false
            break
        fi
    done

    rm -rf "$tmpdir"

    if [ "$all_present" = "true" ]; then
        pass "install.sh creates the explicit SDLC docs and helper"
    else
        fail "install.sh did not create the expected SDLC docs/helper"
    fi
}

test_install_creates_skill() {
    local tmpdir
    tmpdir=$(mktemp -d)
    (cd "$tmpdir" && CODEX_HOME="$tmpdir/.codex-home" bash "$REPO_DIR/install.sh" >/dev/null 2>&1)
    local all_present=true
    for skill in "setup-wizard" "update-wizard" "feedback"; do
        if [ ! -f "$tmpdir/.codex-home/skills/$skill/SKILL.md" ]; then
            all_present=false
            break
        fi
    done
    if [ -d "$tmpdir/.codex-home/skills/sdlc" ]; then
        all_present=false
    fi
    if [ ! -f "$tmpdir/.agents/skills/sdlc/SKILL.md" ]; then
        all_present=false
    fi
    if [ -e "$tmpdir/.agents/skills/adlc/SKILL.md" ]; then
        all_present=false
    fi
    if [ -d "$tmpdir/.codex-home/skills/codex-sdlc" ]; then
        all_present=false
    fi
    if [ "$all_present" = "true" ]; then
        pass "install.sh creates global helper skills and one repo-scoped sdlc entrypoint"
    else
        fail "install.sh created duplicate global/repo sdlc skills or missed helper skills"
    fi
    rm -rf "$tmpdir"
}

test_install_keeps_skill_backups_out_of_skills_and_prunes_legacy_sdlc() {
    local tmpdir
    tmpdir=$(mktemp -d)

    mkdir -p "$tmpdir/.codex-home/skills/sdlc" "$tmpdir/.codex-home/skills/codex-sdlc"
    echo "USER OWNED" > "$tmpdir/.codex-home/skills/sdlc/marker.txt"
    echo "LEGACY" > "$tmpdir/.codex-home/skills/codex-sdlc/marker.txt"

    (cd "$tmpdir" && CODEX_HOME="$tmpdir/.codex-home" bash "$REPO_DIR/install.sh" >/dev/null 2>&1)

    local backup_count
    local leaked_backup_count
    local legacy_backup_count
    backup_count=$(find "$tmpdir/.codex-home/backups/skills" -maxdepth 1 -name 'sdlc.bak.*' 2>/dev/null | wc -l | tr -d ' ')
    legacy_backup_count=$(find "$tmpdir/.codex-home/backups/skills" -maxdepth 1 -name 'codex-sdlc.bak.*' 2>/dev/null | wc -l | tr -d ' ')
    leaked_backup_count=$(find "$tmpdir/.codex-home/skills" -maxdepth 1 \( -name 'sdlc.bak.*' -o -name 'codex-sdlc.bak.*' \) | wc -l | tr -d ' ')
    local legacy_present=false
    local user_skill_preserved=false
    [ -d "$tmpdir/.codex-home/skills/codex-sdlc" ] && legacy_present=true
    grep -q 'USER OWNED' "$tmpdir/.codex-home/skills/sdlc/marker.txt" 2>/dev/null && user_skill_preserved=true

    rm -rf "$tmpdir"

    if [ "$backup_count" = "0" ] &&
       [ "$legacy_backup_count" -ge 1 ] &&
       [ "$leaked_backup_count" = "0" ] &&
       [ "$legacy_present" = "false" ] &&
       [ "$user_skill_preserved" = "true" ]; then
        pass "install.sh preserves user-owned global sdlc and prunes legacy codex-sdlc"
    else
        fail "install.sh overwrote user-owned sdlc, leaked backups, or left legacy codex-sdlc installed"
    fi
}

test_install_merges_config() {
    local all_passed=true

    local tmpdir1
    tmpdir1=$(mktemp -d)
    mkdir -p "$tmpdir1/.codex"
    printf '[features]\ncodex_hooks = false\n' > "$tmpdir1/.codex/config.toml"
    (cd "$tmpdir1" && CODEX_HOME="$tmpdir1/.codex-home" bash "$REPO_DIR/install.sh" >/dev/null 2>&1)
    if ! grep -q '^hooks = true' "$tmpdir1/.codex/config.toml" \
        || grep -v '^[[:space:]]*#' "$tmpdir1/.codex/config.toml" | grep -q '^codex_hooks\s*='; then
        fail "install.sh case 1: did not migrate deprecated codex_hooks=false to hooks=true"
        all_passed=false
    fi
    rm -rf "$tmpdir1"

    local tmpdir2
    tmpdir2=$(mktemp -d)
    mkdir -p "$tmpdir2/.codex"
    printf '[features]\ncodex_hooks = true\n' > "$tmpdir2/.codex/config.toml"
    (cd "$tmpdir2" && CODEX_HOME="$tmpdir2/.codex-home" bash "$REPO_DIR/install.sh" >/dev/null 2>&1)
    if ! grep -q '^hooks = true' "$tmpdir2/.codex/config.toml" \
        || grep -v '^[[:space:]]*#' "$tmpdir2/.codex/config.toml" | grep -q '^codex_hooks\s*='; then
        fail "install.sh case 2: did not migrate deprecated codex_hooks=true to hooks=true"
        all_passed=false
    fi
    rm -rf "$tmpdir2"

    local tmpdir3
    tmpdir3=$(mktemp -d)
    mkdir -p "$tmpdir3/.codex"
    printf '[features]\nsome_other = true\n' > "$tmpdir3/.codex/config.toml"
    (cd "$tmpdir3" && CODEX_HOME="$tmpdir3/.codex-home" bash "$REPO_DIR/install.sh" >/dev/null 2>&1)
    if ! grep -q '^hooks = true' "$tmpdir3/.codex/config.toml"; then
        fail "install.sh case 3: did not add hooks under existing [features]"
        all_passed=false
    elif ! grep -x 'hooks = true' "$tmpdir3/.codex/config.toml" >/dev/null 2>&1; then
        fail "install.sh case 3: hooks not on its own line"
        all_passed=false
    fi
    rm -rf "$tmpdir3"

    local tmpdir4
    tmpdir4=$(mktemp -d)
    mkdir -p "$tmpdir4/.codex"
    printf '[model]\nname = "o3"\n' > "$tmpdir4/.codex/config.toml"
    (cd "$tmpdir4" && CODEX_HOME="$tmpdir4/.codex-home" bash "$REPO_DIR/install.sh" >/dev/null 2>&1)
    if ! grep -q '^hooks = true' "$tmpdir4/.codex/config.toml"; then
        fail "install.sh case 4: did not add [features] section"
        all_passed=false
    fi
    rm -rf "$tmpdir4"

    local tmpdir5
    tmpdir5=$(mktemp -d)
    mkdir -p "$tmpdir5/.codex"
    printf '[features]\n# codex_hooks = false\n' > "$tmpdir5/.codex/config.toml"
    (cd "$tmpdir5" && CODEX_HOME="$tmpdir5/.codex-home" bash "$REPO_DIR/install.sh" >/dev/null 2>&1)
    if ! grep -v '^[[:space:]]*#' "$tmpdir5/.codex/config.toml" | grep -q '^hooks = true'; then
        fail "install.sh case 5: commented codex_hooks prevented hooks=true insertion"
        all_passed=false
    fi
    rm -rf "$tmpdir5"

    local tmpdir6
    tmpdir6=$(mktemp -d)
    mkdir -p "$tmpdir6/.codex"
    printf '[features]\n# codex_hooks = true\n' > "$tmpdir6/.codex/config.toml"
    (cd "$tmpdir6" && CODEX_HOME="$tmpdir6/.codex-home" bash "$REPO_DIR/install.sh" >/dev/null 2>&1)
    if ! grep -v '^[[:space:]]*#' "$tmpdir6/.codex/config.toml" | grep -q '^hooks = true'; then
        fail "install.sh case 6: commented codex_hooks treated as real"
        all_passed=false
    fi
    rm -rf "$tmpdir6"

    if [ "$all_passed" = "true" ]; then
        pass "install.sh migrates deprecated codex_hooks and writes hooks=true"
    fi
}

test_install_backs_up_hooks_json() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.codex"
    echo '{"old": true}' > "$tmpdir/.codex/hooks.json"
    (cd "$tmpdir" && CODEX_HOME="$tmpdir/.codex-home" bash "$REPO_DIR/install.sh" >/dev/null 2>&1)
    local backup_count
    backup_count=$(find "$tmpdir/.codex" -maxdepth 1 -name 'hooks.json.bak.*' | wc -l | tr -d ' ')
    rm -rf "$tmpdir"
    if [ "$backup_count" -ge 1 ]; then
        pass "install.sh backs up existing hooks.json"
    else
        fail "install.sh did not create a hooks.json backup"
    fi
}

test_install_merges_existing_hooks_json() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.codex"
    cat > "$tmpdir/.codex/hooks.json" <<'EOF'
{
  "customSetting": "keep-me",
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "node .custom/session.cjs"
          },
          {
            "type": "command",
            "command": "node .codex/hooks/session-start.cjs"
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "^Write$",
        "hooks": [
          {
            "type": "command",
            "command": "node .custom/guard.cjs"
          }
        ]
      },
      {
        "matcher": "^Bash$",
        "hooks": [
          {
            "type": "command",
            "command": "./.codex/hooks/bash-guard.sh"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "node .custom/post-tool.cjs"
          },
          {
            "type": "command",
            "command": "node .custom/audit.cjs .codex/hooks/git-guard.cjs"
          },
          {
            "type": "command",
            "command": "node .codex/hooks/Git-Guard.cjs"
          },
          {
            "type": "command",
            "command": "pwsh -FILE .codex/hooks/git-guard.ps1"
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": ".codex/hooks/sdlc-prompt-check.sh"
          }
        ]
      }
    ]
  }
}
EOF
    HOOKS_PATH="$tmpdir/.codex/hooks.json" node <<'NODE'
const fs = require("fs");
const hooksPath = process.env.HOOKS_PATH;
fs.writeFileSync(hooksPath, `\uFEFF${fs.readFileSync(hooksPath, "utf8")}`);
NODE
    chmod 644 "$tmpdir/.codex/hooks.json"

    local valid=true
    (umask 077; cd "$tmpdir" && CODEX_HOME="$tmpdir/.codex-home" bash "$REPO_DIR/install.sh" >/dev/null 2>&1) || valid=false
    (umask 077; cd "$tmpdir" && CODEX_HOME="$tmpdir/.codex-home" bash "$REPO_DIR/install.sh" >/dev/null 2>&1) || valid=false
    [ "$(node "$REPO_DIR/lib/merge-hooks.cjs" --status "$tmpdir/.codex/hooks.json" "$REPO_DIR/.codex/unix-hooks.json")" = "match" ] || valid=false

    HOOKS_PATH="$tmpdir/.codex/hooks.json" \
    EXPECT_MODE_CHECK="$([ "$IS_WINDOWS" = "false" ] && echo true || echo false)" \
    node <<'NODE' || valid=false
const fs = require("fs");
const path = require("path");
const data = JSON.parse(fs.readFileSync(process.env.HOOKS_PATH, "utf8"));
const commands = Object.values(data.hooks || {}).flatMap((entries) =>
  entries.flatMap((entry) => (entry.hooks || []).map((hook) => hook.command))
);
const expectedOnce = [
  "node .codex/hooks/git-guard.cjs",
  "node .codex/hooks/session-start.cjs",
  "node .codex/hooks/compact-guard.cjs",
];
if (data.customSetting !== "keep-me") process.exit(1);
if (!commands.includes("node .custom/guard.cjs")) process.exit(1);
if (!commands.includes("node .custom/post-tool.cjs")) process.exit(1);
if (!commands.includes("node .custom/audit.cjs .codex/hooks/git-guard.cjs")) process.exit(1);
const hasCaseDistinctHook = commands.includes("node .codex/hooks/Git-Guard.cjs");
const hooksDirectory = path.dirname(process.env.HOOKS_PATH);
let foldsCase = process.platform === "win32";
if (process.platform === "darwin") {
  try {
    const alternate = path.join(path.dirname(hooksDirectory), ".CODEX");
    foldsCase = fs.realpathSync.native(hooksDirectory) === fs.realpathSync.native(alternate);
  } catch (_error) {
    foldsCase = false;
  }
}

if (foldsCase === hasCaseDistinctHook) process.exit(1);
if (commands.includes("pwsh -FILE .codex/hooks/git-guard.ps1")) process.exit(1);
if (!commands.includes("node .custom/session.cjs")) process.exit(1);
if (commands.some((command) => /bash-guard|sdlc-prompt-check/.test(command))) process.exit(1);
for (const command of expectedOnce) {
  const expectedCount = command.includes("compact-guard") ? 2 : 1;
  if (commands.filter((candidate) => candidate === command).length !== expectedCount) process.exit(1);
}
if (process.env.EXPECT_MODE_CHECK === "true" && (fs.statSync(process.env.HOOKS_PATH).mode & 0o777) !== 0o644) process.exit(1);
NODE
    rm -rf "$tmpdir"

    if [ "$valid" = "true" ]; then
        pass "install.sh preserves host hooks and replaces wizard-owned hook entries idempotently"
    else
        fail "install.sh overwrote host hooks or duplicated wizard-owned hook entries"
    fi
}

test_merge_fresh_file_honors_restrictive_umask() {
    if [ "$IS_WINDOWS" = "true" ]; then
        pass "fresh hook merge umask behavior is POSIX-only"
        return
    fi

    local tmpdir valid=true
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.codex"

    (
        umask 077
        node "$REPO_DIR/lib/merge-hooks.cjs" \
            "$tmpdir/.codex/hooks.json" "$REPO_DIR/.codex/unix-hooks.json"
    ) >/dev/null 2>&1 || valid=false
    HOOKS_PATH="$tmpdir/.codex/hooks.json" node <<'NODE' || valid=false
const fs = require("fs");
if ((fs.statSync(process.env.HOOKS_PATH).mode & 0o777) !== 0o600) process.exit(1);
NODE
    rm -rf "$tmpdir"

    if [ "$valid" = "true" ]; then
        pass "fresh hook merge honors a restrictive process umask"
    else
        fail "fresh hook merge widened permissions beyond the process umask"
    fi
}

test_check_passes_merge_helper_as_node_argument() {
    if grep -Fq 'node - "$SCRIPT_DIR/lib/merge-hooks.cjs"' "$REPO_DIR/check.sh" \
        && grep -Fq 'require(process.argv[2])' "$REPO_DIR/check.sh"; then
        pass "check passes the merge helper through MSYS-convertible Node argv"
    else
        fail "check passes the merge helper through an unconverted environment path"
    fi
}

test_check_reports_non_object_hooks_as_broken() {
    local tmpdir output status valid=true
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.codex" "$tmpdir/.codex-sdlc"
    printf '%s\n' 'null' > "$tmpdir/.codex/hooks.json"
    cat > "$tmpdir/.codex-sdlc/manifest.json" <<'EOF'
{
  "managed_files": {
    ".codex/hooks.json": "sha256:0000000000000000000000000000000000000000000000000000000000000000"
  }
}

EOF

    set +e
    output=$(cd "$tmpdir" && bash "$REPO_DIR/check.sh" 2>/dev/null)
    status=$?
    set -e

    [ "$status" -eq 0 ] || valid=false
    CHECK_OUTPUT="$output" node <<'NODE' || valid=false
const data = JSON.parse(process.env.CHECK_OUTPUT);
if (data.managed_files?.[".codex/hooks.json"]?.status !== "drift / broken") process.exit(1);
NODE
    rm -rf "$tmpdir"

    if [ "$valid" = "true" ]; then
        pass "check reports non-object hooks.json as broken"
    else
        fail "check crashed on a non-object hooks.json document"
    fi
}

test_check_reports_structurally_invalid_hooks_as_broken() {
    local tmpdir output status valid=true
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.codex" "$tmpdir/.codex-sdlc"
    printf '%s\n' '{"hooks":[]}' > "$tmpdir/.codex/hooks.json"
    cat > "$tmpdir/.codex-sdlc/manifest.json" <<'EOF'
{
  "managed_files": {
    ".codex/hooks.json": "sha256:0000000000000000000000000000000000000000000000000000000000000000"
  }
}
EOF

    set +e
    output=$(cd "$tmpdir" && bash "$REPO_DIR/check.sh" 2>/dev/null)
    status=$?
    set -e

    [ "$status" -eq 0 ] || valid=false
    CHECK_OUTPUT="$output" node <<'NODE' || valid=false
const data = JSON.parse(process.env.CHECK_OUTPUT);
if (data.managed_files?.[".codex/hooks.json"]?.status !== "drift / broken") process.exit(1);
NODE
    rm -rf "$tmpdir"

    if [ "$valid" = "true" ]; then
        pass "check reports structurally invalid hooks.json as broken"
    else
        fail "check mislabeled structurally invalid hooks.json as customized"
    fi
}

test_merge_status_distinguishes_broken_target_from_bad_template() {
    local tmpdir output status before valid=true
    tmpdir=$(mktemp -d)
    printf '%s\n' '{"hooks":{}}' > "$tmpdir/target.json"
    printf '%s\n' '{ malformed template' > "$tmpdir/template.json"
    before=$(cat "$tmpdir/target.json")

    set +e
    output=$(node "$REPO_DIR/lib/merge-hooks.cjs" --status "$tmpdir/target.json" "$tmpdir/template.json" 2>&1)
    status=$?
    set -e
    [ "$status" -ne 0 ] || valid=false
    [ "$(cat "$tmpdir/target.json")" = "$before" ] || valid=false
    echo "$output" | grep -Fq 'template.json' || valid=false

    printf '%s\n' '{ malformed target' > "$tmpdir/target.json"
    cp "$REPO_DIR/.codex/unix-hooks.json" "$tmpdir/template.json"
    output=$(node "$REPO_DIR/lib/merge-hooks.cjs" --status "$tmpdir/target.json" "$tmpdir/template.json" 2>&1) || valid=false
    [ "$output" = "target-broken" ] || valid=false
    rm -rf "$tmpdir"

    if [ "$valid" = "true" ]; then
        pass "merge status distinguishes a broken target from a bad template"
    else
        fail "merge status could not distinguish target corruption from package failure"
    fi
}

test_install_rejects_malformed_hooks_without_overwrite() {
    local tmpdir before after guard_before guard_after output status valid=true
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.codex/hooks"
    printf '%s\n' '{ malformed hooks json' > "$tmpdir/.codex/hooks.json"
    printf '%s\n' 'USER CUSTOM GUARD' > "$tmpdir/.codex/hooks/git-guard.cjs"
    before=$(cat "$tmpdir/.codex/hooks.json")
    guard_before=$(cat "$tmpdir/.codex/hooks/git-guard.cjs")

    set +e
    output=$(cd "$tmpdir" && CODEX_HOME="$tmpdir/.codex-home" bash "$REPO_DIR/install.sh" 2>&1)
    status=$?
    set -e
    after=$(cat "$tmpdir/.codex/hooks.json")
    guard_after=$(cat "$tmpdir/.codex/hooks/git-guard.cjs")

    [ "$status" -ne 0 ] || valid=false
    [ "$after" = "$before" ] || valid=false
    [ "$guard_after" = "$guard_before" ] || valid=false
    [ ! -e "$tmpdir/.codex/config.toml" ] || valid=false
    [ ! -e "$tmpdir/.codex-home/skills/setup-wizard" ] || valid=false
    echo "$output" | grep -Eqi 'hooks.json|JSON|parse' || valid=false
    rm -rf "$tmpdir"

    if [ "$valid" = "true" ]; then
        pass "install.sh rejects malformed hooks.json without overwriting it"
    else
        fail "install.sh did not fail closed on malformed hooks.json"
    fi
}

test_install_refreshes_unmodified_agents_for_profile_switch() {
    local tmpdir install_output output valid=true
    tmpdir=$(mktemp -d)
    echo '{"name":"profile-switch","scripts":{"test":"jest"}}' > "$tmpdir/package.json"
    mkdir -p "$tmpdir/src"

    (
        umask 077 && cd "$tmpdir" && \
        CODEX_HOME="$tmpdir/.codex-home" \
        CODEX_SDLC_DISABLE_REASONING=1 \
        bash "$REPO_DIR/setup.sh" --yes --model-profile mixed >/dev/null 2>&1
    ) || valid=false

    cat > "$tmpdir/AGENTS.md" <<'EOF'
# SDLC Enforcement

- Selected profile: `mixed`
- Baseline reasoning: `medium`
EOF
    MANIFEST_PATH="$tmpdir/.codex-sdlc/manifest.json" AGENTS_PATH="$tmpdir/AGENTS.md" node <<'NODE'
const crypto = require("crypto");
const fs = require("fs");
const manifest = JSON.parse(fs.readFileSync(process.env.MANIFEST_PATH, "utf8"));
manifest.managed_files["AGENTS.md"] = `sha256:${crypto.createHash("sha256").update(fs.readFileSync(process.env.AGENTS_PATH)).digest("hex")}`;
fs.writeFileSync(process.env.MANIFEST_PATH, `${JSON.stringify(manifest, null, 2)}\n`);
NODE

    install_output=$(
        umask 077 && cd "$tmpdir" && \
        CODEX_HOME="$tmpdir/.codex-home" \
        bash "$REPO_DIR/install.sh" --model-profile maximum 2>&1
    ) || valid=false
    output=$(cd "$tmpdir" && bash "$REPO_DIR/check.sh" 2>/dev/null)

    grep -Fq -- '- Selected profile: `maximum`' "$tmpdir/AGENTS.md" || valid=false
    grep -Fq -- '- Baseline reasoning: `high`' "$tmpdir/AGENTS.md" || valid=false
    ! grep -Fq -- '- Selected profile: mixed' "$tmpdir/AGENTS.md" || valid=false
    echo "$install_output" | grep -Fq 'AGENTS.md is wizard-managed - keeping it; profile guidance will be refreshed if needed' || valid=false
    echo "$install_output" | grep -Fq 'AGENTS.md is user-owned or customized - preserving it' && valid=false
    CHECK_OUTPUT="$output" node <<'NODE' || valid=false
const data = JSON.parse(process.env.CHECK_OUTPUT);
if (data.managed_files?.["AGENTS.md"]?.status !== "match") process.exit(1);
NODE
    rm -rf "$tmpdir"

    if [ "$valid" = "true" ]; then
        pass "install refreshes unmodified AGENTS guidance when the selected profile changes"
    else
        fail "install left trusted AGENTS guidance on the old selected profile"
    fi
}

test_profile_guidance_refresh_rejects_missing_reasoning() {
    local tmpdir status valid=true
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.codex-sdlc"
    cat > "$tmpdir/AGENTS.md" <<'EOF'
- Selected profile: `mixed`
- Baseline reasoning: `medium`
EOF
    ROOT="$tmpdir" node <<'NODE'
const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
const root = process.env.ROOT;
const agents = fs.readFileSync(path.join(root, "AGENTS.md"));
fs.writeFileSync(path.join(root, ".codex-sdlc", "manifest.json"), `${JSON.stringify({
  model_profile: { selected_profile: "mixed" },
  managed_files: {
    "AGENTS.md": `sha256:${crypto.createHash("sha256").update(agents).digest("hex")}`,
    ".codex-sdlc/model-profile.json": "sha256:old",
  },
}, null, 2)}\n`);
fs.writeFileSync(path.join(root, ".codex-sdlc", "model-profile.json"), '{"selected_profile":"maximum"}\n');
NODE

    set +e
    (cd "$tmpdir" && node "$REPO_DIR/lib/refresh-manifest-hashes.cjs" \
        .codex-sdlc/manifest.json .codex-sdlc/model-profile.json) >/dev/null 2>&1
    status=$?
    set -e

    [ "$status" -ne 0 ] || valid=false
    ! grep -Fq '`undefined`' "$tmpdir/AGENTS.md" || valid=false
    grep -Fq -- '- Selected profile: `mixed`' "$tmpdir/AGENTS.md" || valid=false
    rm -rf "$tmpdir"

    if [ "$valid" = "true" ]; then
        pass "profile guidance refresh rejects metadata without a reasoning baseline"
    else
        fail "profile guidance refresh wrote an undefined reasoning baseline"
    fi
}

test_profile_guidance_refresh_handles_legacy_and_partial_guidance() {
    local legacy_dir partial_dir legacy_before partial_before valid=true
    legacy_dir=$(mktemp -d)
    partial_dir=$(mktemp -d)

    for target_dir in "$legacy_dir" "$partial_dir"; do
        mkdir -p "$target_dir/.codex-sdlc"
    done

    cat > "$legacy_dir/AGENTS.md" <<'EOF'
- Selected profile: `maximum`
- Baseline reasoning: `high`
EOF
    cat > "$partial_dir/AGENTS.md" <<'EOF'
- Selected profile: `mixed`
EOF
    legacy_before=$(cat "$legacy_dir/AGENTS.md")
    partial_before=$(cat "$partial_dir/AGENTS.md")

    ROOT="$legacy_dir" PREVIOUS_PROFILE="" node <<'NODE'
const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
const root = process.env.ROOT;
const agents = fs.readFileSync(path.join(root, "AGENTS.md"));
fs.writeFileSync(path.join(root, ".codex-sdlc", "manifest.json"), `${JSON.stringify({
  model_profile: { selected_profile: "mixed", policy_schema_version: 3 },
  managed_files: {
    "AGENTS.md": `sha256:${crypto.createHash("sha256").update(agents).digest("hex")}`,
    ".codex-sdlc/model-profile.json": "sha256:old",
  },
}, null, 2)}\n`);
fs.writeFileSync(path.join(root, ".codex-sdlc", "model-profile.json"), `${JSON.stringify({
  schema_version: 2,
  selected_profile: "maximum",
  profiles: { maximum: { main_reasoning: "high" } },
})}\n`);
NODE
    ROOT="$partial_dir" node <<'NODE'
const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
const root = process.env.ROOT;
const agents = fs.readFileSync(path.join(root, "AGENTS.md"));
fs.writeFileSync(path.join(root, ".codex-sdlc", "manifest.json"), `${JSON.stringify({
  model_profile: { selected_profile: "mixed" },
  managed_files: {
    "AGENTS.md": `sha256:${crypto.createHash("sha256").update(agents).digest("hex")}`,
    ".codex-sdlc/model-profile.json": "sha256:old",
  },
}, null, 2)}\n`);
fs.writeFileSync(path.join(root, ".codex-sdlc", "model-profile.json"), `${JSON.stringify({
  schema_version: 2,
  selected_profile: "maximum",
  profiles: { maximum: { main_reasoning: "high" } },
})}\n`);
NODE

    (cd "$legacy_dir" && node "$REPO_DIR/lib/refresh-manifest-hashes.cjs" \
        .codex-sdlc/manifest.json .codex-sdlc/model-profile.json) >/dev/null 2>&1 || valid=false
    (cd "$partial_dir" && node "$REPO_DIR/lib/refresh-manifest-hashes.cjs" \
        .codex-sdlc/manifest.json .codex-sdlc/model-profile.json) >/dev/null 2>&1 || valid=false

    [ "$(cat "$legacy_dir/AGENTS.md")" = "$legacy_before" ] || valid=false
    [ "$(cat "$partial_dir/AGENTS.md")" = "$partial_before" ] || valid=false
    MANIFEST_PATH="$legacy_dir/.codex-sdlc/manifest.json" node <<'NODE' || valid=false
const manifest = require(process.env.MANIFEST_PATH);
if (manifest.model_profile?.selected_profile !== "maximum") process.exit(1);
if (manifest.model_profile?.baseline_reasoning !== "high") process.exit(1);
if (manifest.model_profile?.policy_schema_version !== 3) process.exit(1);
NODE
    rm -rf "$legacy_dir" "$partial_dir"

    if [ "$valid" = "true" ]; then
        pass "profile refresh synchronizes legacy metadata without partially rewriting guidance"
    else
        fail "profile refresh failed or partially rewrote legacy guidance"
    fi
}

test_install_refreshes_only_touched_manifest_hashes() {
    local tmpdir output valid=true
    tmpdir=$(mktemp -d)
    echo '{"name":"manifest-refresh","scripts":{"test":"jest"}}' > "$tmpdir/package.json"
    mkdir -p "$tmpdir/src"

    (
        cd "$tmpdir" && \
        CODEX_HOME="$tmpdir/.codex-home" \
        CODEX_SDLC_DISABLE_REASONING=1 \
        bash "$REPO_DIR/setup.sh" --yes --model-profile mixed >/dev/null 2>&1
    ) || valid=false

    printf '%s\n' 'legacy bash guard' > "$tmpdir/.codex/hooks/bash-guard.sh"
    printf '%s\n' 'legacy PowerShell guard' > "$tmpdir/.codex/hooks/git-guard.ps1"
    printf '%s\n' 'legacy JavaScript guard' > "$tmpdir/.codex/hooks/git-guard.js"
    printf '%s\n' 'legacy JavaScript session hook' > "$tmpdir/.codex/hooks/session-start.js"
    HOOKS_PATH="$tmpdir/.codex/hooks.json" node <<'NODE'
const fs = require("fs");
const hooksPath = process.env.HOOKS_PATH;
const hooks = JSON.parse(fs.readFileSync(hooksPath, "utf8"));
hooks.hostSetting = "preserve-without-adopting";
fs.writeFileSync(hooksPath, `${JSON.stringify(hooks, null, 2)}\n`);
NODE
    cat > "$tmpdir/.codex/config.toml" <<'EOF'
model = "gpt-5.6-sol"
model_reasoning_effort = "medium"

[features]
hooks = false
EOF
    printf '\nUSER CUSTOM AGENTS CONTENT\n' >> "$tmpdir/AGENTS.md"

    MANIFEST_PATH="$tmpdir/.codex-sdlc/manifest.json" \
    BASH_GUARD_PATH="$tmpdir/.codex/hooks/bash-guard.sh" \
    PS_GUARD_PATH="$tmpdir/.codex/hooks/git-guard.ps1" \
    LEGACY_GIT_GUARD_PATH="$tmpdir/.codex/hooks/git-guard.js" \
    LEGACY_SESSION_PATH="$tmpdir/.codex/hooks/session-start.js" \
    CONFIG_PATH="$tmpdir/.codex/config.toml" \
    node <<'NODE'
const crypto = require("crypto");
const fs = require("fs");
const manifest = JSON.parse(fs.readFileSync(process.env.MANIFEST_PATH, "utf8"));
const hash = (filePath) => `sha256:${crypto.createHash("sha256").update(fs.readFileSync(filePath)).digest("hex")}`;
delete manifest.managed_files[".codex/hooks/compact-guard.cjs"];
manifest.managed_files[".codex/hooks/bash-guard.sh"] = hash(process.env.BASH_GUARD_PATH);
manifest.managed_files[".codex/hooks/git-guard.ps1"] = hash(process.env.PS_GUARD_PATH);
manifest.managed_files[".codex/hooks/git-guard.js"] = hash(process.env.LEGACY_GIT_GUARD_PATH);
manifest.managed_files[".codex/hooks/session-start.js"] = hash(process.env.LEGACY_SESSION_PATH);
manifest.managed_files[".codex/config.toml"] = hash(process.env.CONFIG_PATH);
fs.writeFileSync(process.env.MANIFEST_PATH, `${JSON.stringify(manifest, null, 2)}\n`);
NODE
    chmod 644 "$tmpdir/.codex-sdlc/manifest.json"
    if [ "$IS_WINDOWS" = "false" ]; then
        printf '%s\n' 'USER CUSTOM POWERSHELL GUARD' >> "$tmpdir/.codex/hooks/git-guard.ps1"
    fi

    (
        umask 077 && cd "$tmpdir" && \
        CODEX_HOME="$tmpdir/.codex-home" \
        bash "$REPO_DIR/install.sh" --model-profile maximum >/dev/null 2>&1
    ) || valid=false
    output=$(cd "$tmpdir" && bash "$REPO_DIR/check.sh" 2>/dev/null)

    CHECK_OUTPUT="$output" EXPECT_POWERSHELL_MATCH="$IS_WINDOWS" node <<'NODE' || valid=false
const data = JSON.parse(process.env.CHECK_OUTPUT);
for (const file of [
  ".codex/hooks/bash-guard.sh",
  ".codex/hooks/compact-guard.cjs",
  ".codex/config.toml",
]) {
  if (data.managed_files?.[file]?.status !== "match") process.exit(1);
}
const expectedPowerShellStatus = process.env.EXPECT_POWERSHELL_MATCH === "true" ? "match" : "customized";
if (data.managed_files?.[".codex/hooks/git-guard.ps1"]?.status !== expectedPowerShellStatus) process.exit(1);
if (data.managed_files?.[".codex/hooks.json"]?.status !== "customized") process.exit(1);
if (data.managed_files?.["AGENTS.md"]?.status !== "customized") process.exit(1);
NODE
    MANIFEST_PATH="$tmpdir/.codex-sdlc/manifest.json" EXPECT_POSIX="$([ "$IS_WINDOWS" = "false" ] && echo true || echo false)" node <<'NODE' || valid=false
const fs = require("fs");
const manifest = JSON.parse(fs.readFileSync(process.env.MANIFEST_PATH, "utf8"));
if (manifest.model_profile?.selected_profile !== "maximum") process.exit(1);
if (manifest.model_profile?.baseline_reasoning !== "high") process.exit(1);
if (Object.prototype.hasOwnProperty.call(manifest.managed_files, ".codex/hooks/git-guard.js")) process.exit(1);
if (Object.prototype.hasOwnProperty.call(manifest.managed_files, ".codex/hooks/session-start.js")) process.exit(1);
if (process.env.EXPECT_POSIX === "true" && (fs.statSync(process.env.MANIFEST_PATH).mode & 0o777) !== 0o644) process.exit(1);
NODE
    grep -Fq 'refresh-manifest-hashes.cjs' "$REPO_DIR/install.ps1" || valid=false
    grep -Fq 'merge-hooks.cjs") --status' "$REPO_DIR/install.ps1" || valid=false
    grep -Fq 'Add-TouchedFile -Path ".agents/skills/$Name/SKILL.md"' "$REPO_DIR/install.ps1" || valid=false
    grep -Fq '$touchedFileArgs = $touchedFiles.ToArray()' "$REPO_DIR/install.ps1" || valid=false
    grep -Fq '@touchedFileArgs' "$REPO_DIR/install.ps1" || valid=false
    rm -rf "$tmpdir"

    if [ "$valid" = "true" ]; then
        pass "install refreshes hashes only for artifacts it touched on shell and PowerShell paths"
    else
        fail "install left touched manifest hashes stale or adopted untouched custom content"
    fi
}

test_agents_md_size() {
    local size
    size=$(wc -c < "$REPO_DIR/AGENTS.md" 2>/dev/null | tr -d ' ')
    if [ -n "$size" ] && [ "$size" -lt 32768 ]; then
        pass "AGENTS.md is under the Codex limit"
    else
        fail "AGENTS.md is too large or missing"
    fi
}

test_setup_skill_has_confidence_setup_contract() {
    local skill="$REPO_DIR/skill-sources/setup-wizard/SKILL.template.md"

    if grep -q 'resolved (detected)' "$skill" \
        && grep -q 'resolved (inferred)' "$skill" \
        && grep -q 'unresolved' "$skill" \
        && grep -q 'Do not ask a fixed checklist' "$skill"; then
        pass "setup-wizard carries the confidence-driven setup contract"
    else
        fail "setup-wizard is missing the upstream confidence-driven setup contract"
    fi
}

test_update_skill_has_idempotent_update_contract() {
    local skill="$REPO_DIR/skill-sources/update-wizard/SKILL.template.md"

    if grep -q 'match' "$skill" \
        && grep -q 'missing' "$skill" \
        && grep -q 'customized' "$skill" \
        && grep -q 'drift / broken' "$skill" \
        && grep -q 'Never overwrite customizations blindly' "$skill"; then
        pass "update-wizard carries the idempotent selective-update contract"
    else
        fail "update-wizard is missing the idempotent selective-update contract"
    fi
}

test_update_skill_has_sol_high_default_contract() {
    local skill="$REPO_DIR/skill-sources/update-wizard/SKILL.template.md"

    if grep -Eqi 'Sol `high`.*(standing|default|normal).*(driver|root)|default.*(driver|root).*Sol `high`' "$skill" \
        && grep -Eqi '`mixed`.*experimental.*explicit opt-in|experimental.*`mixed`.*explicit opt-in' "$skill" \
        && grep -Eqi 'profile-less|missing.*model profile' "$skill" \
        && grep -Eqi 'preserve.*explicit.*`mixed`|explicit.*`mixed`.*preserve' "$skill"; then
        pass "update-wizard defaults profile-less repos to Sol high while preserving explicit mixed opt-ins"
    else
        fail "update-wizard is missing the Sol-high default and explicit mixed preservation contract"
    fi
}

test_skills_document_hooks_feature_rename() {
    local setup_skill="$REPO_DIR/skill-sources/setup-wizard/SKILL.template.md"
    local update_skill="$REPO_DIR/skill-sources/update-wizard/SKILL.template.md"
    local all_passed=true

    grep -Fq '[features].hooks' "$setup_skill" || all_passed=false
    grep -Fq '/hooks' "$setup_skill" || all_passed=false
    grep -Fq '[features].hooks' "$update_skill" || all_passed=false
    grep -Fq 'codex_hooks' "$update_skill" || all_passed=false
    grep -Eqi 'deprecated.*codex_hooks|codex_hooks.*deprecated' "$update_skill" || all_passed=false
    grep -Eqi 'replacement.*hooks|hooks.*replacement' "$update_skill" || all_passed=false

    if [ "$all_passed" = "true" ]; then
        pass "setup/update skills document the hooks feature flag rename and /hooks review"
    else
        fail "setup/update skills should document [features].hooks, codex_hooks migration, and /hooks review"
    fi
}

test_update_skill_frontloads_package_upgrade_boundary() {
    local skill="$REPO_DIR/skill-sources/update-wizard/SKILL.template.md"
    local readme="$REPO_DIR/README.md"

    if grep -Fq 'Package upgrade preflight' "$skill" \
        && grep -Fq 'Before scanning repo drift' "$skill" \
        && grep -Fq 'Package upgrade means consuming the newest published' "$skill" \
        && grep -Fq 'Repo repair/sync means inspecting and repairing local SDLC artifacts' "$skill" \
        && grep -Fq 'does not self-update the active Codex session' "$skill" \
        && grep -Fq 'npm view codex-sdlc-wizard version' "$skill" \
        && grep -Fq 'npx codex-sdlc-wizard@latest update' "$skill" \
        && grep -Fq 'restart/reopen Codex' "$skill" \
        && grep -Fq 'Package upgrade vs repo repair' "$readme" \
        && grep -Fq 'Repo repair/sync inside Codex' "$readme"; then
        pass "update-wizard frontloads package upgrade vs repo repair guidance"
    else
        fail "update-wizard does not frontload package upgrade vs repo repair guidance"
    fi
}

test_helper_skill_metadata_uses_codex_sdlc_not_xdlc() {
    local setup_skill="$REPO_DIR/skill-sources/setup-wizard/SKILL.template.md"
    local update_skill="$REPO_DIR/skill-sources/update-wizard/SKILL.template.md"
    local setup_openai="$REPO_DIR/skill-sources/setup-wizard/agents/openai.yaml"
    local update_openai="$REPO_DIR/skill-sources/update-wizard/agents/openai.yaml"
    local all_passed=true

    if grep -REiq 'Codex[[:space:]]+XDLC|XDLC[[:space:]]+adapter|host adapter core|core metadata' \
        "$setup_skill" "$update_skill" "$setup_openai" "$update_openai" "$REPO_DIR/skills/codex-sdlc-wizard/SKILL.md" "$REPO_DIR/skills/codex-sdlc-wizard/agents/openai.yaml" 2>/dev/null; then
        all_passed=false
    fi

    grep -Fq 'Codex SDLC' "$setup_skill" || all_passed=false
    grep -Fq 'Codex SDLC' "$update_skill" || all_passed=false
    grep -Fq 'Codex SDLC' "$setup_openai" || all_passed=false
    grep -Fq 'Codex SDLC' "$update_openai" || all_passed=false

    if grep -Eq 'invoke `?\$setup-wizard|invoke `?\$update-wizard|use /skills and invoke' "$REPO_DIR/install.ps1"; then
        all_passed=false
    fi

    if [ "$all_passed" = "true" ]; then
        pass "helper skill metadata says Codex SDLC and avoids XDLC/palette leakage"
    else
        fail "helper skill metadata should say Codex SDLC and avoid XDLC/palette leakage"
    fi
}

test_setup_and_update_skills_stop_before_product_remediation() {
    local setup_skill="$REPO_DIR/skill-sources/setup-wizard/SKILL.template.md"
    local update_skill="$REPO_DIR/skill-sources/update-wizard/SKILL.template.md"
    local all_passed=true

    for skill in "$setup_skill" "$update_skill"; do
        if ! grep -q 'do not edit application code' "$skill"; then
            fail "$(basename "$(dirname "$skill")") does not forbid application code edits during setup/update"
            all_passed=false
        fi

        if ! grep -q 'application tests' "$skill"; then
            fail "$(basename "$(dirname "$skill")") does not protect application tests during setup/update"
            all_passed=false
        fi

        if ! grep -q 'verification is diagnostic' "$skill"; then
            fail "$(basename "$(dirname "$skill")") does not make verification diagnostic by default"
            all_passed=false
        fi

        if ! grep -q '\$sdlc' "$skill"; then
            fail "$(basename "$(dirname "$skill")") does not hand product regressions to sdlc"
            all_passed=false
        fi

        if ! grep -q 'exit and reopen Codex' "$skill"; then
            fail "$(basename "$(dirname "$skill")") does not explicitly recommend restarting Codex after hook/skill changes"
            all_passed=false
        fi

        if ! grep -q 'do not need to rerun' "$skill"; then
            fail "$(basename "$(dirname "$skill")") does not say restart does not require rerunning setup/update"
            all_passed=false
        fi

        if ! grep -q 'codex resume -m' "$skill"; then
            fail "$(basename "$(dirname "$skill")") does not recommend model-explicit codex resume for interrupted sessions"
            all_passed=false
        fi

        if ! grep -q -- '--dangerously-bypass-approvals-and-sandbox' "$skill"; then
            fail "$(basename "$(dirname "$skill")") does not document the full-trust resume variant"
            all_passed=false
        fi
    done

    if [ "$all_passed" = "true" ]; then
        pass "setup/update skills stop before unrelated product remediation and recommend restart/resume"
    fi
}

test_feedback_skill_has_privacy_prompt_and_dedupe() {
    local skill="$REPO_DIR/skill-sources/feedback/SKILL.template.md"

    if grep -q 'May I scan\?' "$skill" \
        && grep -q 'Check for duplicates' "$skill" \
        && grep -q 'No source code' "$skill"; then
        pass "feedback carries the privacy-first scan and dedupe contract"
    else
        fail "feedback is missing the privacy-first scan and dedupe contract"
    fi
}

test_setup_docs_include_codex_desktop_handoff() {
    local skill="$REPO_DIR/skill-sources/setup-wizard/SKILL.template.md"
    local loop="$REPO_DIR/SDLC-LOOP.md"

    if grep -q 'Codex Desktop handoff' "$loop" \
        && grep -q 'macOS and Windows' "$loop" \
        && grep -q 'codex app .' "$loop" \
        && grep -q 'credentials, MFA, tenant consent' "$loop" \
        && grep -q 'Codex Desktop handoff' "$skill" \
        && grep -q 'computer-use' "$skill"; then
        pass "setup docs include Codex Desktop handoff guidance"
    else
        fail "setup docs are missing Codex Desktop handoff guidance"
    fi
}

test_setup_docs_include_m365_auth_lane_guidance() {
    local skill="$REPO_DIR/skill-sources/setup-wizard/SKILL.template.md"
    local loop="$REPO_DIR/SDLC-LOOP.md"

    if grep -q 'Microsoft 365 auth lane' "$loop" \
        && grep -q 'Graph PowerShell' "$loop" \
        && grep -q 'Get-MgContext' "$loop" \
        && grep -q 'tenant id plus expected work account' "$loop" \
        && grep -q 'personal Microsoft account' "$loop" \
        && grep -q 'read-only' "$loop" \
        && grep -q '.reviews/' "$loop" \
        && grep -q 'Microsoft 365 auth lane' "$skill" \
        && grep -q 'Graph PowerShell' "$skill" \
        && grep -q 'tenant-bound' "$skill"; then
        pass "setup docs include Microsoft 365 auth-lane guidance"
    else
        fail "setup docs are missing Microsoft 365 auth-lane guidance"
    fi
}

test_setup_docs_include_task_routing_gate() {
    local skill="$REPO_DIR/skill-sources/setup-wizard/SKILL.template.md"
    local loop="$REPO_DIR/SDLC-LOOP.md"
    local sdlc_skill="$REPO_DIR/skill-sources/sdlc/SKILL.template.md"

    if grep -q 'Task routing gate' "$loop" \
        && grep -q 'Identify the execution lane before giving instructions' "$loop" \
        && grep -q 'Microsoft browser sign-in' "$loop" \
        && grep -q 'developer program qualification' "$loop" \
        && grep -q 'Desktop/computer-use' "$loop" \
        && grep -q 'credentials, MFA, tenant consent' "$loop" \
        && grep -q 'Task routing gate' "$skill" \
        && grep -q 'before giving CLI or browser instructions' "$skill" \
        && grep -q 'Microsoft browser sign-in' "$skill" \
        && grep -q 'Task routing gate' "$sdlc_skill" \
        && grep -q 'before giving execution steps' "$sdlc_skill"; then
        pass "setup docs include task-routing gate for Desktop/computer-use boundaries"
    else
        fail "setup docs are missing the task-routing gate for Desktop/computer-use boundaries"
    fi
}

test_sdlc_skill_has_docsync_learning_and_merge_guard() {
    local skill="$REPO_DIR/skill-sources/sdlc/SKILL.template.md"

    if grep -q 'docs update' "$skill" \
        && grep -q 'capture learnings' "$skill" \
        && grep -q 'NEVER AUTO-MERGE' "$skill"; then
        pass "sdlc carries doc-sync, learning capture, and merge-guard rules"
    else
        fail "sdlc is missing upstream SDLC enforcement rules"
    fi
}

test_repo_defaults_consumer_and_maintainer_work_to_sol_high() {
    local all_passed=true

    if ! grep -Fq 'use `gpt-5.6-sol` with `high` reasoning for this repo' "$REPO_DIR/AGENTS.md"; then
        fail "AGENTS.md does not default this wizard repo to gpt-5.6 Sol high"
        all_passed=false
    fi

    if ! grep -q '^model_reasoning_effort = "high"' "$REPO_DIR/.codex/config.toml"; then
        fail "repo-local config does not default wizard maintenance to high"
        all_passed=false
    fi

    if grep -Eiq 'gpt-5\.6-sol.*xhigh|xhigh.*gpt-5\.6-sol|xhigh.*throughout|standing.*xhigh' "$REPO_DIR/AGENTS.md"; then
        fail "AGENTS.md still defines xhigh as the standing wizard-repo baseline"
        all_passed=false
    fi

    if ! grep -Eiq 'consumer.*default.*`high`|default.*consumer.*`high`|agentic coding.*default.*`high`' "$REPO_DIR/README.md"; then
        fail "README.md does not set high as the broad consumer/agentic-coding default"
        all_passed=false
    fi

    if ! grep -Eiq 'xhigh.*(security|migration|destructive|long-running|difficult)|security.*xhigh|migration.*xhigh' "$REPO_DIR/README.md"; then
        fail "README.md does not document risk-based xhigh escalation"
        all_passed=false
    fi

    if ! grep -q 'default: `high`' "$REPO_DIR/skill-sources/sdlc/SKILL.template.md"; then
        fail "sdlc skill does not set high as the portable default reasoning policy"
        all_passed=false
    fi

    if ! grep -q 'Default to `high`' "$REPO_DIR/SDLC-LOOP.md"; then
        fail "SDLC-LOOP.md does not set high as the portable default reasoning policy"
        all_passed=false
    fi

    if ! grep -q 'Use high reasoning by default' "$REPO_DIR/START-SDLC.md"; then
        fail "START-SDLC.md does not set high as the portable default reasoning policy"
        all_passed=false
    fi

    if ! grep -Fq 'Baseline reasoning: `{{REASONING_BASELINE}}`' "$REPO_DIR/templates/AGENTS.md.tmpl" ||
       ! grep -Fq '{{REASONING_ESCALATION_SCOPES}}' "$REPO_DIR/templates/AGENTS.md.tmpl"; then
        fail "generated AGENTS template does not expose adaptive reasoning guidance"
        all_passed=false
    fi

    if grep -Eq 'gpt-5\.4(["` ,]|$)' \
        "$REPO_DIR/.codex/config.toml" \
        "$REPO_DIR/lib/codex-config.sh" \
        "$REPO_DIR/install.sh" \
        "$REPO_DIR/install.ps1" \
        "$REPO_DIR/README.md"; then
        fail "repo model/config surface still contains stale legacy model references"
        all_passed=false
    fi

    if grep -R -n -E --exclude-dir=.git --exclude-dir=node_modules --exclude=test-adapter.sh \
        --exclude=WINDOWS-E2E-FINDINGS-20260804.md \
        'gpt-5\.(5|4|3)|GPT-5\.(5|4|3)|Codex Spark|mini-only' "$REPO_DIR" 2>/dev/null | \
        grep -Ev 'ROADMAP\.md:.*#114: evaluate GPT-5\.3-Codex-Spark' | grep -q .; then
        fail "repo still contains stale legacy model-family references"
        all_passed=false
    fi

    if ! grep -q 'codex resume -m gpt-5.6-sol' "$REPO_DIR/install.ps1" ||
       ! grep -q 'model_reasoning_effort=`"high`"' "$REPO_DIR/install.ps1"; then
        fail "PowerShell installer does not print model-explicit gpt-5.6 Sol high resume guidance"
        all_passed=false
    fi

    if ! grep -Eq '\[string\]\$ModelProfile = "maximum"' "$REPO_DIR/install.ps1" ||
       ! grep -Eq '^MODEL_PROFILE="maximum"$' "$REPO_DIR/install.sh"; then
        fail "installers do not default to the Sol maximum profile"
        all_passed=false
    fi

    local ps_guard_line ps_install_line
    ps_guard_line=$(grep -n '^Assert-Gpt56CodexVersion$' "$REPO_DIR/install.ps1" | head -1 | cut -d: -f1 || true)
    ps_install_line=$(grep -n '^Write-Host "Installing SDLC Wizard for Codex CLI\.\.\."$' "$REPO_DIR/install.ps1" | head -1 | cut -d: -f1 || true)
    if ! grep -Fq 'function Assert-Gpt56CodexVersion' "$REPO_DIR/install.ps1" ||
       ! grep -Fq '0.144.0' "$REPO_DIR/install.ps1" ||
       [ -z "$ps_guard_line" ] ||
       [ -z "$ps_install_line" ] ||
       [ "$ps_guard_line" -ge "$ps_install_line" ]; then
        fail "PowerShell installer does not enforce the GPT-5.6 Codex minimum before mutation"
        all_passed=false
    fi

    if ! grep -Fq 'CODEX_SDLC_CODEX_BIN' "$REPO_DIR/lib/codex-config.sh" ||
       ! grep -Fq 'CODEX_SDLC_CODEX_BIN' "$REPO_DIR/install.ps1"; then
        fail "installer version gates do not honor the configured Codex binary"
        all_passed=false
    fi

    if ! sed -n '/function Assert-Gpt56CodexVersion/,/^}/p' "$REPO_DIR/install.ps1" | grep -Fq 'not installed or is unavailable' ||
       ! sed -n '/function Assert-Gpt56CodexVersion/,/^}/p' "$REPO_DIR/install.ps1" | grep -Fq 'could not report its version'; then
        fail "PowerShell installer version gate does not fail closed for missing or unqueryable Codex binaries"
        all_passed=false
    fi

    if sed -n '/function Assert-Gpt56CodexVersion/,/^}/p' "$REPO_DIR/install.ps1" | grep -Fq 'CODEX_SDLC_DISABLE_REASONING' ||
       ! grep -Fq '(?im)^\s*(?:OpenAI\s+)?Codex' "$REPO_DIR/install.ps1"; then
        fail "PowerShell installer bypasses compatibility validation or parses an unanchored version"
        all_passed=false
    fi

    if ! grep -Fq 'Selected profile: `{{MODEL_PROFILE}}`' "$REPO_DIR/templates/AGENTS.baseline.md" ||
       ! grep -Fq 'Baseline reasoning: `{{REASONING_BASELINE}}`' "$REPO_DIR/templates/AGENTS.baseline.md" ||
       ! grep -Fq 'install_agents_baseline' "$REPO_DIR/install.sh" ||
       ! grep -Fq 'Install-AgentsBaseline' "$REPO_DIR/install.ps1"; then
        fail "direct installers do not render AGENTS baseline from the selected profile"
        all_passed=false
    fi

    if ! grep -Fq 'review = "gpt-5.6-sol"' "$REPO_DIR/install.ps1" ||
       ! grep -Fq 'review_model: "gpt-5.6-sol"' "$REPO_DIR/lib/codex-config.sh"; then
        fail "maximum profile does not pin Sol reviews across installer/config paths"
        all_passed=false
    fi

    if ! grep -Fq 'Write-ModelProfile' "$REPO_DIR/install.ps1" ||
       ! grep -Fq 'schema_version = 2' "$REPO_DIR/install.ps1" ||
       ! grep -Fq 'review_effort_source = "explicit command override"' "$REPO_DIR/install.ps1" ||
       ! grep -Fq 'selected_profile' "$REPO_DIR/install.ps1"; then
        fail "PowerShell installer does not persist the selected Sol-high model profile"
        all_passed=false
    fi

    if ! grep -q -- '--dangerously-bypass-approvals-and-sandbox' "$REPO_DIR/install.ps1" ||
       grep -q -- '--full-auto' "$REPO_DIR/install.ps1"; then
        fail "PowerShell installer does not print current canonical full-trust guidance"
        all_passed=false
    fi

    if ! grep -Fq '.codex\hooks\git-guard.cjs' "$REPO_DIR/install.ps1" ||
       ! grep -Fq '.codex\hooks\session-start.cjs' "$REPO_DIR/install.ps1" ||
       ! grep -Fq '.codex\hooks\compact-guard.cjs' "$REPO_DIR/install.ps1" ||
       grep -Eq 'Copy-Item.*(git-guard|session-start)\.js' "$REPO_DIR/install.ps1"; then
        fail "PowerShell installer does not install the universal .cjs hook runtime"
        all_passed=false
    fi

    if [ "$all_passed" = "true" ]; then
        pass "consumer guidance and wizard maintenance default to Sol high with task-scoped xhigh escalation"
    fi
}

test_repo_documents_max_ultra_reasoning_boundary() {
    local all_passed=true

    if ! grep -Eiq 'Max.*single|single.*Max|max.*single|single.*max' "$REPO_DIR/AI_SETUP_LANES.md" "$REPO_DIR/README.md"; then
        fail "model guidance does not explain that Max is a single-task reasoning escalation"
        all_passed=false
    fi

    if ! grep -Eiq 'Ultra.*subagent|subagent.*Ultra|ultra.*subagent|subagent.*ultra|Ultra.*parallel|parallel.*Ultra' "$REPO_DIR/AI_SETUP_LANES.md" "$REPO_DIR/README.md"; then
        fail "model guidance does not explain that Ultra is for subagent-backed parallel work"
        all_passed=false
    fi

    if ! grep -Eiq 'most tasks do not need Max or Ultra|do not.*default.*(max|ultra)|max.*ultra.*not.*default|not.*default.*(max|ultra)' "$REPO_DIR/AI_SETUP_LANES.md" "$REPO_DIR/README.md" "$REPO_DIR/AGENTS.md"; then
        fail "repo guidance does not keep Max and Ultra out of default profiles"
        all_passed=false
    fi

    if grep -Eq 'model_reasoning_effort = "(max|ultra)"' \
        "$REPO_DIR/.codex/config.toml" \
        "$REPO_DIR/lib/codex-config.sh" \
        "$REPO_DIR/install.sh" \
        "$REPO_DIR/install.ps1"; then
        fail "repo config/installers should not write Max or Ultra as project defaults"
        all_passed=false
    fi

    if [ "$all_passed" = "true" ]; then
        pass "repo documents Max versus Ultra without making either a default"
    fi
}

test_package_has_npm_release_surface() {
    local package_json="$REPO_DIR/package.json"
    local bin_script="$REPO_DIR/bin/codex-sdlc-wizard.js"
    local all_passed=true

    if [ ! -f "$package_json" ]; then
        fail "package.json is missing"
        return
    fi

    if [ ! -f "$bin_script" ]; then
        fail "bin/codex-sdlc-wizard.js is missing"
        return
    fi

    if ! grep -q '"name"[[:space:]]*:[[:space:]]*"codex-sdlc-wizard"' "$package_json"; then
        fail "package.json is missing the codex-sdlc-wizard package name"
        all_passed=false
    fi

    if ! grep -q '"codex-sdlc-wizard"[[:space:]]*:[[:space:]]*"bin/codex-sdlc-wizard.js"' "$package_json"; then
        fail "package.json is missing the codex-sdlc-wizard bin entry"
        all_passed=false
    fi

    for path in \
        ".agents/" \
        ".codex-plugin/" \
        "bin/" \
        "skills/" \
        "skill-sources/" \
        ".codex/config.toml" \
        ".codex/hooks.json" \
        ".codex/unix-hooks.json" \
        ".codex/windows-hooks.json" \
        ".codex/hooks/" \
        "templates/" \
        "lib/" \
        "install.sh" \
        "install.ps1" \
        "setup.sh" \
        "check.sh" \
        "update.sh" \
        "AGENTS.md" \
        "README.md" \
        "WINDOWS-CODEX-DESKTOP-E2E.md" \
        "ROADMAP.md" \
        "SDLC-LOOP.md" \
        "START-SDLC.md" \
        "PROVE-IT.md" \
        "UPSTREAM_VERSION" \
        "start-sdlc.sh" \
        "start-sdlc.ps1"; do
        if ! grep -Fq "\"$path\"" "$package_json"; then
            fail "package.json files is missing $path"
            all_passed=false
        fi
    done

    if grep -Fq '".codex/"' "$package_json"; then
        fail "package.json uses a broad .codex/ allowlist that can leak backup files"
        all_passed=false
    fi

    if [ "$all_passed" = "true" ]; then
        pass "package.json ships the npm release surface for the current Codex wizard"
    fi
}

test_package_cli_is_honest_about_supported_flags() {
    local output
    local exit_code

    output=$(node "$REPO_DIR/bin/codex-sdlc-wizard.js" --help 2>&1)
    exit_code=$?

    if [ "$exit_code" -ne 0 ]; then
        fail "npm CLI help failed"
        return
    fi

    if echo "$output" | grep -q -- '--model-profile' &&
       echo "$output" | grep -q 'mixed' &&
       echo "$output" | grep -q 'maximum' &&
       echo "$output" | grep -Fq 'Type "full-trust"'; then
        pass "npm CLI help advertises the supported model-profile flag"
    else
        fail "npm CLI help is missing the supported model-profile flag"
    fi
}

test_package_uses_single_canonical_sdlc_skill_name() {
    local all_passed=true
    local bad_slash_sdlc

    [ -f "$REPO_DIR/skill-sources/sdlc/SKILL.template.md" ] || all_passed=false
    [ ! -e "$REPO_DIR/skill-sources/codex-sdlc" ] || all_passed=false
    grep -q '^name: sdlc$' "$REPO_DIR/skill-sources/sdlc/SKILL.template.md" || all_passed=false
    grep -q '^  display_name: sdlc$' "$REPO_DIR/skill-sources/sdlc/agents/openai.yaml" || all_passed=false
    grep -Fq 'Canonical entrypoint: `$sdlc`' "$REPO_DIR/README.md" || all_passed=false
    grep -Fq 'Codex treats same-name skills from different scopes as distinct choices' "$REPO_DIR/README.md" || all_passed=false
    grep -Fq 'normal setup installs global helper skills only' "$REPO_DIR/README.md" || all_passed=false
    grep -Fq 'Canonical entrypoint: `$sdlc`' "$REPO_DIR/skill-sources/sdlc/SKILL.template.md" || all_passed=false
    grep -Fq 'do not pretend Codex has a native `/sdlc` command' "$REPO_DIR/skill-sources/sdlc/SKILL.template.md" || all_passed=false
    grep -RE '\$codex-sdlc([^A-Za-z0-9_-]|$)' "$REPO_DIR/README.md" "$REPO_DIR/skills/codex-sdlc-wizard/SKILL.md" "$REPO_DIR/skill-sources" 2>/dev/null && all_passed=false
    bad_slash_sdlc=$(grep -REin '(invoke|run|use|type|call|start|enter|execute)[[:space:]]+(the[[:space:]]+)?`?/sdlc`?' "$REPO_DIR/README.md" "$REPO_DIR/skills/codex-sdlc-wizard/SKILL.md" "$REPO_DIR/skill-sources" "$REPO_DIR/START-SDLC.md" "$REPO_DIR/SDLC-LOOP.md" 2>/dev/null || true)
    [ -z "$bad_slash_sdlc" ] || all_passed=false

    if [ "$all_passed" = "true" ]; then
        pass "package exposes one canonical SDLC skill name, display name, and entrypoint: sdlc"
    else
        fail "package still exposes duplicate or legacy SDLC skill naming"
    fi
}

test_package_cli_help_documents_bootstrap_profile_policy() {
    local output
    output=$(node "$REPO_DIR/bin/codex-sdlc-wizard.js" --help 2>&1)

    if echo "$output" | grep -Eqi 'default.*adaptive setup|adaptive setup.*default' &&
       echo "$output" | grep -Eqi 'setup.*maximum|bootstrap.*maximum' &&
       echo "$output" | grep -Eqi 'normal.*(driver|work).*Sol high|Sol high.*normal.*(driver|work)' &&
       echo "$output" | grep -Eqi 'mixed.*experimental.*explicit opt-in|experimental.*mixed.*explicit opt-in' &&
       ! echo "$output" | grep -Eqi 'routine work.*mixed|day-to-day.*mixed|after bootstrap.*mixed'; then
        pass "npm CLI help documents Sol high as the normal driver and mixed as experimental opt-in"
    else
        fail "npm CLI help does not document the Sol-high default and experimental mixed policy"
    fi
}

test_package_cli_help_explains_update_version_boundary() {
    local output
    output=$(node "$REPO_DIR/bin/codex-sdlc-wizard.js" --help 2>&1)

    if echo "$output" | grep -Fq 'npx codex-sdlc-wizard@latest update' &&
       echo "$output" | grep -Fq 'does not self-update the npm package'; then
        pass "npm CLI help explains that update uses the invoked package version"
    else
        fail "npm CLI help does not explain how to consume the newest package during update"
    fi
}

test_package_cli_help_mentions_check() {
    local output
    local exit_code

    output=$(node "$REPO_DIR/bin/codex-sdlc-wizard.js" --help 2>&1)
    exit_code=$?

    if [ "$exit_code" -ne 0 ]; then
        fail "npm CLI help failed while checking for check command"
        return
    fi

    if echo "$output" | grep -q 'check'; then
        pass "npm CLI help advertises the check command"
    else
        fail "npm CLI help is missing the check command"
    fi
}

test_package_cli_help_mentions_update() {
    local output
    local exit_code

    output=$(node "$REPO_DIR/bin/codex-sdlc-wizard.js" --help 2>&1)
    exit_code=$?

    if [ "$exit_code" -ne 0 ]; then
        fail "npm CLI help failed while checking for update command"
        return
    fi

    if echo "$output" | grep -q 'update'; then
        pass "npm CLI help advertises the update command"
    else
        fail "npm CLI help is missing the update command"
    fi
}

test_package_cli_runs_check_command() {
    local tmpdir
    tmpdir=$(mktemp -d)
    local output
    local exit_code

    set +e
    output=$(cd "$tmpdir" && node "$REPO_DIR/bin/codex-sdlc-wizard.js" check 2>&1)
    exit_code=$?
    set -e

    rm -rf "$tmpdir"

    if [ "$exit_code" -eq 0 ] \
        && echo "$output" | grep -q '"repo_state"[[:space:]]*:[[:space:]]*"uninitialized"' \
        && echo "$output" | grep -q '"reason"[[:space:]]*:[[:space:]]*"manifest_missing"'; then
        pass "npm CLI runs check.sh and reports uninitialized repos"
    else
        fail "npm CLI check command did not return the expected uninitialized repo payload"
    fi
}

test_package_cli_runs_update_command() {
    local tmpdir
    tmpdir=$(mktemp -d)
    local output
    local exit_code

    set +e
    output=$(cd "$tmpdir" && node "$REPO_DIR/bin/codex-sdlc-wizard.js" update check-only 2>&1)
    exit_code=$?
    set -e

    rm -rf "$tmpdir"

    if [ "$exit_code" -ne 0 ] \
        && echo "$output" | grep -qi 'uninitialized' \
        && echo "$output" | grep -q '\$setup-wizard'; then
        pass "npm CLI runs update.sh and reports uninitialized repos"
    else
        fail "npm CLI update command did not report the expected uninitialized repo guidance"
    fi
}

test_readme_mentions_npx_entrypoint() {
    if grep -q 'npx codex-sdlc-wizard' "$REPO_DIR/README.md" \
        && grep -q 'npx codex-sdlc-wizard@latest' "$REPO_DIR/README.md" \
        && grep -q 'npx codex-sdlc-wizard check' "$REPO_DIR/README.md"; then
        pass "README documents the npm entrypoint"
    else
        fail "README is missing the npm entrypoint"
    fi
}

test_readme_explains_plugin_to_daily_workflow() {
    local readme="$REPO_DIR/README.md"
    local valid=true

    grep -Fq '## Which entry point should I use?' "$readme" || valid=false
    grep -Fq '`/plugins`' "$readme" || valid=false
    grep -Fq '`$codex-sdlc-wizard`' "$readme" || valid=false
    grep -Fq '`$sdlc`' "$readme" || valid=false
    grep -Fq 'Ordinary Chat' "$readme" || valid=false

    if [ "$valid" = "true" ]; then
        pass "README explains plugin installation, repo setup, and daily SDLC as separate steps"
    else
        fail "README lacks a concise plugin-to-installer-to-daily-workflow decision path"
    fi
}

test_e2e_requires_explicit_token_opt_in() {
    if grep -q 'CODEX_E2E:-0' "$REPO_DIR/tests/test-e2e.sh" \
        && grep -q 'CODEX_E2E=1 bash tests/test-e2e.sh' "$REPO_DIR/README.md" \
        && grep -qi 'token-consuming' "$REPO_DIR/README.md"; then
        pass "E2E tests require explicit token-consuming opt-in"
    else
        fail "E2E tests should be opt-in so normal verification does not consume tokens"
    fi
}

test_e2e_bypasses_hook_trust_only_for_ephemeral_automation() {
    local exec_count
    local bypass_count

    exec_count=$(grep -Ec '^[[:space:]]*output=.*codex exec' "$REPO_DIR/tests/test-e2e.sh")
    bypass_count=$(grep -c -- '--dangerously-bypass-hook-trust' "$REPO_DIR/tests/test-e2e.sh" || true)

    if [ "$exec_count" -gt 0 ] && [ "$bypass_count" -eq "$exec_count" ]; then
        pass "E2E explicitly bypasses hook trust for every ephemeral automation session"
    else
        fail "E2E must bypass hook trust for each ephemeral temp repo (exec=$exec_count, bypass=$bypass_count)"
    fi
}

test_docs_document_proof_stamp_gate() {
    if grep -q 'git-guard.cjs prove --reviewed' "$REPO_DIR/PROVE-IT.md" \
        && grep -q 'git-guard.cjs prove --reviewed' "$REPO_DIR/README.md" \
        && grep -Fq 'node .codex/hooks/git-guard.cjs prove --reviewed --check "node scripts/run-proof-suite.cjs"' "$REPO_DIR/PROVE-IT.md" \
        && grep -Fq 'node .codex/hooks/git-guard.cjs prove --reviewed --check "node scripts/run-proof-suite.cjs"' "$REPO_DIR/README.md" \
        && grep -q 'fresh SDLC proof' "$REPO_DIR/README.md" \
        && grep -qi 'same-repository linked worktree' "$REPO_DIR/README.md" \
        && grep -qi 'same-repository linked worktree' "$REPO_DIR/PROVE-IT.md" \
        && grep -q 'GIT_NAMESPACE' "$REPO_DIR/README.md" \
        && grep -q 'GIT_OBJECT_DIRECTORY' "$REPO_DIR/README.md" \
        && grep -q 'GIT_NAMESPACE' "$REPO_DIR/PROVE-IT.md" \
        && grep -q 'GIT_OBJECT_DIRECTORY' "$REPO_DIR/PROVE-IT.md" \
        && grep -q 'git -C' "$REPO_DIR/README.md" \
        && grep -q 'git -C' "$REPO_DIR/PROVE-IT.md" \
        && grep -q 'Invoke-Pester' "$REPO_DIR/README.md" \
        && grep -q -- '-EnableExit' "$REPO_DIR/README.md" \
        && grep -q 'Invoke-Pester' "$REPO_DIR/PROVE-IT.md" \
        && grep -q -- '-EnableExit' "$REPO_DIR/PROVE-IT.md" \
        && grep -q 'scan.language' "$REPO_DIR/README.md" \
        && grep -q '`"PowerShell"`' "$REPO_DIR/README.md" \
        && grep -q '& ./tests.ps1' "$REPO_DIR/README.md" \
        && grep -q 'mixed shell/PowerShell' "$REPO_DIR/README.md" \
        && grep -q 'scan.language' "$REPO_DIR/PROVE-IT.md" \
        && grep -q '`"PowerShell"`' "$REPO_DIR/PROVE-IT.md" \
        && grep -q '& ./tests.ps1' "$REPO_DIR/PROVE-IT.md" \
        && grep -q 'mixed shell/PowerShell' "$REPO_DIR/PROVE-IT.md"; then
        pass "docs document the proof-stamp git gate"
    else
        fail "docs should explain the proof-stamp git gate"
    fi
}

test_fable_review_requires_consent_and_safe_subscription_auth() {
    local ws fake_dir fake_cli marker output status valid=true
    ws=$(mktemp -d)
    fake_dir=$(mktemp -d)
    fake_cli="$fake_dir/fake-claude.cjs"
    marker="$fake_dir/invoked.json"

    git -C "$ws" init -q
    git -C "$ws" config user.email test@example.com
    git -C "$ws" config user.name "SDLC Test"
    printf '%s\n' baseline > "$ws/file.txt"
    mkdir -p "$ws/.codex/hooks"
    cp "$UNIVERSAL_PRETOOL_SCRIPT" "$ws/.codex/hooks/git-guard.cjs"
    git -C "$ws" add file.txt .codex/hooks/git-guard.cjs
    git -C "$ws" commit -qm baseline
    printf '%s\n' candidate > "$ws/file.txt"
    git -C "$ws" add file.txt
    (cd "$ws" && node .codex/hooks/git-guard.cjs prove --reviewed --check true >/dev/null)

    cat > "$fake_cli" <<'NODE'
const fs = require("node:fs");
const args = process.argv.slice(2);
if (args[0] === "auth" && args[1] === "status") {
  process.stdout.write(JSON.stringify({
    authMethod: "claude.ai",
    apiProvider: "firstParty",
    subscriptionType: "max",
  }));
  process.exit(0);
}
fs.writeFileSync(process.env.FABLE_TEST_MARKER, JSON.stringify({
  args,
  cwd: process.cwd(),
  hasApiKey: Boolean(process.env.ANTHROPIC_API_KEY),
  prompt: fs.readFileSync(0, "utf8"),
}));
process.stdout.write(JSON.stringify([
  { type: "system", subtype: "init", model: "claude-fable-5" },
  {
    type: "result",
    model: "claude-fable-5",
    result: JSON.stringify({ findings: [], verdict: "CERTIFIED" }),
    structured_output: { findings: [], verdict: "CERTIFIED" },
  },
]));
NODE

    set +e
    output=$(cd "$ws" && CODEX_SDLC_TEST_MODE=1 CODEX_SDLC_CLAUDE_PATH="$fake_cli" \
        FABLE_TEST_MARKER="$marker" node "$FABLE_REVIEW_SCRIPT" --base HEAD 2>&1)
    status=$?
    set -e
    [ "$status" -eq 2 ] || valid=false
    echo "$output" | grep -qi 'consent-subscription-quota' || valid=false
    [ ! -e "$marker" ] || valid=false

    set +e
    output=$(cd "$ws" && ANTHROPIC_API_KEY=unsafe CODEX_SDLC_TEST_MODE=1 \
        CODEX_SDLC_CLAUDE_PATH="$fake_cli" FABLE_TEST_MARKER="$marker" \
        node "$FABLE_REVIEW_SCRIPT" --base HEAD --consent-subscription-quota 2>&1)
    status=$?
    set -e
    [ "$status" -eq 2 ] || valid=false
    echo "$output" | grep -qi 'ANTHROPIC_API_KEY' || valid=false
    [ ! -e "$marker" ] || valid=false

    rm -rf "$ws" "$fake_dir"
    if [ "$valid" = "true" ]; then
        pass "Fable review requires quota consent and rejects metered API auth"
    else
        fail "Fable review should require consent and verified subscription auth"
    fi
}

test_fable_review_is_tool_free_high_and_candidate_bound() {
    local ws fake_dir fake_cli marker receipt base tree output status valid=true
    ws=$(mktemp -d)
    fake_dir=$(mktemp -d)
    fake_cli="$fake_dir/fake-claude.cjs"
    marker="$fake_dir/invoked.json"

    git -C "$ws" init -q
    git -C "$ws" config user.email test@example.com
    git -C "$ws" config user.name "SDLC Test"
    printf '%s\n' baseline > "$ws/file.txt"
    mkdir -p "$ws/.codex/hooks"
    cp "$UNIVERSAL_PRETOOL_SCRIPT" "$ws/.codex/hooks/git-guard.cjs"
    git -C "$ws" add file.txt .codex/hooks/git-guard.cjs
    git -C "$ws" commit -qm baseline
    base=$(git -C "$ws" rev-parse HEAD)
    printf '%s\n' candidate > "$ws/file.txt"
    git -C "$ws" add file.txt
    tree=$(git -C "$ws" write-tree)
    (cd "$ws" && node .codex/hooks/git-guard.cjs prove --reviewed --check true >/dev/null)

    cat > "$fake_cli" <<'NODE'
const fs = require("node:fs");
const args = process.argv.slice(2);
if (args[0] === "auth" && args[1] === "status") {
  process.stdout.write(JSON.stringify({
    authMethod: "claude.ai",
    apiProvider: "firstParty",
    subscriptionType: "max",
  }));
  process.exit(0);
}
fs.writeFileSync(process.env.FABLE_TEST_MARKER, JSON.stringify({
  args,
  cwd: process.cwd(),
  hasApiKey: Boolean(process.env.ANTHROPIC_API_KEY),
  prompt: fs.readFileSync(0, "utf8"),
}));
if (process.env.FABLE_TEST_MUTATE_PATH) {
  fs.appendFileSync(process.env.FABLE_TEST_MUTATE_PATH, "changed during review\n");
}
process.stdout.write(JSON.stringify([
  { type: "system", subtype: "init", model: "claude-fable-5" },
  {
    type: "result",
    model: "claude-fable-5",
    result: JSON.stringify({ findings: [], verdict: "CERTIFIED" }),
    structured_output: { findings: [], verdict: "CERTIFIED" },
  },
]));
NODE

    set +e
    output=$(cd "$ws" && CODEX_SDLC_TEST_MODE=1 CODEX_SDLC_CLAUDE_PATH="$fake_cli" \
        FABLE_TEST_MARKER="$marker" node "$FABLE_REVIEW_SCRIPT" --base HEAD \
        --consent-subscription-quota 2>&1)
    status=$?
    set -e
    receipt=$(git -C "$ws" rev-parse --git-path codex-sdlc/fable-review.json)

    [ "$status" -eq 0 ] || valid=false
    [ -f "$ws/$receipt" ] || [ -f "$receipt" ] || valid=false
    RECEIPT_PATH=$(cd "$ws" && git rev-parse --git-path codex-sdlc/fable-review.json)
    if [[ "$RECEIPT_PATH" != /* ]]; then RECEIPT_PATH="$ws/$RECEIPT_PATH"; fi
    RECEIPT_PATH="$RECEIPT_PATH" MARKER_PATH="$marker" BASE_SHA="$base" TREE_SHA="$tree" node <<'NODE' || valid=false
const fs = require("node:fs");
const receipt = JSON.parse(fs.readFileSync(process.env.RECEIPT_PATH, "utf8"));
const call = JSON.parse(fs.readFileSync(process.env.MARKER_PATH, "utf8"));
const requiredArgs = ["-p", "--model", "fable", "--effort", "high", "--safe-mode", "--max-turns", "1", "--setting-sources", "user", "--tools", "", "--disable-slash-commands", "--no-session-persistence", "--json-schema", "--output-format", "json"];
for (const value of requiredArgs) {
  if (!call.args.includes(value)) process.exit(1);
}
if (call.cwd === process.cwd()) process.exit(1);
if (call.hasApiKey) process.exit(1);
if (!call.prompt.includes(`Base commit: ${process.env.BASE_SHA}`)) process.exit(1);
if (!call.prompt.includes(`Candidate tree: ${process.env.TREE_SHA}`)) process.exit(1);
if (!call.prompt.includes("Do not rerun tests")) process.exit(1);
if (!call.prompt.includes("code-review findings only")) process.exit(1);
if (receipt.status !== "certified") process.exit(1);
if (receipt.base_commit !== process.env.BASE_SHA) process.exit(1);
if (receipt.candidate_tree !== process.env.TREE_SHA) process.exit(1);
if (receipt.reviewer_effort !== "high") process.exit(1);
if (!String(receipt.patch_sha256 || "").startsWith("sha256:")) process.exit(1);
if (!receipt.report.endsWith("Verdict: CERTIFIED")) process.exit(1);
NODE
    echo "$output" | grep -q 'Fable review certified' || valid=false

    set +e
    output=$(cd "$ws" && CODEX_SDLC_TEST_MODE=1 CODEX_SDLC_CLAUDE_PATH="$fake_cli" \
        FABLE_TEST_MARKER="$marker" FABLE_TEST_MUTATE_PATH="$ws/file.txt" \
        node "$FABLE_REVIEW_SCRIPT" --base HEAD --consent-subscription-quota 2>&1)
    status=$?
    set -e
    [ "$status" -eq 2 ] || valid=false
    echo "$output" | grep -Eqi 'candidate.*(changed|unstaged)|unstaged.*candidate' || valid=false
    [ ! -f "$RECEIPT_PATH" ] || valid=false

    rm -rf "$ws" "$fake_dir"
    if [ "$valid" = "true" ]; then
        pass "Fable review is isolated, tool-free, high-effort, and candidate-bound"
    else
        echo "$output"
        fail "Fable review did not preserve its bounded review contract"
    fi
}

test_fable_review_rejects_stale_proof() {
    local ws fake_dir fake_cli marker output status valid=true
    ws=$(mktemp -d)
    fake_dir=$(mktemp -d)
    fake_cli="$fake_dir/fake-claude.cjs"
    marker="$fake_dir/invoked.json"

    git -C "$ws" init -q
    git -C "$ws" config user.email test@example.com
    git -C "$ws" config user.name "SDLC Test"
    printf '%s\n' baseline > "$ws/file.txt"
    mkdir -p "$ws/.codex/hooks"
    cp "$UNIVERSAL_PRETOOL_SCRIPT" "$ws/.codex/hooks/git-guard.cjs"
    git -C "$ws" add file.txt .codex/hooks/git-guard.cjs
    git -C "$ws" commit -qm baseline
    printf '%s\n' candidate > "$ws/file.txt"
    git -C "$ws" add file.txt
    (cd "$ws" && node .codex/hooks/git-guard.cjs prove --reviewed --check true >/dev/null)
    printf '%s\n' changed-after-proof > "$ws/file.txt"
    git -C "$ws" add file.txt
    cat > "$fake_cli" <<'NODE'
const args = process.argv.slice(2);
if (args[0] === "auth" && args[1] === "status") {
  process.stdout.write(JSON.stringify({
    authMethod: "claude.ai",
    apiProvider: "firstParty",
    subscriptionType: "max",
  }));
  process.exit(0);
}

process.exit(99);
NODE

    set +e
    output=$(cd "$ws" && CODEX_SDLC_TEST_MODE=1 CODEX_SDLC_CLAUDE_PATH="$fake_cli" \
        FABLE_TEST_MARKER="$marker" node "$FABLE_REVIEW_SCRIPT" --base HEAD \
        --consent-subscription-quota 2>&1)
    status=$?
    set -e
    [ "$status" -eq 2 ] || valid=false
    echo "$output" | grep -qi 'proof.*stale\|stale.*proof' || valid=false
    [ ! -e "$marker" ] || valid=false

    rm -rf "$ws" "$fake_dir"
    if [ "$valid" = "true" ]; then
        pass "Fable review rejects a stale proof before invoking Claude"
    else
        echo "$output"
        fail "Fable review should reject stale candidate proof"
    fi
}

test_fable_review_uses_windows_cmd_shim_and_freezes_before_proof_check() {
    local valid=true

    FABLE_REVIEW_PATH="$FABLE_REVIEW_SCRIPT" node <<'NODE' || valid=false
const fs = require("node:fs");
const source = fs.readFileSync(process.env.FABLE_REVIEW_PATH, "utf8");
if (!source.includes('process.platform === "win32"')) process.exit(1);
if (!source.includes("process.env.ComSpec")) process.exit(1);
if (!source.includes('["/d", "/s", "/c", "claude"]')) process.exit(1);
const candidateIndex = source.indexOf('const candidateTree = git(root, ["write-tree"]);');
const proofIndex = source.indexOf("proofStatus(root);");
if (candidateIndex < 0 || proofIndex < 0 || candidateIndex >= proofIndex) process.exit(1);
NODE

    if [ "$valid" = "true" ]; then
        pass "Fable review launches the Windows cmd shim and freezes its candidate before proof verification"
    else
        fail "Fable review lacks safe Windows shim launch or verifies proof before freezing its candidate"
    fi
}

test_pretool_blocks_commit
test_pretool_blocks_push
test_pretool_blocks_git_after_shell_prefixes
test_pretool_allows_safe_command
test_pretool_reads_command_field
test_pretool_allows_non_git_command_mentions
test_pretool_does_not_crash_on_non_git_prototype_words
test_pretool_blocks_deep_wrapper_recursion
test_session_warns_missing
test_session_silent_when_present
test_universal_pretool_blocks_commit
test_universal_pretool_allows_commit_with_fresh_proof
test_universal_proof_runs_powershell_manifest_commands_in_pwsh
test_universal_proof_rejects_shell_prefixed_powershell_hosts
test_universal_proof_preserves_powershell_names_as_data
test_universal_proof_rejects_pester_without_exit_propagation
test_universal_proof_accepts_pester_switch_after_quoted_separators
test_universal_proof_checks_every_pester_entry_from_zero_depth
test_universal_proof_validates_explicit_powershell_host_wrappers
test_universal_proof_ignores_placeholder_manifest_commands
test_universal_proof_preserves_commands_that_begin_with_none
test_universal_pretool_blocks_stale_proof
test_universal_pretool_blocks_cross_repo_proof_reuse
test_universal_pretool_blocks_cd_proof_reuse
test_universal_pretool_blocks_git_env_proof_reuse
test_universal_pretool_blocks_exported_git_env_proof_reuse
test_universal_pretool_blocks_auto_exported_git_env_proof_reuse
test_universal_pretool_blocks_workdir_proof_reuse
test_universal_pretool_allows_workdir_with_fresh_proof
test_universal_pretool_allows_linked_worktree_with_fresh_proof
test_universal_pretool_supports_git_without_path_format
test_universal_pretool_reports_git_context_inspection_failure
test_universal_pretool_preserves_builtin_git_action_precedence
test_universal_pretool_allows_inert_inherited_git_settings
test_universal_pretool_allows_same_context_git_dir_without_index
test_universal_pretool_blocks_inherited_linked_worktree_rebinding
test_universal_pretool_blocks_inherited_config_worktree_proof_rebinding
test_universal_pretool_preserves_case_sensitive_worktree_identity
test_universal_pretool_allows_case_variant_linked_worktree_context
test_universal_pretool_blocks_case_variant_windows_git_env
test_universal_pretool_blocks_windows_cmd_path_expansion
test_universal_pretool_blocks_symlink_parent_directory_rebinding
test_universal_pretool_blocks_linked_worktree_without_fresh_proof
test_universal_pretool_blocks_wrapper_directory_proof_rebinding
test_universal_pretool_blocks_shell_alias_proof_rebinding
test_universal_pretool_blocks_git_after_shell_prefixes
test_universal_pretool_allows_non_git_command_mentions
test_universal_pretool_does_not_crash_on_non_git_prototype_words
test_universal_pretool_blocks_deep_wrapper_recursion
test_universal_session_warns_missing
test_universal_compact_guard_emits_lifecycle_context
test_universal_compact_guard_handles_post_compact
test_universal_node_hooks_work_in_type_module_repos
test_hooks_json_matcher
test_hooks_json_valid
test_live_hooks_file_uses_universal_node_hooks
test_live_hooks_file_is_windows_safe
test_config_enables_hooks
test_install_preserves_agents_md
test_install_reports_current_agents_baseline
test_install_omits_inactive_prompt_hook
test_installers_share_agents_ownership_messages
test_install_creates_sdlc_docs
test_install_creates_skill
test_install_keeps_skill_backups_out_of_skills_and_prunes_legacy_sdlc
test_install_merges_config
test_install_backs_up_hooks_json
test_install_merges_existing_hooks_json
test_merge_fresh_file_honors_restrictive_umask
test_check_passes_merge_helper_as_node_argument
test_install_rejects_malformed_hooks_without_overwrite
test_check_reports_non_object_hooks_as_broken
test_check_reports_structurally_invalid_hooks_as_broken
test_merge_status_distinguishes_broken_target_from_bad_template
test_install_refreshes_unmodified_agents_for_profile_switch
test_profile_guidance_refresh_rejects_missing_reasoning
test_profile_guidance_refresh_handles_legacy_and_partial_guidance
test_install_refreshes_only_touched_manifest_hashes
test_agents_md_size
test_setup_skill_has_confidence_setup_contract
test_update_skill_has_idempotent_update_contract
test_update_skill_has_sol_high_default_contract
test_skills_document_hooks_feature_rename
test_update_skill_frontloads_package_upgrade_boundary
test_helper_skill_metadata_uses_codex_sdlc_not_xdlc
test_setup_and_update_skills_stop_before_product_remediation
test_feedback_skill_has_privacy_prompt_and_dedupe
test_setup_docs_include_codex_desktop_handoff
test_setup_docs_include_m365_auth_lane_guidance
test_setup_docs_include_task_routing_gate
test_sdlc_skill_has_docsync_learning_and_merge_guard
test_repo_defaults_consumer_and_maintainer_work_to_sol_high
test_repo_documents_max_ultra_reasoning_boundary
test_package_has_npm_release_surface
test_package_uses_single_canonical_sdlc_skill_name
test_package_cli_is_honest_about_supported_flags
test_package_cli_help_documents_bootstrap_profile_policy
test_package_cli_help_explains_update_version_boundary
test_package_cli_help_mentions_check
test_package_cli_help_mentions_update
test_package_cli_runs_check_command
test_package_cli_runs_update_command
test_readme_mentions_npx_entrypoint
test_readme_explains_plugin_to_daily_workflow
test_e2e_requires_explicit_token_opt_in
test_e2e_bypasses_hook_trust_only_for_ephemeral_automation
test_docs_document_proof_stamp_gate
test_fable_review_requires_consent_and_safe_subscription_auth
test_fable_review_is_tool_free_high_and_candidate_bound
test_fable_review_rejects_stale_proof
test_fable_review_uses_windows_cmd_shim_and_freezes_before_proof_check

echo ""
echo "=== Results: $PASSED passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
    exit 1
fi
