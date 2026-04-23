#!/bin/bash
# Adaptive setup — scans project, generates tailored docs, installs hooks
# Pure bash + jq. No API tokens needed.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Source dependencies
source "$SCRIPT_DIR/templates/domain-testing-sections.sh"

# ---- Parse args ----
AUTO_YES=false
FORCE=false
MODEL_PROFILE="mixed"
MODEL_PROFILE_SET=false
while [ $# -gt 0 ]; do
    case "$1" in
        --yes|-y) AUTO_YES=true ;;
        --force) FORCE=true ;;
        --model-profile)
            shift
            if [ $# -eq 0 ]; then
                echo "Missing value for --model-profile (expected: mixed or maximum)" >&2
                exit 1
            fi
            MODEL_PROFILE="$1"
            MODEL_PROFILE_SET=true
            ;;
        --model-profile=*)
            MODEL_PROFILE="${1#*=}"
            MODEL_PROFILE_SET=true
            ;;
    esac
    shift
done

case "$MODEL_PROFILE" in
    mixed|maximum) ;;
    *)
        echo "Unsupported model profile: $MODEL_PROFILE (expected: mixed or maximum)" >&2
        exit 1
        ;;
esac

# ---- Step 1: Scan project ----
echo "Scanning project..."
SCAN_JSON=$(cd "$(pwd)" && bash "$SCRIPT_DIR/lib/scan.sh")

# Extract scan values
LANGUAGE=$(echo "$SCAN_JSON" | jq -r '.language')
SOURCE_DIR=$(echo "$SCAN_JSON" | jq -r '.source_dir')
TEST_DIR=$(echo "$SCAN_JSON" | jq -r '.test_dir')
TEST_FRAMEWORK=$(echo "$SCAN_JSON" | jq -r '.test_framework')
TEST_COMMAND=$(echo "$SCAN_JSON" | jq -r '.test_command')
LINT_COMMAND=$(echo "$SCAN_JSON" | jq -r '.lint_command')
BUILD_COMMAND=$(echo "$SCAN_JSON" | jq -r '.build_command')
CI=$(echo "$SCAN_JSON" | jq -r '.ci')
DOMAIN=$(echo "$SCAN_JSON" | jq -r '.domain')
REPO_SHAPE=$(echo "$SCAN_JSON" | jq -r '.repo_shape')
CONFIDENCE_OVERALL=$(echo "$SCAN_JSON" | jq -r '.confidence_map.overall')
CONFIDENCE_KNOWN_SUMMARY=$(echo "$SCAN_JSON" | jq -r '.confidence_map.known | join("; ")')
CONFIDENCE_UNRESOLVED_SUMMARY=$(echo "$SCAN_JSON" | jq -r '.confidence_map.unresolved | join("; ")')

echo ""
echo "Detected:"
echo "  Language:       $LANGUAGE"
echo "  Source dir:     ${SOURCE_DIR:-<none>}"
echo "  Test dir:       ${TEST_DIR:-<none>}"
echo "  Test framework: ${TEST_FRAMEWORK:-<none>}"
echo "  Test command:   ${TEST_COMMAND:-<none>}"
echo "  Lint command:   ${LINT_COMMAND:-<none>}"
echo "  Build command:  ${BUILD_COMMAND:-<none>}"
echo "  CI:             ${CI:-<none>}"
echo "  Domain:         $DOMAIN"
echo "  Repo shape:     $REPO_SHAPE"
echo ""
echo "Confidence map:"
echo "  Overall:        $(printf '%s' "$CONFIDENCE_OVERALL" | tr '[:lower:]' '[:upper:]')"
echo "  Known:"
if echo "$SCAN_JSON" | jq -e '.confidence_map.known | length > 0' >/dev/null 2>&1; then
    echo "$SCAN_JSON" | jq -r '.confidence_map.known[] | "    - " + .'
else
    echo "    - none"
fi
echo "  Unresolved:"
if echo "$SCAN_JSON" | jq -e '.confidence_map.unresolved | length > 0' >/dev/null 2>&1; then
    echo "$SCAN_JSON" | jq -r '.confidence_map.unresolved[] | "    - " + .'
else
    echo "    - none"
fi
echo ""

