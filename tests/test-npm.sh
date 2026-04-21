#!/bin/bash
# npm packaging tests — keep the npx install surface working end to end

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$SCRIPT_DIR/.."
PACKAGE_JSON="$REPO_DIR/package.json"
PASSED=0
FAILED=0
MKTEMP_DIR="${TMPDIR:-/tmp}"

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
    jq -e '.name == "codex-sdlc-wizard"' "$PACKAGE_JSON" >/dev/null 2>&1 || has_name=false
    jq -e '.version | type == "string"' "$PACKAGE_JSON" >/dev/null 2>&1 || has_version=false
    jq -e '.bin["codex-sdlc-wizard"] == "bin/codex-sdlc-wizard.js"' "$PACKAGE_JSON" >/dev/null 2>&1 || has_bin=false

    if [ "$has_name" = "true" ] &&
       [ "$has_version" = "true" ] &&
       [ "$has_bin" = "true" ]; then
        pass "package.json exposes the codex-sdlc-wizard CLI"
    else
        fail "package.json is missing the expected npm CLI metadata"
    fi
}

test_npm_pack_includes_runtime_files() {
    local pack_dir
    pack_dir=$(mktemp -d "$MKTEMP_DIR/sdlc-npm-pack.XXXXXX")
    local npm_cache
    npm_cache=$(mktemp -d "$MKTEMP_DIR/sdlc-npm-cache.XXXXXX")

    local tarball json tarball_name
    json=$(cd "$REPO_DIR" && npm_config_cache="$npm_cache" npm pack --json --pack-destination "$pack_dir" 2>/dev/null) || true
    tarball_name=$(printf '%s' "$json" | jq -r 'if type=="array" then .[0].filename // empty else empty end' 2>/dev/null || true)

    local has_tarball=true
    local has_install=true
    local has_setup=true
    local has_hooks=true
    local has_bin=true
    local has_skill=true
    local has_openai_yaml=true

    if [ -z "$tarball_name" ] || [ ! -f "$pack_dir/$tarball_name" ]; then
        has_tarball=false
        has_install=false
        has_setup=false
        has_hooks=false
        has_bin=false
        has_skill=false
        has_openai_yaml=false
    else
        tar -tzf "$pack_dir/$tarball_name" | grep -q '^package/install.sh$' || has_install=false
        tar -tzf "$pack_dir/$tarball_name" | grep -q '^package/setup.sh$' || has_setup=false
        tar -tzf "$pack_dir/$tarball_name" | grep -q '^package/.codex/hooks/bash-guard.sh$' || has_hooks=false
        tar -tzf "$pack_dir/$tarball_name" | grep -q '^package/bin/codex-sdlc-wizard.js$' || has_bin=false
        tar -tzf "$pack_dir/$tarball_name" | grep -q '^package/SKILL.md$' || has_skill=false
        tar -tzf "$pack_dir/$tarball_name" | grep -q '^package/agents/openai.yaml$' || has_openai_yaml=false
    fi

    rm -rf "$pack_dir" "$npm_cache"

    if [ "$has_tarball" = "true" ] &&
       [ "$has_install" = "true" ] &&
       [ "$has_setup" = "true" ] &&
       [ "$has_hooks" = "true" ] &&
       [ "$has_bin" = "true" ] &&
       [ "$has_skill" = "true" ] &&
       [ "$has_openai_yaml" = "true" ]; then
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
    tarball_name=$(printf '%s' "$json" | jq -r 'if type=="array" then .[0].filename // empty else empty end' 2>/dev/null || true)

    local tarball_path="$pack_dir/$tarball_name"
    local installed=true

    if [ -z "$tarball_name" ] || [ ! -f "$tarball_path" ]; then
        installed=false
    else
        (
            cd "$target_repo"
            npm_config_cache="$npm_cache" npm exec --yes --package "$tarball_path" -- codex-sdlc-wizard >/dev/null 2>&1
        ) || installed=false
    fi

    [ -f "$target_repo/AGENTS.md" ] || installed=false
    [ -f "$target_repo/.codex/config.toml" ] || installed=false
    [ -f "$target_repo/.codex/hooks.json" ] || installed=false
    [ -x "$target_repo/.codex/hooks/bash-guard.sh" ] || installed=false

    rm -rf "$pack_dir" "$target_repo" "$npm_cache"

    if [ "$installed" = "true" ]; then
        pass "local npm exec installs SDLC enforcement into a clean repo"
    else
        fail "local npm exec did not install the package correctly"
    fi
}

test_package_metadata_exists
test_npm_pack_includes_runtime_files
test_local_npx_installs_into_clean_repo

echo ""
echo "=== Results: $PASSED passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
    exit 1
fi
