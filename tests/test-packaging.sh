#!/bin/bash
# Packaging tests — keep README aligned with the actual distribution model

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$SCRIPT_DIR/.."
README="$REPO_DIR/README.md"
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

echo "=== Packaging Tests ==="
echo ""

test_installer_smoke_test_clean_project() {
    local adapter_clone
    local target_repo
    adapter_clone=$(mktemp -d "$MKTEMP_DIR/sdlc-adapter-clone.XXXXXX")
    target_repo=$(mktemp -d "$MKTEMP_DIR/sdlc-target-repo.XXXXXX")

    cp -R "$REPO_DIR/." "$adapter_clone/"

    (
        cd "$target_repo"
        bash "$adapter_clone/install.sh" >/dev/null 2>&1
    )

    local has_agents=true
    local has_config=true
    local has_hooks_json=true
    local has_bash_guard=true

    [ -f "$target_repo/AGENTS.md" ] || has_agents=false
    [ -f "$target_repo/.codex/config.toml" ] || has_config=false
    [ -f "$target_repo/.codex/hooks.json" ] || has_hooks_json=false
    [ -x "$target_repo/.codex/hooks/bash-guard.sh" ] || has_bash_guard=false

    rm -rf "$adapter_clone" "$target_repo"

    if [ "$has_agents" = "true" ] &&
       [ "$has_config" = "true" ] &&
       [ "$has_hooks_json" = "true" ] &&
       [ "$has_bash_guard" = "true" ]; then
        pass "Installer smoke test succeeds in a clean temp project"
    else
        fail "Installer smoke test did not produce the expected project files"
    fi
}

test_installer_recommends_full_auto() {
    local adapter_clone
    local target_repo
    local output
    adapter_clone=$(mktemp -d "$MKTEMP_DIR/sdlc-adapter-clone.XXXXXX")
    target_repo=$(mktemp -d "$MKTEMP_DIR/sdlc-target-repo.XXXXXX")

    cp -R "$REPO_DIR/." "$adapter_clone/"

    output=$(
        cd "$target_repo" &&
        bash "$adapter_clone/install.sh" 2>&1
    )

    rm -rf "$adapter_clone" "$target_repo"

    if echo "$output" | grep -q "codex --full-auto"; then
        pass "Installer output recommends codex --full-auto after setup"
    else
        fail "Installer output does not recommend codex --full-auto"
    fi
}

test_readme_explains_distribution_model() {
    local has_section=true
    local has_adapter=true
    local has_skill=true
    local has_not_plugin=true
    local has_install_sh=true

    grep -q '^## What This Repo Is$' "$README" || has_section=false
    grep -qi 'installer-style adapter' "$README" || has_adapter=false
    grep -qi 'Codex skill' "$README" || has_skill=false
    grep -qi 'not a Codex plugin' "$README" || has_not_plugin=false
    grep -q '`install.sh`' "$README" || has_install_sh=false

    if [ "$has_section" = "true" ] &&
       [ "$has_adapter" = "true" ] &&
       [ "$has_skill" = "true" ] &&
       [ "$has_not_plugin" = "true" ] &&
       [ "$has_install_sh" = "true" ]; then
        pass "README explains the dual skill plus installer distribution near the top"
    else
        fail "README does not clearly explain adapter vs skill vs plugin"
    fi
}

test_readme_has_install_choice_table() {
    if grep -q '^| Need | Use | Why |$' "$README"; then
        pass "README includes an install choice table"
    else
        fail "README is missing an install choice table"
    fi
}

test_readme_explains_install_side_effects() {
    local has_heading=true
    local mentions_config=true
    local mentions_hooks=true
    local mentions_agents=true

    grep -q '^### What `install.sh` Changes$' "$README" || has_heading=false
    grep -q '\.codex/config\.toml' "$README" || mentions_config=false
    grep -q '\.codex/hooks\.json' "$README" || mentions_hooks=false
    grep -q 'AGENTS\.md' "$README" || mentions_agents=false

    if [ "$has_heading" = "true" ] &&
       [ "$mentions_config" = "true" ] &&
       [ "$mentions_hooks" = "true" ] &&
       [ "$mentions_agents" = "true" ]; then
        pass "README explains what install.sh changes in a target repo"
    else
        fail "README does not describe install.sh side effects clearly enough"
    fi
}

test_readme_mentions_packaging_test_command() {
    if grep -q 'bash tests/test-packaging.sh' "$README"; then
        pass "README includes the packaging smoke test command"
    else
        fail "README does not mention the packaging smoke test command"
    fi
}

test_readme_recommends_full_auto() {
    local has_full_auto=true
    local has_manual_fallback=true

    grep -q 'codex --full-auto' "$README" || has_full_auto=false
    grep -q 'plain `codex`' "$README" || has_manual_fallback=false

    if [ "$has_full_auto" = "true" ] && [ "$has_manual_fallback" = "true" ]; then
        pass "README recommends codex --full-auto and documents plain codex as fallback"
    else
        fail "README does not document the recommended Codex startup mode clearly"
    fi
}

test_installer_smoke_test_clean_project
test_installer_recommends_full_auto
test_readme_explains_distribution_model
test_readme_has_install_choice_table
test_readme_explains_install_side_effects
test_readme_mentions_packaging_test_command
test_readme_recommends_full_auto

echo ""
echo "=== Results: $PASSED passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
    exit 1
fi
