#!/bin/bash
# Packaging tests — keep README aligned with the actual distribution model

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$SCRIPT_DIR/.."
README="$REPO_DIR/README.md"
PROVE_IT="$REPO_DIR/PROVE-IT.md"
WINDOWS_E2E_RUNBOOK="$REPO_DIR/WINDOWS-CODEX-DESKTOP-E2E.md"
GIT_ATTRIBUTES="$REPO_DIR/.gitattributes"
ROADMAP="$REPO_DIR/ROADMAP.md"
GOALS_TEMPLATE="$REPO_DIR/templates/GOALS.md.tmpl"
PACKAGE_JSON="$REPO_DIR/package.json"
PLUGIN_MANIFEST="$REPO_DIR/.codex-plugin/plugin.json"
PLUGIN_SKILL="$REPO_DIR/skills/codex-sdlc-wizard/SKILL.md"
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
        CODEX_HOME="$target_repo/.codex-home" bash "$adapter_clone/install.sh" 2>&1
    )

    local has_agents=true
    local has_config=true
    local has_hooks_json=true
    local has_bash_guard=true
    local has_node_guard=true
    local has_fable_review=true
    local has_dual_review=true
    local avoids_unreleased_skill_labels=true

    [ -f "$target_repo/AGENTS.md" ] || has_agents=false
    [ -f "$target_repo/.codex/config.toml" ] || has_config=false
    [ -f "$target_repo/.codex/hooks.json" ] || has_hooks_json=false
    [ -x "$target_repo/.codex/hooks/bash-guard.sh" ] || has_bash_guard=false
    [ -f "$target_repo/.codex/hooks/git-guard.cjs" ] || has_node_guard=false
    [ -f "$target_repo/.codex/hooks/fable-review.cjs" ] || has_fable_review=false
    [ -f "$target_repo/.codex/hooks/dual-review.cjs" ] || has_dual_review=false
    grep -q 'node \.codex/hooks/git-guard\.cjs' "$target_repo/.codex/hooks.json" 2>/dev/null || has_node_guard=false
    echo "$output" | grep -Eq '(^|[^A-Za-z])(gdlc|rdlc)([^A-Za-z]|$)' && avoids_unreleased_skill_labels=false

    rm -rf "$adapter_clone" "$target_repo"

    if [ "$has_agents" = "true" ] &&
       [ "$has_config" = "true" ] &&
       [ "$has_hooks_json" = "true" ] &&
       [ "$has_bash_guard" = "true" ] &&
       [ "$has_node_guard" = "true" ] &&
       [ "$has_fable_review" = "true" ] &&
       [ "$has_dual_review" = "true" ] &&
       [ "$avoids_unreleased_skill_labels" = "true" ]; then
        pass "Installer smoke test succeeds in a clean temp project"
    else
        fail "Installer smoke test did not produce the expected project files"
    fi
}

test_installer_scaffolds_only_default_repo_scope_sdlc_skill() {
    local adapter_clone
    local target_repo
    adapter_clone=$(mktemp -d "$MKTEMP_DIR/sdlc-adapter-clone.XXXXXX")
    target_repo=$(mktemp -d "$MKTEMP_DIR/sdlc-target-repo.XXXXXX")

    cp -R "$REPO_DIR/." "$adapter_clone/"

    (
        cd "$target_repo"
        CODEX_HOME="$target_repo/.codex-home" bash "$adapter_clone/install.sh" >/dev/null 2>&1
    )

    local has_sdlc_skill=true
    local avoids_adlc_skill=true

    [ -f "$target_repo/.agents/skills/sdlc/SKILL.md" ] || has_sdlc_skill=false
    [ -e "$target_repo/.agents/skills/adlc/SKILL.md" ] && avoids_adlc_skill=false

    rm -rf "$adapter_clone" "$target_repo"

    if [ "$has_sdlc_skill" = "true" ] && [ "$avoids_adlc_skill" = "true" ]; then
        pass "Installer scaffolds only the default repo-scope Codex sdlc skill"
    else
        fail "Installer should scaffold sdlc only by default, not adlc"
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
        CODEX_HOME="$target_repo/.codex-home" bash "$adapter_clone/install.sh" >/dev/null 2>&1
    )

    local has_profile=true
    if [ ! -f "$target_repo/.codex-sdlc/model-profile.json" ]; then
        has_profile=false
    elif ! json_has_truthy_file "$target_repo/.codex-sdlc/model-profile.json" 'data.selected_profile === "maximum"'; then
        has_profile=false
    elif ! json_has_truthy_file "$target_repo/.codex-sdlc/model-profile.json" 'data.profiles && data.profiles.maximum && data.profiles.maximum.main_model === "gpt-5.6-sol"'; then
        has_profile=false
    elif ! json_has_truthy_file "$target_repo/.codex-sdlc/model-profile.json" 'data.profiles && data.profiles.maximum && data.profiles.maximum.review_model === "gpt-5.6-sol"'; then
        has_profile=false
    elif ! json_has_truthy_file "$target_repo/.codex-sdlc/model-profile.json" 'data.profiles && data.profiles.mixed && data.profiles.mixed.main_model === "gpt-5.6-terra"'; then
        has_profile=false
    elif ! json_has_truthy_file "$target_repo/.codex-sdlc/model-profile.json" 'data.profiles && data.profiles.mixed && data.profiles.mixed.review_model === "gpt-5.6-sol"'; then
        has_profile=false
    elif ! json_has_truthy_file "$target_repo/.codex-sdlc/model-profile.json" 'data.profiles.maximum.main_reasoning === "high" && data.profiles.maximum.review_reasoning === "high"'; then
        has_profile=false
    elif ! json_has_truthy_file "$target_repo/.codex-sdlc/model-profile.json" 'data.profiles.mixed.main_reasoning === "medium" && data.profiles.mixed.review_reasoning === "high"'; then
        has_profile=false
    elif ! json_has_truthy_file "$target_repo/.codex-sdlc/model-profile.json" 'data.schema_version === 2 && data.profiles.mixed.review_effort_source === "explicit command override"'; then
        has_profile=false
    fi

    if ! grep -q '^model = "gpt-5.6-sol"' "$target_repo/.codex/config.toml" 2>/dev/null; then
        has_profile=false
    elif ! grep -q '^model_reasoning_effort = "high"' "$target_repo/.codex/config.toml" 2>/dev/null; then
        has_profile=false
    elif ! grep -q '^review_model = "gpt-5.6-sol"' "$target_repo/.codex/config.toml" 2>/dev/null; then
        has_profile=false
    elif ! grep -q '^hooks = true' "$target_repo/.codex/config.toml" 2>/dev/null; then
        has_profile=false
    elif grep -v '^[[:space:]]*#' "$target_repo/.codex/config.toml" | grep -q '^codex_hooks\s*=' 2>/dev/null; then
        has_profile=false
    elif ! grep -Fq 'Baseline reasoning: `high`' "$target_repo/AGENTS.md" 2>/dev/null; then
        has_profile=false
    elif ! grep -Eqi 'xhigh.*(security|migration|destructive|long-running|difficult)' "$target_repo/AGENTS.md" 2>/dev/null; then
        has_profile=false
    elif grep -Eqi 'codex-sdlc-wizard itself|always keep this repo.*xhigh|wizard-repo' "$target_repo/AGENTS.md" 2>/dev/null; then
        has_profile=false
    fi

    rm -rf "$adapter_clone" "$target_repo"

    if [ "$has_profile" = "true" ]; then
        pass "Installer writes the default maximum Sol model profile with high reasoning into metadata and repo-local Codex config"
    else
        fail "Installer did not write the expected high default maximum Sol model profile into metadata and .codex/config.toml"
    fi
}

test_installer_renders_explicit_mixed_baseline() {
    local adapter_clone target_repo valid=true
    adapter_clone=$(mktemp -d "$MKTEMP_DIR/sdlc-adapter-clone.XXXXXX")
    target_repo=$(mktemp -d "$MKTEMP_DIR/sdlc-target-repo.XXXXXX")

    cp -R "$REPO_DIR/." "$adapter_clone/"

    (
        cd "$target_repo"
        CODEX_HOME="$target_repo/.codex-home" CODEX_SDLC_DISABLE_REASONING=1 \
            bash "$adapter_clone/install.sh" --model-profile mixed >/dev/null 2>&1
    ) || valid=false

    grep -Fq 'Selected profile: `mixed`' "$target_repo/AGENTS.md" 2>/dev/null || valid=false
    grep -Fq 'Baseline reasoning: `medium`' "$target_repo/AGENTS.md" 2>/dev/null || valid=false
    grep -q '^model = "gpt-5.6-terra"' "$target_repo/.codex/config.toml" 2>/dev/null || valid=false
    grep -q '^model_reasoning_effort = "medium"' "$target_repo/.codex/config.toml" 2>/dev/null || valid=false
    grep -Eq '\{\{(MODEL_PROFILE|REASONING_BASELINE)\}\}' "$target_repo/AGENTS.md" 2>/dev/null && valid=false

    rm -rf "$adapter_clone" "$target_repo"

    if [ "$valid" = "true" ]; then
        pass "Direct installer renders AGENTS baseline from the explicit mixed profile"
    else
        fail "Direct installer wrote contradictory AGENTS guidance for the explicit mixed profile"
    fi
}

