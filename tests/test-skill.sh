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
GLOBAL_SKILL_SOURCES="$REPO_DIR/skill-sources"
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

test_readme_recommends_current_codex_startup() {
    local has_current_start=true
    local has_manual_fallback=true
    local has_full_trust_boundary=true

    grep -q 'codex -m gpt-5.6-sol' "$README" || has_current_start=false
    grep -q 'plain `codex`' "$README" || has_manual_fallback=false
    grep -q -- '--dangerously-bypass-approvals-and-sandbox' "$README" || has_full_trust_boundary=false

    if [ "$has_current_start" = "true" ] && [ "$has_manual_fallback" = "true" ] && [ "$has_full_trust_boundary" = "true" ]; then
        pass "README recommends current Codex startup with full-trust as a separate mode"
    else
        fail "README does not document the recommended Codex startup mode"
    fi
}

test_skill_recommends_current_codex_after_install() {
    local mentions_current_start=true
    local mentions_fresh_session=true
    local mentions_full_trust_boundary=true

    grep -q 'codex -m' "$SKILL_MD" || mentions_current_start=false
    grep -qi 'fresh Codex session' "$SKILL_MD" || mentions_fresh_session=false
    grep -q -- '--dangerously-bypass-approvals-and-sandbox' "$SKILL_MD" || mentions_full_trust_boundary=false

    if [ "$mentions_current_start" = "true" ] && [ "$mentions_fresh_session" = "true" ] && [ "$mentions_full_trust_boundary" = "true" ]; then
        pass "SKILL.md tells users to start a fresh current Codex session after install"
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
    local has_sol_driver_default=true
    local has_experimental_mixed_rule=true
    local avoids_routine_mixed_recommendation=true
    local has_adaptive_reasoning_policy=true

    grep -q '`mixed`' "$SKILL_MD" || has_mixed=false
    grep -q '`maximum`' "$SKILL_MD" || has_maximum=false
    grep -q 'gpt-5.6-sol' "$SKILL_MD" || has_tradeoff=false
    grep -q 'gpt-5.6-terra' "$SKILL_MD" || has_tradeoff=false
    grep -q 'gpt-5.6-luna' "$SKILL_MD" || has_tradeoff=false
    grep -Eqi 'speed|latency|token|stability|ultimate' "$SKILL_MD" || has_tradeoff=false
    grep -Eqi 'ask|interactive `setup` should ask|does not pass `--yes`' "$SKILL_MD" || has_interactive_setup=false
    grep -Eqi 'this repo.*maximum|wizard repo.*maximum|maintaining codex-sdlc-wizard.*maximum' "$SKILL_MD" || has_repo_maximum_rule=false
    grep -Eqi 'setup/update.*maximum|bootstrap.*maximum' "$SKILL_MD" || has_bootstrap_maximum_rule=false
    grep -Eqi 'Sol `high`.*(normal|default|standing).*(driver|root|work)|normal.*(driver|root|work).*Sol `high`' "$SKILL_MD" || has_sol_driver_default=false
    grep -Eqi '`mixed`.*experimental.*explicit opt-in|experimental.*`mixed`.*explicit opt-in' "$SKILL_MD" || has_experimental_mixed_rule=false
    grep -Eqi 'routine work.*mixed|day-to-day.*mixed|after bootstrap.*mixed' "$SKILL_MD" && avoids_routine_mixed_recommendation=false
    grep -Eqi 'consumer.*default.*`high`|agentic coding.*default.*`high`|default.*`high`.*agentic' "$SKILL_MD" || has_adaptive_reasoning_policy=false
    grep -Eqi 'xhigh.*(security|migration|destructive|long-running|difficult)|security.*xhigh|migration.*xhigh' "$SKILL_MD" || has_adaptive_reasoning_policy=false

    if [ "$has_mixed" = "true" ] &&
       [ "$has_maximum" = "true" ] &&
       [ "$has_tradeoff" = "true" ] &&
       [ "$has_interactive_setup" = "true" ] &&
       [ "$has_repo_maximum_rule" = "true" ] &&
       [ "$has_bootstrap_maximum_rule" = "true" ] &&
       [ "$has_sol_driver_default" = "true" ] &&
       [ "$has_experimental_mixed_rule" = "true" ] &&
       [ "$avoids_routine_mixed_recommendation" = "true" ] &&
       [ "$has_adaptive_reasoning_policy" = "true" ]; then
        pass "SKILL.md documents Sol high as the normal driver, mixed as experimental opt-in, and keeps this repo on maximum"
    else
        fail "SKILL.md does not document the Sol-high default, experimental mixed policy, and this repo's maximum-only policy clearly enough"
    fi
}

