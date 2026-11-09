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
CONDUCT_SKILL_SOURCE="$GLOBAL_SKILL_SOURCES/conduct/SKILL.template.md"
CONDUCT_OPENAI_YAML="$GLOBAL_SKILL_SOURCES/conduct/agents/openai.yaml"
CONDUCT_SCRIPT="$GLOBAL_SKILL_SOURCES/conduct/scripts/conduct.cjs"
CONDUCT_STATUS_TEST="$REPO_DIR/tests/test-conduct-status.cjs"
CONDUCT_PARITY_TEST="$REPO_DIR/tests/test-conduct-parity.cjs"
CONDUCT_PROTOCOL="$GLOBAL_SKILL_SOURCES/conduct/references/protocol.md"
CONDUCT_CODEX_NATIVE_REFERENCE="$GLOBAL_SKILL_SOURCES/conduct/references/codex-native.md"
CONDUCT_CLAUDE_DESKTOP_REFERENCE="$GLOBAL_SKILL_SOURCES/conduct/references/claude-desktop.md"
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

    for skill_name in conduct feedback sdlc setup-wizard update-wizard; do
        [ -f "$GLOBAL_SKILL_SOURCES/$skill_name/SKILL.template.md" ] || has_installable_sources=false
    done

    grep -Fq '$sourceSkillsRoot = Join-Path $SourceRoot "skill-sources"' "$REPO_DIR/install.ps1" || powershell_materializes_sources=false
    grep -Fq '$globalHelperSkills = @("conduct", "feedback", "setup-wizard", "update-wizard")' "$REPO_DIR/install.ps1" || powershell_materializes_sources=false
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
        grep -Eqi 'implement-first.*named gate blocks.*(RED|evidence act)' "$file" || valid=false
        grep -Eqi '(final|completion).*(proof|review).*(review|proof)|(proof|review).*(final|completion).*(review|proof)' "$file" || valid=false
        grep -Eqi 'loop until clean|repeat.*review.*until.*clean' "$file" && valid=false
    done

    if [ "$valid" = "true" ]; then
        pass "SDLC workflow terminates, controls scope, and permits bounded harness repair"
    else
        fail "SDLC workflow is missing bounded review, scope, severity, reconciliation, or harness-repair rules"
    fi
}

test_sdlc_scopes_red_to_writable_behavior() {
    local file
    local valid=true
    local workflow_files=(
        "$REPO_SDLC_SKILL"
        "$SHIPPED_SDLC_SKILL"
        "$SDLC_LOOP"
        "$AGENTS_BASELINE"
        "$AGENTS_TEMPLATE"
    )
    local active_surfaces=(
        "${workflow_files[@]}"
        "$REPO_AGENTS"
        "$REPO_DIR/README.md"
        "$REPO_DIR/CODEX_ADAPTER_PLAN.md"
        "$REPO_DIR/templates/GOALS.md.tmpl"
        "$REPO_DIR/templates/SDLC.md.tmpl"
        "$REPO_DIR/TESTING.md"
        "$REPO_DIR/templates/TESTING.md.tmpl"
    )

    for file in "${workflow_files[@]}"; do
        grep -Fqi 'RED mutation is writable' "$file" || valid=false
        grep -Eqi 'EVAL it|eval.*observable scenario' "$file" || valid=false
        grep -Fqi 'Plain-assert it' "$file" || valid=false
        grep -Eqi 'Review it|DON.T TEST IT|judg(e)?ment-call prose' "$file" || valid=false
        grep -Eqi 'observable input/output or side-effect' "$file" || valid=false
        grep -Eqi 'meaning exception.*only.*prose|only.*prose.*meaning exception' "$file" || valid=false
        grep -Eqi 'cross-model.*APPROVE.*same act.*scope|same act.*scope.*cross-model.*APPROVE' "$file" || valid=false
    done

    for file in "${active_surfaces[@]}"; do
        grep -Eqi 'TDD is mandatory: write the failing test first|Write a failing test FIRST|Every bug fix starts with a failing test' "$file" && valid=false
    done

    if [ "$valid" = "true" ]; then
        pass "SDLC scopes RED to writable behavior and routes other evidence honestly"
    else
        fail "SDLC still mandates fake RED evidence or omits the three-way evidence rule"
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

    grep -Fq 'MODEL_POLICY_SCHEMA_VERSION=4' "$REPO_DIR/lib/codex-config.sh" || valid=false

    if [ "$valid" = "true" ]; then
        pass "SDLC review consumes one proof receipt without rerunning broad suites"
    else
        fail "SDLC review does not consistently bind prompt-only review to one proof, base, candidate, and upgrade schema"
    fi
}

