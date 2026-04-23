#!/bin/bash
# Test Codex SDLC Adapter - platform-aware behavior, payload format, config, install

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$SCRIPT_DIR/.."
HOOKS_DIR="$REPO_DIR/.codex/hooks"
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

echo "=== Codex SDLC Adapter Tests ==="
echo ""

if [ "$IS_WINDOWS" = "true" ]; then
    PRETOOL_SCRIPT="$HOOKS_DIR/git-guard.ps1"
    SESSION_SCRIPT="$HOOKS_DIR/session-start.ps1"
    HOOKS_FILE="$REPO_DIR/.codex/windows-hooks.json"
    ACTIVE_HOOKS_FILE="$REPO_DIR/.codex/hooks.json"
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
    if echo "$output" | grep -q '"decision":"block"'; then
        pass "pre-tool hook blocks git commit"
    else
        fail "pre-tool hook did not block git commit (output: $output)"
    fi
}

test_pretool_blocks_push() {
    local output
    output=$(run_json_hook '{"tool_input":{"command":"git push origin main"}}' "$PRETOOL_SCRIPT")
    if echo "$output" | grep -q '"decision":"block"'; then
        pass "pre-tool hook blocks git push"
    else
        fail "pre-tool hook did not block git push (output: $output)"
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
        && ! grep -q '"UserPromptSubmit"' "$HOOKS_FILE"; then
        pass "hook config matches the quiet hook set"
    else
        fail "hook config does not match the quiet hook set"
    fi
}

test_live_hooks_file_is_windows_safe() {
    if [ "$IS_WINDOWS" != "true" ]; then
        return
    fi

    if grep -q 'git-guard\.ps1' "$ACTIVE_HOOKS_FILE" \
        && grep -q 'session-start\.ps1' "$ACTIVE_HOOKS_FILE" \
        && ! grep -q 'bash-guard\.sh' "$ACTIVE_HOOKS_FILE"; then
        pass "live hooks.json uses the quiet PowerShell hook set on Windows"
    else
        fail "live hooks.json still points at Bash hooks on Windows"
    fi
}

test_config_enables_hooks() {
    if grep -q 'codex_hooks\s*=\s*true' "$REPO_DIR/.codex/config.toml" 2>/dev/null; then
        pass "config.toml enables codex hooks"
    else
        fail "config.toml missing codex_hooks = true"
    fi
}

test_install_preserves_agents_md() {
    local tmpdir
    tmpdir=$(mktemp -d)
    echo "CUSTOM AGENTS CONTENT" > "$tmpdir/AGENTS.md"
    (cd "$tmpdir" && CODEX_HOME="$tmpdir/.codex-home" bash "$REPO_DIR/install.sh" >/dev/null 2>&1)
    local content
    content=$(cat "$tmpdir/AGENTS.md")
    rm -rf "$tmpdir"
    if [ "$content" = "CUSTOM AGENTS CONTENT" ]; then
        pass "install.sh preserves existing AGENTS.md"
    else
        fail "install.sh overwrote existing AGENTS.md"
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
    for skill in "codex-sdlc" "setup-wizard" "update-wizard" "feedback"; do
        if [ ! -f "$tmpdir/.codex-home/skills/$skill/SKILL.md" ]; then
            all_present=false
            break
        fi
    done
    if [ "$all_present" = "true" ]; then
        pass "install.sh creates the native Codex skills"
    else
        fail "install.sh did not create the native Codex skills"
    fi
    rm -rf "$tmpdir"
}

test_install_keeps_skill_backups_out_of_skills() {
    local tmpdir
    tmpdir=$(mktemp -d)

    mkdir -p "$tmpdir/.codex-home/skills/codex-sdlc"
    echo "OLD" > "$tmpdir/.codex-home/skills/codex-sdlc/marker.txt"

    (cd "$tmpdir" && CODEX_HOME="$tmpdir/.codex-home" bash "$REPO_DIR/install.sh" >/dev/null 2>&1)

    local backup_count
    local leaked_backup_count
    backup_count=$(find "$tmpdir/.codex-home/backups/skills" -maxdepth 1 -name 'codex-sdlc.bak.*' 2>/dev/null | wc -l | tr -d ' ')
    leaked_backup_count=$(find "$tmpdir/.codex-home/skills" -maxdepth 1 -name 'codex-sdlc.bak.*' | wc -l | tr -d ' ')

    rm -rf "$tmpdir"

    if [ "$backup_count" -ge 1 ] && [ "$leaked_backup_count" = "0" ]; then
        pass "install.sh keeps skill backups out of the live skills directory"
    else
        fail "install.sh leaked skill backups into the live skills directory"
    fi
}