test_repo_contract_keeps_this_repo_on_maximum() {
    local has_maximum_rule=true
    local has_sol_xhigh_rule=true
    local has_no_downgrade_rule=true
    local has_meta_reason=true
    local has_high_measurement_gate=true

    grep -Eqi 'this repo.*maximum|codex-sdlc-wizard itself.*maximum|maintaining this wizard repo.*maximum' "$REPO_AGENTS" || has_maximum_rule=false
    grep -Eqi 'gpt-5\.6-sol.*xhigh|xhigh.*gpt-5\.6-sol' "$REPO_AGENTS" || has_sol_xhigh_rule=false
    grep -Eqi 'do not.*(downgrade|switch).*(mixed|terra|luna|lower)|always.*gpt-5\.6-sol.*xhigh|gpt-5\.6-sol.*xhigh.*always' "$REPO_AGENTS" || has_no_downgrade_rule=false
    grep -Eqi 'explicitly asks for less|asks for less' "$REPO_AGENTS" && has_no_downgrade_rule=false
    grep -Eqi 'meta|high-blast-radius|too meta' "$REPO_AGENTS" || has_meta_reason=false
    grep -Eqi 'measure.*high|compare.*high|high.*candidate|one level lower' "$REPO_AGENTS" || has_high_measurement_gate=false

    if [ "$has_maximum_rule" = "true" ] &&
       [ "$has_sol_xhigh_rule" = "true" ] &&
       [ "$has_no_downgrade_rule" = "true" ] &&
       [ "$has_meta_reason" = "true" ] &&
       [ "$has_high_measurement_gate" = "true" ]; then
        pass "AGENTS.md keeps this wizard repo on gpt-5.6 Sol xhigh maximum because the work is meta/high-blast-radius"
    else
        fail "AGENTS.md does not keep this wizard repo on gpt-5.6 Sol xhigh maximum clearly enough"
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

test_root_skill_bundle_avoids_nested_skill_discovery() {
    local avoids_nested_skill_files=true
    local has_installable_sources=true
    local powershell_materializes_sources=true
    local skill_name

    if find "$GLOBAL_SKILL_SOURCES" -name SKILL.md -print -quit 2>/dev/null | grep -q .; then
        avoids_nested_skill_files=false
    fi

    for skill_name in feedback sdlc setup-wizard update-wizard; do
        [ -f "$GLOBAL_SKILL_SOURCES/$skill_name/SKILL.template.md" ] || has_installable_sources=false
    done

    grep -Fq '$sourceSkillsRoot = Join-Path $SourceRoot "skill-sources"' "$REPO_DIR/install.ps1" || powershell_materializes_sources=false
    grep -Fq '$globalHelperSkills = @("feedback", "setup-wizard", "update-wizard")' "$REPO_DIR/install.ps1" || powershell_materializes_sources=false
    grep -Fq '$installedTemplatePath = Join-Path $installedSkillPath "SKILL.template.md"' "$REPO_DIR/install.ps1" || powershell_materializes_sources=false
    grep -Fq 'Move-Item -LiteralPath $installedTemplatePath -Destination $installedSkillFile' "$REPO_DIR/install.ps1" || powershell_materializes_sources=false
    grep -Fq 'Install-RepoSkill -SourceRoot $scriptDir -Name "sdlc"' "$REPO_DIR/install.ps1" || powershell_materializes_sources=false
    grep -Fq '$repoSkillTarget = ".agents\skills\$Name\SKILL.md"' "$REPO_DIR/install.ps1" || powershell_materializes_sources=false
    grep -Fq '$collidingSdlcPath = Join-Path $skillsRoot "sdlc"' "$REPO_DIR/install.ps1" || powershell_materializes_sources=false
    grep -Fq 'Test-WizardManagedSkill' "$REPO_DIR/install.ps1" || powershell_materializes_sources=false

    if [ "$avoids_nested_skill_files" = "true" ] &&
       [ "$has_installable_sources" = "true" ] &&
       [ "$powershell_materializes_sources" = "true" ]; then
        pass "Root bundle templates avoid recursive discovery and materialize on shell and PowerShell paths"
    else
        fail "Root bundle templates are discoverable, missing, or not materialized by the PowerShell installer"
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

test_repo_scoped_sdlc_skill_documents_native_review() {
    local has_review_command=true
    local has_uncommitted=true
    local has_base=true
    local has_commit=true
    local has_review_model=true
    local has_explicit_high_review=true
    local explains_review_effort_boundary=true
    local explains_slash_boundary=true
    local avoids_autoreview_requirement=true

    grep -q 'codex review' "$REPO_SDLC_SKILL" || has_review_command=false
    grep -q 'codex review --uncommitted' "$REPO_SDLC_SKILL" || has_uncommitted=false
    grep -q 'codex review --base' "$REPO_SDLC_SKILL" || has_base=false
    grep -q 'codex review --commit' "$REPO_SDLC_SKILL" || has_commit=false
    grep -q 'review_model' "$REPO_SDLC_SKILL" || has_review_model=false
    grep -Fq "codex -c 'model_reasoning_effort=\"high\"' review --uncommitted" "$REPO_SDLC_SKILL" || has_explicit_high_review=false
    grep -Eqi 'review_model.*(does not|doesn.t).*reasoning|reasoning.*(does not|doesn.t).*review_model' "$REPO_SDLC_SKILL" || explains_review_effort_boundary=false
    grep -Eqi 'slash-command|slash command' "$REPO_SDLC_SKILL" || explains_slash_boundary=false
    grep -Eqi '(must|always|requires).*/autoreview|/autoreview.*(must|always)' "$REPO_SDLC_SKILL" && avoids_autoreview_requirement=false

    if [ "$has_review_command" = "true" ] &&
       [ "$has_uncommitted" = "true" ] &&
       [ "$has_base" = "true" ] &&
       [ "$has_commit" = "true" ] &&
       [ "$has_review_model" = "true" ] &&
       [ "$has_explicit_high_review" = "true" ] &&
       [ "$explains_review_effort_boundary" = "true" ] &&
       [ "$explains_slash_boundary" = "true" ] &&
       [ "$avoids_autoreview_requirement" = "true" ]; then
        pass "Repo-scoped sdlc skill documents native Codex review"
    else
        fail "Repo-scoped sdlc skill does not document native Codex review clearly enough"
    fi
}

test_skill_manifest_exists
test_agents_openai_yaml_exists
test_readme_documents_dual_distribution
test_readme_recommends_current_codex_startup
test_skill_recommends_current_codex_after_install
test_skill_documents_model_profiles
test_repo_contract_keeps_this_repo_on_maximum
test_default_repo_scoped_skill_surface_is_sdlc_only
test_root_skill_bundle_avoids_nested_skill_discovery
test_repo_scoped_skills_are_codex_native
test_repo_scoped_sdlc_skill_documents_codex_shape_and_repo_focus
test_repo_scoped_sdlc_skill_documents_native_review

echo ""
echo "=== Results: $PASSED passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
    exit 1
fi