test_sdlc_defaults_to_direct_delivery_without_pr() {
    local help
    local valid=true

    python3 - "$REPO_SDLC_SKILL" "$SHIPPED_SDLC_SKILL" "$SDLC_LOOP" "$AGENTS_BASELINE" "$AGENTS_TEMPLATE" \
        "$REPO_DIR/README.md" "$REPO_DIR/PROVE-IT.md" <<'PYCHECK' || valid=false
import re, sys
direct = "dual-review.cjs deliver direct --message <text> --branch <base>"
ok = True
for path in sys.argv[1:]:
    text = open(path, encoding="utf-8").read()
    flat = re.sub(r"\s+", " ", text)
    at = flat.find(direct)
    gh = flat.find("deliver github")
    if at < 0 or gh < 0 or at > gh:
        ok = False
    elif not re.search(r"is the default: ", flat[at:at + 200]):
        ok = False
    if "only when the repository requires pull requests" not in flat or "non-GitHub" in flat:
        ok = False
    for sentence in re.split(r"(?<=[.;])\s", flat):
        if "deliver github" in sentence and re.search(r"\bdefault\b", sentence):
            ok = False
    if not ok:
        print("direct-delivery default missing or regressed in " + path)
        break
sys.exit(0 if ok else 1)
PYCHECK
    help=$(node "$REPO_DIR/.codex/hooks/dual-review.cjs" deliver --help 2>&1)
    printf '%s\n' "$help" | grep -m1 'deliver ' | grep -Fq 'deliver direct' || valid=false
    printf '%s\n' "$help" | grep -Fq 'direct is the default' || valid=false

    if [ "$valid" = "true" ]; then
        pass "SDLC delivers the certified commit straight to the base branch by default; PRs only when required"
    else
        fail "SDLC still makes a pull request the default delivery or limits direct delivery to non-GitHub paths"
    fi
}

