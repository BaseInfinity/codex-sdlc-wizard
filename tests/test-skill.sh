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
REPO_AGENTS="$REPO_DIR/AGENTS.md"
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

test_skill_documents_model_profiles() {
    local has_mixed=true
    local has_maximum=true
    local has_tradeoff=true
    local has_interactive_setup=true
    local has_repo_maximum_rule=true
    local has_bootstrap_maximum_rule=true
    local has_routine_mixed_rule=true

    grep -q '`mixed`' "$SKILL_MD" || has_mixed=false
    grep -q '`maximum`' "$SKILL_MD" || has_maximum=false
    grep -Eqi 'speed|latency|token|stability|ultimate' "$SKILL_MD" || has_tradeoff=false
    grep -Eqi 'ask|interactive `setup` should ask|does not pass `--yes`' "$SKILL_MD" || has_interactive_setup=false
    grep -Eqi 'this repo.*maximum|wizard repo.*maximum|maintaining codex-sdlc-wizard.*maximum' "$SKILL_MD" || has_repo_maximum_rule=false
    grep -Eqi 'setup/update.*maximum|bootstrap.*maximum' "$SKILL_MD" || has_bootstrap_maximum_rule=false
    grep -Eqi 'routine work.*mixed|day-to-day.*mixed|after bootstrap.*mixed' "$SKILL_MD" || has_routine_mixed_rule=false

    if [ "$has_mixed" = "true" ] &&
       [ "$has_maximum" = "true" ] &&
       [ "$has_tradeoff" = "true" ] &&
       [ "$has_interactive_setup" = "true" ] &&
       [ "$has_repo_maximum_rule" = "true" ] &&
       [ "$has_bootstrap_maximum_rule" = "true" ] &&
       [ "$has_routine_mixed_rule" = "true" ]; then
        pass "SKILL.md documents bootstrap maximum, routine mixed, and keeps this repo on maximum"
    else
        fail "SKILL.md does not document bootstrap maximum, routine mixed, and this repo's maximum-only policy clearly enough"
    fi
}

test_repo_contract_keeps_this_repo_on_maximum() {
    local has_maximum_rule=true
    local has_gpt55_xhigh_rule=true
    local has_no_downgrade_rule=true
    local has_meta_reason=true

    grep -Eqi 'this repo.*maximum|codex-sdlc-wizard itself.*maximum|maintaining this wizard repo.*maximum' "$REPO_AGENTS" || has_maximum_rule=false
    grep -Eqi 'gpt-5\.5.*xhigh|xhigh.*gpt-5\.5' "$REPO_AGENTS" || has_gpt55_xhigh_rule=false
    grep -Eqi 'do not.*(downgrade|switch).*(mixed|mini|lower)|always.*gpt-5\.5.*xhigh|gpt-5\.5.*xhigh.*always' "$REPO_AGENTS" || has_no_downgrade_rule=false
    grep -Eqi 'explicitly asks for less|asks for less' "$REPO_AGENTS" && has_no_downgrade_rule=false
    grep -Eqi 'meta|high-blast-radius|too meta' "$REPO_AGENTS" || has_meta_reason=false

    if [ "$has_maximum_rule" = "true" ] &&
       [ "$has_gpt55_xhigh_rule" = "true" ] &&
       [ "$has_no_downgrade_rule" = "true" ] &&
       [ "$has_meta_reason" = "true" ]; then
        pass "AGENTS.md keeps this wizard repo on gpt-5.5 xhigh maximum because the work is meta/high-blast-radius"
    else
        fail "AGENTS.md does not keep this wizard repo on gpt-5.5 xhigh maximum clearly enough"
    fi
}

test_default_repo_scoped_skill_surface_is_sdlc_only() {
    local has_sdlc=true
    local avoids_adlc=true

    [ -f "$REPO_SDLC_SKILL" ] || has_sdlc=false
    [ -e "$REPO_ADLC_SKILL" ] && avoids_adlc=false

    if [ "$has_sdlc" = "true" ] && [ "$avoids_adlc" = "true" ]; then
        pass "Default repo-scoped Codex skill surface is sdlc only"
    else
        fail "Default repo-scoped Codex skill surface should not include adlc"
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

test_repo_scoped_sdlc_skill_documents_codex_shape_and_repo_focus() {
    local has_shape=true
    local has_confidence=true
    local has_direct_issue=true
    local has_product_repo=true
    local has_blocked_boundary=true
    local avoids_pilot_rollout_note=true

    grep -q 'skills = explicit workflow layer' "$REPO_SDLC_SKILL" || has_shape=false
    grep -q 'hooks = silent event enforcement' "$REPO_SDLC_SKILL" || has_shape=false
    grep -q 'repo docs = source of local truth' "$REPO_SDLC_SKILL" || has_shape=false
    grep -qi 'keep slices small' "$REPO_SDLC_SKILL" || has_confidence=false
    grep -qi 'direct GitHub issue' "$REPO_SDLC_SKILL" || has_direct_issue=false
    grep -qi 'product repo' "$REPO_SDLC_SKILL" || has_product_repo=false
    grep -qi 'actually blocked' "$REPO_SDLC_SKILL" || has_blocked_boundary=false
    grep -qi 'pilot-rollout.csv' "$REPO_SDLC_SKILL" && avoids_pilot_rollout_note=false

    if [ "$has_shape" = "true" ] &&
       [ "$has_confidence" = "true" ] &&
       [ "$has_direct_issue" = "true" ] &&
       [ "$has_product_repo" = "true" ] &&
       [ "$has_blocked_boundary" = "true" ] &&
       [ "$avoids_pilot_rollout_note" = "true" ]; then
        pass "Repo-scoped sdlc skill documents the Codex shape and repo-focus feedback loop"
    else
        fail "Repo-scoped sdlc skill does not document the Codex shape and repo-focus feedback loop clearly enough"
    fi
}

test_skill_manifest_exists
test_agents_openai_yaml_exists
test_readme_documents_dual_distribution
test_readme_recommends_full_auto
test_skill_recommends_full_auto_after_install
test_skill_documents_model_profiles
test_repo_contract_keeps_this_repo_on_maximum
test_default_repo_scoped_skill_surface_is_sdlc_only
test_repo_scoped_skills_are_codex_native
test_repo_scoped_sdlc_skill_documents_codex_shape_and_repo_focus

echo ""
echo "=== Results: $PASSED passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
    exit 1
fi