# ---- Step 2: Confirm ----
if [ "$AUTO_YES" = "false" ]; then
    if [ "$MODEL_PROFILE_SET" = "false" ]; then
        read -rp "Model profile [mixed/maximum] (default: mixed): " model_choice
        case "$model_choice" in
            ""|mixed) MODEL_PROFILE="mixed" ;;
            maximum) MODEL_PROFILE="maximum" ;;
            *)
                echo "Unsupported model profile: $model_choice (expected: mixed or maximum)" >&2
                exit 1
                ;;
        esac
    fi
    read -rp "Proceed with setup? [Y/n] " confirm
    case "$confirm" in
        [nN]*) echo "Aborted."; exit 0 ;;
    esac
fi

# ---- Step 3: Generate docs from templates ----

# Helper: substitute {{MARKERS}} in a template
substitute_template() {
    local template="$1"
    sed \
        -e "s|{{LANGUAGE}}|${LANGUAGE}|g" \
        -e "s|{{SOURCE_DIR}}|${SOURCE_DIR:-N/A}|g" \
        -e "s|{{TEST_DIR}}|${TEST_DIR:-N/A}|g" \
        -e "s|{{TEST_FRAMEWORK}}|${TEST_FRAMEWORK:-N/A}|g" \
        -e "s|{{TEST_COMMAND}}|${TEST_COMMAND:-N/A}|g" \
        -e "s|{{LINT_COMMAND}}|${LINT_COMMAND:-N/A}|g" \
        -e "s|{{BUILD_COMMAND}}|${BUILD_COMMAND:-N/A}|g" \
        -e "s|{{CI}}|${CI:-N/A}|g" \
        -e "s|{{DOMAIN}}|${DOMAIN}|g" \
        -e "s|{{REPO_SHAPE}}|${REPO_SHAPE}|g" \
        -e "s|{{SETUP_CONFIDENCE}}|${CONFIDENCE_OVERALL}|g" \
        -e "s|{{SETUP_KNOWN_SUMMARY}}|${CONFIDENCE_KNOWN_SUMMARY:-none}|g" \
        -e "s|{{SETUP_UNRESOLVED_SUMMARY}}|${CONFIDENCE_UNRESOLVED_SUMMARY:-none}|g" \
        -e "s|{{MODEL_PROFILE}}|${MODEL_PROFILE}|g" \
        "$template"
}

# Generate AGENTS.md
generate_file() {
    local target="$1"
    local template="$2"
    local label="$3"

    if [ -f "$target" ] && [ "$FORCE" = "false" ]; then
        echo "$label exists — skipping (pass --force to overwrite)"
        return
    fi
    substitute_template "$template" > "$target"
    echo "Generated $label"
}

generate_file "AGENTS.md" "$SCRIPT_DIR/templates/AGENTS.md.tmpl" "AGENTS.md"
generate_file "ARCHITECTURE.md" "$SCRIPT_DIR/templates/ARCHITECTURE.md.tmpl" "ARCHITECTURE.md"

# TESTING.md needs domain section injection
generate_testing_md() {
    local target="TESTING.md"
    if [ -f "$target" ] && [ "$FORCE" = "false" ]; then
        echo "TESTING.md exists — skipping (pass --force to overwrite)"
        return
    fi

    local domain_section
    domain_section=$(get_domain_section "$DOMAIN")

    local content
    content=$(substitute_template "$SCRIPT_DIR/templates/TESTING.md.tmpl")

    # Replace {{DOMAIN_SECTION}} with the actual domain content
    # Use parameter expansion — simpler and more portable than sed r
    echo "${content//\{\{DOMAIN_SECTION\}\}/$domain_section}" > "$target"
    echo "Generated TESTING.md ($DOMAIN domain)"
}

generate_testing_md

# ---- Step 4: Run install.sh (hooks + config) ----
echo ""
bash "$SCRIPT_DIR/install.sh" --model-profile "$MODEL_PROFILE"

# ---- Step 5: Write manifest ----
mkdir -p .codex-sdlc

compute_hash() {
    if [ -f "$1" ]; then
        echo "sha256:$(shasum -a 256 "$1" | cut -d' ' -f1)"
    else
        echo ""
    fi
}

MANIFEST=".codex-sdlc/manifest.json"
ADAPTER_VERSION=$(cat "$SCRIPT_DIR/UPSTREAM_VERSION" 2>/dev/null | tr -d '[:space:]')

