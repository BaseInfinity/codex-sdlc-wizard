#!/bin/bash
# Packaging tests — keep README aligned with the actual distribution model

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$SCRIPT_DIR/.."
README="$REPO_DIR/README.md"
PACKAGE_JSON="$REPO_DIR/package.json"
JSON_HELPERS="$REPO_DIR/lib/json-node.sh"
source "$JSON_HELPERS"
require_node
CURRENT_VERSION="$(json_get_file "$PACKAGE_JSON" 'data.version')"
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
    local output
    adapter_clone=$(mktemp -d "$MKTEMP_DIR/sdlc-adapter-clone.XXXXXX")
    target_repo=$(mktemp -d "$MKTEMP_DIR/sdlc-target-repo.XXXXXX")

    cp -R "$REPO_DIR/." "$adapter_clone/"

    output=$(
        cd "$target_repo"
        bash "$adapter_clone/install.sh" 2>&1
    )

    local has_agents=true
    local has_config=true
    local has_hooks_json=true
    local has_bash_guard=true
    local has_node_guard=true
    local avoids_unreleased_skill_labels=true

    [ -f "$target_repo/AGENTS.md" ] || has_agents=false
    [ -f "$target_repo/.codex/config.toml" ] || has_config=false
    [ -f "$target_repo/.codex/hooks.json" ] || has_hooks_json=false
    [ -x "$target_repo/.codex/hooks/bash-guard.sh" ] || has_bash_guard=false
    [ -f "$target_repo/.codex/hooks/git-guard.cjs" ] || has_node_guard=false
    grep -q 'node \.codex/hooks/git-guard\.cjs' "$target_repo/.codex/hooks.json" 2>/dev/null || has_node_guard=false
    echo "$output" | grep -Eq '(^|[^A-Za-z])(gdlc|rdlc)([^A-Za-z]|$)' && avoids_unreleased_skill_labels=false

    rm -rf "$adapter_clone" "$target_repo"

    if [ "$has_agents" = "true" ] &&
       [ "$has_config" = "true" ] &&
       [ "$has_hooks_json" = "true" ] &&
       [ "$has_bash_guard" = "true" ] &&
       [ "$has_node_guard" = "true" ] &&
       [ "$avoids_unreleased_skill_labels" = "true" ]; then
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
    elif ! json_has_truthy_file "$target_repo/.codex-sdlc/model-profile.json" 'data.selected_profile === "mixed"'; then
        has_profile=false
    elif ! json_has_truthy_file "$target_repo/.codex-sdlc/model-profile.json" 'data.profiles && data.profiles.maximum && data.profiles.maximum.main_model === "gpt-5.5"'; then
        has_profile=false
    elif ! json_has_truthy_file "$target_repo/.codex-sdlc/model-profile.json" 'data.profiles && data.profiles.maximum && data.profiles.maximum.review_model === "gpt-5.5"'; then
        has_profile=false
    elif ! json_has_truthy_file "$target_repo/.codex-sdlc/model-profile.json" 'data.profiles && data.profiles.mixed && data.profiles.mixed.review_model === "gpt-5.5"'; then
        has_profile=false
    fi

    if ! grep -q '^model = "gpt-5.4-mini"' "$target_repo/.codex/config.toml" 2>/dev/null; then
        has_profile=false
    elif ! grep -q '^model_reasoning_effort = "xhigh"' "$target_repo/.codex/config.toml" 2>/dev/null; then
        has_profile=false
    elif ! grep -q '^review_model = "gpt-5.5"' "$target_repo/.codex/config.toml" 2>/dev/null; then
        has_profile=false
    elif ! grep -q '^codex_hooks = true' "$target_repo/.codex/config.toml" 2>/dev/null; then
        has_profile=false
    fi

    rm -rf "$adapter_clone" "$target_repo"

    if [ "$has_profile" = "true" ]; then
        pass "Installer writes the default mixed model profile with xhigh reasoning into metadata and repo-local Codex config"
    else
        fail "Installer did not write the expected xhigh default mixed model profile into metadata and .codex/config.toml"
    fi
}

