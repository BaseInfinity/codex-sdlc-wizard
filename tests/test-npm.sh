#!/bin/bash
# npm packaging tests — keep the npx install surface working end to end

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$SCRIPT_DIR/.."
PACKAGE_JSON="$REPO_DIR/package.json"
ROADMAP="$REPO_DIR/ROADMAP.md"
JSON_HELPERS="$REPO_DIR/lib/json-node.sh"
source "$JSON_HELPERS"
require_node
PASSED=0
FAILED=0
MKTEMP_DIR="${TMPDIR:-/tmp}"
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

echo "=== npm Packaging Tests ==="
echo ""

test_package_metadata_exists() {
    local has_name=true
    local has_version=true
    local has_bin=true

    [ -f "$PACKAGE_JSON" ] || has_name=false
    json_has_truthy_file "$PACKAGE_JSON" 'data.name === "codex-sdlc-wizard"' || has_name=false
    json_has_truthy_file "$PACKAGE_JSON" 'typeof data.version === "string"' || has_version=false
    json_has_truthy_file "$PACKAGE_JSON" 'data.bin && data.bin["codex-sdlc-wizard"] === "bin/codex-sdlc-wizard.js"' || has_bin=false

    if [ "$has_name" = "true" ] &&
       [ "$has_version" = "true" ] &&
       [ "$has_bin" = "true" ]; then
        pass "package.json exposes the codex-sdlc-wizard CLI"
    else
        fail "package.json is missing the expected npm CLI metadata"
    fi
}

