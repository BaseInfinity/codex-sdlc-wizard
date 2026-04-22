#!/bin/bash
# Test Codex SDLC Adapter — hook behavior, payload format, config, install
# Tests validate BEHAVIOR against real Codex hook payloads, not just existence

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$SCRIPT_DIR/.."
HOOKS_DIR="$REPO_DIR/.codex/hooks"
PASSED=0
FAILED=0

# Color output
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

echo "=== Codex SDLC Adapter Tests ==="
echo ""

# ---- Hook behavior tests ----

# Test 1: sdlc-prompt-check.sh outputs SDLC keywords (TDD, confidence, test)
test_sdlc_prompt_keywords() {
    local output
    output=$("$HOOKS_DIR/sdlc-prompt-check.sh" 2>/dev/null)
    local has_all=true
    for keyword in "TDD" "confidence" "test"; do
        if ! echo "$output" | grep -qi "$keyword"; then
            has_all=false
            break
        fi
    done
    if [ "$has_all" = "true" ]; then
        pass "sdlc-prompt-check.sh outputs SDLC keywords (TDD, confidence, test)"
    else
        fail "sdlc-prompt-check.sh missing expected SDLC keywords"
    fi
}

# Test 2: bash-guard.sh blocks git commit
test_bash_guard_blocks_commit() {
    local output
    output=$(echo '{"tool_input":{"command":"git commit -m '\''test'\''"}}' | "$HOOKS_DIR/bash-guard.sh" 2>/dev/null)
    if echo "$output" | jq -e '.decision == "block"' >/dev/null 2>&1; then
        pass "bash-guard.sh blocks git commit"
    else
        fail "bash-guard.sh did not block git commit (output: $output)"
    fi
}

# Test 3: bash-guard.sh blocks git push
test_bash_guard_blocks_push() {
    local output
    output=$(echo '{"tool_input":{"command":"git push origin main"}}' | "$HOOKS_DIR/bash-guard.sh" 2>/dev/null)
    if echo "$output" | jq -e '.decision == "block"' >/dev/null 2>&1; then
        pass "bash-guard.sh blocks git push"
    else
        fail "bash-guard.sh did not block git push (output: $output)"
    fi
}

# Test 4: bash-guard.sh allows other commands (npm test)
test_bash_guard_allows_npm_test() {
    local output
    output=$(echo '{"tool_input":{"command":"npm test"}}' | "$HOOKS_DIR/bash-guard.sh" 2>/dev/null)
    if [ -z "$output" ]; then
        pass "bash-guard.sh allows npm test (no output)"
    else
        fail "bash-guard.sh unexpectedly blocked npm test (output: $output)"
    fi
}

# Test 5: bash-guard.sh allows git diff
test_bash_guard_allows_git_diff() {
    local output
    output=$(echo '{"tool_input":{"command":"git diff"}}' | "$HOOKS_DIR/bash-guard.sh" 2>/dev/null)
    if [ -z "$output" ]; then
        pass "bash-guard.sh allows git diff (no output)"
    else
        fail "bash-guard.sh unexpectedly blocked git diff (output: $output)"
    fi
}

# Test 6: session-start.sh warns when AGENTS.md missing
test_session_start_warns_missing() {
    local tmpdir
    tmpdir=$(mktemp -d)
    local output
    output=$(cd "$tmpdir" && "$HOOKS_DIR/session-start.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    if echo "$output" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1; then
        pass "session-start.sh warns when AGENTS.md missing"
    else
        fail "session-start.sh did not warn about missing AGENTS.md (output: $output)"
    fi
}

# Test 7: session-start.sh silent when AGENTS.md present
test_session_start_silent_when_present() {
    local tmpdir
    tmpdir=$(mktemp -d)
    touch "$tmpdir/AGENTS.md"
    local output
    output=$(cd "$tmpdir" && "$HOOKS_DIR/session-start.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    if [ -z "$output" ]; then
        pass "session-start.sh silent when AGENTS.md present"
    else
        fail "session-start.sh produced output when AGENTS.md exists (output: $output)"
    fi
}

# ---- Payload format tests ----

# Test 8: bash-guard.sh reads tool_input.command (NOT file_path)
test_bash_guard_reads_command_field() {
    # Send a payload with file_path containing "git commit" but command containing something safe
    local output
    output=$(echo '{"tool_input":{"command":"echo hello","file_path":"git commit -m test"}}' | "$HOOKS_DIR/bash-guard.sh" 2>/dev/null)
    if [ -z "$output" ]; then
        pass "bash-guard.sh reads tool_input.command, not file_path"
    else
        fail "bash-guard.sh incorrectly reads file_path instead of command"
    fi
}

# Test 9: bash-guard.sh also blocks root-level command payloads
test_bash_guard_blocks_root_command_field() {
    local output
    output=$(echo '{"command":"git commit -m '\''test'\''"}' | "$HOOKS_DIR/bash-guard.sh" 2>/dev/null)
    if echo "$output" | jq -e '.decision == "block"' >/dev/null 2>&1; then
        pass "bash-guard.sh blocks git commit from a root-level command field too"
    else
        fail "bash-guard.sh did not block git commit from a root-level command field (output: $output)"
    fi
}

# Test 10: bash-guard.sh blocks git commit even when git -c flags are present
test_bash_guard_blocks_commit_with_git_flags() {
    local output
    output=$(echo '{"tool_input":{"command":"git -c user.name=test -c user.email=test@example.com commit -m '\''test'\''"}}' | "$HOOKS_DIR/bash-guard.sh" 2>/dev/null)
    if echo "$output" | jq -e '.decision == "block"' >/dev/null 2>&1; then
        pass "bash-guard.sh blocks git commit even when git -c flags are present"
    else
        fail "bash-guard.sh did not block git commit with git -c flags (output: $output)"
    fi
}

# Test 11: bash-guard.sh blocks a bare interactive shell launch used to bypass commit/push guards
test_bash_guard_blocks_bare_interactive_shell() {
    local output
    output=$(echo '{"tool_input":{"command":"zsh"}}' | "$HOOKS_DIR/bash-guard.sh" 2>/dev/null)
    if echo "$output" | jq -e '.decision == "block"' >/dev/null 2>&1; then
        pass "bash-guard.sh blocks a bare interactive shell launch"
    else
        fail "bash-guard.sh did not block a bare interactive shell launch (output: $output)"
    fi
}

# Test 12: hooks.json PreToolUse matcher covers both legacy Bash and current command_execution
test_hooks_json_matcher() {
    local matcher
    matcher=$(jq -r '.hooks.PreToolUse[0].matcher' "$REPO_DIR/.codex/hooks.json" 2>/dev/null)
    if [ "$matcher" = "^(Bash|command_execution)\$" ]; then
        pass "hooks.json PreToolUse matcher covers Bash and command_execution for Codex shell runs"
    else
        fail "hooks.json PreToolUse matcher is '$matcher' — should cover Bash and command_execution"
    fi
}

# Test 13: hooks.json is valid JSON with correct event-keyed format
test_hooks_json_valid() {
    if jq -e '.hooks.UserPromptSubmit and .hooks.PreToolUse and .hooks.SessionStart' "$REPO_DIR/.codex/hooks.json" >/dev/null 2>&1; then
        pass "hooks.json is valid JSON with all 3 event keys"
    else
        fail "hooks.json invalid or missing event keys"
    fi
}

# ---- Config and install tests ----

# Test 14: config.toml enables codex_hooks feature flag
test_config_enables_hooks() {
    if grep -q 'codex_hooks\s*=\s*true' "$REPO_DIR/.codex/config.toml" 2>/dev/null; then
        pass "config.toml enables codex_hooks = true"
    else
        fail "config.toml missing codex_hooks = true"
    fi
}

# Test 15: install.sh doesn't overwrite existing AGENTS.md
test_install_preserves_agents_md() {
    local tmpdir
    tmpdir=$(mktemp -d)
    echo "CUSTOM AGENTS CONTENT" > "$tmpdir/AGENTS.md"
    (cd "$tmpdir" && bash "$REPO_DIR/install.sh" >/dev/null 2>&1)
    local content
    content=$(cat "$tmpdir/AGENTS.md")
    rm -rf "$tmpdir"
    if [ "$content" = "CUSTOM AGENTS CONTENT" ]; then
        pass "install.sh preserves existing AGENTS.md"
    else
        fail "install.sh overwrote existing AGENTS.md"
    fi
}

# Test 16: install.sh merges codex_hooks into existing config.toml (4 cases)
test_install_merges_config() {
    local all_passed=true

    # Case 1: false → true
    local tmpdir1
    tmpdir1=$(mktemp -d)
    mkdir -p "$tmpdir1/.codex"
    printf '[features]\ncodex_hooks = false\n' > "$tmpdir1/.codex/config.toml"
    (cd "$tmpdir1" && bash "$REPO_DIR/install.sh" >/dev/null 2>&1)
    if ! grep -q 'codex_hooks = true' "$tmpdir1/.codex/config.toml"; then
        fail "install.sh case 1: did not flip false→true"
        all_passed=false
    fi
    rm -rf "$tmpdir1"

    # Case 2: already true
    local tmpdir2
    tmpdir2=$(mktemp -d)
    mkdir -p "$tmpdir2/.codex"
    printf '[features]\ncodex_hooks = true\n' > "$tmpdir2/.codex/config.toml"
    (cd "$tmpdir2" && bash "$REPO_DIR/install.sh" >/dev/null 2>&1)
    if ! grep -q 'codex_hooks = true' "$tmpdir2/.codex/config.toml"; then
        fail "install.sh case 2: lost existing codex_hooks = true"
        all_passed=false
    fi
    rm -rf "$tmpdir2"

    # Case 3: [features] exists but no codex_hooks — verify valid TOML structure
    local tmpdir3
    tmpdir3=$(mktemp -d)
    mkdir -p "$tmpdir3/.codex"
    printf '[features]\nsome_other = true\n' > "$tmpdir3/.codex/config.toml"
    (cd "$tmpdir3" && bash "$REPO_DIR/install.sh" >/dev/null 2>&1)
    if ! grep -q 'codex_hooks = true' "$tmpdir3/.codex/config.toml"; then
        fail "install.sh case 3: did not add codex_hooks under existing [features]"
        all_passed=false
    # Verify codex_hooks is on its own line (valid TOML), not concatenated
    elif ! grep -x 'codex_hooks = true' "$tmpdir3/.codex/config.toml" >/dev/null 2>&1; then
        fail "install.sh case 3: codex_hooks not on its own line (invalid TOML)"
        all_passed=false
    fi
    rm -rf "$tmpdir3"

    # Case 4: no [features] table
    local tmpdir4
    tmpdir4=$(mktemp -d)
    mkdir -p "$tmpdir4/.codex"
    printf '[model]\nname = "o3"\n' > "$tmpdir4/.codex/config.toml"
    (cd "$tmpdir4" && bash "$REPO_DIR/install.sh" >/dev/null 2>&1)
    if ! grep -q 'codex_hooks = true' "$tmpdir4/.codex/config.toml"; then
        fail "install.sh case 4: did not add [features] section"
        all_passed=false
    fi
    rm -rf "$tmpdir4"

    # Case 5: commented codex_hooks should NOT count as active (regression for P1 finding)
    local tmpdir5
    tmpdir5=$(mktemp -d)
    mkdir -p "$tmpdir5/.codex"
    printf '[features]\n# codex_hooks = false\n' > "$tmpdir5/.codex/config.toml"
    (cd "$tmpdir5" && bash "$REPO_DIR/install.sh" >/dev/null 2>&1)
    if ! grep -v '^[[:space:]]*#' "$tmpdir5/.codex/config.toml" | grep -q 'codex_hooks = true'; then
        fail "install.sh case 5: commented codex_hooks treated as active — hooks left disabled"
        all_passed=false
    fi
    rm -rf "$tmpdir5"

    # Case 6: commented "# codex_hooks = true" should NOT count as active
    local tmpdir6
    tmpdir6=$(mktemp -d)
    mkdir -p "$tmpdir6/.codex"
    printf '[features]\n# codex_hooks = true\n' > "$tmpdir6/.codex/config.toml"
    (cd "$tmpdir6" && bash "$REPO_DIR/install.sh" >/dev/null 2>&1)
    if ! grep -v '^[[:space:]]*#' "$tmpdir6/.codex/config.toml" | grep -q 'codex_hooks = true'; then
        fail "install.sh case 6: commented 'codex_hooks = true' treated as active"
        all_passed=false
    fi
    rm -rf "$tmpdir6"

    if [ "$all_passed" = "true" ]; then
        pass "install.sh merges codex_hooks into existing config.toml (6 cases)"
    fi
}

# Test 14: install.sh backs up existing hooks.json
test_install_backs_up_hooks_json() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.codex"
    echo '{"old": true}' > "$tmpdir/.codex/hooks.json"
    (cd "$tmpdir" && bash "$REPO_DIR/install.sh" >/dev/null 2>&1)
    local backup_count
    backup_count=$(ls "$tmpdir/.codex/hooks.json.bak."* 2>/dev/null | wc -l | tr -d ' ')
    rm -rf "$tmpdir"
    if [ "$backup_count" -ge 1 ]; then
        pass "install.sh backs up existing hooks.json"
    else
        fail "install.sh did not create hooks.json backup"
    fi
}

# Test 15: AGENTS.md under 32KiB (Codex limit)
test_agents_md_size() {
    local size
    size=$(wc -c < "$REPO_DIR/AGENTS.md" 2>/dev/null | tr -d ' ')
    if [ -n "$size" ] && [ "$size" -lt 32768 ]; then
        pass "AGENTS.md is ${size} bytes (under 32KiB limit)"
    else
        fail "AGENTS.md is ${size:-missing} bytes (must be under 32768)"
    fi
}

# ---- Run all tests ----

test_sdlc_prompt_keywords
test_bash_guard_blocks_commit
test_bash_guard_blocks_push
test_bash_guard_allows_npm_test
test_bash_guard_allows_git_diff
test_session_start_warns_missing
test_session_start_silent_when_present
test_bash_guard_reads_command_field
test_bash_guard_blocks_root_command_field
test_bash_guard_blocks_commit_with_git_flags
test_bash_guard_blocks_bare_interactive_shell
test_hooks_json_matcher
test_hooks_json_valid
test_config_enables_hooks
test_install_preserves_agents_md
test_install_merges_config
test_install_backs_up_hooks_json
test_agents_md_size

echo ""
echo "=== Results: $PASSED passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
    exit 1
fi