test_install_merges_config() {
    local all_passed=true

    local tmpdir1
    tmpdir1=$(mktemp -d)
    mkdir -p "$tmpdir1/.codex"
    printf '[features]\ncodex_hooks = false\n' > "$tmpdir1/.codex/config.toml"
    (cd "$tmpdir1" && CODEX_HOME="$tmpdir1/.codex-home" bash "$REPO_DIR/install.sh" >/dev/null 2>&1)
    if ! grep -q 'codex_hooks = true' "$tmpdir1/.codex/config.toml"; then
        fail "install.sh case 1: did not flip false to true"
        all_passed=false
    fi
    rm -rf "$tmpdir1"

    local tmpdir2
    tmpdir2=$(mktemp -d)
    mkdir -p "$tmpdir2/.codex"
    printf '[features]\ncodex_hooks = true\n' > "$tmpdir2/.codex/config.toml"
    (cd "$tmpdir2" && CODEX_HOME="$tmpdir2/.codex-home" bash "$REPO_DIR/install.sh" >/dev/null 2>&1)
    if ! grep -q 'codex_hooks = true' "$tmpdir2/.codex/config.toml"; then
        fail "install.sh case 2: lost existing codex_hooks = true"
        all_passed=false
    fi
    rm -rf "$tmpdir2"

    local tmpdir3
    tmpdir3=$(mktemp -d)
    mkdir -p "$tmpdir3/.codex"
    printf '[features]\nsome_other = true\n' > "$tmpdir3/.codex/config.toml"
    (cd "$tmpdir3" && CODEX_HOME="$tmpdir3/.codex-home" bash "$REPO_DIR/install.sh" >/dev/null 2>&1)
    if ! grep -q 'codex_hooks = true' "$tmpdir3/.codex/config.toml"; then
        fail "install.sh case 3: did not add codex_hooks under existing [features]"
        all_passed=false
    elif ! grep -x 'codex_hooks = true' "$tmpdir3/.codex/config.toml" >/dev/null 2>&1; then
        fail "install.sh case 3: codex_hooks not on its own line"
        all_passed=false
    fi
    rm -rf "$tmpdir3"

    local tmpdir4
    tmpdir4=$(mktemp -d)
    mkdir -p "$tmpdir4/.codex"
    printf '[model]\nname = "o3"\n' > "$tmpdir4/.codex/config.toml"
    (cd "$tmpdir4" && CODEX_HOME="$tmpdir4/.codex-home" bash "$REPO_DIR/install.sh" >/dev/null 2>&1)
    if ! grep -q 'codex_hooks = true' "$tmpdir4/.codex/config.toml"; then
        fail "install.sh case 4: did not add [features] section"
        all_passed=false
    fi
    rm -rf "$tmpdir4"

    local tmpdir5
    tmpdir5=$(mktemp -d)
    mkdir -p "$tmpdir5/.codex"
    printf '[features]\n# codex_hooks = false\n' > "$tmpdir5/.codex/config.toml"
    (cd "$tmpdir5" && CODEX_HOME="$tmpdir5/.codex-home" bash "$REPO_DIR/install.sh" >/dev/null 2>&1)
    if ! grep -v '^[[:space:]]*#' "$tmpdir5/.codex/config.toml" | grep -q 'codex_hooks = true'; then
        fail "install.sh case 5: commented codex_hooks treated as active"
        all_passed=false
    fi
    rm -rf "$tmpdir5"

    local tmpdir6
    tmpdir6=$(mktemp -d)
    mkdir -p "$tmpdir6/.codex"
    printf '[features]\n# codex_hooks = true\n' > "$tmpdir6/.codex/config.toml"
    (cd "$tmpdir6" && CODEX_HOME="$tmpdir6/.codex-home" bash "$REPO_DIR/install.sh" >/dev/null 2>&1)
    if ! grep -v '^[[:space:]]*#' "$tmpdir6/.codex/config.toml" | grep -q 'codex_hooks = true'; then
        fail "install.sh case 6: commented active hook treated as real"
        all_passed=false
    fi
    rm -rf "$tmpdir6"

    if [ "$all_passed" = "true" ]; then
        pass "install.sh merges codex_hooks into existing config.toml"
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
    local skill="$REPO_DIR/skills/setup-wizard/SKILL.md"

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
    local skill="$REPO_DIR/skills/update-wizard/SKILL.md"

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

test_feedback_skill_has_privacy_prompt_and_dedupe() {
    local skill="$REPO_DIR/skills/feedback/SKILL.md"

    if grep -q 'May I scan\?' "$skill" \
        && grep -q 'Check for duplicates' "$skill" \
        && grep -q 'No source code' "$skill"; then
        pass "feedback carries the privacy-first scan and dedupe contract"
    else
        fail "feedback is missing the privacy-first scan and dedupe contract"
    fi
}

test_sdlc_skill_has_docsync_learning_and_merge_guard() {
    local skill="$REPO_DIR/skills/codex-sdlc/SKILL.md"

    if grep -q 'docs update' "$skill" \
        && grep -q 'capture learnings' "$skill" \
        && grep -q 'NEVER AUTO-MERGE' "$skill"; then
        pass "codex-sdlc carries doc-sync, learning capture, and merge-guard rules"
    else
        fail "codex-sdlc is missing upstream SDLC enforcement rules"
    fi
}

test_repo_defaults_to_xhigh_reasoning() {
    local all_passed=true

    if ! grep -q 'default to XHIGH' "$REPO_DIR/AGENTS.md"; then
        fail "AGENTS.md does not set XHIGH as the default reasoning policy"
        all_passed=false
    fi

    if ! grep -q 'Default to `xhigh`' "$REPO_DIR/README.md"; then
        fail "README.md does not set xhigh as the default reasoning policy"
        all_passed=false
    fi

    if ! grep -q 'default: `xhigh`' "$REPO_DIR/skills/codex-sdlc/SKILL.md"; then
        fail "codex-sdlc skill does not set xhigh as the default reasoning policy"
        all_passed=false
    fi

    if ! grep -q 'Default to `xhigh`' "$REPO_DIR/SDLC-LOOP.md"; then
        fail "SDLC-LOOP.md does not set xhigh as the default reasoning policy"
        all_passed=false
    fi

    if ! grep -q 'Use xhigh reasoning by default' "$REPO_DIR/START-SDLC.md"; then
        fail "START-SDLC.md does not set xhigh as the default reasoning policy"
        all_passed=false
    fi

    if [ "$all_passed" = "true" ]; then
        pass "repo contract defaults to xhigh reasoning"
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
        "agents/" \
        "bin/" \
        "skills/" \
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
        "SKILL.md" \
        "AGENTS.md" \
        "README.md" \
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
       echo "$output" | grep -q 'maximum'; then
        pass "npm CLI help advertises the supported model-profile flag"
    else
        fail "npm CLI help is missing the supported model-profile flag"
    fi
}

test_package_cli_help_documents_bootstrap_profile_policy() {
    local output
    output=$(node "$REPO_DIR/bin/codex-sdlc-wizard.js" --help 2>&1)

    if echo "$output" | grep -Eqi 'setup.*maximum|bootstrap.*maximum' &&
       echo "$output" | grep -Eqi 'routine work.*mixed|day-to-day.*mixed|after bootstrap.*mixed'; then
        pass "npm CLI help documents maximum for bootstrap and mixed for routine work"
    else
        fail "npm CLI help does not document the bootstrap-versus-routine profile policy"
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
        && grep -q 'npx codex-sdlc-wizard setup --yes' "$REPO_DIR/README.md" \
        && grep -q 'npx codex-sdlc-wizard check' "$REPO_DIR/README.md"; then
        pass "README documents the npm entrypoint"
    else
        fail "README is missing the npm entrypoint"
    fi
}

test_pretool_blocks_commit
test_pretool_blocks_push
test_pretool_allows_safe_command
test_pretool_reads_command_field
test_session_warns_missing
test_session_silent_when_present
test_hooks_json_matcher
test_hooks_json_valid
test_live_hooks_file_is_windows_safe
test_config_enables_hooks
test_install_preserves_agents_md
test_install_creates_sdlc_docs
test_install_creates_skill
test_install_keeps_skill_backups_out_of_skills
test_install_merges_config
test_install_backs_up_hooks_json
test_agents_md_size
test_setup_skill_has_confidence_setup_contract
test_update_skill_has_idempotent_update_contract
test_feedback_skill_has_privacy_prompt_and_dedupe
test_sdlc_skill_has_docsync_learning_and_merge_guard
test_repo_defaults_to_xhigh_reasoning
test_package_has_npm_release_surface
test_package_cli_is_honest_about_supported_flags
test_package_cli_help_documents_bootstrap_profile_policy
test_package_cli_help_mentions_check
test_package_cli_help_mentions_update
test_package_cli_runs_check_command
test_package_cli_runs_update_command
test_readme_mentions_npx_entrypoint

echo ""
echo "=== Results: $PASSED passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
    exit 1
fi