test_installer_uses_canonical_sdlc_skill_name() {
    local adapter_clone
    local target_repo
    adapter_clone=$(mktemp -d "$MKTEMP_DIR/sdlc-adapter-clone.XXXXXX")
    target_repo=$(mktemp -d "$MKTEMP_DIR/sdlc-target-repo.XXXXXX")

    cp -R "$REPO_DIR/." "$adapter_clone/"
    mkdir -p "$target_repo/.codex-home/skills/codex-sdlc"
    echo "LEGACY" > "$target_repo/.codex-home/skills/codex-sdlc/marker.txt"

    (
        cd "$target_repo"
        CODEX_HOME="$target_repo/.codex-home" bash "$adapter_clone/install.sh" >/dev/null 2>&1
    )

    local valid=true
    [ ! -d "$target_repo/.codex-home/skills/sdlc" ] || valid=false
    [ -f "$target_repo/.codex-home/skills/setup-wizard/SKILL.md" ] || valid=false
    [ -f "$target_repo/.codex-home/skills/update-wizard/SKILL.md" ] || valid=false
    [ -f "$target_repo/.codex-home/skills/feedback/SKILL.md" ] || valid=false
    [ -f "$target_repo/.agents/skills/sdlc/SKILL.md" ] || valid=false
    [ ! -d "$target_repo/.codex-home/skills/codex-sdlc" ] || valid=false
    find "$target_repo/.codex-home/backups/skills" -maxdepth 1 -name 'codex-sdlc.bak.*' 2>/dev/null | grep -q . || valid=false

    rm -rf "$adapter_clone" "$target_repo"

    if [ "$valid" = "true" ]; then
        pass "Installer uses repo-scoped sdlc only and prunes legacy codex-sdlc"
    else
        fail "Installer left duplicate global/repo SDLC skill names installed"
    fi
}

