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

test_installer_scaffolds_repo_scope_skills() {
    local adapter_clone
    local target_repo
    adapter_clone=$(mktemp -d "$MKTEMP_DIR/sdlc-adapter-clone.XXXXXX")
    target_repo=$(mktemp -d "$MKTEMP_DIR/sdlc-target-repo.XXXXXX")

    cp -R "$REPO_DIR/." "$adapter_clone/"

    (
        cd "$target_repo"
        bash "$adapter_clone/install.sh" >/dev/null 2>&1
    )

    local has_sdlc_skill=true
    local has_adlc_skill=true

    [ -f "$target_repo/.agents/skills/sdlc/SKILL.md" ] || has_sdlc_skill=false
    [ -f "$target_repo/.agents/skills/adlc/SKILL.md" ] || has_adlc_skill=false

    rm -rf "$adapter_clone" "$target_repo"

    if [ "$has_sdlc_skill" = "true" ] && [ "$has_adlc_skill" = "true" ]; then
        pass "Installer scaffolds repo-scope Codex sdlc and adlc skills"
    else
        fail "Installer did not scaffold repo-scope Codex sdlc/adlc skills"
    fi
}

test_installer_writes_default_model_profile() {
    local adapter_clone
    local target_repo
    adapter_clone=$(mktemp -d "$MKTEMP_DIR/sdlc-adapter-clone.XXXXXX")
    target_repo=$(mktemp -d "$MKTEMP_DIR/sdlc-target-repo.XXXXXX")

    cp -R "$REPO_DIR/." "$adapter_clone/"

    (
        cd "$target_repo"
        bash "$adapter_clone/install.sh" >/dev/null 2>&1
    )

    local has_profile=true
    if [ ! -f "$target_repo/.codex-sdlc/model-profile.json" ]; then
        has_profile=false
    elif ! jq -e '.selected_profile == "mixed"' "$target_repo/.codex-sdlc/model-profile.json" >/dev/null 2>&1; then
        has_profile=false
    elif ! jq -e '.profiles.maximum.main_model == "gpt-5.4"' "$target_repo/.codex-sdlc/model-profile.json" >/dev/null 2>&1; then
        has_profile=false
    fi

    rm -rf "$adapter_clone" "$target_repo"

    if [ "$has_profile" = "true" ]; then
        pass "Installer writes the default mixed model profile with a maximum option"
    else
        fail "Installer did not write the expected default model profile"
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

test_installer_mentions_model_profile_tradeoff() {
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

    if echo "$output" | grep -qi 'mixed' &&
       echo "$output" | grep -qi 'maximum' &&
       echo "$output" | grep -Eqi 'speed|token|latency' &&
       echo "$output" | grep -qi 'stability'; then
        pass "Installer output explains the mixed versus maximum model-profile tradeoff"
    else
        fail "Installer output does not explain the mixed versus maximum profile tradeoff"
    fi
}

test_installer_calls_out_auth_heavy_boundary() {
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

    if echo "$output" | grep -qi 'Windows / WAM / MFA' &&
       echo "$output" | grep -qi 'user-owned' &&
       echo "$output" | grep -qi 'sign-in'; then
        pass "Installer output explains the user-owned boundary for auth-heavy Windows / WAM / MFA flows"
    else
        fail "Installer output does not explain the auth-heavy boundary clearly enough"
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

test_readme_documents_auth_heavy_boundaries() {
    local has_heading=true
    local has_windows=true
    local has_user_owned=true
    local has_resume_pattern=true
    local has_not_refusal=true

    grep -q '^## Auth-Heavy Workflow Boundaries$' "$README" || has_heading=false
    grep -qi 'Windows' "$README" || has_windows=false
    grep -Eqi 'user-owned|your live sign-in' "$README" || has_user_owned=false
    grep -Eqi 'resume|wrap' "$README" || has_resume_pattern=false
    grep -Eqi 'not a refusal|isn.t refusing|without sounding like the agent is refusing' "$README" || has_not_refusal=false

    if [ "$has_heading" = "true" ] &&
       [ "$has_windows" = "true" ] &&
       [ "$has_user_owned" = "true" ] &&
       [ "$has_resume_pattern" = "true" ] &&
       [ "$has_not_refusal" = "true" ]; then
        pass "README documents auth-heavy workflow boundaries and how to present them"
    else
        fail "README does not document auth-heavy workflow boundaries clearly enough"
    fi
}

test_readme_documents_capability_detectors() {
    local has_heading=true
    local has_doctor_pattern=true
    local has_one_command_classifier=true
    local has_setup_data_language=true

    grep -q '^## Capability Detectors for Auth / License-Sensitive Repos$' "$README" || has_heading=false
    grep -Eqi 'doctor|check-capability|Test-.*Access' "$README" || has_doctor_pattern=false
    grep -Eqi 'one-command classification|one command classification|single command classification' "$README" || has_one_command_classifier=false
    grep -Eqi 'setup data|account type|licen(s|c)e|permission state|tenant shape' "$README" || has_setup_data_language=false

    if [ "$has_heading" = "true" ] &&
       [ "$has_doctor_pattern" = "true" ] &&
       [ "$has_one_command_classifier" = "true" ] &&
       [ "$has_setup_data_language" = "true" ]; then
        pass "README documents the capability-detector pattern for auth / license-sensitive repos"
    else
        fail "README does not document the capability-detector pattern clearly enough"
    fi
}

test_readme_documents_repo_scope_skills() {
    local has_heading=true
    local has_agents_path=true
    local has_sdlc=true
    local has_wip_language=true
    local has_gdlc=true
    local has_rdlc=true
    local has_fresh_session=true

    grep -q '^## Repo-Scoped Skills$' "$README" || has_heading=false
    grep -q '\.agents/skills' "$README" || has_agents_path=false
    grep -q '\$sdlc' "$README" || has_sdlc=false
    grep -Eqi 'work in progress|still in progress|not all available yet' "$README" || has_wip_language=false
    grep -q 'gdlc' "$README" || has_gdlc=false
    grep -q 'rdlc' "$README" || has_rdlc=false
    grep -Eqi 'fresh Codex session|start a fresh codex session|restart Codex' "$README" || has_fresh_session=false

    if [ "$has_heading" = "true" ] &&
       [ "$has_agents_path" = "true" ] &&
       [ "$has_sdlc" = "true" ] &&
       [ "$has_wip_language" = "true" ] &&
       [ "$has_gdlc" = "true" ] &&
       [ "$has_rdlc" = "true" ] &&
       [ "$has_fresh_session" = "true" ]; then
        pass "README documents the current repo-scope skill rollout and future skill roadmap"
    else
        fail "README does not document the repo-scope skill rollout clearly enough"
    fi
}

test_readme_documents_honest_codex_shape() {
    local has_skills_layer=true
    local has_hooks_layer=true
    local has_docs_truth=true

    grep -q 'skills = explicit workflow layer' "$README" || has_skills_layer=false
    grep -q 'hooks = silent event enforcement' "$README" || has_hooks_layer=false
    grep -q 'repo docs = source of local truth' "$README" || has_docs_truth=false

    if [ "$has_skills_layer" = "true" ] &&
       [ "$has_hooks_layer" = "true" ] &&
       [ "$has_docs_truth" = "true" ]; then
        pass "README documents the honest Codex SDLC shape"
    else
        fail "README does not document the honest Codex SDLC shape clearly enough"
    fi
}

test_readme_documents_feedback_flow_and_repo_focus() {
    local has_direct_issue=true
    local has_proven_finding=true
    local has_product_repo=true
    local has_blocked_boundary=true

    grep -qi 'direct GitHub issue' "$README" || has_direct_issue=false
    grep -qi 'proven reusable' "$README" || has_proven_finding=false
    grep -qi 'product repo' "$README" || has_product_repo=false
    grep -qi 'actually blocked' "$README" || has_blocked_boundary=false

    if [ "$has_direct_issue" = "true" ] &&
       [ "$has_proven_finding" = "true" ] &&
       [ "$has_product_repo" = "true" ] &&
       [ "$has_blocked_boundary" = "true" ]; then
        pass "README documents the feedback flow and repo-focus rule"
    else
        fail "README does not document the feedback flow and repo-focus rule clearly enough"
    fi
}

test_readme_documents_model_profiles() {
    local has_heading=true
    local has_mixed=true
    local has_maximum=true
    local has_tradeoff=true
    local has_confidence_rule=true

    grep -q '^## Model Profiles$' "$README" || has_heading=false
    grep -q '`mixed`' "$README" || has_mixed=false
    grep -q '`maximum`' "$README" || has_maximum=false
    grep -Eqi 'speed|latency|token' "$README" || has_tradeoff=false
    grep -Eqi 'stability|ultimate' "$README" || has_tradeoff=false
    grep -Eqi '95%|xhigh review|research more first' "$README" || has_confidence_rule=false

    if [ "$has_heading" = "true" ] &&
       [ "$has_mixed" = "true" ] &&
       [ "$has_maximum" = "true" ] &&
       [ "$has_tradeoff" = "true" ] &&
       [ "$has_confidence_rule" = "true" ]; then
        pass "README documents the mixed versus maximum model profiles and the confidence escalation rule"
    else
        fail "README does not document the model profiles and escalation rule clearly enough"
    fi
}

test_installer_smoke_test_clean_project
test_installer_scaffolds_repo_scope_skills
test_installer_writes_default_model_profile
test_installer_recommends_full_auto
test_installer_mentions_model_profile_tradeoff
test_installer_calls_out_auth_heavy_boundary
test_readme_explains_distribution_model
test_readme_has_install_choice_table
test_readme_explains_install_side_effects
test_readme_mentions_packaging_test_command
test_readme_recommends_full_auto
test_readme_documents_auth_heavy_boundaries
test_readme_documents_capability_detectors
test_readme_documents_repo_scope_skills
test_readme_documents_honest_codex_shape
test_readme_documents_feedback_flow_and_repo_focus
test_readme_documents_model_profiles

echo ""
echo "=== Results: $PASSED passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
    exit 1
fi
