#!/bin/bash
# Skill tests — keep the Codex skill package real and documented

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$SCRIPT_DIR/.."
README="$REPO_DIR/README.md"
SKILL_MD="$REPO_DIR/skills/codex-sdlc-wizard/SKILL.md"
OPENAI_YAML="$REPO_DIR/skills/codex-sdlc-wizard/agents/openai.yaml"
PLUGIN_MANIFEST="$REPO_DIR/.codex-plugin/plugin.json"
REPO_SDLC_SKILL="$REPO_DIR/.agents/skills/sdlc/SKILL.md"
SHIPPED_SDLC_SKILL="$REPO_DIR/skill-sources/sdlc/SKILL.template.md"
SDLC_LOOP="$REPO_DIR/SDLC-LOOP.md"
AGENTS_BASELINE="$REPO_DIR/templates/AGENTS.baseline.md"
AGENTS_TEMPLATE="$REPO_DIR/templates/AGENTS.md.tmpl"
REPO_ADLC_SKILL="$REPO_DIR/.agents/skills/adlc/SKILL.md"
GLOBAL_SKILL_SOURCES="$REPO_DIR/skill-sources"
REPO_AGENTS="$REPO_DIR/AGENTS.md"
REPO_CODEX_CONFIG="$REPO_DIR/.codex/config.toml"
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

test_plugin_skill_resolves_bundled_scripts_from_plugin_root() {
    local has_plugin_root_rule=true
    local has_relative_location=true
    local has_absolute_execution_path=true
    local has_target_repo_workdir=true
    local documents_windows_paths=true
    local requires_git_bash_for_windows_adaptive_setup=true
    local keeps_windows_adaptive_setup_noninteractive=true
    local avoids_nonexistent_setup_ps1=true
    local avoids_bare_npx_adaptive_setup=true

    grep -Eqi 'plugin root' "$SKILL_MD" || has_plugin_root_rule=false
    grep -Fq '`../..`' "$SKILL_MD" || has_relative_location=false
    grep -Eqi 'absolute path.*(install|setup)\.sh|(install|setup)\.sh.*absolute path' "$SKILL_MD" || has_absolute_execution_path=false
    grep -Eqi 'target repo(sitory)?.*(working directory|current working directory)|(working directory|current working directory).*target repo(sitory)?' "$SKILL_MD" || has_target_repo_workdir=false
    grep -Fq '`install.ps1`' "$SKILL_MD" || documents_windows_paths=false
    grep -Eqi 'PowerShell.*Git Bash|Git Bash.*PowerShell' "$SKILL_MD" || requires_git_bash_for_windows_adaptive_setup=false
    grep -Eqi 'PowerShell.*`bash .*setup\.sh.*--yes`|`bash .*setup\.sh.*--yes`.*PowerShell' "$SKILL_MD" || keeps_windows_adaptive_setup_noninteractive=false
    grep -Fq 'there is no `setup.ps1`' "$SKILL_MD" || avoids_nonexistent_setup_ps1=false
    grep -Eqi 'PowerShell.*adaptive setup uses `npx codex-sdlc-wizard`' "$SKILL_MD" && avoids_bare_npx_adaptive_setup=false

    if [ "$has_plugin_root_rule" = "true" ] &&
       [ "$has_relative_location" = "true" ] &&
       [ "$has_absolute_execution_path" = "true" ] &&
       [ "$has_target_repo_workdir" = "true" ] &&
       [ "$documents_windows_paths" = "true" ] &&
       [ "$requires_git_bash_for_windows_adaptive_setup" = "true" ] &&
       [ "$keeps_windows_adaptive_setup_noninteractive" = "true" ] &&
       [ "$avoids_nonexistent_setup_ps1" = "true" ] &&
       [ "$avoids_bare_npx_adaptive_setup" = "true" ]; then
        pass "Plugin skill resolves bundled scripts from its installed plugin root"
    else
        fail "Plugin skill does not safely resolve bundled scripts from its installed plugin root"
    fi
}

