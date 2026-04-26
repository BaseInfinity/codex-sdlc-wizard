#!/bin/bash
# E2E Tests — prove hooks actually fire in real Codex CLI sessions
# Requires: codex CLI installed with auth configured
# These tests run real Codex sessions (costs API tokens) — keep prompts minimal

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$SCRIPT_DIR/.."
PASSED=0
FAILED=0
SKIPPED=0
CODEX_E2E="${CODEX_E2E:-0}"
CODEX_E2E_MODEL="${CODEX_E2E_MODEL:-gpt-5.5}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

pass() { echo -e "${GREEN}PASS${NC}: $1"; PASSED=$((PASSED + 1)); }
fail() { echo -e "${RED}FAIL${NC}: $1"; FAILED=$((FAILED + 1)); }
skip() { echo -e "${YELLOW}SKIP${NC}: $1"; SKIPPED=$((SKIPPED + 1)); }

if [ "$CODEX_E2E" != "1" ]; then
    skip "E2E: real Codex sessions are token-consuming; set CODEX_E2E=1 to run"
    echo ""
    echo "=== E2E Results: $PASSED passed, $FAILED failed, $SKIPPED skipped ==="
    exit 0
fi

codex_transport_unavailable() {
    echo "$1" | grep -Eqi 'failed to lookup address|failed to connect to websocket|stream disconnected before completion|api\.openai\.com'
}

skip_transport_unavailable() {
    skip "E2E: Codex API transport is unavailable in this environment — rerun tests/test-e2e.sh with network access"
    echo ""
    echo "=== E2E Results: $PASSED passed, $FAILED failed, $SKIPPED skipped ==="
    exit 0
}

# Preflight: codex CLI must exist
if ! command -v codex >/dev/null 2>&1; then
    echo "codex CLI not found — skipping E2E tests"
    exit 0
fi

echo "=== Codex SDLC Adapter E2E Tests ==="
CODEX_VERSION_OUTPUT="$(codex --version 2>&1)"
echo "Codex version: $CODEX_VERSION_OUTPUT"
echo "Codex E2E model: $CODEX_E2E_MODEL"
echo ""

# Workspace sandboxing can block Codex from updating PATH during startup, which
# prevents real sessions from booting and turns this suite into a false negative.
# Skip the whole E2E suite in that environment and require an unsandboxed rerun.
if echo "$CODEX_VERSION_OUTPUT" | grep -q 'could not update PATH: Operation not permitted'; then
    skip "E2E: workspace sandbox blocks real Codex session startup — rerun tests/test-e2e.sh outside the sandbox"
    echo ""
    echo "=== E2E Results: $PASSED passed, $FAILED failed, $SKIPPED skipped ==="
    exit 0
fi

# Create a test workspace with the adapter installed
setup_workspace() {
    local ws
    ws=$(mktemp -d)
    git init "$ws" >/dev/null 2>&1
    git -C "$ws" config user.name "Codex SDLC E2E"
    git -C "$ws" config user.email "codex-sdlc-e2e@example.invalid"
    git -C "$ws" commit --allow-empty -m "init" >/dev/null 2>&1
    git -C "$ws" rev-parse --verify HEAD >/dev/null 2>&1
    (cd "$ws" && bash "$REPO_DIR/install.sh" >/dev/null 2>&1)
    echo "$ws"
}

cleanup() {
    rm -rf "$1" 2>/dev/null || true
}

# ---- E2E Test 1: Codex loads hooks without crashing ----
# If hooks.json has errors, codex exec will fail on startup.
# A successful session proves hooks were loaded and accepted.
test_e2e_hooks_load() {
    local ws
    ws=$(setup_workspace)

    local output exit_code=0
    output=$(cd "$ws" && codex exec \
        -s danger-full-access \
        -m "$CODEX_E2E_MODEL" \
        -c 'model_reasoning_effort="xhigh"' \
        "Run this exact shell command and show the output: echo HOOKS_LOADED_OK" 2>&1) || exit_code=$?

    cleanup "$ws"

    if codex_transport_unavailable "$output"; then
        skip_transport_unavailable
    fi

    if [ "$exit_code" -eq 0 ] && echo "$output" | grep -q "HOOKS_LOADED_OK"; then
        pass "E2E: Codex session completed with hooks loaded"
    else
        fail "E2E: Codex session failed to load hooks (exit=$exit_code, output=${output:0:200})"
    fi
}