test_installer_recommends_full_auto_and_restart_resume() {
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

    if echo "$output" | grep -q "codex --full-auto" &&
       echo "$output" | grep -Eqi 'exit and reopen Codex|restart Codex' &&
       echo "$output" | grep -q "codex resume --full-auto -m gpt-5.5" &&
       echo "$output" | grep -Fq 'model_reasoning_effort="xhigh"'; then
        pass "Installer output recommends codex --full-auto plus restart/resume after setup"
    else
        fail "Installer output does not recommend codex --full-auto plus restart/resume clearly enough"
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

test_installer_offers_issue_ready_feedback_on_wizard_failure() {
    local adapter_clone
    local target_repo
    local output
    adapter_clone=$(mktemp -d "$MKTEMP_DIR/sdlc-adapter-clone.XXXXXX")
    target_repo=$(mktemp -d "$MKTEMP_DIR/sdlc-target-repo.XXXXXX")

    cp -R "$REPO_DIR/." "$adapter_clone/"
    rm -f "$adapter_clone/.codex/hooks.json"

    output=$(
        cd "$target_repo" &&
        bash "$adapter_clone/install.sh" 2>&1
    ) || true

    rm -rf "$adapter_clone" "$target_repo"

    if echo "$output" | grep -qi 'Likely wizard-level failure' &&
       echo "$output" | grep -qi 'codex-sdlc-wizard' &&
       echo "$output" | grep -qi 'No issue will be posted automatically' &&
       echo "$output" | grep -qi 'wizard version:' &&
       echo "$output" | grep -qi 'command:' &&
       echo "$output" | grep -qi 'failure point:' &&
       echo "$output" | grep -qi 'repo shape:'; then
        pass "Installer offers issue-ready feedback when bundled wizard runtime is broken"
    else
        fail "Installer does not offer issue-ready feedback for obvious wizard-level failures"
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

test_readme_stays_consumer_focused() {
    local avoids_auth_heavy_section=true
    local avoids_capability_detector_section=true
    local avoids_internal_lane_copy=true

    grep -q '^## Auth-Heavy Workflow Boundaries$' "$README" && avoids_auth_heavy_section=false
    grep -q '^## Capability Detectors for Auth / License-Sensitive Repos$' "$README" && avoids_capability_detector_section=false
    grep -Eqi '(^|[^A-Za-z])(OK|NotConnected|PermissionError|UnsupportedAccount)([^A-Za-z]|$)|tenant shape|license-sensitive repos|one-command classification|setup data' "$README" && avoids_internal_lane_copy=false

    if [ "$avoids_auth_heavy_section" = "true" ] &&
       [ "$avoids_capability_detector_section" = "true" ] &&
       [ "$avoids_internal_lane_copy" = "true" ]; then
        pass "README stays consumer-focused and avoids internal operator-only prose"
    else
        fail "README still contains internal operator prose that should not be in the public README"
    fi
}

test_readme_documents_repo_scope_skills() {
    local has_heading=true
    local has_agents_path=true
    local has_sdlc=true
    local has_wip_language=true
    local avoids_unreleased_skill_labels=true
    local has_fresh_session=true

    grep -q '^## Repo-Scoped Skills$' "$README" || has_heading=false
    grep -q '\.agents/skills' "$README" || has_agents_path=false
    grep -q '\$sdlc' "$README" || has_sdlc=false
    grep -Eqi 'work in progress|still in progress|not all available yet' "$README" || has_wip_language=false
    grep -Eq '(^|[^A-Za-z])(gdlc|rdlc)([^A-Za-z]|$)' "$README" && avoids_unreleased_skill_labels=false
    grep -Eqi 'fresh Codex session|start a fresh codex session|restart Codex' "$README" || has_fresh_session=false

    if [ "$has_heading" = "true" ] &&
       [ "$has_agents_path" = "true" ] &&
       [ "$has_sdlc" = "true" ] &&
       [ "$has_wip_language" = "true" ] &&
       [ "$avoids_unreleased_skill_labels" = "true" ] &&
       [ "$has_fresh_session" = "true" ]; then
        pass "README documents current repo-scope skills without unreleased labels"
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
    local feedback_section
    local has_direct_issue=true
    local has_proven_finding=true
    local has_product_repo=true
    local has_blocked_boundary=true
    local avoids_pilot_rollout_note=true

    feedback_section=$(awk '
        /^## Feedback Flow and Repo Focus$/ { in_section=1; next }
        /^## / && in_section { exit }
        in_section { print }
    ' "$README")

    echo "$feedback_section" | grep -qi 'direct GitHub issue' || has_direct_issue=false
    echo "$feedback_section" | grep -qi 'proven reusable' || has_proven_finding=false
    echo "$feedback_section" | grep -qi 'product repo' || has_product_repo=false
    echo "$feedback_section" | grep -qi 'actually blocked' || has_blocked_boundary=false
    echo "$feedback_section" | grep -qi 'pilot-rollout.csv' && avoids_pilot_rollout_note=false

    if [ "$has_direct_issue" = "true" ] &&
       [ "$has_proven_finding" = "true" ] &&
       [ "$has_product_repo" = "true" ] &&
       [ "$has_blocked_boundary" = "true" ] &&
       [ "$avoids_pilot_rollout_note" = "true" ]; then
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
    local has_gpt55=true
    local has_confidence_rule=true
    local has_repo_maximum_rule=true
    local has_bootstrap_maximum_rule=true
    local has_routine_mixed_rule=true

    grep -q '^## Model Profiles$' "$README" || has_heading=false
    grep -q '`mixed`' "$README" || has_mixed=false
    grep -q '`maximum`' "$README" || has_maximum=false
    grep -q 'gpt-5.5' "$README" || has_gpt55=false
    grep -Eqi 'speed|latency|token' "$README" || has_tradeoff=false
    grep -Eqi 'stability|ultimate' "$README" || has_tradeoff=false
    grep -Eqi '95%|xhigh review|research more first' "$README" || has_confidence_rule=false
    grep -Eqi 'this repo.*maximum|wizard repo.*maximum|codex-sdlc-wizard itself.*maximum' "$README" || has_repo_maximum_rule=false
    grep -Eqi 'setup/update.*maximum|bootstrap.*maximum' "$README" || has_bootstrap_maximum_rule=false
    grep -Eqi 'routine work.*mixed|day-to-day.*mixed|after bootstrap.*mixed' "$README" || has_routine_mixed_rule=false

    if [ "$has_heading" = "true" ] &&
       [ "$has_mixed" = "true" ] &&
       [ "$has_maximum" = "true" ] &&
       [ "$has_gpt55" = "true" ] &&
       [ "$has_tradeoff" = "true" ] &&
       [ "$has_confidence_rule" = "true" ] &&
       [ "$has_repo_maximum_rule" = "true" ] &&
       [ "$has_bootstrap_maximum_rule" = "true" ] &&
       [ "$has_routine_mixed_rule" = "true" ]; then
        pass "README documents the bootstrap maximum rule, routine mixed guidance, and this repo's maximum-only policy"
    else
        fail "README does not document the bootstrap maximum rule, routine mixed guidance, and this repo's maximum-only policy clearly enough"
    fi
}

test_readme_uses_real_release_examples() {
    local has_current_npx=true
    local has_latest_npx=true
    local has_current_git=true
    local has_no_placeholder_npx=true
    local has_no_placeholder_git=true

    grep -q "npx codex-sdlc-wizard@$CURRENT_VERSION" "$README" || has_current_npx=false
    grep -q 'npx codex-sdlc-wizard@latest' "$README" || has_latest_npx=false
    grep -q "git clone --branch v$CURRENT_VERSION" "$README" || has_current_git=false
    if grep -q 'npx codex-sdlc-wizard@X.Y.Z' "$README"; then
        has_no_placeholder_npx=false
    fi
    if grep -q 'git clone --branch vX.Y.Z' "$README"; then
        has_no_placeholder_git=false
    fi

    if [ "$has_current_npx" = "true" ] &&
       [ "$has_latest_npx" = "true" ] &&
       [ "$has_current_git" = "true" ] &&
       [ "$has_no_placeholder_npx" = "true" ] &&
       [ "$has_no_placeholder_git" = "true" ]; then
        pass "README uses real current release install examples and keeps @latest as the floating option"
    else
        fail "README still uses placeholder install examples or does not show the current release plus @latest"
    fi
}

test_readme_puts_quick_start_near_the_top() {
    local quick_start_line
    local what_this_repo_is_line
    local quick_start_section
    local quick_start_command
    local has_latest=true
    local has_adaptive_setup_note=true
    local avoids_git_clone=true
    local avoids_model_experiment=true
    local avoids_pilot_rollout=true

    quick_start_line=$(grep -n '^## Quick Start$' "$README" | cut -d: -f1 | head -n1)
    what_this_repo_is_line=$(grep -n '^## What This Repo Is$' "$README" | cut -d: -f1 | head -n1)
    quick_start_section=$(awk '
        /^## Quick Start$/ { in_section=1; next }
        /^## / && in_section { exit }
        in_section { print }
    ' "$README")
    quick_start_command=$(printf '%s\n' "$quick_start_section" | grep '^npx codex-sdlc-wizard@' | head -n1)

    echo "$quick_start_command" | grep -q '^npx codex-sdlc-wizard@latest$' || has_latest=false
    echo "$quick_start_section" | grep -Eqi 'adaptive interactive setup|adaptive setup' || has_adaptive_setup_note=false
    echo "$quick_start_section" | grep -q 'git clone' && avoids_git_clone=false
    echo "$quick_start_section" | grep -Eqi 'model-experiment|benchmark|gpt-5\.4-mini|20-slice' && avoids_model_experiment=false
    echo "$quick_start_section" | grep -Eqi 'pilot-rollout|default-use gate|default use gate|3-5 pilot repos' && avoids_pilot_rollout=false

    if [ -n "${quick_start_line:-}" ] &&
       [ -n "${what_this_repo_is_line:-}" ] &&
       [ "$quick_start_line" -lt "$what_this_repo_is_line" ] &&
       [ "$has_latest" = "true" ] &&
       [ "$has_adaptive_setup_note" = "true" ] &&
       [ "$avoids_git_clone" = "true" ] &&
       [ "$avoids_model_experiment" = "true" ] &&
       [ "$avoids_pilot_rollout" = "true" ]; then
        pass "README puts Quick Start near the top, starts with the adaptive default command, and keeps it free of extra noise"
    else
        fail "README does not keep Quick Start near the top and consumer-focused"
    fi
}

test_sponsor_metadata_exists() {
    local funding_file="$REPO_DIR/.github/FUNDING.yml"
    local has_github_funding=true
    local has_npm_funding=true

    [ -f "$funding_file" ] || has_github_funding=false
    grep -Eq '^github:[[:space:]]*BaseInfinity$' "$funding_file" 2>/dev/null || has_github_funding=false
    json_has_truthy_file "$PACKAGE_JSON" 'data.funding && data.funding.type === "github" && data.funding.url === "https://github.com/sponsors/BaseInfinity"' || has_npm_funding=false

    if [ "$has_github_funding" = "true" ] &&
       [ "$has_npm_funding" = "true" ]; then
        pass "Sponsor metadata exists for GitHub and npm"
    else
        fail "Sponsor metadata is missing or does not match the BaseInfinity convention"
    fi
}

test_consumer_bug_report_template_exists() {
    local template="$REPO_DIR/.github/ISSUE_TEMPLATE/consumer-bug-report.yml"
    local has_file=true
    local has_name=true
    local has_description=true
    local has_wizard_version=true
    local has_command=true
    local has_repo_shape=true
    local has_failed_step=true
    local has_visible_output=true
    local has_auth_boundary=true
    local has_expected_behavior=true
    local has_no_secrets_warning=true
    local avoids_benchmark_prompt=true

    [ -f "$template" ] || has_file=false
    grep -q '^name:' "$template" || has_name=false
    grep -qi 'consumer bug report' "$template" || has_description=false
    grep -qi 'wizard version' "$template" || has_wizard_version=false
    grep -qi 'command used' "$template" || has_command=false
    grep -Eqi 'repo shape|repo stack|repo type' "$template" || has_repo_shape=false
    grep -qi 'failed step' "$template" || has_failed_step=false
    grep -qi 'visible output' "$template" || has_visible_output=false
    grep -Eqi 'auth|mfa|browser sign-in|wam' "$template" || has_auth_boundary=false
    grep -qi 'expected behavior' "$template" || has_expected_behavior=false
    grep -Eqi 'do not include secrets|do not paste tokens|never paste tokens' "$template" || has_no_secrets_warning=false
    grep -Eqi 'benchmark|pilot-rollout\.csv|model-experiment\.csv' "$template" && avoids_benchmark_prompt=false

    if [ "$has_file" = "true" ] &&
       [ "$has_name" = "true" ] &&
       [ "$has_description" = "true" ] &&
       [ "$has_wizard_version" = "true" ] &&
       [ "$has_command" = "true" ] &&
       [ "$has_repo_shape" = "true" ] &&
       [ "$has_failed_step" = "true" ] &&
       [ "$has_visible_output" = "true" ] &&
       [ "$has_auth_boundary" = "true" ] &&
       [ "$has_expected_behavior" = "true" ] &&
       [ "$has_no_secrets_warning" = "true" ] &&
       [ "$avoids_benchmark_prompt" = "true" ]; then
        pass "Consumer bug report template exists and asks for the right issue details without benchmark noise"
    else
        fail "Consumer bug report template is missing, incomplete, or asks for benchmark-style logging"
    fi
}

test_installer_smoke_test_clean_project
test_installer_scaffolds_repo_scope_skills
test_installer_uses_canonical_sdlc_skill_name
test_installer_writes_default_model_profile
test_installer_recommends_full_auto_and_restart_resume
test_installer_mentions_model_profile_tradeoff
test_installer_calls_out_auth_heavy_boundary
test_installer_offers_issue_ready_feedback_on_wizard_failure
test_readme_explains_distribution_model
test_readme_has_install_choice_table
test_readme_explains_install_side_effects
test_readme_mentions_packaging_test_command
test_readme_recommends_full_auto
test_readme_stays_consumer_focused
test_readme_documents_repo_scope_skills
test_readme_documents_honest_codex_shape
test_readme_documents_feedback_flow_and_repo_focus
test_readme_documents_model_profiles
test_readme_uses_real_release_examples
test_readme_puts_quick_start_near_the_top
test_sponsor_metadata_exists
test_consumer_bug_report_template_exists

echo ""
echo "=== Results: $PASSED passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
    exit 1
fi