test_plugin_skill_handles_legacy_standalone_install() {
    local identifies_legacy_path=true
    local explains_duplicate_risk=true
    local requires_permission=true
    local avoids_automatic_deletion=true

    grep -Fq '${CODEX_HOME:-$HOME/.codex}/skills/codex-sdlc-wizard' "$SKILL_MD" || identifies_legacy_path=false
    grep -Eqi 'duplicate|two copies|stale standalone' "$SKILL_MD" || explains_duplicate_risk=false
    grep -Eqi 'ask.*(permission|confirmation)|explicit (permission|confirmation)' "$SKILL_MD" || requires_permission=false
    grep -Eqi 'do not (delete|remove|move).*(automatically|without)|never (delete|remove|move).*(automatically|without)' "$SKILL_MD" || avoids_automatic_deletion=false

    if [ "$identifies_legacy_path" = "true" ] &&
       [ "$explains_duplicate_risk" = "true" ] &&
       [ "$requires_permission" = "true" ] &&
       [ "$avoids_automatic_deletion" = "true" ]; then
        pass "Plugin skill safely detects and migrates legacy standalone installs"
    else
        fail "Plugin skill does not safely handle legacy standalone skill duplication"
    fi
}

test_plugin_skill_documents_surface_specific_installation() {
    local has_shared_catalog=true
    local has_surface_specific_install=true

    grep -Eqi 'shared plugin directory|same public catalog|universal plugin directory' "$SKILL_MD" || has_shared_catalog=false
    grep -Eqi 'install(ation)?(/enablement)? (is|remains) surface-specific|install or enable (it|the plugin) (on|in) each intended surface' "$SKILL_MD" || has_surface_specific_install=false

    if [ "$has_shared_catalog" = "true" ] &&
       [ "$has_surface_specific_install" = "true" ]; then
        pass "Plugin skill distinguishes shared discovery from surface-specific installation"
    else
        fail "Plugin skill conflates the shared plugin catalog with installation state"
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

test_plugin_and_installer_skill_have_distinct_picker_intents() {
    local plugin_default_prompt
    local plugin_display_name
    local plugin_short_description
    local skill_default_prompt
    local skill_display_name
    local skill_short_description
    local valid=true

    plugin_default_prompt=$(node -e 'process.stdout.write(require(process.argv[1]).interface.defaultPrompt)' "$PLUGIN_MANIFEST")
    plugin_display_name=$(node -e 'process.stdout.write(require(process.argv[1]).interface.displayName)' "$PLUGIN_MANIFEST")
    plugin_short_description=$(node -e 'process.stdout.write(require(process.argv[1]).interface.shortDescription)' "$PLUGIN_MANIFEST")
    skill_default_prompt=$(sed -n 's/^  default_prompt: "\(.*\)"$/\1/p' "$OPENAI_YAML")
    skill_display_name=$(sed -n 's/^  display_name: "\(.*\)"$/\1/p' "$OPENAI_YAML")
    skill_short_description=$(sed -n 's/^  short_description: "\(.*\)"$/\1/p' "$OPENAI_YAML")

    [ "$plugin_display_name" = "Codex SDLC Wizard" ] || valid=false
    [ "$plugin_short_description" = "Explore Codex SDLC workflows" ] || valid=false
    [ "$plugin_default_prompt" = "Show me the Codex SDLC Wizard workflows available for this repository and help me choose the right one." ] || valid=false
    [ "$skill_display_name" = "Install SDLC Guardrails" ] || valid=false
    [ "$skill_short_description" = "Set up or repair repo SDLC" ] || valid=false
    [ "$skill_default_prompt" = "Use \$codex-sdlc-wizard to install or update Codex SDLC enforcement in this repository." ] || valid=false
    [ "$plugin_display_name" != "$skill_display_name" ] || valid=false
    [ "$plugin_short_description" != "$skill_short_description" ] || valid=false
    [ "$plugin_default_prompt" != "$skill_default_prompt" ] || valid=false

    if [ "$valid" = "true" ]; then
        pass "Plugin and bundled installer skill have distinct picker intents"
    else
        fail "Plugin and bundled installer skill are ambiguous in the picker"
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

test_repo_contract_defaults_this_repo_to_sol_high() {
    local has_maximum_rule=true
    local has_sol_high_rule=true
    local has_repo_config=true
    local has_no_downgrade_rule=true
    local has_meta_reason=true
    local has_task_scoped_xhigh_rule=true
    local avoids_standing_xhigh=true

    grep -Eqi 'this repo.*maximum|codex-sdlc-wizard itself.*maximum|maintaining this wizard repo.*maximum' "$REPO_AGENTS" || has_maximum_rule=false
    grep -Eqi 'gpt-5\.6-sol.*high|high.*gpt-5\.6-sol' "$REPO_AGENTS" || has_sol_high_rule=false
    grep -qx 'model = "gpt-5.6-sol"' "$REPO_CODEX_CONFIG" || has_repo_config=false
    grep -qx 'model_reasoning_effort = "high"' "$REPO_CODEX_CONFIG" || has_repo_config=false
    grep -Eqi 'do not.*(downgrade|switch).*(mixed|terra|luna|lower)|always.*gpt-5\.6-sol.*high|gpt-5\.6-sol.*high.*always' "$REPO_AGENTS" || has_no_downgrade_rule=false
    grep -Eqi 'explicitly asks for less|asks for less' "$REPO_AGENTS" && has_no_downgrade_rule=false
    grep -Eqi 'meta|high-blast-radius|too meta' "$REPO_AGENTS" || has_meta_reason=false
    grep -Eqi 'xhigh.*(security|migration|destructive|long-running|difficult|high-risk)|(security|migration|destructive|long-running|difficult|high-risk).*xhigh' "$REPO_AGENTS" || has_task_scoped_xhigh_rule=false
    grep -Eqi 'gpt-5\.6-sol.*xhigh|xhigh.*gpt-5\.6-sol|xhigh.*throughout|standing.*xhigh' "$REPO_AGENTS" && avoids_standing_xhigh=false

    if [ "$has_maximum_rule" = "true" ] &&
       [ "$has_sol_high_rule" = "true" ] &&
       [ "$has_repo_config" = "true" ] &&
       [ "$has_no_downgrade_rule" = "true" ] &&
       [ "$has_meta_reason" = "true" ] &&
       [ "$has_task_scoped_xhigh_rule" = "true" ] &&
       [ "$avoids_standing_xhigh" = "true" ]; then
        pass "Repo contract defaults this wizard repo to gpt-5.6 Sol high with task-scoped xhigh escalation"
    else
        fail "Repo contract does not default this wizard repo to gpt-5.6 Sol high clearly enough"
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

test_plugin_skill_bundle_avoids_duplicate_helper_discovery() {
    local avoids_nested_skill_files=true
    local has_installable_sources=true
    local powershell_materializes_sources=true
    local readme_treats_templates_as_installer_inputs=true
    local avoids_legacy_root_bundle_explanation=true
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
    grep -Eqi 'installer inputs?.*not.*directly discoverable plugin skills?|not.*directly discoverable plugin skills?.*installer inputs?' "$README" || readme_treats_templates_as_installer_inputs=false
    grep -Eqi 'repo root is installed as|repo-root.*installed as' "$README" && avoids_legacy_root_bundle_explanation=false

    if [ "$avoids_nested_skill_files" = "true" ] &&
       [ "$has_installable_sources" = "true" ] &&
       [ "$powershell_materializes_sources" = "true" ] &&
       [ "$readme_treats_templates_as_installer_inputs" = "true" ] &&
       [ "$avoids_legacy_root_bundle_explanation" = "true" ]; then
        pass "Plugin bundle templates avoid recursive discovery and materialize on shell and PowerShell paths"
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

test_sdlc_workflow_is_bounded_and_repairable() {
    local file
    local valid=true

    for file in "$REPO_SDLC_SKILL" "$SHIPPED_SDLC_SKILL" "$SDLC_LOOP" "$AGENTS_BASELINE" "$AGENTS_TEMPLATE"; do
        grep -Eqi 'closed (behavior )?allowlist' "$file" || valid=false
        grep -Eqi 'feature creep.*(follow-up|separate).*issue|(follow-up|separate).*issue.*feature creep' "$file" || valid=false
        grep -Eqi 'candidate-born.*outside.*allowlist.*(remove|delete)|(remove|delete).*candidate-born.*outside.*allowlist' "$file" || valid=false
        grep -Eq 'P0.*P1.*P2.*P3' "$file" || valid=false
        grep -Eqi '(at most|maximum|max(imum)?) two corrective rounds|two-corrective-round' "$file" || valid=false
        grep -Eqi 'exchange.*findings.*once|one.*exchange.*findings|one.*cross-feed.*findings' "$file" || valid=false
        grep -Fqi 'do not rerun tests' "$file" || valid=false
        grep -Fqi 'code-review findings only' "$file" || valid=false
        grep -Eqi 'builder (owns|implements) every correction' "$file" || valid=false
        grep -Eqi 'harness.repair|repair.*enforcement' "$file" || valid=false
        grep -Eqi 'test.*immediately after|immediately.*test' "$file" || valid=false
        grep -Eqi 'loop until clean|repeat.*review.*until.*clean' "$file" && valid=false
    done

    if [ "$valid" = "true" ]; then
        pass "SDLC workflow terminates, controls scope, and permits bounded harness repair"
    else
        fail "SDLC workflow is missing bounded review, scope, severity, reconciliation, or harness-repair rules"
    fi
}

test_sdlc_review_reuses_one_broad_proof() {
    local file
    local valid=true

    for file in "$REPO_SDLC_SKILL" "$SHIPPED_SDLC_SKILL" "$SDLC_LOOP" "$AGENTS_BASELINE" "$AGENTS_TEMPLATE"; do
        grep -Fqi 'one broad proof run total' "$file" || valid=false
        grep -Eqi 'prompt-only.*review|review.*prompt-only' "$file" || valid=false
        grep -Eqi 'custom prompt.*(cannot|must not|do not).*--(uncommitted|base|commit)|(cannot|must not|do not).*--(uncommitted|base|commit).*custom prompt' "$file" || valid=false
        grep -Eqi 'base.*candidate|candidate.*base' "$file" || valid=false
        grep -Eqi 'targeted verification.*concrete suspected defect|concrete suspected defect.*targeted verification' "$file" || valid=false
        grep -Eqi 'proof command and result|proof.*command.*result' "$file" || valid=false
    done

    grep -Fq 'MODEL_POLICY_SCHEMA_VERSION=3' "$REPO_DIR/lib/codex-config.sh" || valid=false

    if [ "$valid" = "true" ]; then
        pass "SDLC review consumes one proof receipt without rerunning broad suites"
    else
        fail "SDLC review does not consistently bind prompt-only review to one proof, base, candidate, and upgrade schema"
    fi
}

test_sdlc_documents_bounded_dual_review() {
    local file
    local valid=true

    for file in "$REPO_SDLC_SKILL" "$SHIPPED_SDLC_SKILL" "$SDLC_LOOP" "$AGENTS_BASELINE" "$AGENTS_TEMPLATE"; do
        grep -Fq 'dual-review.cjs --base <ref> --consent-subscription-quota' "$file" || valid=false
        grep -Fqi 'Sol High' "$file" || valid=false
        grep -Fqi 'Fable High' "$file" || valid=false
        grep -Eqi 'subscription[- ]quota' "$file" || valid=false
        grep -Eqi 'independent|independently' "$file" || valid=false
        grep -Eqi 'cross-feed|exchange.*findings.*once|one.*exchange.*findings' "$file" || valid=false
    done

    if [ "$valid" = "true" ]; then
        pass "SDLC workflow documents the bounded consent-based Sol High and Fable High joint review"
    else
        fail "SDLC workflow does not consistently document the bounded dual-review gate"
    fi
}

test_sdlc_documents_incremental_completion_cadence() {
    local file
    local valid=true

    for file in "$REPO_SDLC_SKILL" "$SHIPPED_SDLC_SKILL" "$SDLC_LOOP" "$AGENTS_BASELINE" "$AGENTS_TEMPLATE"; do
        grep -Fqi 'incremental checkpoint' "$file" || valid=false
        grep -Eqi 'at most one risk-based reviewer|one risk-based reviewer at most' "$file" || valid=false
        grep -Fqi 'completion boundary' "$file" || valid=false
        grep -Eqi 'during (this |the )?ten-delivery pilot|when cross-model policy requires it' "$file" || valid=false
        grep -Eqi 'whole base-to-candidate|complete base-to-candidate' "$file" || valid=false
        grep -Fqi 'corrective delta' "$file" || valid=false
        grep -Eqi 'third same-plan correction.*stop|third correction.*stop' "$file" || valid=false
        grep -Eqi 'human approval.*replan|human.*authoriz.*new plan' "$file" || valid=false
        grep -Fqi 'ten-delivery' "$file" || valid=false
    done

    if [ "$valid" = "true" ]; then
        pass "SDLC workflow distinguishes incremental checkpoints from the final completion gate"
    else
        fail "SDLC workflow is missing the incremental checkpoint, completion, correction, or pilot contract"
    fi
}

test_sdlc_exposes_linked_worktree_git_target_to_hooks() {
    local file
    local valid=true

    for file in "$REPO_SDLC_SKILL" "$SHIPPED_SDLC_SKILL" "$SDLC_LOOP" "$AGENTS_BASELINE" "$AGENTS_TEMPLATE"; do
        grep -Fq 'git -C <absolute-worktree>' "$file" || valid=false
        grep -Eqi 'linked worktree.*(commit|push)|(commit|push).*linked worktree' "$file" || valid=false
        grep -Eqi '(do not|never).*(rely|depend).*tool.*workdir|tool.*workdir.*(may|can).*(drop|omit|missing)' "$file" || valid=false
    done

    if [ "$valid" = "true" ]; then
        pass "SDLC workflow exposes linked-worktree Git targets to PreToolUse hooks"
    else
        fail "SDLC workflow can hide linked-worktree Git targets in a dropped tool workdir"
    fi
}

test_skill_manifest_exists
test_plugin_skill_resolves_bundled_scripts_from_plugin_root
test_plugin_skill_handles_legacy_standalone_install
test_plugin_skill_documents_surface_specific_installation
test_agents_openai_yaml_exists
test_plugin_and_installer_skill_have_distinct_picker_intents
test_readme_documents_dual_distribution
test_readme_recommends_current_codex_startup
test_skill_recommends_current_codex_after_install
test_skill_documents_model_profiles
test_repo_contract_defaults_this_repo_to_sol_high
test_default_repo_scoped_skill_surface_is_sdlc_only
test_plugin_skill_bundle_avoids_duplicate_helper_discovery
test_repo_scoped_skills_are_codex_native
test_repo_scoped_sdlc_skill_documents_codex_shape_and_repo_focus
test_repo_scoped_sdlc_skill_documents_native_review
test_sdlc_workflow_is_bounded_and_repairable
test_sdlc_review_reuses_one_broad_proof
test_sdlc_documents_bounded_dual_review
test_sdlc_documents_incremental_completion_cadence
test_sdlc_exposes_linked_worktree_git_target_to_hooks

echo ""
echo "=== Results: $PASSED passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
    exit 1
fi