test_installer_rejects_unsupported_codex_before_mutation() {
    local target_repo fakebin output status valid=true
    target_repo=$(mktemp -d "$MKTEMP_DIR/sdlc-target-repo.XXXXXX")
    fakebin=$(mktemp -d "$MKTEMP_DIR/sdlc-fake-bin.XXXXXX")

    cat > "$fakebin/codex" <<'EOF'
#!/bin/sh
if [ "${1:-}" = "--version" ]; then
    echo "launcher 9.9.9 warning"
    echo "codex-cli 0.143.9"
    exit 0
fi
exit 99
EOF
    chmod +x "$fakebin/codex"

    set +e
    output=$(
        cd "$target_repo"
        CODEX_HOME="$target_repo/.codex-home" PATH="$fakebin:$PATH" bash "$REPO_DIR/install.sh" 2>&1
    )
    status=$?
    set -e

    [ "$status" -ne 0 ] || valid=false
    echo "$output" | grep -Fq 'Codex CLI 0.144.0 or newer' || valid=false
    echo "$output" | grep -Fq 'npm install -g @openai/codex@latest' || valid=false
    [ ! -e "$target_repo/AGENTS.md" ] || valid=false
    [ ! -e "$target_repo/.codex" ] || valid=false
    [ ! -e "$target_repo/.codex-sdlc" ] || valid=false
    [ ! -e "$target_repo/.codex-home" ] || valid=false

    rm -rf "$target_repo" "$fakebin"

    if [ "$valid" = "true" ]; then
        pass "Direct installer rejects unsupported Codex versions before mutating the target repo"
    else
        fail "Direct installer did not reject an unsupported Codex version before mutation"
    fi
}

test_installer_rejects_missing_or_unqueryable_configured_codex_before_mutation() {
    local mode target_repo fakebin configured_bin output status valid=true

    for mode in missing unqueryable reasoning-disabled; do
        target_repo=$(mktemp -d "$MKTEMP_DIR/sdlc-target-repo.XXXXXX")
        fakebin=$(mktemp -d "$MKTEMP_DIR/sdlc-fake-bin.XXXXXX")
        configured_bin="$fakebin/codex"

        if [ "$mode" = "unqueryable" ]; then
            cat > "$configured_bin" <<'EOF'
#!/bin/sh
exit 42
EOF
            chmod +x "$configured_bin"
        fi

        local disable_reasoning=0
        if [ "$mode" = "reasoning-disabled" ]; then
            disable_reasoning=1
        fi

        set +e
        output=$(
            cd "$target_repo"
            CODEX_HOME="$target_repo/.codex-home" \
                CODEX_SDLC_CODEX_BIN="$configured_bin" \
                CODEX_SDLC_DISABLE_REASONING="$disable_reasoning" \
                bash "$REPO_DIR/install.sh" 2>&1
        )
        status=$?
        set -e

        [ "$status" -ne 0 ] || valid=false
        echo "$output" | grep -Fq 'Codex CLI 0.144.0 or newer' || valid=false
        echo "$output" | grep -Fq 'npm install -g @openai/codex@latest' || valid=false
        [ ! -e "$target_repo/AGENTS.md" ] || valid=false
        [ ! -e "$target_repo/.codex" ] || valid=false
        [ ! -e "$target_repo/.codex-sdlc" ] || valid=false
        [ ! -e "$target_repo/.codex-home" ] || valid=false

        rm -rf "$target_repo" "$fakebin"
    done

    if [ "$valid" = "true" ]; then
        pass "Direct installer rejects missing or unqueryable configured Codex binaries before mutation"
    else
        fail "Direct installer accepted a missing or unqueryable configured Codex binary"
    fi
}

test_installer_rejects_minimum_version_prerelease_before_mutation() {
    local target_repo fakebin output status valid=true
    target_repo=$(mktemp -d "$MKTEMP_DIR/sdlc-target-repo.XXXXXX")
    fakebin=$(mktemp -d "$MKTEMP_DIR/sdlc-fake-bin.XXXXXX")

    cat > "$fakebin/codex" <<'EOF'
#!/bin/sh
echo "codex-cli 0.144.0-beta.1"
EOF
    chmod +x "$fakebin/codex"

    set +e
    output=$(
        cd "$target_repo"
        CODEX_HOME="$target_repo/.codex-home" PATH="$fakebin:$PATH" bash "$REPO_DIR/install.sh" 2>&1
    )
    status=$?
    set -e

    [ "$status" -ne 0 ] || valid=false
    echo "$output" | grep -Fq 'Codex CLI 0.144.0 or newer' || valid=false
    [ ! -e "$target_repo/AGENTS.md" ] || valid=false
    [ ! -e "$target_repo/.codex" ] || valid=false

    rm -rf "$target_repo" "$fakebin"

    if [ "$valid" = "true" ]; then
        pass "Direct installer rejects a prerelease of the minimum supported Codex version"
    else
        fail "Direct installer accepted a prerelease below the minimum stable Codex version"
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

test_installer_recommends_current_codex_restart_resume() {
    local adapter_clone
    local target_repo
    local output
    adapter_clone=$(mktemp -d "$MKTEMP_DIR/sdlc-adapter-clone.XXXXXX")
    target_repo=$(mktemp -d "$MKTEMP_DIR/sdlc-target-repo.XXXXXX")

    cp -R "$REPO_DIR/." "$adapter_clone/"

    output=$(
        cd "$target_repo" &&
        CODEX_HOME="$target_repo/.codex-home" bash "$adapter_clone/install.sh" 2>&1
    )

    rm -rf "$adapter_clone" "$target_repo"

    if echo "$output" | grep -q "codex -m gpt-5.6-sol -c 'model_reasoning_effort=\"high\"'" &&
       echo "$output" | grep -Eqi 'exit and reopen Codex|restart Codex' &&
       echo "$output" | grep -Eqi '/hooks.*review|review.*\/hooks' &&
       echo "$output" | grep -q "codex resume -m gpt-5.6-sol" &&
       echo "$output" | grep -Fq 'model_reasoning_effort="high"' &&
       ! echo "$output" | grep -q -- '--full-auto'; then
        pass "Installer output recommends current Codex restart/resume after setup"
    else
        fail "Installer output does not recommend current Codex restart/resume clearly enough"
    fi
}

test_installer_prints_explicit_yolo_style_flags() {
    local adapter_clone
    local target_repo
    local output
    adapter_clone=$(mktemp -d "$MKTEMP_DIR/sdlc-adapter-clone.XXXXXX")
    target_repo=$(mktemp -d "$MKTEMP_DIR/sdlc-target-repo.XXXXXX")

    cp -R "$REPO_DIR/." "$adapter_clone/"

    output=$(
        cd "$target_repo" &&
        CODEX_HOME="$target_repo/.codex-home" bash "$adapter_clone/install.sh" --model-profile maximum 2>&1
    )

    rm -rf "$adapter_clone" "$target_repo"

    if echo "$output" | grep -qi 'yolo-style sessions' &&
       echo "$output" | grep -q -- '--dangerously-bypass-approvals-and-sandbox' &&
       echo "$output" | grep -Fq "codex --dangerously-bypass-approvals-and-sandbox -m gpt-5.6-sol -c 'model_reasoning_effort=\"high\"'" &&
       echo "$output" | grep -Fq "codex resume --dangerously-bypass-approvals-and-sandbox -m gpt-5.6-sol -c 'model_reasoning_effort=\"high\"'" &&
       echo "$output" | grep -Eqi 'yolo.*shorthand|shorthand.*yolo' &&
       echo "$output" | grep -Eqi 'fully trust|full-trust' &&
       echo "$output" | grep -Eqi 'full-auto.*not.*full-trust|full-trust.*not.*full-auto'; then
        pass "Installer output prints canonical full-trust flags for yolo-style sessions"
    else
        fail "Installer output does not print canonical full-trust flags for yolo-style sessions"
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
        CODEX_HOME="$target_repo/.codex-home" bash "$adapter_clone/install.sh" 2>&1
    )

    rm -rf "$adapter_clone" "$target_repo"

    if echo "$output" | grep -qi 'mixed' &&
       echo "$output" | grep -qi 'maximum' &&
       echo "$output" | grep -Eqi 'speed|token|latency' &&
       echo "$output" | grep -qi 'stability' &&
       echo "$output" | grep -Eqi 'Sol high.*(default|normal).*(driver|work)|default.*Sol high.*(driver|work)' &&
       echo "$output" | grep -Eqi 'mixed.*experimental.*explicit opt-in|experimental.*mixed.*explicit opt-in'; then
        pass "Installer output recommends Sol high and marks mixed as experimental opt-in"
    else
        fail "Installer output does not explain the Sol-high default and experimental mixed tradeoff"
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
        CODEX_HOME="$target_repo/.codex-home" bash "$adapter_clone/install.sh" 2>&1
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
        CODEX_HOME="$target_repo/.codex-home" bash "$adapter_clone/install.sh" 2>&1
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
    local has_plugin=true
    local has_skills_only_boundary=true
    local has_install_sh=true

    grep -q '^## What This Repo Is$' "$README" || has_section=false
    grep -qi 'installer-style adapter' "$README" || has_adapter=false
    grep -qi 'Codex skill' "$README" || has_skill=false
    grep -qi 'skills-only plugin' "$README" || has_plugin=false
    grep -Eqi 'plugin.*(does not|doesn.t).*(bundle|declare).*(hooks|MCP)|hooks.*remain.*repo' "$README" || has_skills_only_boundary=false
    grep -q '`install.sh`' "$README" || has_install_sh=false

    if [ "$has_section" = "true" ] &&
       [ "$has_adapter" = "true" ] &&
       [ "$has_skill" = "true" ] &&
       [ "$has_plugin" = "true" ] &&
       [ "$has_skills_only_boundary" = "true" ] &&
       [ "$has_install_sh" = "true" ]; then
        pass "README explains the skills-only plugin plus adaptive installer distribution near the top"
    else
        fail "README does not clearly explain the plugin, skill, installer, and hook boundary"
    fi
}