jq -n \
    --arg adapter_version "$ADAPTER_VERSION" \
    --arg installed_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg language "$LANGUAGE" \
    --arg domain "$DOMAIN" \
    --arg test_command "$TEST_COMMAND" \
    --arg repo_shape "$REPO_SHAPE" \
    --arg confidence_overall "$CONFIDENCE_OVERALL" \
    --argjson confidence_known "$(echo "$SCAN_JSON" | jq -c '.confidence_map.known')" \
    --argjson confidence_unresolved "$(echo "$SCAN_JSON" | jq -c '.confidence_map.unresolved')" \
    --arg model_profile "$MODEL_PROFILE" \
    --arg agents_hash "$(compute_hash AGENTS.md)" \
    --arg testing_hash "$(compute_hash TESTING.md)" \
    --arg arch_hash "$(compute_hash ARCHITECTURE.md)" \
    --arg model_profile_hash "$(compute_hash .codex-sdlc/model-profile.json)" \
    --arg hooks_json_hash "$(compute_hash .codex/hooks.json)" \
    --arg bash_guard_hash "$(compute_hash .codex/hooks/bash-guard.sh)" \
    --arg prompt_check_hash "$(compute_hash .codex/hooks/sdlc-prompt-check.sh)" \
    --arg session_start_hash "$(compute_hash .codex/hooks/session-start.sh)" \
    --arg sdlc_skill_hash "$(compute_hash .agents/skills/sdlc/SKILL.md)" \
    --arg adlc_skill_hash "$(compute_hash .agents/skills/adlc/SKILL.md)" \
    '{
        adapter_version: $adapter_version,
        installed_at: $installed_at,
        scan: {
            language: $language,
            domain: $domain,
            test_command: $test_command,
            repo_shape: $repo_shape
        },
        confidence_map: {
            overall: $confidence_overall,
            known: $confidence_known,
            unresolved: $confidence_unresolved
        },
        model_profile: {
            selected_profile: $model_profile
        },
        managed_files: {
            "AGENTS.md": $agents_hash,
            "TESTING.md": $testing_hash,
            "ARCHITECTURE.md": $arch_hash,
            ".codex-sdlc/model-profile.json": $model_profile_hash,
            ".codex/hooks.json": $hooks_json_hash,
            ".codex/hooks/bash-guard.sh": $bash_guard_hash,
            ".codex/hooks/sdlc-prompt-check.sh": $prompt_check_hash,
            ".codex/hooks/session-start.sh": $session_start_hash,
            ".agents/skills/sdlc/SKILL.md": $sdlc_skill_hash,
            ".agents/skills/adlc/SKILL.md": $adlc_skill_hash
        }
    }' > "$MANIFEST"

echo ""
echo "Created $MANIFEST"

# ---- Step 6: Verify ----
echo ""
echo "Verifying installation..."
ERRORS=0
for f in AGENTS.md TESTING.md ARCHITECTURE.md .codex/hooks.json .codex/config.toml .codex-sdlc/manifest.json .codex-sdlc/model-profile.json .agents/skills/sdlc/SKILL.md .agents/skills/adlc/SKILL.md; do
    if [ ! -f "$f" ]; then
        echo "  MISSING: $f"
        ERRORS=$((ERRORS + 1))
    fi
done

if [ "$ERRORS" -eq 0 ]; then
    echo "  All files present."
    echo ""
    echo "Setup complete. Trust this repo in Codex, then start with 'codex --full-auto'."
    echo "Use plain 'codex' instead if you want more manual confirmation."
    echo "Model profile: '$MODEL_PROFILE'."
    echo "  - mixed: gpt-5.4-mini main pass + gpt-5.4 xhigh review for better speed, lower latency, and lower token usage."
    echo "  - maximum: gpt-5.4 xhigh throughout for maximum stability and the most thorough \"ultimate mode\"."
    echo "If confidence drops below 95%, research more first. If it still stays below 95%, escalate review to xhigh."
    echo "Repo-scoped skills are still a work in progress. Today the supported public workflow skill is '\$sdlc'."
    echo "Future repo-scoped skills like 'gdlc' and 'rdlc' are planned next."
    echo "If a repo hits Windows / WAM / MFA sign-in, the live prompt remains user-owned in your session."
    echo "Let Codex handle the wrapped checks, then resume with the verify step after you complete sign-in."
    echo "For auth / license-sensitive repos, add a repo-local doctor / check-capability / Test-*Access helper."
    echo "Bias toward one-command classification instead of raw provider commands when account, license, or permission state decides the lane."
else
    echo ""
    echo "WARNING: $ERRORS file(s) missing — setup may be incomplete."
    exit 1
fi