test_sdlc_documents_bounded_dual_review() {
    local file
    local valid=true

    for file in "$REPO_SDLC_SKILL" "$SHIPPED_SDLC_SKILL" "$SDLC_LOOP" "$AGENTS_BASELINE" "$AGENTS_TEMPLATE"; do
        grep -Fq 'dual-review.cjs --base <ref> --consent-subscription-quota' "$file" || valid=false
        grep -Fq 'dual-review.cjs deliver github' "$file" || valid=false
        grep -Fqi 'Sol High' "$file" || valid=false
        grep -Eqi 'Fable High|fable-high' "$file" || valid=false
        grep -Fqi 'opus-4.8-xhigh' "$file" || valid=false
        grep -Eqi 'requested.*actual reviewer|requested and actual reviewer|requested.*actual provider' "$file" || valid=false
        grep -Eqi 'quota/model unavailability|quota or model availability' "$file" || valid=false
        grep -Eqi 'subscription[- ]quota' "$file" || valid=false
        grep -Eqi 'independent|independently' "$file" || valid=false
        grep -Eqi 'cross-feed|exchange.*findings.*once|one.*exchange.*findings' "$file" || valid=false
    done

    if [ "$valid" = "true" ]; then
        pass "SDLC workflow documents the bounded consent-based Sol High and repo-selected cross-model review"
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

test_conduct_skill_documents_shared_protocol_and_reachability_boundary() {
    local has_source=true
    local has_metadata=true
    local has_eight_fields=true
    local has_native_first=true
    local has_registered_boundary=true
    local has_desktop_boundary=true
    local has_loop_guard=true
    local has_no_raw_trigger=true

    [ -f "$CONDUCT_SKILL_SOURCE" ] || has_source=false
    [ -f "$CONDUCT_OPENAI_YAML" ] || has_metadata=false
    grep -Fq '{v, id, from, to, type, prompt, cwd, ref}' "$CONDUCT_SKILL_SOURCE" 2>/dev/null || has_eight_fields=false
    grep -Eqi 'native-first|native first' "$CONDUCT_SKILL_SOURCE" 2>/dev/null || has_native_first=false
    grep -Eqi 'registered.*reachable|reachable.*registered' "$CONDUCT_SKILL_SOURCE" 2>/dev/null || has_registered_boundary=false
    grep -Eqi 'Claude Desktop.*adapter|adapter.*Claude Desktop' "$CONDUCT_SKILL_SOURCE" 2>/dev/null || has_desktop_boundary=false
    grep -Eqi 'one request.*one response|response.*must.*reference' "$CONDUCT_SKILL_SOURCE" 2>/dev/null || has_loop_guard=false
    grep -Eqi 'no raw.*trigger|never.*raw.*trigger' "$CONDUCT_SKILL_SOURCE" 2>/dev/null || has_no_raw_trigger=false

    if [ "$has_source" = "true" ] &&
       [ "$has_metadata" = "true" ] &&
       [ "$has_eight_fields" = "true" ] &&
       [ "$has_native_first" = "true" ] &&
       [ "$has_registered_boundary" = "true" ] &&
       [ "$has_desktop_boundary" = "true" ] &&
       [ "$has_loop_guard" = "true" ] &&
       [ "$has_no_raw_trigger" = "true" ]; then
        pass "conduct skill documents the shared protocol, reachability boundary, and loop guard"
    else
        fail "conduct skill is missing the protocol, reachability boundary, or safety contract"
    fi
}

test_conduct_operating_model_block_is_unique_and_matches_peer() {
    local ws peer_skill output
    local valid=true
    ws=$(mktemp -d)
    peer_skill="$ws/peer/skills/conduct/SKILL.md"
    mkdir -p "$(dirname "$peer_skill")"

    if ! output=$(CONDUCT_SKILL_SOURCE="$CONDUCT_SKILL_SOURCE" \
        node "$CONDUCT_PARITY_TEST" 2>&1); then
        valid=false
    fi
    if [ -z "${CLAUDE_SDLC_WIZARD_DIR:-}" ]; then
        printf '%s\n' "$output" | grep -Fq 'SKIP: CLAUDE_SDLC_WIZARD_DIR is unset' || valid=false
    fi

    cp "$CONDUCT_SKILL_SOURCE" "$peer_skill"
    CLAUDE_SDLC_WIZARD_DIR="$ws/peer" CONDUCT_SKILL_SOURCE="$CONDUCT_SKILL_SOURCE" \
        node "$CONDUCT_PARITY_TEST" >/dev/null 2>&1 || valid=false

    if CLAUDE_SDLC_WIZARD_DIR="$ws/missing" CONDUCT_SKILL_SOURCE="$CONDUCT_SKILL_SOURCE" \
        node "$CONDUCT_PARITY_TEST" >/dev/null 2>&1; then
        valid=false
    fi

    PEER_SKILL="$peer_skill" node <<'NODE'
const fs = require("node:fs");
const file = process.env.PEER_SKILL;
const content = fs.readFileSync(file);
const needle = Buffer.from("The conductor only routes.");
const offset = content.indexOf(needle);
if (offset === -1) process.exit(1);
content[offset] ^= 1;
fs.writeFileSync(file, content);
NODE
    if CLAUDE_SDLC_WIZARD_DIR="$ws/peer" CONDUCT_SKILL_SOURCE="$CONDUCT_SKILL_SOURCE" \
        node "$CONDUCT_PARITY_TEST" >/dev/null 2>&1; then
        valid=false
    fi

    cp "$CONDUCT_SKILL_SOURCE" "$peer_skill"
    PEER_SKILL="$peer_skill" node <<'NODE'
const fs = require("node:fs");
const file = process.env.PEER_SKILL;
const begin = "<!-- conduct-operating-model:begin -->";
const content = fs.readFileSync(file, "utf8");
if (!content.includes(begin)) process.exit(1);
fs.writeFileSync(file, content.replace(begin, ""));
NODE
    if CLAUDE_SDLC_WIZARD_DIR="$ws/peer" CONDUCT_SKILL_SOURCE="$CONDUCT_SKILL_SOURCE" \
        node "$CONDUCT_PARITY_TEST" >/dev/null 2>&1; then
        valid=false
    fi

    cp "$CONDUCT_SKILL_SOURCE" "$peer_skill"
    PEER_SKILL="$peer_skill" node <<'NODE'
const fs = require("node:fs");
const file = process.env.PEER_SKILL;
const content = fs.readFileSync(file, "utf8");
fs.writeFileSync(file, content.replace(/\n/g, "\r\n"));
NODE
    if CLAUDE_SDLC_WIZARD_DIR="$ws/peer" CONDUCT_SKILL_SOURCE="$CONDUCT_SKILL_SOURCE" \
        node "$CONDUCT_PARITY_TEST" >/dev/null 2>&1; then
        valid=false
    fi

    cp "$CONDUCT_SKILL_SOURCE" "$peer_skill"
    PEER_SKILL="$peer_skill" node <<'NODE'
const fs = require("node:fs");
const file = process.env.PEER_SKILL;
const begin = "<!-- conduct-operating-model:begin -->";
const content = fs.readFileSync(file, "utf8");
fs.writeFileSync(file, `${content}${begin}\n`);
NODE
    if CLAUDE_SDLC_WIZARD_DIR="$ws/peer" CONDUCT_SKILL_SOURCE="$CONDUCT_SKILL_SOURCE" \
        node "$CONDUCT_PARITY_TEST" >/dev/null 2>&1; then
        valid=false
    fi

    cp "$CONDUCT_SKILL_SOURCE" "$peer_skill"
    PEER_SKILL="$peer_skill" node <<'NODE'
const fs = require("node:fs");
const file = process.env.PEER_SKILL;
const begin = "<!-- conduct-operating-model:begin -->";
const end = "<!-- conduct-operating-model:end -->";
const content = fs.readFileSync(file, "utf8");
fs.writeFileSync(file, content.replace(begin, "PLACEHOLDER").replace(end, begin).replace("PLACEHOLDER", end));
NODE
    if CLAUDE_SDLC_WIZARD_DIR="$ws/peer" CONDUCT_SKILL_SOURCE="$CONDUCT_SKILL_SOURCE" \
        node "$CONDUCT_PARITY_TEST" >/dev/null 2>&1; then
        valid=false
    fi

    local local_skill="$ws/local/SKILL.template.md"
    mkdir -p "$(dirname "$local_skill")"
    cp "$CONDUCT_SKILL_SOURCE" "$local_skill"
    cp "$CONDUCT_SKILL_SOURCE" "$peer_skill"
    LOCAL_SKILL="$local_skill" PEER_SKILL="$peer_skill" node <<'NODE'
const fs = require("node:fs");
for (const file of [process.env.LOCAL_SKILL, process.env.PEER_SKILL]) {
  const content = fs.readFileSync(file, "utf8");
  fs.writeFileSync(file, content.replace(/^\| 4 \|.*\n/m, ""));
}
NODE
    if CLAUDE_SDLC_WIZARD_DIR="$ws/peer" CONDUCT_SKILL_SOURCE="$local_skill" \
        node "$CONDUCT_PARITY_TEST" >/dev/null 2>&1; then
        valid=false
    fi

    rm -rf "$ws"
    if [ "$valid" = "true" ]; then
        printf '%s\n' "$output"
        pass "conduct operating model uses strict directory-based raw-byte peer parity"
    else
        printf '%s\n' "$output" >&2
        fail "conduct operating model markers or strict peer parity are invalid"
    fi
}

test_conduct_status_public_entrypoint() {
    if node "$CONDUCT_STATUS_TEST"; then
        pass "conduct exposes status through its shipped public entrypoint"
    else
        fail "conduct does not dispatch its public status command"
    fi
}

test_conduct_status_docs_use_shipped_entrypoint() {
    local valid=true
    grep -Fq 'node <skill-root>/scripts/conduct.cjs status --root <repo>' "$CONDUCT_SKILL_SOURCE" || valid=false
    grep -Fq 'node <skill-root>/scripts/conduct.cjs status set' "$CONDUCT_SKILL_SOURCE" || valid=false
    grep -Fq 'Each controller updates only its own rows.' "$CONDUCT_SKILL_SOURCE" || valid=false
    grep -Fq 'does not install a usage collector' "$CONDUCT_SKILL_SOURCE" || valid=false
    grep -Fq 'claude-sdlc-harness #749' "$REPO_DIR/TESTING.md" || valid=false
    if [ "$valid" = "true" ]; then
        pass "conduct documents the shipped status entrypoint, row ownership, and vendor limitation"
    else
        fail "conduct status documentation is missing or overclaims the installed runtime"
    fi
}

test_conduct_helper_writes_exact_envelopes_and_blocks_response_loops() {
    local ws request_path response_path ledger_path
    local valid=true
    ws=$(mktemp -d)
    request_path="$ws/.brain/runs/run-001/outbox/req-001.json"
    response_path="$ws/.brain/runs/run-001/inbox/res-001.json"
    ledger_path="$ws/.brain/runs/run-001/turns.jsonl"

    [ -f "$CONDUCT_SCRIPT" ] || valid=false

    if [ "$valid" = "true" ]; then
        node "$CONDUCT_SCRIPT" emit \
            --root "$ws" --run run-001 --box outbox --id req-001 \
            --from codex:primary --to claude:reviewer --type review \
            --prompt "Review the protocol" --cwd "$ws" >/dev/null || valid=false

        node "$CONDUCT_SCRIPT" emit \
            --root "$ws" --run run-001 --box inbox --id res-001 \
            --from claude:reviewer --to codex:primary --type result \
            --prompt "Protocol is sound" --cwd "$ws" --ref req-001 >/dev/null || valid=false
    fi

    [ -f "$request_path" ] || valid=false
    [ -f "$response_path" ] || valid=false
    [ -f "$ledger_path" ] || valid=false

    if [ "$valid" = "true" ]; then
        REQUEST_PATH="$request_path" RESPONSE_PATH="$response_path" LEDGER_PATH="$ledger_path" node <<'NODE' || valid=false
const fs = require("fs");
const expectedFields = ["v", "id", "from", "to", "type", "prompt", "cwd", "ref"];
const request = JSON.parse(fs.readFileSync(process.env.REQUEST_PATH, "utf8"));
const response = JSON.parse(fs.readFileSync(process.env.RESPONSE_PATH, "utf8"));
const turns = fs.readFileSync(process.env.LEDGER_PATH, "utf8").trim().split("\n").map(JSON.parse);
if (JSON.stringify(Object.keys(request)) !== JSON.stringify(expectedFields)) process.exit(1);
if (JSON.stringify(Object.keys(response)) !== JSON.stringify(expectedFields)) process.exit(1);
if (request.v !== 1 || request.ref !== null) process.exit(1);
if (response.ref !== request.id || response.type !== "result") process.exit(1);
if (turns.length !== 2 || turns.some((turn) => !turn.ts || !turn.envelope || !turn.status)) process.exit(1);
NODE
    fi

    if [ "$valid" = "true" ] && node "$CONDUCT_SCRIPT" emit \
        --root "$ws" --run run-001 --box outbox --id loop-001 \
        --from codex:primary --to claude:reviewer --type result \
        --prompt "Do not recurse" --cwd "$ws" --ref res-001 >/dev/null 2>&1; then
        valid=false
    fi

    if [ "$valid" = "true" ] && node "$CONDUCT_SCRIPT" emit \
        --root "$ws" --run ../escape --box outbox --id escape-001 \
        --from codex:primary --to claude:reviewer --type question \
        --prompt "Do not escape" --cwd "$ws" >/dev/null 2>&1; then
        valid=false
    fi

    rm -rf "$ws"

    if [ "$valid" = "true" ]; then
        pass "conduct helper writes exact envelopes and blocks recursive/path-escape dispatch"
    else
        fail "conduct helper did not enforce the envelope, ledger, or loop-safety contract"
    fi
}

test_conduct_rejects_symlink_state() {
    local ws valid=true
    ws=$(mktemp -d)
    mkdir -p "$ws/.brain/runs/symlink-test"
    touch "$ws/external.jsonl"
    ln -s "$ws/external.jsonl" "$ws/.brain/runs/symlink-test/turns.jsonl"
    if node "$CONDUCT_SCRIPT" emit --root "$ws" --run symlink-test \
        --from codex:a --to claude:b --type question --prompt test >/dev/null 2>&1; then
        valid=false
    fi
    [ ! -s "$ws/external.jsonl" ] || valid=false
    rm -rf "$ws"
    if [ "$valid" = true ]; then
        pass "conduct rejects symlink state without writing outside its ledger"
    else
        fail "conduct follows symlink state"
    fi
}

test_conduct_cli_validation() {
    local ws valid=true
    ws=$(mktemp -d)
    if node "$CONDUCT_SCRIPT" emit --root "$ws" --run bad-box --box inbox --from a --to b --type task --prompt test >/dev/null 2>&1; then valid=false; fi
    if node "$CONDUCT_SCRIPT" emit --root "$ws" --run typo --from a --to b --type task --prompt test --roo "$ws" >/dev/null 2>&1; then valid=false; fi
    if node "$CONDUCT_SCRIPT" emit --root "$ws" --run false-answer --from a --to b --type task --prompt test --status answered >/dev/null 2>&1; then valid=false; fi
    if node "$CONDUCT_SCRIPT" emit --root "$ws" --run bad-status --from a --to b --type task --prompt test --status invented >/dev/null 2>&1; then valid=false; fi
    node "$CONDUCT_SCRIPT" emit --root "$ws" --run diff --id diff-request --from a --to b --type review --prompt '--- a/file' >/dev/null 2>&1 || valid=false
    if node "$CONDUCT_SCRIPT" emit --root "$ws" --run diff --box outbox --from b --to a --type result --ref diff-request --prompt test >/dev/null 2>&1; then valid=false; fi
    rm -rf "$ws"
    if [ "$valid" = true ]; then pass "conduct validates boxes/options and accepts raw diff prompts"; else fail "conduct CLI validation is incomplete"; fi
}

test_conduct_rolls_back_failed_ledger_append() {
    if CONDUCT_SCRIPT="$CONDUCT_SCRIPT" node <<'NODE'
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const root = fs.mkdtempSync(path.join(os.tmpdir(), "conduct-append-"));
const append = fs.appendFileSync;
fs.appendFileSync = () => { throw new Error("injected append failure"); };
process.argv = [process.execPath, process.env.CONDUCT_SCRIPT, "emit", "--root", root, "--run", "failure", "--id", "req", "--from", "a", "--to", "b", "--type", "question", "--prompt", "test"];
require(process.env.CONDUCT_SCRIPT);
fs.appendFileSync = append;
const stranded = fs.existsSync(path.join(root, ".brain/runs/failure/outbox/req.json"));
fs.rmSync(root, { recursive: true });
process.exitCode = stranded ? 1 : 0;
NODE
    then pass "conduct rolls back envelope when ledger append fails"; else fail "conduct strands envelope on append failure"; fi
}

test_conduct_reconciles_matching_orphan_after_verified_lock_removal() {
    local ws valid=true
    ws=$(mktemp -d)

    ROOT="$ws" node <<'NODE'
const fs = require("node:fs");
const path = require("node:path");
const root = process.env.ROOT;
const run = path.join(root, ".brain/runs/orphan");
const envelope = { v: 1, id: "req-orphan", from: "codex:a", to: "claude:b", type: "task", prompt: "recover me", cwd: path.resolve(root), ref: null };
fs.mkdirSync(path.join(run, "outbox"), { recursive: true });
fs.writeFileSync(path.join(run, "outbox/req-orphan.json"), `${JSON.stringify(envelope, null, 2)}\n`, { flag: "wx" });
fs.mkdirSync(path.join(run, ".write-lock"));
fs.writeFileSync(path.join(run, ".write-lock/owner.json"), JSON.stringify({ pid: 999999, started: "verified-stale-fixture" }));
NODE

    if node "$CONDUCT_SCRIPT" emit --root "$ws" --run orphan --id req-orphan \
        --from codex:a --to claude:b --type task --prompt 'recover me' --cwd "$ws" >/dev/null 2>&1; then
        valid=false
    fi
    [ -d "$ws/.brain/runs/orphan/.write-lock" ] || valid=false
    [ ! -e "$ws/.brain/runs/orphan/turns.jsonl" ] || valid=false

    rm "$ws/.brain/runs/orphan/.write-lock/owner.json"
    rmdir "$ws/.brain/runs/orphan/.write-lock"
    node "$CONDUCT_SCRIPT" emit --root "$ws" --run orphan --id req-orphan \
        --from codex:a --to claude:b --type task --prompt 'recover me' --cwd "$ws" >/dev/null 2>&1 || valid=false

    ROOT="$ws" node <<'NODE' || valid=false
const fs = require("node:fs");
const path = require("node:path");
const root = process.env.ROOT;
const message = JSON.parse(fs.readFileSync(path.join(root, ".brain/runs/orphan/outbox/req-orphan.json"), "utf8"));
const turns = fs.readFileSync(path.join(root, ".brain/runs/orphan/turns.jsonl"), "utf8").trim().split("\n").map(JSON.parse);
const fields = ["v", "id", "from", "to", "type", "prompt", "cwd", "ref"];
if (JSON.stringify(Object.keys(message)) !== JSON.stringify(fields)) process.exit(1);
if (turns.length !== 1 || JSON.stringify(turns[0].envelope) !== JSON.stringify(message)) process.exit(1);
NODE

    ROOT="$ws" node <<'NODE'
const fs = require("node:fs");
const path = require("node:path");
const root = process.env.ROOT;
const run = path.join(root, ".brain/runs/mismatch");
const envelope = { v: 1, id: "req-mismatch", from: "codex:a", to: "claude:b", type: "task", prompt: "different orphan", cwd: path.resolve(root), ref: null };
fs.mkdirSync(path.join(run, "outbox"), { recursive: true });
fs.writeFileSync(path.join(run, "outbox/req-mismatch.json"), `${JSON.stringify(envelope, null, 2)}\n`, { flag: "wx" });
NODE
    if node "$CONDUCT_SCRIPT" emit --root "$ws" --run mismatch --id req-mismatch \
        --from codex:a --to claude:b --type task --prompt expected --cwd "$ws" >/dev/null 2>&1; then
        valid=false
    fi
    ROOT="$ws" node <<'NODE' || valid=false
const fs = require("node:fs");
const path = require("node:path");
const root = process.env.ROOT;
const run = path.join(root, ".brain/runs/mismatch");
const message = JSON.parse(fs.readFileSync(path.join(run, "outbox/req-mismatch.json"), "utf8"));
if (message.prompt !== "different orphan" || fs.existsSync(path.join(run, "turns.jsonl"))) process.exit(1);
NODE

    node "$CONDUCT_SCRIPT" emit --root "$ws" --run duplicate --id req-duplicate \
        --from codex:a --to claude:b --type task --prompt once --cwd "$ws" >/dev/null 2>&1 || valid=false
    if node "$CONDUCT_SCRIPT" emit --root "$ws" --run duplicate --id req-duplicate \
        --from codex:a --to claude:b --type task --prompt once --cwd "$ws" >/dev/null 2>&1; then
        valid=false
    fi
    LEDGER="$ws/.brain/runs/duplicate/turns.jsonl" node <<'NODE' || valid=false
const fs = require("node:fs");
const turns = fs.readFileSync(process.env.LEDGER, "utf8").trim().split("\n").map(JSON.parse);
if (turns.length !== 1 || turns[0].envelope.id !== "req-duplicate") process.exit(1);
NODE

    rm -rf "$ws"
    if [ "$valid" = true ]; then
        pass "conduct reconciles only a matching orphan after verified stale-lock removal"
    else
        fail "conduct cannot safely reconcile a matching orphan envelope"
    fi
}

test_conduct_status_events_and_lock_owner() {
    local ws valid=true
    ws=$(mktemp -d)
    node "$CONDUCT_SCRIPT" emit --root "$ws" --run state --id req --from a --to b --type task --prompt test >/dev/null || valid=false
    node "$CONDUCT_SCRIPT" mark --root "$ws" --run state --id req --status sent --transport codex_queue >/dev/null 2>&1 || valid=false
    node "$CONDUCT_SCRIPT" mark --root "$ws" --run state --id missing --status sent >/dev/null 2>&1 && valid=false
    node "$CONDUCT_SCRIPT" mark --root "$ws" --run state --id req --status invented >/dev/null 2>&1 && valid=false
    if [ "$valid" = true ]; then
        LEDGER="$ws/.brain/runs/state/turns.jsonl" node <<'NODE' || valid=false
const fs = require("node:fs");
const turns = fs.readFileSync(process.env.LEDGER, "utf8").trim().split("\n").map(JSON.parse);
if (turns.length !== 2 || turns[1].status !== "sent" || turns[1].transport !== "codex_queue") process.exit(1);
if (JSON.stringify(turns[0].envelope) !== JSON.stringify(turns[1].envelope)) process.exit(1);
NODE
    fi
    node "$CONDUCT_SCRIPT" mark --root "$ws" --run state --id req --status answered >/dev/null 2>&1 && valid=false
    node "$CONDUCT_SCRIPT" emit --root "$ws" --run state --box inbox --id response --from b --to a --type result --ref req --prompt done >/dev/null || valid=false
    node "$CONDUCT_SCRIPT" mark --root "$ws" --run state --id req --status answered >/dev/null || valid=false
    mkdir "$ws/.brain/runs/state/.write-lock"
    local error
    error=$(node "$CONDUCT_SCRIPT" mark --root "$ws" --run state --id req --status delivered 2>&1) && valid=false
    [[ "$error" == *"$ws/.brain/runs/state/.write-lock"* ]] || valid=false
    rm -rf "$ws"
    if [ "$valid" = true ]; then pass "conduct records delivery events and identifies locked run"; else fail "conduct status or lock diagnostics failed"; fi
}

test_conduct_reciprocal_recovery_contract() {
    local valid=true
    # These are independent authorization/concurrency invariants of peer recovery.
    grep -Eqi 'any (registered and reachable|reachable) peer.*recover' "$CONDUCT_SKILL_SOURCE" || valid=false
    grep -Eqi 'one recovery owner|single recovery owner' "$CONDUCT_SKILL_SOURCE" || valid=false
    grep -Eqi 'preserve.*(draft|unsubmitted)' "$CONDUCT_SKILL_SOURCE" || valid=false
    grep -Eqi 'confirm.*(old|previous).*(exit|terminated)' "$CONDUCT_SKILL_SOURCE" || valid=false
    grep -Eqi 'direct user instruction.*(restart|permission)' "$CONDUCT_SKILL_SOURCE" || valid=false
    grep -Eqi 'peer.*claim.*(not|never).*authorization' "$CONDUCT_SKILL_SOURCE" || valid=false
    grep -Eqi '(reciprocal|mutual).*recovery' "$CONDUCT_PROTOCOL" || valid=false
    grep -Eqi 'unresolved user choices' "$CONDUCT_SKILL_SOURCE" || valid=false
    grep -Eqi 'draft.*unsubmitted.*unless.*user' "$CONDUCT_SKILL_SOURCE" || valid=false
    grep -Eqi 'earliest unanswered recovery request' "$CONDUCT_SKILL_SOURCE" || valid=false
    grep -Eqi "recovering agent.s own user turn" "$CONDUCT_SKILL_SOURCE" || valid=false
    grep -Eqi 'no correlated result' "$CONDUCT_SKILL_SOURCE" || valid=false
    grep -Eqi 'supersedes.*current owning request' "$CONDUCT_SKILL_SOURCE" || valid=false
    grep -Eqi 'first emit.*ledger order' "$CONDUCT_SKILL_SOURCE" || valid=false
    grep -Eqi 'ambiguous provenance.*peer content' "$CONDUCT_SKILL_SOURCE" || valid=false
    grep -Eqi 'contenders mark.*failed' "$CONDUCT_SKILL_SOURCE" || valid=false
    grep -Eqi 'only.*adapter.*keep.*unsubmitted' "$CONDUCT_SKILL_SOURCE" || valid=false
    local contract_file
    for contract_file in "$CONDUCT_SKILL_SOURCE" "$CONDUCT_PROTOCOL"; do
        grep -Eqi 'emit.*then reread the ledger' "$contract_file" || valid=false
        grep -Eqi '(cite|citing).*verified evidence.*(owner stopped|handed off)' "$contract_file" || valid=false
        grep -Eqi 'no correlated result' "$contract_file" || valid=false
        grep -Eqi 'supersedes.*current owning request' "$contract_file" || valid=false
        grep -Eqi 'ambiguous provenance.*peer content' "$contract_file" || valid=false
    done
    if [ "$valid" = true ]; then
        pass "conduct recovery preserves user authority, drafts, and one live writer"
    else
        fail "conduct lacks the reciprocal recovery contract"
    fi
}

test_conduct_codex_delegates_claude_desktop_startup_through_registered_conductor() {
    local ws request_prompt result_prompt valid=true
    ws=$(mktemp -d)
    request_prompt='User-authorized bounded host delegation: start one Claude Desktop Code session for this folder. Use --no-trust; if Trust is required, do not approve it and return NEEDS_TRUST with actual receiver evidence.'
    result_prompt='NEEDS_TRUST: receiver invoked claude-desktop.sh --no-trust; no Trust control was pressed.'

    node "$CONDUCT_SCRIPT" emit \
        --root "$ws" --run desktop-startup --box outbox --id start-request \
        --from codex:controller --to claude:registered-conductor --type task \
        --prompt "$request_prompt" --cwd "$ws" >/dev/null || valid=false
    node "$CONDUCT_SCRIPT" mark \
        --root "$ws" --run desktop-startup --id start-request \
        --status sent --transport claude_native >/dev/null || valid=false
    node "$CONDUCT_SCRIPT" emit \
        --root "$ws" --run desktop-startup --box inbox --id start-result \
        --from claude:registered-conductor --to codex:controller --type result \
        --prompt "$result_prompt" --cwd "$ws" --ref start-request >/dev/null || valid=false
    node "$CONDUCT_SCRIPT" mark \
        --root "$ws" --run desktop-startup --id start-request \
        --status answered --transport claude_native >/dev/null || valid=false

    if [ "$valid" = true ]; then
        ROOT="$ws" REQUEST_PROMPT="$request_prompt" RESULT_PROMPT="$result_prompt" node <<'NODE' || valid=false
const fs = require("node:fs");
const path = require("node:path");
const root = process.env.ROOT;
const run = path.join(root, ".brain", "runs", "desktop-startup");
const request = JSON.parse(fs.readFileSync(path.join(run, "outbox", "start-request.json"), "utf8"));
const result = JSON.parse(fs.readFileSync(path.join(run, "inbox", "start-result.json"), "utf8"));
const turns = fs.readFileSync(path.join(run, "turns.jsonl"), "utf8").trim().split("\n").map(JSON.parse);
if (request.from !== "codex:controller" || request.to !== "claude:registered-conductor") process.exit(1);
if (request.type !== "task" || request.prompt !== process.env.REQUEST_PROMPT || request.ref !== null) process.exit(1);
if (result.from !== request.to || result.to !== request.from || result.type !== "result") process.exit(1);
if (result.ref !== request.id || result.prompt !== process.env.RESULT_PROMPT) process.exit(1);
if (turns.length !== 4) process.exit(1);
if (new Set(turns.map((turn) => turn.envelope.id)).size !== 2) process.exit(1);
if (turns[turns.length - 1].status !== "answered") process.exit(1);
NODE
    fi

    grep -Eqi 'Codex conductor.*registered Claude conductor|registered Claude conductor.*Codex conductor' \
        "$CONDUCT_SKILL_SOURCE" "$CONDUCT_CLAUDE_DESKTOP_REFERENCE" || valid=false
    grep -Eqi 'user-authorized.*delegat|delegat.*user-authorized' \
        "$CONDUCT_SKILL_SOURCE" "$CONDUCT_CLAUDE_DESKTOP_REFERENCE" || valid=false
    grep -Fq -- '--no-trust' "$CONDUCT_CLAUDE_DESKTOP_REFERENCE" || valid=false
    grep -Fq 'NEEDS_TRUST' "$CONDUCT_CLAUDE_DESKTOP_REFERENCE" || valid=false
    grep -Eqi 'runtime.*denial|denied action' \
        "$CONDUCT_SKILL_SOURCE" "$CONDUCT_CLAUDE_DESKTOP_REFERENCE" || valid=false
    grep -Eqi 'receiver.*owns?.*permission|permission.*owned by.*receiver' \
        "$CONDUCT_SKILL_SOURCE" "$CONDUCT_CLAUDE_DESKTOP_REFERENCE" || valid=false
    grep -Eqi 'not.*direct.*(GUI|Desktop).*access|does not grant.*direct.*access' \
        "$CONDUCT_SKILL_SOURCE" "$CONDUCT_CLAUDE_DESKTOP_REFERENCE" || valid=false
    grep -Eqi 'canonical inbox|\.brain/runs/.*/inbox' \
        "$CONDUCT_SKILL_SOURCE" "$CONDUCT_CLAUDE_DESKTOP_REFERENCE" || valid=false
    grep -Eqi 'relay.*return message.*expire|return message.*expire' \
        "$CONDUCT_CLAUDE_DESKTOP_REFERENCE" || valid=false
    grep -Eqi 'actual receiver evidence' \
        "$CONDUCT_SKILL_SOURCE" "$CONDUCT_CLAUDE_DESKTOP_REFERENCE" || valid=false

    rm -rf "$ws"
    if [ "$valid" = true ]; then
        pass "conduct records one bounded Codex-to-Claude Desktop startup delegation and exact result"
    else
        fail "conduct lacks the bounded registered-Claude Desktop startup route or its denial guardrails"
    fi
}

test_conduct_new_thread_docs_use_platform_python_launchers() {
    local valid=true
    grep -Eqi 'platform(-appropriate)? Python( 3)? launcher|Python 3.*platform(-appropriate)? launcher' \
        "$CONDUCT_SKILL_SOURCE" || valid=false
    grep -Fq '[references/codex-native.md](references/codex-native.md)' \
        "$CONDUCT_SKILL_SOURCE" || valid=false
    grep -Fq '`python3 scripts/codex-thread.py CWD PROMPT_FILE`' \
        "$CONDUCT_SKILL_SOURCE" && valid=false
    grep -Eqi 'On Unix.*`python3`|`python3`.*on Unix' \
        "$CONDUCT_CODEX_NATIVE_REFERENCE" || valid=false
    grep -Eqi 'On Windows.*`py -3`|`py -3`.*on Windows' \
        "$CONDUCT_CODEX_NATIVE_REFERENCE" || valid=false
    grep -Eqi 'verified Python 3.*`python(\.exe)?`|`python(\.exe)?`.*verified Python 3' \
        "$CONDUCT_CODEX_NATIVE_REFERENCE" || valid=false
    grep -Eqi 'argument array|separate argument' \
        "$CONDUCT_CODEX_NATIVE_REFERENCE" || valid=false
    grep -Eqi 'quote each path|quoted path' \
        "$CONDUCT_CODEX_NATIVE_REFERENCE" || valid=false
    grep -Eqi 'no live Windows.*(proof|coverage)|not.*live Windows.*(proof|coverage)' \
        "$CONDUCT_CODEX_NATIVE_REFERENCE" || valid=false

    if [ "$valid" = true ]; then
        pass "conduct documents platform-appropriate Python launchers for new Codex threads"
    else
        fail "conduct new-thread docs require a python3 alias or overclaim Windows coverage"
    fi
}

test_conduct_new_target_workflow_records_before_dispatch() {
    local valid=true
    grep -Fq -- '--ledger-root' "$CONDUCT_SKILL_SOURCE" || valid=false
    grep -Fq -- '--request-id' "$CONDUCT_CODEX_NATIVE_REFERENCE" || valid=false
    grep -Fq -- '--create-only' "$CONDUCT_SKILL_SOURCE" "$CONDUCT_CODEX_NATIVE_REFERENCE" && valid=false
    grep -Eqi 'actual (thread )?UUID.*(emit|write).*canonical|(emit|write).*canonical.*actual (thread )?UUID' \
        "$CONDUCT_SKILL_SOURCE" "$CONDUCT_CODEX_NATIVE_REFERENCE" || valid=false
    grep -Eqi 'canonical.*(request|outbox).*(before|prior to).*turn/start|turn/start.*after.*canonical' \
        "$CONDUCT_SKILL_SOURCE" "$CONDUCT_CODEX_NATIVE_REFERENCE" || valid=false
    grep -Eqi 'same.*(stdio|app-server).*connection|same.*connection' \
        "$CONDUCT_CODEX_NATIVE_REFERENCE" || valid=false
    grep -Eqi 'startup[- ]probe.*(convenience|not.*Conduct)|convenience.*startup[- ]probe' \
        "$CONDUCT_CODEX_NATIVE_REFERENCE" || valid=false

    if [ "$valid" = true ]; then
        pass "conduct emits the actual target before the same-connection first turn"
    else
        fail "conduct new-target docs permit a first turn before canonical ledger emit"
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
test_conduct_skill_documents_shared_protocol_and_reachability_boundary
test_conduct_operating_model_block_is_unique_and_matches_peer
test_conduct_status_public_entrypoint
test_conduct_status_docs_use_shipped_entrypoint
test_conduct_helper_writes_exact_envelopes_and_blocks_response_loops
test_conduct_rejects_symlink_state
test_conduct_cli_validation
test_conduct_rolls_back_failed_ledger_append
test_conduct_reconciles_matching_orphan_after_verified_lock_removal
test_conduct_status_events_and_lock_owner
test_conduct_reciprocal_recovery_contract
test_conduct_codex_delegates_claude_desktop_startup_through_registered_conductor
test_conduct_new_thread_docs_use_platform_python_launchers
test_conduct_new_target_workflow_records_before_dispatch
test_sdlc_workflow_is_bounded_and_repairable
test_sdlc_scopes_red_to_writable_behavior
test_sdlc_review_reuses_one_broad_proof
test_sdlc_documents_bounded_dual_review
test_sdlc_defaults_to_direct_delivery_without_pr
test_sdlc_documents_incremental_completion_cadence
test_sdlc_exposes_linked_worktree_git_target_to_hooks

echo ""
echo "=== Results: $PASSED passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
    exit 1
fi