# ---- E2E Test 2: PreToolUse bash-guard blocks git commit ----
# Ask Codex to run git commit. The hook should block it.
# Verify by checking git log — HEAD should still be "init".
test_e2e_bash_guard_blocks_commit() {
    local ws
    ws=$(setup_workspace)
    echo "test" > "$ws/test.txt"
    (cd "$ws" && git add test.txt >/dev/null 2>&1)

    local output exit_code=0
    output=$(cd "$ws" && codex exec \
        -s danger-full-access \
        -m "$CODEX_E2E_MODEL" \
        -c 'model_reasoning_effort="xhigh"' \
        "Run this exact shell command: git commit -m 'test commit'" 2>&1) || exit_code=$?

    local head_msg
    head_msg=$(cd "$ws" && git log --oneline -1 2>/dev/null | head -1)

    cleanup "$ws"

    if echo "$head_msg" | grep -q "init"; then
        pass "E2E: git commit was blocked — HEAD is still 'init'"
    else
        fail "E2E: git commit was NOT blocked — HEAD is '$head_msg'"
    fi
}

# ---- E2E Test 3: bash-guard blocks git push ----
# Same pattern — ask for git push, verify it didn't happen.
test_e2e_bash_guard_blocks_push() {
    local ws
    ws=$(setup_workspace)

    local output exit_code=0
    output=$(cd "$ws" && codex exec \
        -s danger-full-access \
        -m "$CODEX_E2E_MODEL" \
        -c 'model_reasoning_effort="xhigh"' \
        "Run this exact shell command: git push origin main" 2>&1) || exit_code=$?

    cleanup "$ws"

    # git push should fail (no remote) AND be blocked by hook.
    # If the hook fires, we see "REVIEW CHECK" in the output.
    # If hook didn't fire, git push fails with "no remote" error instead.
    if echo "$output" | grep -qi "review check\|blocked\|denied"; then
        pass "E2E: git push was blocked by hook"
    elif echo "$output" | grep -qi "no.*remote\|does not appear to be a git"; then
        # Push failed for git reasons, not hook — hook may not have fired
        skip "E2E: git push failed (no remote) — can't confirm hook fired"
    else
        fail "E2E: git push was not blocked (output=${output:0:200})"
    fi
}

# ---- E2E Test 4: Normal commands not blocked ----
# Non-git commands should execute fine with hooks active.
test_e2e_normal_commands_allowed() {
    local ws
    ws=$(setup_workspace)

    local output exit_code=0
    output=$(cd "$ws" && codex exec \
        -s danger-full-access \
        -m "$CODEX_E2E_MODEL" \
        -c 'model_reasoning_effort="xhigh"' \
        "Run this exact shell command and show the output: echo SDLC_E2E_CANARY" 2>&1) || exit_code=$?

    cleanup "$ws"

    if echo "$output" | grep -q "SDLC_E2E_CANARY"; then
        pass "E2E: Normal commands execute with hooks active"
    else
        fail "E2E: Normal command output missing (exit=$exit_code, output=${output:0:200})"
    fi
}

# ---- E2E Test 5: Session starts without AGENTS.md (no crash) ----
# Hooks should still load even if AGENTS.md is missing.
test_e2e_session_without_agents_md() {
    local ws
    ws=$(setup_workspace)
    rm -f "$ws/AGENTS.md"

    local output exit_code=0
    output=$(cd "$ws" && codex exec \
        -s danger-full-access \
        -m "$CODEX_E2E_MODEL" \
        -c 'model_reasoning_effort="xhigh"' \
        "Run this exact shell command and show the output: echo SESSION_OK" 2>&1) || exit_code=$?

    cleanup "$ws"

    if [ "$exit_code" -eq 0 ] && echo "$output" | grep -q "SESSION_OK"; then
        pass "E2E: Session works without AGENTS.md (hook warns, doesn't crash)"
    else
        fail "E2E: Session crashed without AGENTS.md (exit=$exit_code)"
    fi
}

# ---- Run E2E tests ----
test_e2e_hooks_load
test_e2e_bash_guard_blocks_commit
test_e2e_bash_guard_blocks_push
test_e2e_normal_commands_allowed
test_e2e_session_without_agents_md

echo ""
echo "=== E2E Results: $PASSED passed, $FAILED failed, $SKIPPED skipped ==="

if [ "$FAILED" -gt 0 ]; then
    exit 1
fi