test_repo_is_installable_skills_only_plugin() {
    local has_manifest=true
    local version_matches=true
    local has_plugin_skills_directory=true
    local avoids_legacy_root_skill=true
    local has_interface_metadata=true
    local passes_final_directory_metadata_limits=true
    local has_square_brand_assets=true
    local avoids_unsupported_runtime_declarations=true
    local composer_icon="$REPO_DIR/assets/composer-icon.svg"
    local logo="$REPO_DIR/assets/logo.svg"

    [ -f "$PLUGIN_MANIFEST" ] || has_manifest=false

    if [ "$has_manifest" = "true" ]; then
        json_has_truthy_file "$PLUGIN_MANIFEST" 'data.name === "codex-sdlc-wizard"' || has_manifest=false
        [ "$(json_get_file "$PLUGIN_MANIFEST" 'data.version')" = "$CURRENT_VERSION" ] || version_matches=false
        json_has_truthy_file "$PLUGIN_MANIFEST" 'data.skills === "./skills/"' || has_plugin_skills_directory=false
        [ -f "$PLUGIN_SKILL" ] || has_plugin_skills_directory=false
        [ ! -e "$REPO_DIR/SKILL.md" ] || avoids_legacy_root_skill=false
        json_has_truthy_file "$PLUGIN_MANIFEST" 'data.author && typeof data.author.name === "string" && data.author.name.length > 0' || has_interface_metadata=false
        json_has_truthy_file "$PLUGIN_MANIFEST" 'data.interface && data.interface.displayName === "Codex SDLC Wizard"' || has_interface_metadata=false
        json_has_truthy_file "$PLUGIN_MANIFEST" 'data.interface && typeof data.interface.shortDescription === "string" && data.interface.shortDescription.length > 0' || has_interface_metadata=false
        json_has_truthy_file "$PLUGIN_MANIFEST" 'data.interface && typeof data.interface.longDescription === "string" && data.interface.longDescription.length > 0' || has_interface_metadata=false
        json_has_truthy_file "$PLUGIN_MANIFEST" 'data.interface && (typeof data.interface.defaultPrompt === "string" || Array.isArray(data.interface.defaultPrompt))' || has_interface_metadata=false
        json_has_truthy_file "$PLUGIN_MANIFEST" 'data.interface.displayName.length <= 30 && data.interface.shortDescription.length <= 30 && data.interface.longDescription.length <= 4000' || passes_final_directory_metadata_limits=false
        json_has_truthy_file "$PLUGIN_MANIFEST" 'data.interface.composerIcon === "./assets/composer-icon.svg" && data.interface.logo === "./assets/logo.svg"' || has_square_brand_assets=false
        [ -f "$composer_icon" ] || has_square_brand_assets=false
        [ -f "$logo" ] || has_square_brand_assets=false
        grep -Eq '<svg[^>]+(width="512"[^>]+height="512"|height="512"[^>]+width="512"|viewBox="0 0 512 512")' "$composer_icon" 2>/dev/null || has_square_brand_assets=false
        grep -Eq '<svg[^>]+(width="512"[^>]+height="512"|height="512"[^>]+width="512"|viewBox="0 0 512 512")' "$logo" 2>/dev/null || has_square_brand_assets=false
        json_has_truthy_file "$PLUGIN_MANIFEST" '!Object.hasOwn(data, "mcpServers") && !Object.hasOwn(data, "apps") && !Object.hasOwn(data, "hooks")' || avoids_unsupported_runtime_declarations=false
    else
        version_matches=false
        has_plugin_skills_directory=false
        avoids_legacy_root_skill=false
        has_interface_metadata=false
        passes_final_directory_metadata_limits=false
        has_square_brand_assets=false
        avoids_unsupported_runtime_declarations=false
    fi

    if [ "$has_manifest" = "true" ] &&
       [ "$version_matches" = "true" ] &&
       [ "$has_plugin_skills_directory" = "true" ] &&
       [ "$avoids_legacy_root_skill" = "true" ] &&
       [ "$has_interface_metadata" = "true" ] &&
       [ "$passes_final_directory_metadata_limits" = "true" ] &&
       [ "$has_square_brand_assets" = "true" ] &&
       [ "$avoids_unsupported_runtime_declarations" = "true" ]; then
        pass "Repository root is a version-aligned, directory-ready skills-only Codex plugin"
    else
        fail "Repository root is not yet a valid directory-ready skills-only Codex plugin"
    fi
}

test_readme_documents_standalone_skill_migration() {
    local has_migration_heading=true
    local identifies_legacy_path=true
    local uses_recoverable_backup=true
    local explains_duplicate_risk=true
    local requires_fresh_thread=true

    grep -Eq '^### Migrate (the )?legacy standalone skill$' "$README" || has_migration_heading=false
    grep -Fq '.codex/skills/codex-sdlc-wizard' "$README" || identifies_legacy_path=false
    grep -Fq '.codex/skill-backups' "$README" || uses_recoverable_backup=false
    grep -Eqi 'duplicate|two copies|stale standalone' "$README" || explains_duplicate_risk=false
    grep -Eqi 'fresh (thread|session)' "$README" || requires_fresh_thread=false

    if [ "$has_migration_heading" = "true" ] &&
       [ "$identifies_legacy_path" = "true" ] &&
       [ "$uses_recoverable_backup" = "true" ] &&
       [ "$explains_duplicate_risk" = "true" ] &&
       [ "$requires_fresh_thread" = "true" ]; then
        pass "README documents a recoverable standalone-skill to plugin migration"
    else
        fail "README does not document how existing standalone-skill users avoid duplicate plugin discovery"
    fi
}

test_plugin_skill_documents_cross_surface_execution_boundary() {
    local has_work=true
    local has_codex_surfaces=true
    local has_invocation_syntax=true
    local has_plain_chat_boundary=true
    local has_local_repo_boundary=true

    grep -q 'ChatGPT Work' "$PLUGIN_SKILL" || has_work=false
    grep -Eqi 'Codex (desktop|app).*(CLI|command line)|CLI.*Codex (desktop|app)' "$PLUGIN_SKILL" || has_codex_surfaces=false
    grep -Eq 'ChatGPT.*`@`|`@`.*ChatGPT' "$PLUGIN_SKILL" || has_invocation_syntax=false
    grep -Eq 'Codex.*`\$`|`\$`.*Codex' "$PLUGIN_SKILL" || has_invocation_syntax=false
    grep -Eqi 'ordinary Chat|plain Chat|Chat mode' "$PLUGIN_SKILL" || has_plain_chat_boundary=false
    grep -Eqi 'does not support plugins|plugins are not available|plugin support is unavailable' "$PLUGIN_SKILL" || has_plain_chat_boundary=false
    grep -Eqi 'local repo|local repository|project access' "$PLUGIN_SKILL" || has_local_repo_boundary=false

    if [ "$has_work" = "true" ] &&
       [ "$has_codex_surfaces" = "true" ] &&
       [ "$has_invocation_syntax" = "true" ] &&
       [ "$has_plain_chat_boundary" = "true" ] &&
       [ "$has_local_repo_boundary" = "true" ]; then
        pass "Plugin skill explains supported plugin surfaces, invocation syntax, and local-repo boundary"
    else
        fail "Plugin skill does not explain supported plugin surfaces and execution boundaries"
    fi
}

