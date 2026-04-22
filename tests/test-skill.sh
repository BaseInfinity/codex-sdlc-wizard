#!/bin/bash
# Skill tests — keep the Codex skill package real and documented

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$SCRIPT_DIR/.."
README="$REPO_DIR/README.md"
SKILL_MD="$REPO_DIR/SKILL.md"
OPENAI_YAML="$REPO_DIR/agents/openai.yaml"
REPO_SDLC_SKILL="$REPO_DIR/.agents/skills/sdlc/SKILL.md"
REPO_ADLC_SKILL="$REPO_DIR/.agents/skills/adlc/SKILL.md"
PASSED=0
FAILED=0

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

echo "=== Skill Tests ==="
echo ""

test_skill_manifest_exists() {
    local has_name=true
    local has_description=true
    local mentions_install=true
    local mentions_setup=true

    [ -f "$SKILL_MD" ] || has_name=false
    grep -q '^name:' "$SKILL_MD" || has_name=false
    grep -q '^description:' "$SKILL_MD" || has_description=false
    grep -q '`install.sh`' "$SKILL_MD" || mentions_install=false
    grep -q '`setup.sh`' "$SKILL_MD" || mentions_setup=false

    if [ "$has_name" = "true" ] &&
       [ "$has_description" = "true" ] &&
       [ "$mentions_install" = "true" ] &&
       [ "$mentions_setup" = "true" ]; then
        pass "SKILL.md exists and explains the installer/setup split"
    else
        fail "SKILL.md is missing or does not explain how to use the bundled scripts"
    fi
}

test_agents_openai_yaml_exists() {
    local has_display_name=true
    local has_short_description=true
    local has_default_prompt=true

    [ -f "$OPENAI_YAML" ] || has_display_name=false
    grep -q '^interface:$' "$OPENAI_YAML" || has_display_name=false
    grep -q '^  display_name:' "$OPENAI_YAML" || has_display_name=false
    grep -q '^  short_description:' "$OPENAI_YAML" || has_short_description=false
    grep -q '^  default_prompt:' "$OPENAI_YAML" || has_default_prompt=false

    if [ "$has_display_name" = "true" ] &&
       [ "$has_short_description" = "true" ] &&
       [ "$has_default_prompt" = "true" ]; then
        pass "agents/openai.yaml exists with Codex skill metadata"
    else
        fail "agents/openai.yaml is missing or incomplete"
    fi
}

test_readme_documents_dual_distribution() {
    local mentions_skill=true
    local mentions_installer=true
    local mentions_skill_install=true
    local does_not_deny_skill=true

    grep -qi 'Codex skill' "$README" || mentions_skill=false
    grep -q '`install.sh`' "$README" || mentions_installer=false
    grep -q 'SKILL.md' "$README" || mentions_skill_install=false
    if grep -qi 'not a Codex skill' "$README"; then
        does_not_deny_skill=false
    fi

    if [ "$mentions_skill" = "true" ] &&
       [ "$mentions_installer" = "true" ] &&
       [ "$mentions_skill_install" = "true" ] &&
       [ "$does_not_deny_skill" = "true" ]; then
        pass "README documents the repo as a Codex skill plus installer"
    else
        fail "README does not document the dual skill/installer distribution cleanly"
    fi
}

test_readme_recommends_full_auto() {
    local has_full_auto=true
    local has_manual_fallback=true

    grep -q 'codex --full-auto' "$README" || has_full_auto=false
    grep -q 'plain `codex`' "$README" || has_manual_fallback=false

    if [ "$has_full_auto" = "true" ] && [ "$has_manual_fallback" = "true" ]; then
        pass "README recommends codex --full-auto with plain codex as the manual fallback"
    else
        fail "README does not document the recommended Codex startup mode"
    fi
}

test_skill_recommends_full_auto_after_install() {
    local mentions_full_auto=true
    local mentions_fresh_session=true

    grep -q 'codex --full-auto' "$SKILL_MD" || mentions_full_auto=false
    grep -qi 'fresh Codex session' "$SKILL_MD" || mentions_fresh_session=false

    if [ "$mentions_full_auto" = "true" ] && [ "$mentions_fresh_session" = "true" ]; then
        pass "SKILL.md tells users to start a fresh codex --full-auto session after install"
    else
        fail "SKILL.md does not guide post-install Codex startup clearly enough"
    fi
}

test_repo_scoped_skills_exist() {
    local has_sdlc=true
    local has_adlc=true

    [ -f "$REPO_SDLC_SKILL" ] || has_sdlc=false
    [ -f "$REPO_ADLC_SKILL" ] || has_adlc=false

    if [ "$has_sdlc" = "true" ] && [ "$has_adlc" = "true" ]; then
        pass "Repo-scoped Codex sdlc/adlc skills exist under .agents/skills"
    else
        fail "Repo-scoped Codex sdlc/adlc skills are missing"
    fi
}

test_repo_scoped_skills_are_codex_native() {
    local has_no_todowrite=true
    local has_no_slash_review=true
    local has_no_read_tool=true

    if grep -Rqi 'TodoWrite' "$REPO_DIR/.agents/skills" 2>/dev/null; then
        has_no_todowrite=false
    fi
    if grep -Rqi '/code-review' "$REPO_DIR/.agents/skills" 2>/dev/null; then
        has_no_slash_review=false
    fi
    if grep -Rqi 'Read tool' "$REPO_DIR/.agents/skills" 2>/dev/null; then
        has_no_read_tool=false
    fi

    if [ "$has_no_todowrite" = "true" ] &&
       [ "$has_no_slash_review" = "true" ] &&
       [ "$has_no_read_tool" = "true" ]; then
        pass "Repo-scoped skills avoid Claude-only TodoWrite, /code-review, and Read tool assumptions"
    else
        fail "Repo-scoped skills still contain Claude-only workflow assumptions"
    fi
}

test_skill_manifest_exists
test_agents_openai_yaml_exists
test_readme_documents_dual_distribution
test_readme_recommends_full_auto
test_skill_recommends_full_auto_after_install
test_repo_scoped_skills_exist
test_repo_scoped_skills_are_codex_native

echo ""
echo "=== Results: $PASSED passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
    exit 1
fi
