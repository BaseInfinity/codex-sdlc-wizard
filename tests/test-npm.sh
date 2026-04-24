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
    local has_repo_adlc_skill=true

    if [ -z "$tarball_name" ] || [ ! -f "$pack_dir/$tarball_name" ]; then
        has_tarball=false
        has_install=false
        has_setup=false
        has_hooks=false
        has_bin=false
        has_skill=false
        has_openai_yaml=false
        has_repo_sdlc_skill=false
        has_repo_adlc_skill=false
    else
        [ "$(printf '%s' "$json" | json_get_stdin 'Array.isArray(data) && data[0] && Array.isArray(data[0].files) && data[0].files.some((file) => file.path === "install.sh") ? "yes" : ""')" = "yes" ] || has_install=false
        [ "$(printf '%s' "$json" | json_get_stdin 'Array.isArray(data) && data[0] && Array.isArray(data[0].files) && data[0].files.some((file) => file.path === "setup.sh") ? "yes" : ""')" = "yes" ] || has_setup=false
        [ "$(printf '%s' "$json" | json_get_stdin 'Array.isArray(data) && data[0] && Array.isArray(data[0].files) && data[0].files.some((file) => file.path === ".codex/hooks/bash-guard.sh") ? "yes" : ""')" = "yes" ] || has_hooks=false
        [ "$(printf '%s' "$json" | json_get_stdin 'Array.isArray(data) && data[0] && Array.isArray(data[0].files) && data[0].files.some((file) => file.path === "bin/codex-sdlc-wizard.js") ? "yes" : ""')" = "yes" ] || has_bin=false
        [ "$(printf '%s' "$json" | json_get_stdin 'Array.isArray(data) && data[0] && Array.isArray(data[0].files) && data[0].files.some((file) => file.path === "SKILL.md") ? "yes" : ""')" = "yes" ] || has_skill=false
        [ "$(printf '%s' "$json" | json_get_stdin 'Array.isArray(data) && data[0] && Array.isArray(data[0].files) && data[0].files.some((file) => file.path === "skills/sdlc/SKILL.md") ? "yes" : ""')" = "yes" ] || has_canonical_sdlc_skill=false
        [ "$(printf '%s' "$json" | json_get_stdin 'Array.isArray(data) && data[0] && Array.isArray(data[0].files) && data[0].files.some((file) => file.path.startsWith("skills/codex-sdlc/")) ? "yes" : ""')" = "yes" ] && has_legacy_sdlc_skill=true
        [ "$(printf '%s' "$json" | json_get_stdin 'Array.isArray(data) && data[0] && Array.isArray(data[0].files) && data[0].files.some((file) => file.path === "agents/openai.yaml") ? "yes" : ""')" = "yes" ] || has_openai_yaml=false
        [ "$(printf '%s' "$json" | json_get_stdin 'Array.isArray(data) && data[0] && Array.isArray(data[0].files) && data[0].files.some((file) => file.path === ".agents/skills/sdlc/SKILL.md") ? "yes" : ""')" = "yes" ] || has_repo_sdlc_skill=false
        [ "$(printf '%s' "$json" | json_get_stdin 'Array.isArray(data) && data[0] && Array.isArray(data[0].files) && data[0].files.some((file) => file.path === ".agents/skills/adlc/SKILL.md") ? "yes" : ""')" = "yes" ] || has_repo_adlc_skill=false
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
       [ "$has_repo_adlc_skill" = "true" ]; then
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
            CODEX_SDLC_DISABLE_REASONING=1 npm_config_cache="$npm_cache" npm exec --yes --package "$tarball_path" -- codex-sdlc-wizard --yes >/dev/null 2>&1
        ) || installed=false
    fi

    [ -f "$target_repo/AGENTS.md" ] || installed=false
    [ -f "$target_repo/.codex/config.toml" ] || installed=false
    [ -f "$target_repo/.codex/hooks.json" ] || installed=false
    [ -x "$target_repo/.codex/hooks/bash-guard.sh" ] || installed=false
    [ -f "$target_repo/.agents/skills/sdlc/SKILL.md" ] || installed=false
    [ -f "$target_repo/.agents/skills/adlc/SKILL.md" ] || installed=false
    [ -f "$target_repo/.codex-sdlc/manifest.json" ] || installed=false
    if [ "$IS_WINDOWS" = "true" ]; then
        grep -q 'git-guard\.ps1' "$target_repo/.codex/hooks.json" 2>/dev/null || installed=false
        grep -q 'session-start\.ps1' "$target_repo/.codex/hooks.json" 2>/dev/null || installed=false
        grep -q '\.sh' "$target_repo/.codex/hooks.json" 2>/dev/null && installed=false
    fi

    rm -rf "$pack_dir" "$target_repo" "$npm_cache"

    if [ "$installed" = "true" ]; then
        pass "local npm exec defaults to adaptive setup with platform-native hooks when automation passes --yes"
    else
        fail "local npm exec did not route the default command through adaptive setup with platform-native hooks"
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
            CODEX_SDLC_DISABLE_REASONING=1 npm_config_cache="$npm_cache" npm exec --yes --package "$tarball_path" -- codex-sdlc-wizard setup --yes --model-profile maximum >/dev/null 2>&1
        ) || configured=false
    fi

    if [ "$configured" = "true" ]; then
        if [ ! -f "$target_repo/.codex-sdlc/model-profile.json" ] ||
           ! json_has_truthy_file "$target_repo/.codex-sdlc/model-profile.json" 'data.selected_profile === "maximum"'; then
            configured=false
        elif ! grep -q '^model = "gpt-5.4"' "$target_repo/.codex/config.toml" 2>/dev/null; then
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
            CODEX_SDLC_DISABLE_REASONING=1 npm_config_cache="$npm_cache" npm exec --yes --package "$tarball_path" -- \
                codex-sdlc-wizard setup --yes 2>&1
        ) || valid=false

        check_output=$(
            cd "$target_repo" && \
            npm_config_cache="$npm_cache" npm exec --yes --package "$tarball_path" -- \
                codex-sdlc-wizard check 2>&1
        ) || valid=false

        update_output=$(
            cd "$target_repo" && \
            npm_config_cache="$npm_cache" npm exec --yes --package "$tarball_path" -- \
                codex-sdlc-wizard update check-only 2>&1
        ) || valid=false
    fi

    [ -f "$target_repo/.codex-sdlc/manifest.json" ] || valid=false
    json_has_truthy_file "$target_repo/.codex-sdlc/manifest.json" 'typeof data.managed_files?.["AGENTS.md"] === "string" && /^sha256:[0-9a-f]{64}$/.test(data.managed_files["AGENTS.md"])' || valid=false
    echo "$setup_output" | grep -q 'Setup complete' || valid=false
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
    local ws fakebin fakebin_win codex_home args_file input_file output
    ws=$(mktemp -d "$MKTEMP_DIR/sdlc-npx-target.XXXXXX")
    fakebin=$(mktemp -d "$MKTEMP_DIR/sdlc-npx-bin.XXXXXX")
    codex_home=$(mktemp -d "$MKTEMP_DIR/sdlc-npx-home.XXXXXX")
    args_file="$ws/codex-args.txt"
    input_file="$ws/handoff-input.txt"

    printf '%s' '{"name":"handoff-smoke","scripts":{"test":"npm test"}}' > "$ws/package.json"
    mkdir -p "$ws/tests"
    touch "$ws/tests/app.e2e.ts" "$ws/playwright.config.js"
    printf '\n' > "$input_file"

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
        CODEX_HOME="$codex_home" \
        CODEX_SDLC_CODEX_BIN="$fakebin_win\\codex.cmd" \
        CODEX_SDLC_DISABLE_REASONING=1 \
        FAKE_CODEX_ARGS_FILE="$args_file" \
        PATH="$fakebin_win;$PATH" \
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
    grep -Fq 'gpt-5.4' "$args_file" 2>/dev/null || valid=false
    grep -Fq "model_reasoning_effort='xhigh'" "$args_file" 2>/dev/null || valid=false
    grep -Fq '$setup-wizard' "$args_file" 2>/dev/null || valid=false
    echo "$output" | grep -Fq 'Choose first-run Codex handoff mode' || valid=false
    echo "$output" | grep -Fq 'Press Enter: plain codex (recommended)' || valid=false
    echo "$output" | grep -Fq 'Type full-auto: codex --full-auto' || valid=false
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
    local ws fakebin fakebin_win codex_home args_file input_file output
    ws=$(mktemp -d "$MKTEMP_DIR/sdlc-npx-target.XXXXXX")
    fakebin=$(mktemp -d "$MKTEMP_DIR/sdlc-npx-bin.XXXXXX")
    codex_home=$(mktemp -d "$MKTEMP_DIR/sdlc-npx-home.XXXXXX")
    args_file="$ws/codex-args.txt"
    input_file="$ws/handoff-input.txt"

    printf '%s' '{"name":"handoff-smoke","scripts":{"test":"npm test"}}' > "$ws/package.json"
    mkdir -p "$ws/tests"
    touch "$ws/tests/app.e2e.ts" "$ws/playwright.config.js"
    printf 'full-auto\n' > "$input_file"

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
        CODEX_HOME="$codex_home" \
        CODEX_SDLC_CODEX_BIN="$fakebin_win\\codex.cmd" \
        CODEX_SDLC_DISABLE_REASONING=1 \
        FAKE_CODEX_ARGS_FILE="$args_file" \
        PATH="$fakebin_win;$PATH" \
        node "$REPO_DIR/bin/codex-sdlc-wizard.js" < "$input_file" 2>&1
    ) || true

    local valid=true
    grep -Fq -- '--full-auto' "$args_file" 2>/dev/null || valid=false
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
test_ci_mode_keeps_shell_setup_path
test_cli_help_documents_bootstrap_profile_policy
test_cli_help_explains_update_version_boundary

echo ""
echo "=== Results: $PASSED passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
    exit 1
fi