test_readme_has_install_choice_table() {
    local has_table=true
    local marks_source_path_inspection_only=true
    local avoids_broken_standalone_install_claim=true

    grep -q '^| Need | Use | Why |$' "$README" || has_table=false
    grep -Fq '| Inspect the plugin skill source |' "$README" || marks_source_path_inspection_only=false
    grep -Eqi 'inspection-only|inspect(ion)? only' "$README" || marks_source_path_inspection_only=false
    grep -Fq 'Inspect or install the reusable Codex skill from source' "$README" && avoids_broken_standalone_install_claim=false

    if [ "$has_table" = "true" ] &&
       [ "$marks_source_path_inspection_only" = "true" ] &&
       [ "$avoids_broken_standalone_install_claim" = "true" ]; then
        pass "README includes an install choice table without advertising a broken standalone skill"
    else
        fail "README install table is missing or advertises a non-self-contained standalone skill"
    fi
}

test_readme_explains_install_side_effects() {
    local has_heading=true
    local mentions_config=true
    local mentions_hooks=true
    local mentions_agents=true
    local mentions_sdlc_skill=true
    local mentions_hooks_flag=true
    local mentions_hooks_review=true
    local avoids_default_adlc_skill=true

    grep -q '^### What `install.sh` Changes$' "$README" || has_heading=false
    grep -q '\.codex/config\.toml' "$README" || mentions_config=false
    grep -q '\.codex/hooks\.json' "$README" || mentions_hooks=false
    grep -q 'AGENTS\.md' "$README" || mentions_agents=false
    grep -q '\.agents/skills/sdlc/SKILL.md' "$README" || mentions_sdlc_skill=false
    grep -Fq '[features].hooks' "$README" || mentions_hooks_flag=false
    grep -Eiq '/hooks.*review|review.*\/hooks' "$README" || mentions_hooks_review=false
    grep -q '\.agents/skills/adlc/SKILL.md' "$README" && avoids_default_adlc_skill=false

    if [ "$has_heading" = "true" ] &&
       [ "$mentions_config" = "true" ] &&
       [ "$mentions_hooks" = "true" ] &&
       [ "$mentions_agents" = "true" ] &&
       [ "$mentions_sdlc_skill" = "true" ] &&
       [ "$mentions_hooks_flag" = "true" ] &&
       [ "$mentions_hooks_review" = "true" ] &&
       [ "$avoids_default_adlc_skill" = "true" ]; then
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

test_readme_documents_optional_goals_contract() {
    local has_goals=true
    local has_active_until_stop=true
    local has_roadmap_boundary=true
    local has_evidence_contract=true

    grep -q 'GOALS.md' "$README" || has_goals=false
    grep -q 'complete everything in GOALS.md until the user says stop' "$README" || has_active_until_stop=false
    grep -Eqi 'ROADMAP.md.*backlog|backlog.*ROADMAP.md' "$README" || has_roadmap_boundary=false
    grep -Eqi 'evidence contract|runtime boundary' "$README" || has_evidence_contract=false

    if [ "$has_goals" = "true" ] &&
       [ "$has_active_until_stop" = "true" ] &&
       [ "$has_roadmap_boundary" = "true" ] &&
       [ "$has_evidence_contract" = "true" ]; then
        pass "README documents the optional GOALS.md active-scope contract"
    else
        fail "README does not document the optional GOALS.md active-scope contract"
    fi
}

test_roadmap_is_the_single_project_backlog() {
    local has_source_of_truth=true
    local has_single_backlog=true
    local has_consumer_boundary=true

    grep -Eqi 'GitHub issues.*source of truth|source of truth.*GitHub issues' "$ROADMAP" || has_source_of_truth=false
    grep -Eqi 'single ordered project backlog|single.*backlog' "$ROADMAP" || has_single_backlog=false
    grep -Eqi 'GOALS\.md.*consumer repo|consumer repo.*GOALS\.md' "$ROADMAP" || has_consumer_boundary=false
    grep -Eqi 'GOALS\.md.*(never|does not).*override|never overrides.*priority queue' "$ROADMAP" || has_consumer_boundary=false

    if [ "$has_source_of_truth" = "true" ] &&
       [ "$has_single_backlog" = "true" ] &&
       [ "$has_consumer_boundary" = "true" ]; then
        pass "ROADMAP is the single GitHub-backed project backlog"
    else
        fail "ROADMAP does not remain the single GitHub-backed project backlog"
    fi
}

test_readme_and_goals_template_document_goal_mode_with_sdlc() {
    local has_readme_goal_heading=true
    local has_sdlc_anchor=true
    local has_goal_as_sdlc_task=true
    local has_extra_skills_generic=true
    local has_confidence_stop=true
    local has_verification=true
    local has_clean_break=true
    local has_template_goal_block=true
    local has_template_goal_phrase=true
    local avoids_ecosystem_reveal=true

    grep -q '^### Codex `/goal` With SDLC$' "$README" || has_readme_goal_heading=false
    grep -Eiq '/goal.*\$sdlc|\$sdlc.*/goal' "$README" || has_sdlc_anchor=false
    grep -Eiq 'SDLC task|active SDLC task|SDLC-backed' "$README" || has_goal_as_sdlc_task=false
    grep -Eiq 'repo-local.*skills|repo-specific.*skills|additional.*skills' "$README" || has_extra_skills_generic=false
    grep -Eiq '95%|confidence.*drop|drops.*confidence' "$README" || has_confidence_stop=false
    grep -Eiq 'RED/GREEN|focused checks|full.*tests|verification' "$README" || has_verification=false
    grep -Eiq 'clean break|committed locally|safe.*resume' "$README" || has_clean_break=false
    grep -q '^## Codex /goal Prompt$' "$GOALS_TEMPLATE" || has_template_goal_block=false
    grep -q '/goal' "$GOALS_TEMPLATE" || has_template_goal_phrase=false
    grep -Eqi '^## XDLC Ecosystem|Full ecosystem|\$gdlc|\$adlc|domain DLC' "$README" "$GOALS_TEMPLATE" && avoids_ecosystem_reveal=false

    if [ "$has_readme_goal_heading" = "true" ] &&
       [ "$has_sdlc_anchor" = "true" ] &&
       [ "$has_goal_as_sdlc_task" = "true" ] &&
       [ "$has_extra_skills_generic" = "true" ] &&
       [ "$has_confidence_stop" = "true" ] &&
       [ "$has_verification" = "true" ] &&
       [ "$has_clean_break" = "true" ] &&
       [ "$has_template_goal_block" = "true" ] &&
       [ "$has_template_goal_phrase" = "true" ] &&
       [ "$avoids_ecosystem_reveal" = "true" ]; then
        pass "README and GOALS template document Codex /goal as SDLC-backed active work"
    else
        fail "README or GOALS template does not document Codex /goal as an SDLC-backed active task"
    fi
}

test_readme_recommends_full_auto() {
    local has_current_start=true
    local has_manual_fallback=true
    local explains_full_trust=true

    grep -q 'codex -m gpt-5.6-sol' "$README" || has_current_start=false
    grep -q 'plain `codex`' "$README" || has_manual_fallback=false
    grep -q -- '--dangerously-bypass-approvals-and-sandbox' "$README" || explains_full_trust=false
    grep -Eqi 'full-auto.*not.*full-trust|full-trust.*not.*full-auto' "$README" || explains_full_trust=false

    if [ "$has_current_start" = "true" ] && [ "$has_manual_fallback" = "true" ] && [ "$explains_full_trust" = "true" ]; then
        pass "README recommends current Codex startup and documents full-trust separately"
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

test_readme_documents_current_codex_hook_surface() {
    local has_current_version=true
    local has_eight_hooks=true
    local has_active_subset=true
    local has_all_event_names=true

    grep -q 'Codex CLI `0.144.0+`' "$README" || has_current_version=false
    grep -q 'eight hook events' "$README" || has_eight_hooks=false
    grep -q 'actively installs `SessionStart`, `PreToolUse`, `PreCompact`, and `PostCompact`' "$README" || has_active_subset=false

    for event in PreToolUse PermissionRequest PostToolUse PreCompact PostCompact SessionStart UserPromptSubmit Stop; do
        grep -Fq "\`$event\`" "$README" || has_all_event_names=false
    done

    if [ "$has_current_version" = "true" ] &&
       [ "$has_eight_hooks" = "true" ] &&
       [ "$has_active_subset" = "true" ] &&
       [ "$has_all_event_names" = "true" ]; then
        pass "README documents the minimum GPT-5.6 Codex version, hook surface, and active subset"
    else
        fail "README does not document the minimum GPT-5.6 Codex version and current hook surface"
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
    local has_gpt56=true
    local has_confidence_rule=true
    local has_repo_maximum_rule=true
    local has_bootstrap_maximum_rule=true
    local has_sol_driver_default=true
    local has_experimental_mixed_rule=true
    local avoids_routine_mixed_recommendation=true
    local has_adaptive_reasoning_policy=true

    grep -q '^## Model Profiles$' "$README" || has_heading=false
    grep -q '`mixed`' "$README" || has_mixed=false
    grep -q '`maximum`' "$README" || has_maximum=false
    grep -q 'gpt-5.6-sol' "$README" || has_gpt56=false
    grep -q 'gpt-5.6-terra' "$README" || has_gpt56=false
    grep -q 'gpt-5.6-luna' "$README" || has_gpt56=false
    grep -Eqi 'speed|latency|token' "$README" || has_tradeoff=false
    grep -Eqi 'stability|ultimate' "$README" || has_tradeoff=false
    grep -Eqi '95%|xhigh review|research more first' "$README" || has_confidence_rule=false
    grep -Eqi 'this repo.*maximum|wizard repo.*maximum|codex-sdlc-wizard itself.*maximum' "$README" || has_repo_maximum_rule=false
    grep -Eqi 'setup/update.*maximum|bootstrap.*maximum' "$README" || has_bootstrap_maximum_rule=false
    grep -Eqi 'Sol `high`.*(normal|default|standing).*(driver|root|work)|normal.*(driver|root|work).*Sol `high`' "$README" || has_sol_driver_default=false
    grep -Eqi '`mixed`.*experimental.*explicit opt-in|experimental.*`mixed`.*explicit opt-in' "$README" || has_experimental_mixed_rule=false
    grep -Eqi 'routine work.*mixed|day-to-day.*mixed|after bootstrap.*mixed' "$README" && avoids_routine_mixed_recommendation=false
    grep -Eqi 'consumer.*default.*`high`|agentic coding.*default.*`high`|default.*`high`.*agentic' "$README" || has_adaptive_reasoning_policy=false
    grep -Eqi 'xhigh.*(security|migration|destructive|long-running|difficult)|security.*xhigh|migration.*xhigh' "$README" || has_adaptive_reasoning_policy=false

    if [ "$has_heading" = "true" ] &&
       [ "$has_mixed" = "true" ] &&
       [ "$has_maximum" = "true" ] &&
       [ "$has_gpt56" = "true" ] &&
       [ "$has_tradeoff" = "true" ] &&
       [ "$has_confidence_rule" = "true" ] &&
       [ "$has_repo_maximum_rule" = "true" ] &&
       [ "$has_bootstrap_maximum_rule" = "true" ] &&
       [ "$has_sol_driver_default" = "true" ] &&
       [ "$has_experimental_mixed_rule" = "true" ] &&
       [ "$avoids_routine_mixed_recommendation" = "true" ] &&
       [ "$has_adaptive_reasoning_policy" = "true" ]; then
        pass "README documents Sol high as the normal driver, mixed as experimental opt-in, and this repo's maximum-only policy"
    else
        fail "README does not document the Sol-high default, experimental mixed policy, and this repo's maximum-only policy clearly enough"
    fi
}

test_readme_documents_native_codex_review() {
    local has_review_command=true
    local has_uncommitted=true
    local has_base=true
    local has_commit=true
    local has_review_model=true
    local has_explicit_high_review=true
    local explains_review_effort_boundary=true
    local explains_auto_review_boundary=true
    local avoids_autoreview_requirement=true
    local has_single_proof_contract=true
    local has_prompt_only_contract=true
    local has_targeted_verification_boundary=true
    local binds_base_and_candidate=true
    local documents_bounded_dual_review=true

    grep -q 'codex review' "$README" || has_review_command=false
    grep -q 'codex review --uncommitted' "$README" || has_uncommitted=false
    grep -q 'codex review --base' "$README" || has_base=false
    grep -q 'codex review --commit' "$README" || has_commit=false
    grep -q 'review_model = "gpt-5.6-sol"' "$README" || has_review_model=false
    grep -Fq "codex -c 'model_reasoning_effort=\"high\"' review --uncommitted" "$README" || has_explicit_high_review=false
    grep -Eqi 'review_model.*(does not|doesn.t).*reasoning|reasoning.*(does not|doesn.t).*review_model' "$README" || explains_review_effort_boundary=false
    grep -Eqi 'auto_review.*approval|approval.*auto_review' "$README" || explains_auto_review_boundary=false
    grep -Eqi '(must|always|requires).*/autoreview|/autoreview.*(must|always)' "$README" && avoids_autoreview_requirement=false
    grep -Fqi 'one broad proof run total' "$README" || has_single_proof_contract=false
    grep -Eqi 'prompt-only.*review|review.*prompt-only' "$README" || has_prompt_only_contract=false
    grep -Eqi 'custom prompt.*(cannot|must not|do not).*--(uncommitted|base|commit)|(cannot|must not|do not).*--(uncommitted|base|commit).*custom prompt' "$README" || has_prompt_only_contract=false
    grep -Eqi 'targeted verification.*concrete suspected defect|concrete suspected defect.*targeted verification' "$README" || has_targeted_verification_boundary=false
    grep -Eqi 'Base: <base-[^>]+>.*Candidate: <candidate-[^>]+>' "$README" || binds_base_and_candidate=false
    grep -Fq 'node .codex/hooks/dual-review.cjs --base main --consent-subscription-quota' "$README" || documents_bounded_dual_review=false

    if [ "$has_review_command" = "true" ] &&
       [ "$has_uncommitted" = "true" ] &&
       [ "$has_base" = "true" ] &&
       [ "$has_commit" = "true" ] &&
       [ "$has_review_model" = "true" ] &&
       [ "$has_explicit_high_review" = "true" ] &&
       [ "$explains_review_effort_boundary" = "true" ] &&
       [ "$explains_auto_review_boundary" = "true" ] &&
       [ "$avoids_autoreview_requirement" = "true" ] &&
       [ "$has_single_proof_contract" = "true" ] &&
       [ "$has_prompt_only_contract" = "true" ] &&
       [ "$has_targeted_verification_boundary" = "true" ] &&
       [ "$binds_base_and_candidate" = "true" ] &&
       [ "$documents_bounded_dual_review" = "true" ]; then
        pass "README documents proof-aware native Codex review without redundant broad verification"
    else
        fail "README does not document proof-aware native Codex review and its verification boundaries clearly enough"
    fi
}

test_prove_it_documents_bounded_dual_review() {
    if grep -Fq 'node .codex/hooks/dual-review.cjs --base <ref> --consent-subscription-quota' "$PROVE_IT"; then
        pass "PROVE-IT documents the bounded dual-review gate"
    else
        fail "PROVE-IT omits the bounded dual-review gate"
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

test_readme_has_consumer_parity_sections_without_ecosystem_reveal() {
    local has_strong_intro=true
    local has_why=true
    local has_actual_shape=true
    local has_different=true
    local has_documentation=true
    local has_feedback=true
    local has_proof_gate=true
    local has_native_review=true
    local avoids_ecosystem_reveal=true

    grep -qi 'self-evolving Software Development Life Cycle (SDLC) enforcement system for AI coding agents' "$README" || has_strong_intro=false
    grep -q '^## Why Use This$' "$README" || has_why=false
    grep -q '^## What This Actually Is$' "$README" || has_actual_shape=false
    grep -q '^## What Makes This Different$' "$README" || has_different=false
    grep -q '^## Documentation$' "$README" || has_documentation=false
    grep -q '^## Feedback$' "$README" || has_feedback=false
    grep -qi 'Proof-aware git gates' "$README" || has_proof_gate=false
    grep -qi 'Codex-native review' "$README" || has_native_review=false
    grep -Eqi '^## XDLC Ecosystem|Full ecosystem|broader .*ecosystem' "$README" && avoids_ecosystem_reveal=false

    if [ "$has_strong_intro" = "true" ] &&
       [ "$has_why" = "true" ] &&
       [ "$has_actual_shape" = "true" ] &&
       [ "$has_different" = "true" ] &&
       [ "$has_documentation" = "true" ] &&
       [ "$has_feedback" = "true" ] &&
       [ "$has_proof_gate" = "true" ] &&
       [ "$has_native_review" = "true" ] &&
       [ "$avoids_ecosystem_reveal" = "true" ]; then
        pass "README has sibling-parity consumer sections without ecosystem reveal"
    else
        fail "README is missing consumer parity sections or reveals ecosystem framing too early"
    fi
}

test_readme_documents_official_codex_distribution_status() {
    local has_heading=true
    local has_skill_docs=true
    local has_plugin_docs=true
    local has_authoring_format=true
    local has_installable_unit=true
    local has_universal_directory=true
    local has_surface_specific_install=true
    local has_supported_surfaces=true
    local has_plain_chat_boundary=true
    local has_publish_boundary=true
    local keeps_npx_path=true
    local avoids_endorsement=true

    grep -q '^## Official Codex Distribution Status$' "$README" || has_heading=false
    grep -Eq 'learn.chatgpt.com/docs/skills-and-plugins|developers.openai.com/codex/skills' "$README" || has_skill_docs=false
    grep -Eq 'learn.chatgpt.com/docs/plugins|developers.openai.com/plugins/build/plugins' "$README" || has_plugin_docs=false
    grep -qi 'skills are the authoring format' "$README" || has_authoring_format=false
    grep -qi 'plugins are the installable distribution unit' "$README" || has_installable_unit=false
    grep -Eqi 'universal plugin directory|same plugin directory|shared plugin directory' "$README" || has_universal_directory=false
    grep -Eqi 'install(ation)?(/enablement)? is surface-specific|install or enable (it|the plugin) (on|in) each intended surface' "$README" || has_surface_specific_install=false
    grep -Eqi 'install once through a supported surface' "$README" && has_surface_specific_install=false
    grep -q 'ChatGPT Work' "$README" || has_supported_surfaces=false
    grep -Eqi 'Codex (desktop|app)' "$README" || has_supported_surfaces=false
    grep -q 'Codex CLI' "$README" || has_supported_surfaces=false
    grep -Eqi 'ordinary Chat|plain Chat|Chat mode' "$README" || has_plain_chat_boundary=false
    grep -Eqi 'does not support plugins|plugins are not available|plugin support is unavailable' "$README" || has_plain_chat_boundary=false
    grep -Eq 'developers.openai.com/plugins/deploy/submission' "$README" || has_publish_boundary=false
    grep -Eqi 'submission portal.*(live|available|open)|public listing.*pending' "$README" || has_publish_boundary=false
    grep -q 'npx codex-sdlc-wizard@latest' "$README" || keeps_npx_path=false
    grep -Eqi 'official OpenAI (partner|endorsed|certified)|OpenAI-endorsed|OpenAI certified' "$README" && avoids_endorsement=false

    if [ "$has_heading" = "true" ] &&
       [ "$has_skill_docs" = "true" ] &&
       [ "$has_plugin_docs" = "true" ] &&
       [ "$has_authoring_format" = "true" ] &&
       [ "$has_installable_unit" = "true" ] &&
       [ "$has_universal_directory" = "true" ] &&
       [ "$has_surface_specific_install" = "true" ] &&
       [ "$has_supported_surfaces" = "true" ] &&
       [ "$has_plain_chat_boundary" = "true" ] &&
       [ "$has_publish_boundary" = "true" ] &&
       [ "$keeps_npx_path" = "true" ] &&
       [ "$avoids_endorsement" = "true" ]; then
        pass "README documents the current official Codex distribution status without endorsement claims"
    else
        fail "README does not document the current official Codex distribution status clearly enough"
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

test_windows_desktop_real_install_runbook_exists() {
    local has_file=true
    local is_linked=true
    local identifies_real_install=true
    local protects_wizard_source=true
    local preserves_existing_work=true
    local prefers_plugin=true
    local keeps_verified_checkout_fallback=true
    local enforces_lf_shell_checkouts=true
    local accepts_crlf_gitattributes=true
    local executes_verified_package=true
    local executes_verified_plugin_root=true
    local converts_plugin_root_for_git_bash=true
    local branches_after_npx_fallback=true
    local hashes_every_dirty_path=true
    local hashes_managed_and_installer_targets=true
    local separates_preservation_from_customized=true
    local preflights_conflicting_hook_scripts=true
    local routes_initialized_repos_to_update=true
    local preflights_bash_on_windows=true
    local baselines_codex_home_skills=true
    local redacts_all_report_evidence=true
    local updates_initialized_verified_fallback=true
    local enables_available_plugin=true
    local baselines_legacy_installer_migration=true
    local preflights_all_hook_collisions_before_fallback=true
    local requires_hook_approval=true
    local enforces_minimum_versions=true
    local distinguishes_git_bash_from_wsl=true
    local preflights_bash_before_fallback_download=true
    local preserves_initialized_profile=true
    local requires_current_plugin_version=true
    local avoids_hardcoded_release_identity=true
    local validates_preserved_profile_driver=true
    local preflights_retired_hook_collisions=true
    local stops_on_invalid_manifest=true
    local stops_on_invalid_hooks_document=true
    local preflights_model_profile_collision=true
    local fingerprints_exact_candidate_bundle=true
    local rejects_crlf_shell_payloads=true
    local canonicalizes_generated_plugin_version=true
    local retains_verified_package_through_verification=true
    local reports_verified_package_fallback=true
    local requires_restart_and_sdlc=true
    local produces_issue_ready_report=true
    local avoids_remote_mutation=true
    local resolves_path_codex_binary=true
    local allows_unavailable_bundled_version=true
    local has_cleanup_fallback=true
    local handles_preupdate_profile_pin=true
    local captures_manifest_and_retired_prompt_hook=true
    local requires_hook_enabled_state=true
    local requires_one_repo_scoped_sdlc=true
    local documents_supported_global_helpers=true

    [ -f "$WINDOWS_E2E_RUNBOOK" ] || has_file=false
    grep -Fq '[Windows Codex Desktop real-install E2E](WINDOWS-CODEX-DESKTOP-E2E.md)' "$README" || is_linked=false
    grep -Eqi 'authorized real installation|real product repo' "$WINDOWS_E2E_RUNBOOK" 2>/dev/null || identifies_real_install=false
    grep -Eqi 'stop.*codex-sdlc-wizard.*source repo|codex-sdlc-wizard.*source repo.*stop' "$WINDOWS_E2E_RUNBOOK" 2>/dev/null || protects_wizard_source=false
    grep -Eqi 'preserve.*existing|existing.*preserve' "$WINDOWS_E2E_RUNBOOK" 2>/dev/null || preserves_existing_work=false
    grep -Eqi 'Plugins.*(Personal|Installed)|Personal.*Installed' "$WINDOWS_E2E_RUNBOOK" 2>/dev/null || prefers_plugin=false
    grep -Fq 'npm pack "<verified-head-export>"' "$WINDOWS_E2E_RUNBOOK" 2>/dev/null || keeps_verified_checkout_fallback=false
    grep -Fq 'npm pack codex-sdlc-wizard@latest' "$WINDOWS_E2E_RUNBOOK" 2>/dev/null && keeps_verified_checkout_fallback=false
    [ -f "$GIT_ATTRIBUTES" ] || enforces_lf_shell_checkouts=false
    grep -Eq '^\*\.sh[[:space:]]+text[[:space:]]+eol=lf[[:space:]]*$' "$GIT_ATTRIBUTES" 2>/dev/null || enforces_lf_shell_checkouts=false
    printf '%s\r\n' '*.sh text eol=lf' | grep -Eq '^\*\.sh[[:space:]]+text[[:space:]]+eol=lf[[:space:]]*$' || accepts_crlf_gitattributes=false
    grep -Eqi 'git .*archive.*HEAD|committed HEAD.*(export|archive)' "$WINDOWS_E2E_RUNBOOK" 2>/dev/null || enforces_lf_shell_checkouts=false
    grep -Eqi 'verified.*(extracted|package).*(bin[\\/]codex-sdlc-wizard\.js)|(bin[\\/]codex-sdlc-wizard\.js).*(verified|extracted)' "$WINDOWS_E2E_RUNBOOK" 2>/dev/null || executes_verified_package=false
    grep -Eq 'npx codex-sdlc-wizard@latest (setup|update|check)' "$WINDOWS_E2E_RUNBOOK" 2>/dev/null && executes_verified_package=false
    grep -Fq 'bash "<verified-plugin-root>/update.sh"' "$WINDOWS_E2E_RUNBOOK" 2>/dev/null || executes_verified_plugin_root=false
    grep -Fq 'bash "<verified-plugin-root>/check.sh"' "$WINDOWS_E2E_RUNBOOK" 2>/dev/null || executes_verified_plugin_root=false
    grep -Fq 'cygpath -u' "$WINDOWS_E2E_RUNBOOK" 2>/dev/null || converts_plugin_root_for_git_bash=false
    grep -Eqi 'npm fallback.*skip.*Phase 3|skip.*Phase 3.*npm fallback' "$WINDOWS_E2E_RUNBOOK" 2>/dev/null || branches_after_npx_fallback=false
    grep -Eqi 'hash every pre-existing (modified|untracked).*path|every pre-existing (modified|untracked).*hash' "$WINDOWS_E2E_RUNBOOK" 2>/dev/null || hashes_every_dirty_path=false
    grep -Eqi 'manifest-managed.*installer-targeted.*regardless of Git status|regardless of Git status.*manifest-managed.*installer-targeted' "$WINDOWS_E2E_RUNBOOK" 2>/dev/null || hashes_managed_and_installer_targets=false
    grep -Eqi 'preserved.*(may|can).*report.*match|customized.*drift.*manifest' "$WINDOWS_E2E_RUNBOOK" 2>/dev/null || separates_preservation_from_customized=false
    grep -Eqi 'uninitialized.*stop.*hook|uninitialized.*(wizard-named|existing).*hook.*stop|stop.*uninitialized.*hook' "$WINDOWS_E2E_RUNBOOK" 2>/dev/null || preflights_conflicting_hook_scripts=false
    grep -Eqi 'initialized.*(use|route|run).*update|update.*initialized' "$WINDOWS_E2E_RUNBOOK" 2>/dev/null || routes_initialized_repos_to_update=false
    grep -Eqi 'bash --version|Get-Command bash' "$WINDOWS_E2E_RUNBOOK" 2>/dev/null || preflights_bash_on_windows=false
    grep -Eqi 'CODEX_HOME.*(feedback|setup-wizard|update-wizard)|Codex-home.*skill' "$WINDOWS_E2E_RUNBOOK" 2>/dev/null || baselines_codex_home_skills=false
    grep -Eqi 'redact.*(every|all).*(warning|error|transcript|screenshot)|every.*(warning|error|transcript|screenshot).*redact' "$WINDOWS_E2E_RUNBOOK" 2>/dev/null || redacts_all_report_evidence=false
    grep -Eqi 'initialized.*verified.*update|verified.*update.*initialized' "$WINDOWS_E2E_RUNBOOK" 2>/dev/null || updates_initialized_verified_fallback=false
    grep -Eqi '(not installed|disabled|not enabled).*(Install|Enable)|(Install|Enable).*(not installed|disabled|not enabled)' "$WINDOWS_E2E_RUNBOOK" 2>/dev/null || enables_available_plugin=false
    grep -Fq 'skills\codex-sdlc-wizard' "$WINDOWS_E2E_RUNBOOK" 2>/dev/null || baselines_legacy_installer_migration=false
    grep -Fq 'skill-backups' "$WINDOWS_E2E_RUNBOOK" 2>/dev/null || baselines_legacy_installer_migration=false
    grep -Eqi 'bash-guard.*git-guard.*session-start.*compact-guard|compact-guard.*session-start.*git-guard.*bash-guard' "$WINDOWS_E2E_RUNBOOK" 2>/dev/null || preflights_all_hook_collisions_before_fallback=false
    grep -Eqi '/hooks.*(approved|active)|approved.*active.*hooks' "$WINDOWS_E2E_RUNBOOK" 2>/dev/null || requires_hook_approval=false
    grep -Eqi 'Codex CLI.*0\.144\.0|0\.144\.0.*Codex CLI' "$WINDOWS_E2E_RUNBOOK" 2>/dev/null || enforces_minimum_versions=false
    grep -Eqi 'Node(\.js)?.*18|18.*Node(\.js)?' "$WINDOWS_E2E_RUNBOOK" 2>/dev/null || enforces_minimum_versions=false
    grep -Eqi 'MINGW|MSYS|CYGWIN' "$WINDOWS_E2E_RUNBOOK" 2>/dev/null || distinguishes_git_bash_from_wsl=false
    bash_preflight_line="$(grep -n -m1 'Get-Command bash' "$WINDOWS_E2E_RUNBOOK" 2>/dev/null | cut -d: -f1 || true)"
    fallback_download_line="$(grep -n -m1 'npm pack "<verified-head-export>" --pack-destination' "$WINDOWS_E2E_RUNBOOK" 2>/dev/null | cut -d: -f1 || true)"
    if [ -z "$bash_preflight_line" ] || [ -z "$fallback_download_line" ] || [ "$bash_preflight_line" -ge "$fallback_download_line" ]; then
        preflights_bash_before_fallback_download=false
    fi
    grep -Eqi 'initialized.*preserve.*(selected|existing).*profile|(selected|existing).*profile.*preserve.*initialized' "$WINDOWS_E2E_RUNBOOK" 2>/dev/null || preserves_initialized_profile=false
    grep -Eqi '(plugin|wizard).*version.*(match|equal).*(package\.json|checkout)|(package\.json|checkout).*version.*(match|equal).*(plugin|wizard)' "$WINDOWS_E2E_RUNBOOK" 2>/dev/null || requires_current_plugin_version=false
    grep -Eqi '(stale|older|mismatch).*(npm fallback|stop)|(npm fallback|stop).*(stale|older|mismatch)' "$WINDOWS_E2E_RUNBOOK" 2>/dev/null || requires_current_plugin_version=false
    grep -Eq 'matching `[0-9]+\.[0-9]+\.[0-9]+` label' "$WINDOWS_E2E_RUNBOOK" 2>/dev/null && avoids_hardcoded_release_identity=false
    grep -Eqi 'maximum.*gpt-5\.6-sol.*high|gpt-5\.6-sol.*high.*maximum' "$WINDOWS_E2E_RUNBOOK" 2>/dev/null || validates_preserved_profile_driver=false
    grep -Eqi 'mixed.*gpt-5\.6-terra.*medium|gpt-5\.6-terra.*medium.*mixed' "$WINDOWS_E2E_RUNBOOK" 2>/dev/null || validates_preserved_profile_driver=false
    grep -Fq '.codex/hooks/git-guard.js' "$WINDOWS_E2E_RUNBOOK" 2>/dev/null || preflights_retired_hook_collisions=false
    grep -Fq '.codex/hooks/session-start.js' "$WINDOWS_E2E_RUNBOOK" 2>/dev/null || preflights_retired_hook_collisions=false
    grep -Eqi 'manifest.*exists.*invalid.*stop|stop.*manifest.*invalid' "$WINDOWS_E2E_RUNBOOK" 2>/dev/null || stops_on_invalid_manifest=false
    grep -Eqi 'hooks\.json.*invalid.*stop|stop.*hooks\.json.*invalid|validate.*hooks\.json.*before.*(setup|mutation)' "$WINDOWS_E2E_RUNBOOK" 2>/dev/null || stops_on_invalid_hooks_document=false
    grep -Eqi 'uninitialized.*stop.*model-profile|model-profile.*destructive collision' "$WINDOWS_E2E_RUNBOOK" 2>/dev/null || preflights_model_profile_collision=false
    grep -Eqi '(exact|all).*(hash|fingerprint).*(match|equal)|(match|equal).*(exact|all).*(hash|fingerprint)' "$WINDOWS_E2E_RUNBOOK" 2>/dev/null || fingerprints_exact_candidate_bundle=false
    grep -Eqi 'package\.json.*files|files.*package\.json' "$WINDOWS_E2E_RUNBOOK" 2>/dev/null || fingerprints_exact_candidate_bundle=false
    grep -Eqi '(every|complete|all).*(shipped|payload|package).*(file|path)|(shipped|payload|package).*(every|complete|all).*(file|path)' "$WINDOWS_E2E_RUNBOOK" 2>/dev/null || fingerprints_exact_candidate_bundle=false
    grep -Eqi 'CRLF.*LF|line endings?.*normaliz|normaliz.*line endings?' "$WINDOWS_E2E_RUNBOOK" 2>/dev/null || fingerprints_exact_candidate_bundle=false
    grep -Eqi '(reject|stop).*(CRLF|carriage return).*\.sh|\.sh.*(CRLF|carriage return).*(reject|stop)' "$WINDOWS_E2E_RUNBOOK" 2>/dev/null || rejects_crlf_shell_payloads=false
    grep -Eqi '\.sh.*(raw|unchanged|exact).*bytes|(raw|unchanged|exact).*bytes.*\.sh' "$WINDOWS_E2E_RUNBOOK" 2>/dev/null || rejects_crlf_shell_payloads=false
    grep -Eqi '\+codex.*(canonical|normaliz)|(canonical|normaliz).*\+codex' "$WINDOWS_E2E_RUNBOOK" 2>/dev/null || canonicalizes_generated_plugin_version=false
    grep -Eqi 'keep.*verified package.*(through|until).*Phase 4|verified package.*(through|until).*Phase 4' "$WINDOWS_E2E_RUNBOOK" 2>/dev/null || retains_verified_package_through_verification=false
    grep -Eqi 'restart|fresh.*session' "$WINDOWS_E2E_RUNBOOK" 2>/dev/null || requires_restart_and_sdlc=false
    grep -Fq '$sdlc' "$WINDOWS_E2E_RUNBOOK" 2>/dev/null || requires_restart_and_sdlc=false
    grep -Eqi 'GitHub-issue-ready|issue-ready' "$WINDOWS_E2E_RUNBOOK" 2>/dev/null || produces_issue_ready_report=false
    grep -Eqi 'installation path used:.*verified-package fallback' "$WINDOWS_E2E_RUNBOOK" 2>/dev/null || reports_verified_package_fallback=false
    grep -Eqi 'installation path used:.*npx fallback' "$WINDOWS_E2E_RUNBOOK" 2>/dev/null && reports_verified_package_fallback=false
    grep -Eqi 'do not commit.*push|do not.*(commit|push|tag|publish)' "$WINDOWS_E2E_RUNBOOK" 2>/dev/null || avoids_remote_mutation=false
    grep -Fq 'Get-Command codex' "$WINDOWS_E2E_RUNBOOK" 2>/dev/null || resolves_path_codex_binary=false
    grep -Eqi '0\.144\.0.*(resolved|PATH).*Codex CLI|(resolved|PATH).*Codex CLI.*0\.144\.0' "$WINDOWS_E2E_RUNBOOK" 2>/dev/null || resolves_path_codex_binary=false
    grep -Eqi 'bundled.*(version unavailable|version unobtainable|cannot be executed).*(do not fail|not.*failure)|do not fail.*bundled.*version' "$WINDOWS_E2E_RUNBOOK" 2>/dev/null || allows_unavailable_bundled_version=false
    grep -Eqi 'cmd /c del.*cmd /c rmdir|cmd /c rmdir.*cmd /c del' "$WINDOWS_E2E_RUNBOOK" 2>/dev/null || has_cleanup_fallback=false
    grep -Eqi 'before.*(enforc|validat).*model.*read.*model-profile|read.*model-profile.*before.*(enforc|validat).*model' "$WINDOWS_E2E_RUNBOOK" 2>/dev/null || handles_preupdate_profile_pin=false
    grep -Eqi 'run.*update.*(preserved|pinned|existing).*model|update.*under.*(preserved|pinned|existing).*model' "$WINDOWS_E2E_RUNBOOK" 2>/dev/null || handles_preupdate_profile_pin=false
    grep -Fq '.codex-sdlc/manifest.json' "$WINDOWS_E2E_RUNBOOK" 2>/dev/null || captures_manifest_and_retired_prompt_hook=false
    grep -Fq '.codex/hooks/sdlc-prompt-check.sh' "$WINDOWS_E2E_RUNBOOK" 2>/dev/null || captures_manifest_and_retired_prompt_hook=false
    grep -Eqi '(hooks|PreToolUse).*(enabled = false|enabled state|explicitly enabled)|(enabled = false|enabled state|explicitly enabled).*(hooks|PreToolUse)' "$WINDOWS_E2E_RUNBOOK" 2>/dev/null || requires_hook_enabled_state=false
    grep -Eqi 'exactly one repo(\-| )scoped.*\$sdlc|\$sdlc.*exactly one repo(\-| )scoped' "$WINDOWS_E2E_RUNBOOK" 2>/dev/null || requires_one_repo_scoped_sdlc=false
    grep -Eqi 'preserve.*user-owned global.*\$sdlc|user-owned global.*\$sdlc.*preserve' "$WINDOWS_E2E_RUNBOOK" 2>/dev/null || requires_one_repo_scoped_sdlc=false
    grep -Eqi '(feedback|setup-wizard|update-wizard).*(supported|expected).*(global|user-level)|(supported|expected).*(global|user-level).*(feedback|setup-wizard|update-wizard)' "$WINDOWS_E2E_RUNBOOK" 2>/dev/null || documents_supported_global_helpers=false
    grep -Eqi 'codex-sdlc-wizard.*plugin-owned|plugin-owned.*codex-sdlc-wizard' "$WINDOWS_E2E_RUNBOOK" 2>/dev/null || documents_supported_global_helpers=false

    if [ "$has_file" = "true" ] &&
       [ "$is_linked" = "true" ] &&
       [ "$identifies_real_install" = "true" ] &&
       [ "$protects_wizard_source" = "true" ] &&
       [ "$preserves_existing_work" = "true" ] &&
       [ "$prefers_plugin" = "true" ] &&
       [ "$keeps_verified_checkout_fallback" = "true" ] &&
       [ "$enforces_lf_shell_checkouts" = "true" ] &&
       [ "$accepts_crlf_gitattributes" = "true" ] &&
       [ "$executes_verified_package" = "true" ] &&
       [ "$executes_verified_plugin_root" = "true" ] &&
       [ "$converts_plugin_root_for_git_bash" = "true" ] &&
       [ "$branches_after_npx_fallback" = "true" ] &&
       [ "$hashes_every_dirty_path" = "true" ] &&
       [ "$hashes_managed_and_installer_targets" = "true" ] &&
       [ "$separates_preservation_from_customized" = "true" ] &&
       [ "$preflights_conflicting_hook_scripts" = "true" ] &&
       [ "$routes_initialized_repos_to_update" = "true" ] &&
       [ "$preflights_bash_on_windows" = "true" ] &&
       [ "$baselines_codex_home_skills" = "true" ] &&
       [ "$redacts_all_report_evidence" = "true" ] &&
       [ "$updates_initialized_verified_fallback" = "true" ] &&
       [ "$enables_available_plugin" = "true" ] &&
       [ "$baselines_legacy_installer_migration" = "true" ] &&
       [ "$preflights_all_hook_collisions_before_fallback" = "true" ] &&
       [ "$requires_hook_approval" = "true" ] &&
       [ "$enforces_minimum_versions" = "true" ] &&
       [ "$distinguishes_git_bash_from_wsl" = "true" ] &&
       [ "$preflights_bash_before_fallback_download" = "true" ] &&
       [ "$preserves_initialized_profile" = "true" ] &&
       [ "$requires_current_plugin_version" = "true" ] &&
       [ "$avoids_hardcoded_release_identity" = "true" ] &&
       [ "$validates_preserved_profile_driver" = "true" ] &&
       [ "$preflights_retired_hook_collisions" = "true" ] &&
       [ "$stops_on_invalid_manifest" = "true" ] &&
       [ "$stops_on_invalid_hooks_document" = "true" ] &&
       [ "$preflights_model_profile_collision" = "true" ] &&
       [ "$fingerprints_exact_candidate_bundle" = "true" ] &&
       [ "$rejects_crlf_shell_payloads" = "true" ] &&
       [ "$canonicalizes_generated_plugin_version" = "true" ] &&
       [ "$retains_verified_package_through_verification" = "true" ] &&
       [ "$reports_verified_package_fallback" = "true" ] &&
       [ "$requires_restart_and_sdlc" = "true" ] &&
       [ "$produces_issue_ready_report" = "true" ] &&
       [ "$avoids_remote_mutation" = "true" ] &&
       [ "$resolves_path_codex_binary" = "true" ] &&
       [ "$allows_unavailable_bundled_version" = "true" ] &&
       [ "$has_cleanup_fallback" = "true" ] &&
       [ "$handles_preupdate_profile_pin" = "true" ] &&
       [ "$captures_manifest_and_retired_prompt_hook" = "true" ] &&
       [ "$requires_hook_enabled_state" = "true" ] &&
       [ "$requires_one_repo_scoped_sdlc" = "true" ] &&
       [ "$documents_supported_global_helpers" = "true" ]; then
        pass "Windows Desktop runbook covers a safe real-repo install and issue-ready E2E report"
    else
        fail "Windows Desktop real-install E2E runbook is missing or incomplete"
    fi
}

test_installer_smoke_test_clean_project
test_installer_scaffolds_only_default_repo_scope_sdlc_skill
test_installer_uses_canonical_sdlc_skill_name
test_installer_writes_default_model_profile
test_installer_renders_explicit_mixed_baseline
test_installer_rejects_unsupported_codex_before_mutation
test_installer_rejects_missing_or_unqueryable_configured_codex_before_mutation
test_installer_rejects_minimum_version_prerelease_before_mutation
test_installer_recommends_current_codex_restart_resume
test_installer_prints_explicit_yolo_style_flags
test_installer_mentions_model_profile_tradeoff
test_installer_calls_out_auth_heavy_boundary
test_installer_offers_issue_ready_feedback_on_wizard_failure
test_readme_explains_distribution_model
test_repo_is_installable_skills_only_plugin
test_readme_documents_standalone_skill_migration
test_plugin_skill_documents_cross_surface_execution_boundary
test_readme_has_install_choice_table
test_readme_explains_install_side_effects
test_readme_mentions_packaging_test_command
test_readme_documents_optional_goals_contract
test_roadmap_is_the_single_project_backlog
test_readme_and_goals_template_document_goal_mode_with_sdlc
test_readme_recommends_full_auto
test_readme_stays_consumer_focused
test_readme_documents_repo_scope_skills
test_readme_documents_honest_codex_shape
test_readme_documents_current_codex_hook_surface
test_readme_documents_feedback_flow_and_repo_focus
test_readme_documents_model_profiles
test_readme_documents_native_codex_review
test_prove_it_documents_bounded_dual_review
test_readme_uses_real_release_examples
test_readme_puts_quick_start_near_the_top
test_readme_has_consumer_parity_sections_without_ecosystem_reveal
test_readme_documents_official_codex_distribution_status
test_sponsor_metadata_exists
test_consumer_bug_report_template_exists
test_windows_desktop_real_install_runbook_exists

echo ""
echo "=== Results: $PASSED passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
    exit 1
fi