test_package_version_matches_roadmap_current_release() {
    local package_version current_state_section
    package_version=$(json_get_file "$PACKAGE_JSON" 'data.version')
    current_state_section=$(awk '
        /^## Current State$/ { in_section=1; next }
        /^## / && in_section { exit }
        in_section { print }
    ' "$ROADMAP")

    if [ -n "$package_version" ] && echo "$current_state_section" | grep -q "$package_version"; then
        pass "package.json version matches the roadmap current-release state"
    else
        fail "package.json version does not match the roadmap current-release state"
    fi
}

test_npm_pack_includes_runtime_files() {
    local pack_dir
    pack_dir=$(mktemp -d "$MKTEMP_DIR/sdlc-npm-pack.XXXXXX")
    local npm_cache
    npm_cache=$(mktemp -d "$MKTEMP_DIR/sdlc-npm-cache.XXXXXX")

    local tarball json tarball_name
    json=$(cd "$REPO_DIR" && npm_config_cache="$npm_cache" npm pack --json --pack-destination "$pack_dir" 2>/dev/null) || true
    tarball_name=$(printf '%s' "$json" | json_get_stdin 'Array.isArray(data) && data[0] ? data[0].filename : ""')

    local has_tarball=true
    local has_install=true
    local has_setup=true
    local has_hooks=true
    local has_bin=true
    local has_skill=true
    local has_canonical_sdlc_skill=true
    local has_legacy_sdlc_skill=false
    local has_openai_yaml=true
    local has_repo_sdlc_skill=true
    local has_repo_adlc_skill=false

    if [ -z "$tarball_name" ] || [ ! -f "$pack_dir/$tarball_name" ]; then
        has_tarball=false
        has_install=false
        has_setup=false
        has_hooks=false
        has_bin=false
        has_skill=false
        has_openai_yaml=false
        has_repo_sdlc_skill=false
        has_repo_adlc_skill=true
    else
        [ "$(printf '%s' "$json" | json_get_stdin 'Array.isArray(data) && data[0] && Array.isArray(data[0].files) && data[0].files.some((file) => file.path === "install.sh") ? "yes" : ""')" = "yes" ] || has_install=false
        [ "$(printf '%s' "$json" | json_get_stdin 'Array.isArray(data) && data[0] && Array.isArray(data[0].files) && data[0].files.some((file) => file.path === "setup.sh") ? "yes" : ""')" = "yes" ] || has_setup=false
        [ "$(printf '%s' "$json" | json_get_stdin 'Array.isArray(data) && data[0] && Array.isArray(data[0].files) && data[0].files.some((file) => file.path === ".codex/hooks/bash-guard.sh") ? "yes" : ""')" = "yes" ] || has_hooks=false
        [ "$(printf '%s' "$json" | json_get_stdin 'Array.isArray(data) && data[0] && Array.isArray(data[0].files) && data[0].files.some((file) => file.path === ".codex/hooks/git-guard.cjs") ? "yes" : ""')" = "yes" ] || has_hooks=false
        [ "$(printf '%s' "$json" | json_get_stdin 'Array.isArray(data) && data[0] && Array.isArray(data[0].files) && data[0].files.some((file) => file.path === ".codex/hooks/session-start.cjs") ? "yes" : ""')" = "yes" ] || has_hooks=false
        [ "$(printf '%s' "$json" | json_get_stdin 'Array.isArray(data) && data[0] && Array.isArray(data[0].files) && data[0].files.some((file) => file.path === "bin/codex-sdlc-wizard.js") ? "yes" : ""')" = "yes" ] || has_bin=false
        [ "$(printf '%s' "$json" | json_get_stdin 'Array.isArray(data) && data[0] && Array.isArray(data[0].files) && data[0].files.some((file) => file.path === "SKILL.md") ? "yes" : ""')" = "yes" ] || has_skill=false
        [ "$(printf '%s' "$json" | json_get_stdin 'Array.isArray(data) && data[0] && Array.isArray(data[0].files) && data[0].files.some((file) => file.path === "skills/sdlc/SKILL.md") ? "yes" : ""')" = "yes" ] || has_canonical_sdlc_skill=false
        [ "$(printf '%s' "$json" | json_get_stdin 'Array.isArray(data) && data[0] && Array.isArray(data[0].files) && data[0].files.some((file) => file.path.startsWith("skills/codex-sdlc/")) ? "yes" : ""')" = "yes" ] && has_legacy_sdlc_skill=true
        [ "$(printf '%s' "$json" | json_get_stdin 'Array.isArray(data) && data[0] && Array.isArray(data[0].files) && data[0].files.some((file) => file.path === "agents/openai.yaml") ? "yes" : ""')" = "yes" ] || has_openai_yaml=false
        [ "$(printf '%s' "$json" | json_get_stdin 'Array.isArray(data) && data[0] && Array.isArray(data[0].files) && data[0].files.some((file) => file.path === ".agents/skills/sdlc/SKILL.md") ? "yes" : ""')" = "yes" ] || has_repo_sdlc_skill=false
        [ "$(printf '%s' "$json" | json_get_stdin 'Array.isArray(data) && data[0] && Array.isArray(data[0].files) && data[0].files.some((file) => file.path === ".agents/skills/adlc/SKILL.md") ? "yes" : ""')" = "yes" ] && has_repo_adlc_skill=true
    fi

    rm -rf "$pack_dir" "$npm_cache"

    if [ "$has_tarball" = "true" ] &&
       [ "$has_install" = "true" ] &&
       [ "$has_setup" = "true" ] &&
       [ "$has_hooks" = "true" ] &&
       [ "$has_bin" = "true" ] &&
       [ "$has_skill" = "true" ] &&
       [ "$has_canonical_sdlc_skill" = "true" ] &&
       [ "$has_legacy_sdlc_skill" = "false" ] &&
       [ "$has_openai_yaml" = "true" ] &&
       [ "$has_repo_sdlc_skill" = "true" ] &&
       [ "$has_repo_adlc_skill" = "false" ]; then
        pass "npm pack includes the CLI, installer, and skill runtime files"
    else
        fail "npm pack is missing required runtime files"
    fi
}

test_local_npx_installs_into_clean_repo() {
    local pack_dir target_repo
    pack_dir=$(mktemp -d "$MKTEMP_DIR/sdlc-npx-pack.XXXXXX")
    target_repo=$(mktemp -d "$MKTEMP_DIR/sdlc-npx-target.XXXXXX")
    local npm_cache
    npm_cache=$(mktemp -d "$MKTEMP_DIR/sdlc-npx-cache.XXXXXX")

    local json tarball_name
    json=$(cd "$REPO_DIR" && npm_config_cache="$npm_cache" npm pack --json --pack-destination "$pack_dir" 2>/dev/null) || true
    tarball_name=$(printf '%s' "$json" | json_get_stdin 'Array.isArray(data) && data[0] ? data[0].filename : ""')

    local tarball_path="$pack_dir/$tarball_name"
    local installed=true

    if [ -z "$tarball_name" ] || [ ! -f "$tarball_path" ]; then
        installed=false
    else
        printf '%s' '{"name":"install-smoke","scripts":{"test":"jest"}}' > "$target_repo/package.json"
        mkdir -p "$target_repo/src"
        (
            cd "$target_repo"
            CODEX_HOME="$target_repo/.codex-home" CODEX_SDLC_DISABLE_REASONING=1 npm_config_cache="$npm_cache" npm exec --yes --package "$tarball_path" -- codex-sdlc-wizard --yes >/dev/null 2>&1
        ) || installed=false
    fi

    [ -f "$target_repo/AGENTS.md" ] || installed=false
    [ -f "$target_repo/.codex/config.toml" ] || installed=false
    [ -f "$target_repo/.codex/hooks.json" ] || installed=false
    [ -x "$target_repo/.codex/hooks/bash-guard.sh" ] || installed=false
    [ -f "$target_repo/.codex/hooks/git-guard.cjs" ] || installed=false
    [ -f "$target_repo/.codex/hooks/session-start.cjs" ] || installed=false
    [ -f "$target_repo/.agents/skills/sdlc/SKILL.md" ] || installed=false
    [ ! -e "$target_repo/.agents/skills/adlc/SKILL.md" ] || installed=false
    [ -f "$target_repo/.codex-sdlc/manifest.json" ] || installed=false
    grep -q 'node \.codex/hooks/git-guard\.cjs' "$target_repo/.codex/hooks.json" 2>/dev/null || installed=false
    grep -q 'node \.codex/hooks/session-start\.cjs' "$target_repo/.codex/hooks.json" 2>/dev/null || installed=false
    grep -q 'powershell\.exe' "$target_repo/.codex/hooks.json" 2>/dev/null && installed=false
    grep -q 'bash-guard\.sh' "$target_repo/.codex/hooks.json" 2>/dev/null && installed=false

    rm -rf "$pack_dir" "$target_repo" "$npm_cache"

    if [ "$installed" = "true" ]; then
        pass "local npm exec defaults to adaptive setup with universal Node hooks when automation passes --yes"
    else
        fail "local npm exec did not route the default command through adaptive setup with universal Node hooks"
    fi
}

test_local_npx_setup_honors_model_profile_flag() {
    local pack_dir target_repo
    pack_dir=$(mktemp -d "$MKTEMP_DIR/sdlc-npx-pack.XXXXXX")
    target_repo=$(mktemp -d "$MKTEMP_DIR/sdlc-npx-target.XXXXXX")
    local npm_cache
    npm_cache=$(mktemp -d "$MKTEMP_DIR/sdlc-npx-cache.XXXXXX")

    local json tarball_name
    json=$(cd "$REPO_DIR" && npm_config_cache="$npm_cache" npm pack --json --pack-destination "$pack_dir" 2>/dev/null) || true
    tarball_name=$(printf '%s' "$json" | json_get_stdin 'Array.isArray(data) && data[0] ? data[0].filename : ""')

    local configured=true
    local tarball_path="$pack_dir/$tarball_name"

    if [ -z "$tarball_name" ] || [ ! -f "$tarball_path" ]; then
        configured=false
    else
        (
            cd "$target_repo"
            CODEX_HOME="$target_repo/.codex-home" CODEX_SDLC_DISABLE_REASONING=1 npm_config_cache="$npm_cache" npm exec --yes --package "$tarball_path" -- codex-sdlc-wizard setup --yes --model-profile maximum >/dev/null 2>&1
        ) || configured=false
    fi

    if [ "$configured" = "true" ]; then
        if [ ! -f "$target_repo/.codex-sdlc/model-profile.json" ] ||
           ! json_has_truthy_file "$target_repo/.codex-sdlc/model-profile.json" 'data.selected_profile === "maximum"'; then
            configured=false
        elif ! grep -q '^model = "gpt-5.5"' "$target_repo/.codex/config.toml" 2>/dev/null; then
            configured=false
        elif ! grep -q '^model_reasoning_effort = "xhigh"' "$target_repo/.codex/config.toml" 2>/dev/null; then
            configured=false
        elif grep -q '^review_model =' "$target_repo/.codex/config.toml" 2>/dev/null; then
            configured=false
        elif ! grep -q '^codex_hooks = true' "$target_repo/.codex/config.toml" 2>/dev/null; then
            configured=false
        fi
    fi

    rm -rf "$pack_dir" "$target_repo" "$npm_cache"

    if [ "$configured" = "true" ]; then
        pass "local npm exec setup honors the model-profile flag"
    else
        fail "local npm exec setup did not honor the model-profile flag"
    fi
}

test_packed_tarball_scratch_smoke() {
    local pack_dir target_repo
    pack_dir=$(mktemp -d "$MKTEMP_DIR/sdlc-npx-pack.XXXXXX")
    target_repo=$(mktemp -d "$MKTEMP_DIR/sdlc-npx-target.XXXXXX")
    local npm_cache
    npm_cache=$(mktemp -d "$MKTEMP_DIR/sdlc-npx-cache.XXXXXX")

    local json tarball_name tarball_path
    json=$(cd "$REPO_DIR" && npm_config_cache="$npm_cache" npm pack --json --pack-destination "$pack_dir" 2>/dev/null) || true
    tarball_name=$(printf '%s' "$json" | json_get_stdin 'Array.isArray(data) && data[0] ? data[0].filename : ""')
    tarball_path="$pack_dir/$tarball_name"

    local valid=true
    local setup_output="" check_output="" update_output=""

    if [ -z "$tarball_name" ] || [ ! -f "$tarball_path" ]; then
        valid=false
    else
        printf '%s' '{"name":"release-smoke","scripts":{"test":"jest"}}' > "$target_repo/package.json"
        mkdir -p "$target_repo/src"

        setup_output=$(
            cd "$target_repo" && \
            CODEX_HOME="$target_repo/.codex-home" CODEX_SDLC_DISABLE_REASONING=1 npm_config_cache="$npm_cache" npm exec --yes --package "$tarball_path" -- \
                codex-sdlc-wizard setup --yes 2>&1
        ) || valid=false

        check_output=$(
            cd "$target_repo" && \
            CODEX_HOME="$target_repo/.codex-home" npm_config_cache="$npm_cache" npm exec --yes --package "$tarball_path" -- \
                codex-sdlc-wizard check 2>&1
        ) || valid=false

        update_output=$(
            cd "$target_repo" && \
            CODEX_HOME="$target_repo/.codex-home" npm_config_cache="$npm_cache" npm exec --yes --package "$tarball_path" -- \
                codex-sdlc-wizard update check-only 2>&1
        ) || valid=false
    fi

    [ -f "$target_repo/.codex-sdlc/manifest.json" ] || valid=false
    json_has_truthy_file "$target_repo/.codex-sdlc/manifest.json" 'typeof data.managed_files?.["AGENTS.md"] === "string" && /^sha256:[0-9a-f]{64}$/.test(data.managed_files["AGENTS.md"])' || valid=false
    echo "$setup_output" | grep -q 'Setup complete' || valid=false
    echo "$setup_output" | grep -Eqi 'exit and reopen Codex|restart Codex' || valid=false
    echo "$setup_output" | grep -q 'codex resume --full-auto -m gpt-5.5' || valid=false
    echo "$setup_output" | grep -Fq 'model_reasoning_effort="xhigh"' || valid=false
    echo "$setup_output" | grep -q 'shasum: command not found' && valid=false
    echo "$check_output" | grep -q '"status": "match"' || valid=false
    echo "$update_output" | grep -Eq 'No managed files need updates|"status": "match"|match' || valid=false

    rm -rf "$pack_dir" "$target_repo" "$npm_cache"

    if [ "$valid" = "true" ]; then
        pass "packed tarball scratch smoke proves setup, check, and update on a clean repo"
    else
        fail "packed tarball scratch smoke did not prove the release surface cleanly"
    fi
}

test_default_interactive_hands_off_to_codex() {
    local ws fakebin fakebin_win codex_bin codex_path_entry codex_home args_file input_file output
    ws=$(mktemp -d "$MKTEMP_DIR/sdlc-npx-target.XXXXXX")
    fakebin=$(mktemp -d "$MKTEMP_DIR/sdlc-npx-bin.XXXXXX")
    codex_home=$(mktemp -d "$MKTEMP_DIR/sdlc-npx-home.XXXXXX")
    args_file="$ws/codex-args.txt"
    input_file="$ws/handoff-input.txt"

    printf '%s' '{"name":"handoff-smoke","scripts":{"test":"npm test"}}' > "$ws/package.json"
    mkdir -p "$ws/tests"
    touch "$ws/tests/app.e2e.ts" "$ws/playwright.config.js"
    printf '\n' > "$input_file"

    cat > "$fakebin/codex" <<'EOF'
#!/bin/sh
if [ -n "${FAKE_CODEX_ARGS_FILE:-}" ]; then
  for arg in "$@"; do
    printf '%s\n' "$arg" >> "$FAKE_CODEX_ARGS_FILE"
  done
fi
exit 0
EOF
    chmod +x "$fakebin/codex"

    cat > "$fakebin/codex.cmd" <<'EOF'
@echo off
if not "%FAKE_CODEX_ARGS_FILE%"=="" (
  >>"%FAKE_CODEX_ARGS_FILE%" echo %*
)
exit /b 0
EOF

    if fakebin_win=$(cd "$fakebin" && pwd -W 2>/dev/null); then
        codex_bin="$fakebin_win\\codex.cmd"
        codex_path_entry="$fakebin_win"
    else
        codex_bin="$fakebin/codex"
        codex_path_entry="$fakebin"
    fi

    output=$(
        cd "$ws" && \
        CODEX_HOME="$codex_home" \
        CODEX_SDLC_CODEX_BIN="$codex_bin" \
        CODEX_SDLC_DISABLE_REASONING=1 \
        FAKE_CODEX_ARGS_FILE="$args_file" \
        PATH="$codex_path_entry:$PATH" \
        node "$REPO_DIR/bin/codex-sdlc-wizard.js" < "$input_file" 2>&1
    ) || true

    local valid=true
    [ -f "$ws/.codex/config.toml" ] || valid=false
    [ -f "$ws/.codex/hooks.json" ] || valid=false
    [ -f "$ws/.codex-sdlc/model-profile.json" ] || valid=false
    [ ! -f "$ws/.codex-sdlc/manifest.json" ] || valid=false
    grep -Fq -- '--full-auto' "$args_file" 2>/dev/null && valid=false
    grep -Fq -- '-C' "$args_file" 2>/dev/null || valid=false
    grep -Fq -- '-m' "$args_file" 2>/dev/null || valid=false
    grep -Fq 'gpt-5.5' "$args_file" 2>/dev/null || valid=false
    grep -Fq 'model_reasoning_effort="xhigh"' "$args_file" 2>/dev/null || valid=false
    grep -Fq '$setup-wizard' "$args_file" 2>/dev/null || valid=false
    echo "$output" | grep -Fq 'Choose first-run Codex handoff mode' || valid=false
    echo "$output" | grep -Fq 'Press Enter: plain codex (recommended)' || valid=false
    echo "$output" | grep -Fq 'Type "full-auto": codex --full-auto' || valid=false
    echo "$output" | grep -Fq 'codex resume --full-auto' || valid=false
    echo "$output" | grep -Fq 'Handing off into Codex for live setup using plain codex' || valid=false
    ! echo "$output" | grep -Fq 'DEP0190' || valid=false
    ! echo "$output" | grep -Fq 'Scanning project...' || valid=false

    rm -rf "$ws" "$fakebin" "$codex_home"

    if [ "$valid" = "true" ]; then
        pass "default interactive CLI bootstraps then hands off into plain Codex"
    else
        fail "default interactive CLI did not hand off into plain Codex correctly"
    fi
}

test_full_auto_handoff_choice_is_explicit() {
    local ws fakebin fakebin_win codex_bin codex_path_entry codex_home args_file input_file output
    ws=$(mktemp -d "$MKTEMP_DIR/sdlc-npx-target.XXXXXX")
    fakebin=$(mktemp -d "$MKTEMP_DIR/sdlc-npx-bin.XXXXXX")
    codex_home=$(mktemp -d "$MKTEMP_DIR/sdlc-npx-home.XXXXXX")
    args_file="$ws/codex-args.txt"
    input_file="$ws/handoff-input.txt"

    printf '%s' '{"name":"handoff-smoke","scripts":{"test":"npm test"}}' > "$ws/package.json"
    mkdir -p "$ws/tests"
    touch "$ws/tests/app.e2e.ts" "$ws/playwright.config.js"
    printf 'full-auto\n' > "$input_file"

    cat > "$fakebin/codex" <<'EOF'
#!/bin/sh
if [ -n "${FAKE_CODEX_ARGS_FILE:-}" ]; then
  for arg in "$@"; do
    printf '%s\n' "$arg" >> "$FAKE_CODEX_ARGS_FILE"
  done
fi
exit 0
EOF
    chmod +x "$fakebin/codex"

    cat > "$fakebin/codex.cmd" <<'EOF'
@echo off
if not "%FAKE_CODEX_ARGS_FILE%"=="" (
  >>"%FAKE_CODEX_ARGS_FILE%" echo %*
)
exit /b 0
EOF

    if fakebin_win=$(cd "$fakebin" && pwd -W 2>/dev/null); then
        codex_bin="$fakebin_win\\codex.cmd"
        codex_path_entry="$fakebin_win"
    else
        codex_bin="$fakebin/codex"
        codex_path_entry="$fakebin"
    fi

    output=$(
        cd "$ws" && \
        CODEX_HOME="$codex_home" \
        CODEX_SDLC_CODEX_BIN="$codex_bin" \
        CODEX_SDLC_DISABLE_REASONING=1 \
        FAKE_CODEX_ARGS_FILE="$args_file" \
        PATH="$codex_path_entry:$PATH" \
        node "$REPO_DIR/bin/codex-sdlc-wizard.js" < "$input_file" 2>&1
    ) || true

    local valid=true
    grep -Fq -- '--full-auto' "$args_file" 2>/dev/null || valid=false
    grep -Fq 'gpt-5.5' "$args_file" 2>/dev/null || valid=false
    grep -Fq 'model_reasoning_effort="xhigh"' "$args_file" 2>/dev/null || valid=false
    grep -Fq '$setup-wizard' "$args_file" 2>/dev/null || valid=false
    echo "$output" | grep -Fq 'Handing off into Codex for live setup using codex --full-auto' || valid=false
    ! echo "$output" | grep -Fq 'Scanning project...' || valid=false

    rm -rf "$ws" "$fakebin" "$codex_home"

    if [ "$valid" = "true" ]; then
        pass "full-auto first-run handoff requires an explicit choice"
    else
        fail "full-auto first-run handoff was not controlled by the explicit choice"
    fi
}

test_codex_handoff_watchdog_timeout_is_opt_in() {
    local body
    body="$(awk '/function handoffTimeoutMs\(\)/,/^}/' "$REPO_DIR/bin/codex-sdlc-wizard.js")"

    if echo "$body" | grep -Fq 'return 0;' \
        && ! echo "$body" | grep -Fq '60 * 60 * 1000'; then
        pass "Codex handoff watchdog timeout is opt-in"
    else
        fail "Codex handoff watchdog timeout must not enforce a default wall-clock limit"
    fi
}

test_codex_handoff_watchdog_times_out_and_terminates_child() {
    local ws fakebin fakebin_win codex_bin codex_path_entry codex_home input_file output started_file killed_file completed_file status
    local started_file_env killed_file_env completed_file_env ws_win
    ws=$(mktemp -d "$MKTEMP_DIR/sdlc-npx-target.XXXXXX")
    fakebin=$(mktemp -d "$MKTEMP_DIR/sdlc-npx-bin.XXXXXX")
    codex_home=$(mktemp -d "$MKTEMP_DIR/sdlc-npx-home.XXXXXX")
    input_file="$ws/handoff-input.txt"
    started_file="$ws/codex-started.txt"
    killed_file="$ws/codex-killed.txt"
    completed_file="$ws/codex-completed.txt"

    printf '%s' '{"name":"handoff-watchdog","scripts":{"test":"npm test"}}' > "$ws/package.json"
    mkdir -p "$ws/tests"
    touch "$ws/tests/app.e2e.ts" "$ws/playwright.config.js"
    printf '\n' > "$input_file"

    cat > "$fakebin/codex" <<'EOF'
#!/bin/sh
if [ "${1:-}" = "--version" ]; then
  exit 0
fi
printf started > "$FAKE_CODEX_STARTED_FILE"
trap 'printf terminated > "$FAKE_CODEX_KILLED_FILE"; exit 143' TERM INT
sleep 2
printf completed > "$FAKE_CODEX_COMPLETED_FILE"
exit 0
EOF
    chmod +x "$fakebin/codex"

    cat > "$fakebin/codex.cmd" <<'EOF'
@echo off
if "%~1"=="--version" exit /b 0
>"%FAKE_CODEX_STARTED_FILE%" echo started
ping -n 3 127.0.0.1 >nul
>"%FAKE_CODEX_COMPLETED_FILE%" echo completed
exit /b 0
EOF

    if fakebin_win=$(cd "$fakebin" && pwd -W 2>/dev/null) && ws_win=$(cd "$ws" && pwd -W 2>/dev/null); then
        codex_bin="$fakebin_win\\codex.cmd"
        codex_path_entry="$fakebin_win"
        started_file_env="$ws_win\\codex-started.txt"
        killed_file_env="$ws_win\\codex-killed.txt"
        completed_file_env="$ws_win\\codex-completed.txt"
    else
        codex_bin="$fakebin/codex"
        codex_path_entry="$fakebin"
        started_file_env="$started_file"
        killed_file_env="$killed_file"
        completed_file_env="$completed_file"
    fi

    set +e
    output=$(
        cd "$ws" && \
        CODEX_HOME="$codex_home" \
        CODEX_SDLC_CODEX_BIN="$codex_bin" \
        CODEX_SDLC_DISABLE_REASONING=1 \
        CODEX_SDLC_CODEX_HANDOFF_TIMEOUT_MS=150 \
        FAKE_CODEX_STARTED_FILE="$started_file_env" \
        FAKE_CODEX_KILLED_FILE="$killed_file_env" \
        FAKE_CODEX_COMPLETED_FILE="$completed_file_env" \
        PATH="$codex_path_entry:$PATH" \
        node "$REPO_DIR/bin/codex-sdlc-wizard.js" < "$input_file" 2>&1
    )
    status=$?
    set -e

    local valid=true
    [ "$status" -ne 0 ] || valid=false
    [ -f "$started_file" ] || valid=false
    if [ "$IS_WINDOWS" = "false" ]; then
        [ -f "$killed_file" ] || valid=false
    fi
    [ ! -f "$completed_file" ] || valid=false
    echo "$output" | grep -Eqi 'timeout|timed out|watchdog' || valid=false
    echo "$output" | grep -Eqi 'terminat|kill' || valid=false
    echo "$output" | grep -Fq 'codex resume --full-auto' || valid=false

    rm -rf "$ws" "$fakebin" "$codex_home"

    if [ "$valid" = "true" ]; then
        pass "Codex handoff watchdog times out and terminates the spawned Codex child"
    else
        fail "Codex handoff watchdog did not time out and terminate the spawned Codex child cleanly"
    fi
}

test_codex_handoff_timeout_force_kills_signal_ignoring_descendant() {
    if [ "$IS_WINDOWS" = "true" ]; then
        pass "Codex handoff descendant force-kill cleanup is POSIX-only"
        return
    fi

    local ws fakebin codex_home input_file output_file started_file completed_file grandchild_pid_file status grandchild_pid
    ws=$(mktemp -d "$MKTEMP_DIR/sdlc-npx-target.XXXXXX")
    fakebin=$(mktemp -d "$MKTEMP_DIR/sdlc-npx-bin.XXXXXX")
    codex_home=$(mktemp -d "$MKTEMP_DIR/sdlc-npx-home.XXXXXX")
    input_file="$ws/handoff-input.txt"
    output_file="$ws/handoff-output.txt"
    started_file="$ws/codex-started.txt"
    completed_file="$ws/codex-completed.txt"
    grandchild_pid_file="$ws/codex-grandchild.pid"

    printf '%s' '{"name":"handoff-watchdog","scripts":{"test":"npm test"}}' > "$ws/package.json"
    mkdir -p "$ws/tests"
    touch "$ws/tests/app.e2e.ts" "$ws/playwright.config.js"
    printf '\n' > "$input_file"

    cat > "$fakebin/codex" <<'EOF'
#!/bin/bash
if [ "${1:-}" = "--version" ]; then
  exit 0
fi
printf started > "$FAKE_CODEX_STARTED_FILE"
bash -c 'trap "" TERM INT HUP; printf "%s" "$$" > "$FAKE_CODEX_GRANDCHILD_PID_FILE"; sleep 30' &
trap 'exit 143' TERM INT HUP
sleep 30
printf completed > "$FAKE_CODEX_COMPLETED_FILE"
exit 0
EOF
    chmod +x "$fakebin/codex"

    set +e
    (
        cd "$ws" || exit 1
        CODEX_HOME="$codex_home" \
        CODEX_SDLC_CODEX_BIN="$fakebin/codex" \
        CODEX_SDLC_DISABLE_REASONING=1 \
        CODEX_SDLC_CODEX_HANDOFF_TIMEOUT_MS=150 \
        FAKE_CODEX_STARTED_FILE="$started_file" \
        FAKE_CODEX_COMPLETED_FILE="$completed_file" \
        FAKE_CODEX_GRANDCHILD_PID_FILE="$grandchild_pid_file" \
        PATH="$fakebin:$PATH" \
        node "$REPO_DIR/bin/codex-sdlc-wizard.js" < "$input_file" > "$output_file" 2>&1
    )
    status=$?
    set -e

    grandchild_pid="$(cat "$grandchild_pid_file" 2>/dev/null || true)"

    local grandchild_alive=false
    if [ -n "$grandchild_pid" ] && kill -0 "$grandchild_pid" 2>/dev/null; then
        grandchild_alive=true
        kill -KILL "$grandchild_pid" 2>/dev/null || true
    fi

    local output=""
    output="$(cat "$output_file" 2>/dev/null || true)"
    local valid=true
    [ "$status" -eq 124 ] || valid=false
    [ -f "$started_file" ] || valid=false
    [ -n "$grandchild_pid" ] || valid=false
    [ "$grandchild_alive" = "false" ] || valid=false
    [ ! -f "$completed_file" ] || valid=false
    echo "$output" | grep -Eqi 'timed out|watchdog' || valid=false
    echo "$output" | grep -Fq 'Terminating spawned Codex process tree' || valid=false

    rm -rf "$ws" "$fakebin" "$codex_home"

    if [ "$valid" = "true" ]; then
        pass "Codex handoff timeout force-kills signal-ignoring descendants"
    else
        fail "Codex handoff timeout left a signal-ignoring descendant alive"
    fi
}

test_codex_handoff_sighup_terminates_detached_child() {
    if [ "$IS_WINDOWS" = "true" ]; then
        pass "Codex handoff SIGHUP cleanup is POSIX-only"
        return
    fi

    local ws fakebin codex_home input_file output_file pid_file killed_file completed_file wrapper_pid child_pid status
    ws=$(mktemp -d "$MKTEMP_DIR/sdlc-npx-target.XXXXXX")
    fakebin=$(mktemp -d "$MKTEMP_DIR/sdlc-npx-bin.XXXXXX")
    codex_home=$(mktemp -d "$MKTEMP_DIR/sdlc-npx-home.XXXXXX")
    input_file="$ws/handoff-input.txt"
    output_file="$ws/handoff-output.txt"
    pid_file="$ws/codex.pid"
    killed_file="$ws/codex-killed.txt"
    completed_file="$ws/codex-completed.txt"

    printf '%s' '{"name":"handoff-sighup","scripts":{"test":"npm test"}}' > "$ws/package.json"
    mkdir -p "$ws/tests"
    touch "$ws/tests/app.e2e.ts" "$ws/playwright.config.js"
    printf '\n' > "$input_file"

    cat > "$fakebin/codex" <<'EOF'
#!/bin/sh
if [ "${1:-}" = "--version" ]; then
  exit 0
fi
printf '%s' "$$" > "$FAKE_CODEX_PID_FILE"
trap 'printf terminated > "$FAKE_CODEX_KILLED_FILE"; exit 143' HUP TERM INT
sleep 5
printf completed > "$FAKE_CODEX_COMPLETED_FILE"
exit 0
EOF
    chmod +x "$fakebin/codex"

    (
        cd "$ws" || exit 1
        exec env \
            CODEX_HOME="$codex_home" \
            CODEX_SDLC_CODEX_BIN="$fakebin/codex" \
            CODEX_SDLC_DISABLE_REASONING=1 \
            CODEX_SDLC_CODEX_HANDOFF_TIMEOUT_MS=0 \
            FAKE_CODEX_PID_FILE="$pid_file" \
            FAKE_CODEX_KILLED_FILE="$killed_file" \
            FAKE_CODEX_COMPLETED_FILE="$completed_file" \
            PATH="$fakebin:$PATH" \
            node "$REPO_DIR/bin/codex-sdlc-wizard.js" < "$input_file" > "$output_file" 2>&1
    ) &
    wrapper_pid=$!

    for _ in $(seq 1 50); do
        [ -s "$pid_file" ] && break
        sleep 0.1
    done

    child_pid="$(cat "$pid_file" 2>/dev/null || true)"
    if [ -n "$child_pid" ]; then
        kill -HUP "$wrapper_pid" 2>/dev/null || true
    fi

    set +e
    wait "$wrapper_pid"
    status=$?
    set -e

    local child_alive=false
    if [ -n "$child_pid" ] && kill -0 "$child_pid" 2>/dev/null; then
        child_alive=true
        kill -TERM "-$child_pid" 2>/dev/null || kill "$child_pid" 2>/dev/null || true
    fi

    local output=""
    output="$(cat "$output_file" 2>/dev/null || true)"
    local valid=true
    [ -n "$child_pid" ] || valid=false
    [ "$status" -ne 0 ] || valid=false
    [ "$child_alive" = "false" ] || valid=false
    [ -f "$killed_file" ] || valid=false
    [ ! -f "$completed_file" ] || valid=false
    echo "$output" | grep -q 'SIGHUP' || valid=false
    echo "$output" | grep -Fq 'Terminating spawned Codex process tree' || valid=false

    rm -rf "$ws" "$fakebin" "$codex_home"

    if [ "$valid" = "true" ]; then
        pass "Codex handoff handles SIGHUP without orphaning the detached child"
    else
        fail "Codex handoff SIGHUP handling left the detached child alive or missed recovery output"
    fi
}

test_codex_handoff_sigint_forwards_interrupt_to_child() {
    if [ "$IS_WINDOWS" = "true" ]; then
        pass "Codex handoff SIGINT forwarding is POSIX-only"
        return
    fi

    local ws fakebin codex_home input_file output_file pid_file int_file term_file completed_file wrapper_pid child_pid status
    ws=$(mktemp -d "$MKTEMP_DIR/sdlc-npx-target.XXXXXX")
    fakebin=$(mktemp -d "$MKTEMP_DIR/sdlc-npx-bin.XXXXXX")
    codex_home=$(mktemp -d "$MKTEMP_DIR/sdlc-npx-home.XXXXXX")
    input_file="$ws/handoff-input.txt"
    output_file="$ws/handoff-output.txt"
    pid_file="$ws/codex.pid"
    int_file="$ws/codex-int.txt"
    term_file="$ws/codex-term.txt"
    completed_file="$ws/codex-completed.txt"

    printf '%s' '{"name":"handoff-sigint","scripts":{"test":"npm test"}}' > "$ws/package.json"
    mkdir -p "$ws/tests"
    touch "$ws/tests/app.e2e.ts" "$ws/playwright.config.js"
    printf '\n' > "$input_file"

    cat > "$fakebin/codex" <<'EOF'
#!/bin/sh
if [ "${1:-}" = "--version" ]; then
  exit 0
fi
printf '%s' "$$" > "$FAKE_CODEX_PID_FILE"
trap 'printf interrupted > "$FAKE_CODEX_INT_FILE"; exit 130' INT
trap 'printf terminated > "$FAKE_CODEX_TERM_FILE"; exit 143' TERM
sleep 5
printf completed > "$FAKE_CODEX_COMPLETED_FILE"
exit 0
EOF
    chmod +x "$fakebin/codex"

    (
        cd "$ws" || exit 1
        exec env \
            CODEX_HOME="$codex_home" \
            CODEX_SDLC_CODEX_BIN="$fakebin/codex" \
            CODEX_SDLC_DISABLE_REASONING=1 \
            CODEX_SDLC_CODEX_HANDOFF_TIMEOUT_MS=0 \
            FAKE_CODEX_PID_FILE="$pid_file" \
            FAKE_CODEX_INT_FILE="$int_file" \
            FAKE_CODEX_TERM_FILE="$term_file" \
            FAKE_CODEX_COMPLETED_FILE="$completed_file" \
            PATH="$fakebin:$PATH" \
            node "$REPO_DIR/bin/codex-sdlc-wizard.js" < "$input_file" > "$output_file" 2>&1
    ) &
    wrapper_pid=$!

    for _ in $(seq 1 50); do
        [ -s "$pid_file" ] && break
        sleep 0.1
    done

    child_pid="$(cat "$pid_file" 2>/dev/null || true)"
    if [ -n "$child_pid" ]; then
        kill -INT "$wrapper_pid" 2>/dev/null || true
    fi

    set +e
    wait "$wrapper_pid"
    status=$?
    set -e

    local child_alive=false
    if [ -n "$child_pid" ] && kill -0 "$child_pid" 2>/dev/null; then
        child_alive=true
        kill -TERM "-$child_pid" 2>/dev/null || kill "$child_pid" 2>/dev/null || true
    fi

    local output=""
    output="$(cat "$output_file" 2>/dev/null || true)"
    local valid=true
    [ -n "$child_pid" ] || valid=false
    [ "$status" -ne 0 ] || valid=false
    [ "$child_alive" = "false" ] || valid=false
    [ -f "$int_file" ] || valid=false
    [ ! -f "$term_file" ] || valid=false
    [ ! -f "$completed_file" ] || valid=false
    echo "$output" | grep -q 'SIGINT' || valid=false
    echo "$output" | grep -Fq 'Terminating spawned Codex process tree' || valid=false

    rm -rf "$ws" "$fakebin" "$codex_home"

    if [ "$valid" = "true" ]; then
        pass "Codex handoff forwards SIGINT to the spawned Codex child"
    else
        fail "Codex handoff SIGINT handling did not preserve child interrupt semantics"
    fi
}

test_codex_handoff_repeated_sigint_does_not_orphan_child() {
    if [ "$IS_WINDOWS" = "true" ]; then
        pass "Codex handoff repeated SIGINT cleanup is POSIX-only"
        return
    fi

    local ws fakebin codex_home input_file output_file pid_file wrapper_pid child_pid status
    ws=$(mktemp -d "$MKTEMP_DIR/sdlc-npx-target.XXXXXX")
    fakebin=$(mktemp -d "$MKTEMP_DIR/sdlc-npx-bin.XXXXXX")
    codex_home=$(mktemp -d "$MKTEMP_DIR/sdlc-npx-home.XXXXXX")
    input_file="$ws/handoff-input.txt"
    output_file="$ws/handoff-output.txt"
    pid_file="$ws/codex.pid"

    printf '%s' '{"name":"handoff-sigint-repeat","scripts":{"test":"npm test"}}' > "$ws/package.json"
    mkdir -p "$ws/tests"
    touch "$ws/tests/app.e2e.ts" "$ws/playwright.config.js"
    printf '\n' > "$input_file"

    cat > "$fakebin/codex" <<'EOF'
#!/bin/sh
if [ "${1:-}" = "--version" ]; then
  exit 0
fi
printf '%s' "$$" > "$FAKE_CODEX_PID_FILE"
trap '' INT TERM HUP QUIT
sleep 30
exit 0
EOF
    chmod +x "$fakebin/codex"

    (
        cd "$ws" || exit 1
        exec env \
            CODEX_HOME="$codex_home" \
            CODEX_SDLC_CODEX_BIN="$fakebin/codex" \
            CODEX_SDLC_DISABLE_REASONING=1 \
            CODEX_SDLC_CODEX_HANDOFF_TIMEOUT_MS=0 \
            FAKE_CODEX_PID_FILE="$pid_file" \
            PATH="$fakebin:$PATH" \
            node "$REPO_DIR/bin/codex-sdlc-wizard.js" < "$input_file" > "$output_file" 2>&1
    ) &
    wrapper_pid=$!

    for _ in $(seq 1 50); do
        [ -s "$pid_file" ] && break
        sleep 0.1
    done

    child_pid="$(cat "$pid_file" 2>/dev/null || true)"
    if [ -n "$child_pid" ]; then
        kill -INT "$wrapper_pid" 2>/dev/null || true
        sleep 0.1
        kill -INT "$wrapper_pid" 2>/dev/null || true
    fi

    set +e
    wait "$wrapper_pid"
    status=$?
    set -e

    local child_alive=false
    if [ -n "$child_pid" ] && kill -0 "$child_pid" 2>/dev/null; then
        child_alive=true
        kill -KILL "-$child_pid" 2>/dev/null || kill -KILL "$child_pid" 2>/dev/null || true
    fi

    local output=""
    output="$(cat "$output_file" 2>/dev/null || true)"
    local valid=true
    [ -n "$child_pid" ] || valid=false
    [ "$status" -ne 0 ] || valid=false
    [ "$child_alive" = "false" ] || valid=false
    echo "$output" | grep -q 'SIGINT' || valid=false
    echo "$output" | grep -Fq 'Terminating spawned Codex process tree' || valid=false

    rm -rf "$ws" "$fakebin" "$codex_home"

    if [ "$valid" = "true" ]; then
        pass "Codex handoff repeated SIGINT does not orphan the spawned child"
    else
        fail "Codex handoff repeated SIGINT orphaned the spawned child"
    fi
}

test_codex_handoff_sigquit_terminates_detached_child() {
    if [ "$IS_WINDOWS" = "true" ]; then
        pass "Codex handoff SIGQUIT cleanup is POSIX-only"
        return
    fi

    local ws fakebin codex_home input_file output_file pid_file quit_file term_file completed_file wrapper_pid child_pid status
    ws=$(mktemp -d "$MKTEMP_DIR/sdlc-npx-target.XXXXXX")
    fakebin=$(mktemp -d "$MKTEMP_DIR/sdlc-npx-bin.XXXXXX")
    codex_home=$(mktemp -d "$MKTEMP_DIR/sdlc-npx-home.XXXXXX")
    input_file="$ws/handoff-input.txt"
    output_file="$ws/handoff-output.txt"
    pid_file="$ws/codex.pid"
    quit_file="$ws/codex-quit.txt"
    term_file="$ws/codex-term.txt"
    completed_file="$ws/codex-completed.txt"

    printf '%s' '{"name":"handoff-sigquit","scripts":{"test":"npm test"}}' > "$ws/package.json"
    mkdir -p "$ws/tests"
    touch "$ws/tests/app.e2e.ts" "$ws/playwright.config.js"
    printf '\n' > "$input_file"

    cat > "$fakebin/codex" <<'EOF'
#!/bin/sh
if [ "${1:-}" = "--version" ]; then
  exit 0
fi
printf '%s' "$$" > "$FAKE_CODEX_PID_FILE"
trap 'printf quit > "$FAKE_CODEX_QUIT_FILE"; exit 131' QUIT
trap 'printf term > "$FAKE_CODEX_TERM_FILE"; exit 143' TERM HUP INT
sleep 5
printf completed > "$FAKE_CODEX_COMPLETED_FILE"
exit 0
EOF
    chmod +x "$fakebin/codex"

    (
        cd "$ws" || exit 1
        exec env \
            CODEX_HOME="$codex_home" \
            CODEX_SDLC_CODEX_BIN="$fakebin/codex" \
            CODEX_SDLC_DISABLE_REASONING=1 \
            CODEX_SDLC_CODEX_HANDOFF_TIMEOUT_MS=0 \
            FAKE_CODEX_PID_FILE="$pid_file" \
            FAKE_CODEX_QUIT_FILE="$quit_file" \
            FAKE_CODEX_TERM_FILE="$term_file" \
            FAKE_CODEX_COMPLETED_FILE="$completed_file" \
            PATH="$fakebin:$PATH" \
            node "$REPO_DIR/bin/codex-sdlc-wizard.js" < "$input_file" > "$output_file" 2>&1
    ) &
    wrapper_pid=$!

    for _ in $(seq 1 50); do
        [ -s "$pid_file" ] && break
        sleep 0.1
    done

    child_pid="$(cat "$pid_file" 2>/dev/null || true)"
    if [ -n "$child_pid" ]; then
        kill -QUIT "$wrapper_pid" 2>/dev/null || true
    fi

    set +e
    wait "$wrapper_pid"
    status=$?
    set -e

    local child_alive=false
    if [ -n "$child_pid" ] && kill -0 "$child_pid" 2>/dev/null; then
        child_alive=true
        kill -KILL "-$child_pid" 2>/dev/null || kill -KILL "$child_pid" 2>/dev/null || true
    fi

    local output=""
    output="$(cat "$output_file" 2>/dev/null || true)"
    local valid=true
    [ -n "$child_pid" ] || valid=false
    [ "$status" -ne 0 ] || valid=false
    [ "$child_alive" = "false" ] || valid=false
    [ -f "$quit_file" ] || valid=false
    [ ! -f "$term_file" ] || valid=false
    [ ! -f "$completed_file" ] || valid=false
    echo "$output" | grep -q 'SIGQUIT' || valid=false
    echo "$output" | grep -Fq 'Terminating spawned Codex process tree' || valid=false

    rm -rf "$ws" "$fakebin" "$codex_home"

    if [ "$valid" = "true" ]; then
        pass "Codex handoff SIGQUIT terminates the detached child"
    else
        fail "Codex handoff SIGQUIT left the detached child alive"
    fi
}

test_ci_mode_keeps_shell_setup_path() {
    local ws fakebin fakebin_win codex_home args_file prompts_file output
    ws=$(mktemp -d "$MKTEMP_DIR/sdlc-npx-target.XXXXXX")
    fakebin=$(mktemp -d "$MKTEMP_DIR/sdlc-npx-bin.XXXXXX")
    codex_home=$(mktemp -d "$MKTEMP_DIR/sdlc-npx-home.XXXXXX")
    args_file="$ws/codex-args.txt"
    prompts_file="$ws/prompts.txt"

    printf '%s' '{"name":"handoff-smoke","scripts":{"test":"npm test"}}' > "$ws/package.json"
    mkdir -p "$ws/tests"
    touch "$ws/tests/app.e2e.ts" "$ws/playwright.config.js"
    printf '\n\n\n\n' > "$prompts_file"

    cat > "$fakebin/codex" <<'EOF'
#!/bin/sh
set -eu
args_file="${FAKE_CODEX_ARGS_FILE:-}"
if [ -n "$args_file" ]; then
  for arg in "$@"; do
    printf '%s\n' "$arg" >> "$args_file"
  done
fi
exit 0
EOF
    chmod +x "$fakebin/codex"

    cat > "$fakebin/codex.cmd" <<'EOF'
@echo off
if not "%FAKE_CODEX_ARGS_FILE%"=="" (
  >>"%FAKE_CODEX_ARGS_FILE%" echo %*
)
exit /b 0
EOF

    fakebin_win=$(cd "$fakebin" && pwd -W 2>/dev/null || printf '%s' "$fakebin")

    output=$(
        cd "$ws" && \
        env CI=1 \
        CODEX_HOME="$codex_home" \
        CODEX_SDLC_CODEX_BIN="$fakebin_win\\codex.cmd" \
        CODEX_SDLC_DISABLE_REASONING=1 \
        FAKE_CODEX_ARGS_FILE="$args_file" \
        PATH="$fakebin_win;$PATH" \
        node "$REPO_DIR/bin/codex-sdlc-wizard.js" < "$prompts_file" 2>&1
    ) || true

    local valid=true
    [ -f "$ws/.codex-sdlc/manifest.json" ] || valid=false
    echo "$output" | grep -Fq 'Scanning project...' || valid=false
    ! echo "$output" | grep -Fq 'Handing off into Codex for live setup' || valid=false
    [ ! -s "$args_file" ] || valid=false

    rm -rf "$ws" "$fakebin" "$codex_home"

    if [ "$valid" = "true" ]; then
        pass "CI mode keeps setup on the shell path"
    else
        fail "CI mode did not keep setup on the shell path"
    fi
}

test_cli_help_documents_bootstrap_profile_policy() {
    local output
    output=$(node "$REPO_DIR/bin/codex-sdlc-wizard.js" --help 2>&1) || true

    local valid=true
    echo "$output" | grep -Eqi 'launch.*codex|handoff.*codex|continue.*inside codex' || valid=false
    echo "$output" | grep -qi 'mixed' || valid=false
    echo "$output" | grep -qi 'maximum' || valid=false
    echo "$output" | grep -Eqi 'setup.*maximum|bootstrap.*maximum' || valid=false
    echo "$output" | grep -Eqi 'routine work.*mixed|day-to-day.*mixed|after bootstrap.*mixed' || valid=false
    echo "$output" | grep -Eqi 'default.*adaptive setup|adaptive setup.*default' || valid=false

    if [ "$valid" = "true" ]; then
        pass "CLI help documents adaptive setup as the default plus the bootstrap profile policy"
    else
        fail "CLI help does not document the adaptive default and bootstrap-versus-routine profile policy clearly enough"
    fi
}

test_cli_help_explains_update_version_boundary() {
    local output
    output=$(node "$REPO_DIR/bin/codex-sdlc-wizard.js" --help 2>&1) || true

    local valid=true
    echo "$output" | grep -Fq 'npx codex-sdlc-wizard@latest update' || valid=false
    echo "$output" | grep -Fq 'does not self-update the npm package' || valid=false

    if [ "$valid" = "true" ]; then
        pass "CLI help explains that update repairs repo artifacts using the invoked package version"
    else
        fail "CLI help does not explain the npm-version boundary for update"
    fi
}

test_package_metadata_exists
test_package_version_matches_roadmap_current_release
test_npm_pack_includes_runtime_files
test_local_npx_installs_into_clean_repo
test_local_npx_setup_honors_model_profile_flag
test_packed_tarball_scratch_smoke
test_default_interactive_hands_off_to_codex
test_full_auto_handoff_choice_is_explicit
test_codex_handoff_watchdog_timeout_is_opt_in
test_codex_handoff_watchdog_times_out_and_terminates_child
test_codex_handoff_timeout_force_kills_signal_ignoring_descendant
test_codex_handoff_sighup_terminates_detached_child
test_codex_handoff_sigint_forwards_interrupt_to_child
test_codex_handoff_repeated_sigint_does_not_orphan_child
test_codex_handoff_sigquit_terminates_detached_child
test_ci_mode_keeps_shell_setup_path
test_cli_help_documents_bootstrap_profile_policy
test_cli_help_explains_update_version_boundary

echo ""
echo "=== Results: $PASSED passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
    exit 1
fi
