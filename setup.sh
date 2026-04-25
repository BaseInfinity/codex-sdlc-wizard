#!/bin/bash
# Adaptive setup — scans project, generates tailored docs, installs hooks
# Bash + Node. No API tokens needed.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Source dependencies
source "$SCRIPT_DIR/lib/json-node.sh"
source "$SCRIPT_DIR/templates/domain-testing-sections.sh"

require_node

setup_tmpfile() {
    mktemp "${TMPDIR:-/tmp}/codex-sdlc-$1.XXXXXX"
}

codex_reasoning_enabled() {
    [ "${CODEX_SDLC_DISABLE_REASONING:-0}" != "1" ] || return 1
    command -v codex >/dev/null 2>&1
}

refine_scan_with_codex() {
    local base_scan_json="$1"
    local base_scan_file=""
    local schema_file=""
    local output_file=""
    local prompt_file=""
    local refined_scan_json=""

    codex_reasoning_enabled || {
        printf '%s' "$base_scan_json"
        return 0
    }

    base_scan_file=$(setup_tmpfile scan.json)
    schema_file=$(setup_tmpfile schema.json)
    output_file=$(setup_tmpfile output.json)
    prompt_file=$(setup_tmpfile prompt.txt)

    printf '%s' "$base_scan_json" > "$base_scan_file"

    cat > "$schema_file" <<'EOF'
{
  "type": "object",
  "additionalProperties": false,
  "properties": {
    "language": { "type": "string" },
    "source_dir": { "type": "string" },
    "test_dir": { "type": "string" },
    "test_framework": { "type": "string" },
    "test_command": { "type": "string" },
    "lint_command": { "type": "string" },
    "typecheck_command": { "type": "string" },
    "single_test_command": { "type": "string" },
    "build_command": { "type": "string" },
    "deployment_setup": { "type": "string" },
    "databases": { "type": "string" },
    "cache_layer": { "type": "string" },
    "test_duration": { "type": "string" },
    "test_types": { "type": "string" },
    "coverage_config": { "type": "string" },
    "ci": { "type": "string" },
    "domain": { "type": "string" },
    "confidence_map": {
      "type": "object",
      "additionalProperties": false,
      "properties": {
        "source_dir": { "type": "string", "enum": ["detected", "inferred", "unresolved"] },
        "test_dir": { "type": "string", "enum": ["detected", "inferred", "unresolved"] },
        "test_framework": { "type": "string", "enum": ["detected", "inferred", "unresolved"] },
        "test_command": { "type": "string", "enum": ["detected", "inferred", "unresolved"] },
        "lint_command": { "type": "string", "enum": ["detected", "inferred", "unresolved"] },
        "typecheck_command": { "type": "string", "enum": ["detected", "inferred", "unresolved"] },
        "single_test_command": { "type": "string", "enum": ["detected", "inferred", "unresolved"] },
        "build_command": { "type": "string", "enum": ["detected", "inferred", "unresolved"] },
        "deployment_setup": { "type": "string", "enum": ["detected", "inferred", "unresolved"] },
        "databases": { "type": "string", "enum": ["detected", "inferred", "unresolved"] },
        "cache_layer": { "type": "string", "enum": ["detected", "inferred", "unresolved"] },
        "test_duration": { "type": "string", "enum": ["detected", "inferred", "unresolved"] },
        "test_types": { "type": "string", "enum": ["detected", "inferred", "unresolved"] },
        "coverage_config": { "type": "string", "enum": ["detected", "inferred", "unresolved"] },
        "ci": { "type": "string", "enum": ["detected", "inferred", "unresolved"] },
        "domain": { "type": "string", "enum": ["detected", "inferred", "unresolved"] }
      }
    }
  }
}
EOF

    cat > "$prompt_file" <<EOF
You are refining repository setup detection for the Codex SDLC wizard.
Inspect the current working tree in read-only mode and improve the baseline scan below.
Return JSON only, following the provided schema exactly.

Baseline scan:
$base_scan_json

Rules:
- Prefer concrete repository evidence over the baseline when they disagree.
- Use empty strings for unknown values.
- Provide confidence_map entries using only detected, inferred, or unresolved.
- Do not invent tools, frameworks, or commands that the repo does not support.
EOF

    if codex exec \
        -s read-only \
        --skip-git-repo-check \
        --ignore-rules \
        --ephemeral \
        --output-schema "$schema_file" \
        -o "$output_file" \
        -c 'model="gpt-5.4"' \
        -c 'model_reasoning_effort="xhigh"' \
        "$(cat "$prompt_file")" >/dev/null 2>&1; then
        if json_has_truthy_file "$output_file" 'typeof data === "object" && data !== null && !Array.isArray(data)'; then
            refined_scan_json=$(BASE_SCAN_FILE="$base_scan_file" REFINED_SCAN_FILE="$output_file" node -e '
const fs = require("fs");
const base = JSON.parse(fs.readFileSync(process.env.BASE_SCAN_FILE, "utf8"));
const refined = JSON.parse(fs.readFileSync(process.env.REFINED_SCAN_FILE, "utf8"));
const fields = [
  "language",
  "source_dir",
  "test_dir",
  "test_framework",
  "test_command",
  "lint_command",
  "typecheck_command",
  "single_test_command",
  "build_command",
  "deployment_setup",
  "databases",
  "cache_layer",
  "test_duration",
  "test_types",
  "coverage_config",
  "ci",
  "domain"
];
const merged = { ...base };
for (const field of fields) {
  if (typeof refined[field] === "string") {
    merged[field] = refined[field];
  }
}
if (refined.confidence_map && typeof refined.confidence_map === "object" && !Array.isArray(refined.confidence_map)) {
  const confidenceMap = {};
  for (const field of fields) {
    const value = refined.confidence_map[field];
    if (value === "detected" || value === "inferred" || value === "unresolved") {
      confidenceMap[field] = value;
    }
  }
  if (Object.keys(confidenceMap).length > 0) {
    merged.confidence_map = confidenceMap;
  }
}
process.stdout.write(JSON.stringify(merged));
' 2>/dev/null || true)
        fi
    fi

    rm -f "$base_scan_file" "$schema_file" "$output_file" "$prompt_file"

    if [ -n "$refined_scan_json" ]; then
        printf '%s' "$refined_scan_json"
    else
        printf '%s' "$base_scan_json"
    fi
}

preferred_state() {
    local override="$1"
    local fallback="$2"

    if [ -n "$override" ]; then
        printf '%s' "$override"
    else
        printf '%s' "$fallback"
    fi
}

verify_installation() {
    local errors=0

    echo ""
    echo "Verifying installation..."
    for f in AGENTS.md SDLC.md TESTING.md ARCHITECTURE.md .codex/hooks.json .codex/config.toml .codex-sdlc/manifest.json .codex-sdlc/model-profile.json .agents/skills/sdlc/SKILL.md .agents/skills/adlc/SKILL.md; do
        if [ ! -f "$f" ]; then
            echo "  MISSING: $f"
            errors=$((errors + 1))
        fi
    done

    if [ "$errors" -eq 0 ]; then
        echo "  All files present."
        echo ""
        echo "Setup complete. Trust this repo in Codex, then run 'codex --full-auto' for low-friction SDLC."
        echo "If you are continuing an interrupted Codex handoff and have a resume id, use 'codex resume --full-auto'."
        return 0
    fi

    echo ""
    echo "WARNING: $errors file(s) missing — setup may be incomplete."
    return 1
}

load_regenerate_state() {
    local manifest=".codex-sdlc/manifest.json"

    if [ ! -f "$manifest" ]; then
        echo "Error: $manifest is required for regenerate mode." >&2
        return 1
    fi

    LANGUAGE=$(json_get_file "$manifest" 'data.scan?.language || ""')
    SOURCE_DIR=$(json_get_file "$manifest" 'data.resolved_values?.source_dir || data.scan?.source_dir || ""')
    TEST_DIR=$(json_get_file "$manifest" 'data.resolved_values?.test_dir || data.scan?.test_dir || ""')
    TEST_FRAMEWORK=$(json_get_file "$manifest" 'data.resolved_values?.test_framework || data.scan?.test_framework || ""')
    TEST_COMMAND=$(json_get_file "$manifest" 'data.resolved_values?.test_command || data.scan?.test_command || ""')
    LINT_COMMAND=$(json_get_file "$manifest" 'data.resolved_values?.lint_command || data.scan?.lint_command || ""')
    TYPECHECK_COMMAND=$(json_get_file "$manifest" 'data.resolved_values?.typecheck_command || data.scan?.typecheck_command || ""')
    SINGLE_TEST_COMMAND=$(json_get_file "$manifest" 'data.resolved_values?.single_test_command || data.scan?.single_test_command || ""')
    BUILD_COMMAND=$(json_get_file "$manifest" 'data.resolved_values?.build_command || data.scan?.build_command || ""')
    DEPLOYMENT_SETUP=$(json_get_file "$manifest" 'data.resolved_values?.deployment_setup || data.scan?.deployment_setup || ""')
    DATABASES=$(json_get_file "$manifest" 'data.resolved_values?.databases || data.scan?.databases || ""')
    CACHE_LAYER=$(json_get_file "$manifest" 'data.resolved_values?.cache_layer || data.scan?.cache_layer || ""')
    TEST_DURATION=$(json_get_file "$manifest" 'data.resolved_values?.test_duration || data.scan?.test_duration || ""')
    TEST_TYPES=$(json_get_file "$manifest" 'data.resolved_values?.test_types || data.scan?.test_types || ""')
    COVERAGE_CONFIG=$(json_get_file "$manifest" 'data.resolved_values?.coverage_config || data.scan?.coverage_config || ""')
    CI=$(json_get_file "$manifest" 'data.resolved_values?.ci || data.scan?.ci || ""')
    DOMAIN=$(json_get_file "$manifest" 'data.resolved_values?.domain || data.scan?.domain || "web"')

    SCAN_SOURCE_DIR_RAW=$(json_get_file "$manifest" 'data.scan?.source_dir || ""')
    SCAN_TEST_DIR_RAW=$(json_get_file "$manifest" 'data.scan?.test_dir || ""')
    SCAN_TEST_FRAMEWORK_RAW=$(json_get_file "$manifest" 'data.scan?.test_framework || ""')
    SCAN_TEST_COMMAND_RAW=$(json_get_file "$manifest" 'data.scan?.test_command || ""')
    SCAN_LINT_COMMAND_RAW=$(json_get_file "$manifest" 'data.scan?.lint_command || ""')
    SCAN_TYPECHECK_COMMAND_RAW=$(json_get_file "$manifest" 'data.scan?.typecheck_command || ""')
    SCAN_SINGLE_TEST_COMMAND_RAW=$(json_get_file "$manifest" 'data.scan?.single_test_command || ""')
    SCAN_BUILD_COMMAND_RAW=$(json_get_file "$manifest" 'data.scan?.build_command || ""')
    SCAN_DEPLOYMENT_SETUP_RAW=$(json_get_file "$manifest" 'data.scan?.deployment_setup || ""')
    SCAN_DATABASES_RAW=$(json_get_file "$manifest" 'data.scan?.databases || ""')
    SCAN_CACHE_LAYER_RAW=$(json_get_file "$manifest" 'data.scan?.cache_layer || ""')
    SCAN_TEST_DURATION_RAW=$(json_get_file "$manifest" 'data.scan?.test_duration || ""')
    SCAN_TEST_TYPES_RAW=$(json_get_file "$manifest" 'data.scan?.test_types || ""')
    SCAN_COVERAGE_CONFIG_RAW=$(json_get_file "$manifest" 'data.scan?.coverage_config || ""')
    SCAN_CI_RAW=$(json_get_file "$manifest" 'data.scan?.ci || ""')
    SCAN_DOMAIN_RAW=$(json_get_file "$manifest" 'data.scan?.domain || ""')

    ADAPTER_VERSION=$(cat "$SCRIPT_DIR/UPSTREAM_VERSION" 2>/dev/null | tr -d '[:space:]')
    [ -z "$ADAPTER_VERSION" ] && ADAPTER_VERSION=$(json_get_file "$manifest" 'data.adapter_version || ""')
    INSTALLED_AT_VALUE=$(json_get_file "$manifest" 'data.installed_at || ""')
    [ -z "$INSTALLED_AT_VALUE" ] && INSTALLED_AT_VALUE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    SETUP_DATE="${INSTALLED_AT_VALUE%%T*}"
    COMPLETED_STEPS="step-0.4, step-1, step-9"
    GIT_WORKFLOW=$(json_get_file "$manifest" 'data.setup_answers?.git_workflow || "solo"')
    RESPONSE_DETAIL=$(json_get_file "$manifest" 'data.setup_answers?.response_detail || "concise"')
    TESTING_APPROACH=$(json_get_file "$manifest" 'data.setup_answers?.testing_approach || "strict-tdd"')
    MOCKING_PHILOSOPHY=$(json_get_file "$manifest" 'data.setup_answers?.mocking_philosophy || "minimal"')
    CI_SHEPHERD=$(json_get_file "$manifest" 'data.setup_answers?.ci_shepherd || "disabled"')
    MODEL_PROFILE=$(json_get_file "$manifest" 'data.model_profile?.selected_profile || ""')
    [ -n "$MODEL_PROFILE" ] || MODEL_PROFILE=$(json_get_file ".codex-sdlc/model-profile.json" 'data.selected_profile || ""')
    [ -n "$MODEL_PROFILE" ] || MODEL_PROFILE="maximum"
    MODEL_PROFILE_SET=true

    SOURCE_DIR_STATE=$(json_get_file "$manifest" 'data.confidence_map?.source_dir || ""')
    TEST_DIR_STATE=$(json_get_file "$manifest" 'data.confidence_map?.test_dir || ""')
    TEST_FRAMEWORK_STATE=$(json_get_file "$manifest" 'data.confidence_map?.test_framework || ""')
    TEST_COMMAND_STATE=$(json_get_file "$manifest" 'data.confidence_map?.test_command || ""')
    LINT_COMMAND_STATE=$(json_get_file "$manifest" 'data.confidence_map?.lint_command || ""')
    TYPECHECK_COMMAND_STATE=$(json_get_file "$manifest" 'data.confidence_map?.typecheck_command || ""')
    SINGLE_TEST_COMMAND_STATE=$(json_get_file "$manifest" 'data.confidence_map?.single_test_command || ""')
    BUILD_COMMAND_STATE=$(json_get_file "$manifest" 'data.confidence_map?.build_command || ""')
    DEPLOYMENT_SETUP_STATE=$(json_get_file "$manifest" 'data.confidence_map?.deployment_setup || ""')
    DATABASES_STATE=$(json_get_file "$manifest" 'data.confidence_map?.databases || ""')
    CACHE_LAYER_STATE=$(json_get_file "$manifest" 'data.confidence_map?.cache_layer || ""')
    TEST_DURATION_STATE=$(json_get_file "$manifest" 'data.confidence_map?.test_duration || ""')
    TEST_TYPES_STATE=$(json_get_file "$manifest" 'data.confidence_map?.test_types || ""')
    COVERAGE_CONFIG_STATE=$(json_get_file "$manifest" 'data.confidence_map?.coverage_config || ""')
    CI_STATE=$(json_get_file "$manifest" 'data.confidence_map?.ci || ""')
    DOMAIN_STATE=$(json_get_file "$manifest" 'data.confidence_map?.domain || ""')

    [ -n "$SOURCE_DIR_STATE" ] || SOURCE_DIR_STATE=$([ -n "$SOURCE_DIR" ] && printf 'detected' || printf 'unresolved')
    [ -n "$TEST_DIR_STATE" ] || TEST_DIR_STATE=$([ -n "$TEST_DIR" ] && printf 'detected' || printf 'unresolved')
    [ -n "$TEST_FRAMEWORK_STATE" ] || TEST_FRAMEWORK_STATE=$([ -n "$TEST_FRAMEWORK" ] && printf 'detected' || printf 'unresolved')
    [ -n "$TEST_COMMAND_STATE" ] || TEST_COMMAND_STATE=$([ -n "$TEST_COMMAND" ] && printf 'detected' || printf 'unresolved')
    [ -n "$LINT_COMMAND_STATE" ] || LINT_COMMAND_STATE=$([ -n "$LINT_COMMAND" ] && printf 'detected' || printf 'unresolved')
    [ -n "$TYPECHECK_COMMAND_STATE" ] || TYPECHECK_COMMAND_STATE=$([ -n "$TYPECHECK_COMMAND" ] && printf 'detected' || printf 'unresolved')
    [ -n "$SINGLE_TEST_COMMAND_STATE" ] || SINGLE_TEST_COMMAND_STATE=$([ -n "$SINGLE_TEST_COMMAND" ] && printf 'inferred' || printf 'unresolved')
    [ -n "$BUILD_COMMAND_STATE" ] || BUILD_COMMAND_STATE=$([ -n "$BUILD_COMMAND" ] && printf 'detected' || printf 'unresolved')
    [ -n "$DEPLOYMENT_SETUP_STATE" ] || DEPLOYMENT_SETUP_STATE=$([ -n "$DEPLOYMENT_SETUP" ] && printf 'detected' || printf 'unresolved')
    [ -n "$DATABASES_STATE" ] || DATABASES_STATE=$([ -n "$DATABASES" ] && printf 'detected' || printf 'unresolved')
    [ -n "$CACHE_LAYER_STATE" ] || CACHE_LAYER_STATE=$([ -n "$CACHE_LAYER" ] && printf 'detected' || printf 'unresolved')
    [ -n "$TEST_DURATION_STATE" ] || TEST_DURATION_STATE=$([ -n "$TEST_DURATION" ] && printf 'inferred' || printf 'unresolved')
    [ -n "$TEST_TYPES_STATE" ] || TEST_TYPES_STATE=$([ -n "$TEST_TYPES" ] && printf 'detected' || printf 'unresolved')
    [ -n "$COVERAGE_CONFIG_STATE" ] || COVERAGE_CONFIG_STATE=$([ -n "$COVERAGE_CONFIG" ] && printf 'detected' || printf 'unresolved')
    [ -n "$CI_STATE" ] || CI_STATE=$([ -n "$CI" ] && printf 'detected' || printf 'unresolved')
    [ -n "$DOMAIN_STATE" ] || DOMAIN_STATE=$([ "$DOMAIN" = "web" ] && printf 'inferred' || printf 'detected')

    return 0
}

# ---- Parse args ----
AUTO_YES=false
FORCE=false
SETUP_MODE="normal"
MODEL_PROFILE="maximum"
MODEL_PROFILE_SET=false
while [ $# -gt 0 ]; do
    case "$1" in
        --yes|-y) AUTO_YES=true ;;
        --force) FORCE=true ;;
        regenerate) SETUP_MODE="regenerate" ;;
        verify-only) SETUP_MODE="verify-only" ;;
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

if [ "$SETUP_MODE" = "verify-only" ]; then
    verify_installation
    exit $?
fi

# ---- Step 1: Scan project ----
if [ "$SETUP_MODE" = "regenerate" ]; then
    echo "Regenerating setup docs from .codex-sdlc/manifest.json..."
    load_regenerate_state
else
    echo "Scanning project..."
    SCAN_JSON=$(cd "$(pwd)" && bash "$SCRIPT_DIR/lib/scan.sh")
    SCAN_JSON=$(refine_scan_with_codex "$SCAN_JSON")

    # Extract scan values
    LANGUAGE=$(printf '%s' "$SCAN_JSON" | json_get_stdin 'data.language')
    SOURCE_DIR=$(printf '%s' "$SCAN_JSON" | json_get_stdin 'data.source_dir')
    TEST_DIR=$(printf '%s' "$SCAN_JSON" | json_get_stdin 'data.test_dir')
    TEST_FRAMEWORK=$(printf '%s' "$SCAN_JSON" | json_get_stdin 'data.test_framework')
    TEST_COMMAND=$(printf '%s' "$SCAN_JSON" | json_get_stdin 'data.test_command')
    LINT_COMMAND=$(printf '%s' "$SCAN_JSON" | json_get_stdin 'data.lint_command')
    TYPECHECK_COMMAND=$(printf '%s' "$SCAN_JSON" | json_get_stdin 'data.typecheck_command')
    SINGLE_TEST_COMMAND=$(printf '%s' "$SCAN_JSON" | json_get_stdin 'data.single_test_command')
    BUILD_COMMAND=$(printf '%s' "$SCAN_JSON" | json_get_stdin 'data.build_command')
    DEPLOYMENT_SETUP=$(printf '%s' "$SCAN_JSON" | json_get_stdin 'data.deployment_setup')
    DATABASES=$(printf '%s' "$SCAN_JSON" | json_get_stdin 'data.databases')
    CACHE_LAYER=$(printf '%s' "$SCAN_JSON" | json_get_stdin 'data.cache_layer')
    TEST_DURATION=$(printf '%s' "$SCAN_JSON" | json_get_stdin 'data.test_duration')
    TEST_TYPES=$(printf '%s' "$SCAN_JSON" | json_get_stdin 'data.test_types')
    COVERAGE_CONFIG=$(printf '%s' "$SCAN_JSON" | json_get_stdin 'data.coverage_config')
    CI=$(printf '%s' "$SCAN_JSON" | json_get_stdin 'data.ci')
    DOMAIN=$(printf '%s' "$SCAN_JSON" | json_get_stdin 'data.domain')
    SCAN_SOURCE_DIR_RAW="$SOURCE_DIR"
    SCAN_TEST_DIR_RAW="$TEST_DIR"
    SCAN_TEST_FRAMEWORK_RAW="$TEST_FRAMEWORK"
    SCAN_TEST_COMMAND_RAW="$TEST_COMMAND"
    SCAN_LINT_COMMAND_RAW="$LINT_COMMAND"
    SCAN_TYPECHECK_COMMAND_RAW="$TYPECHECK_COMMAND"
    SCAN_SINGLE_TEST_COMMAND_RAW="$SINGLE_TEST_COMMAND"
    SCAN_BUILD_COMMAND_RAW="$BUILD_COMMAND"
    SCAN_DEPLOYMENT_SETUP_RAW="$DEPLOYMENT_SETUP"
    SCAN_DATABASES_RAW="$DATABASES"
    SCAN_CACHE_LAYER_RAW="$CACHE_LAYER"
    SCAN_TEST_DURATION_RAW="$TEST_DURATION"
    SCAN_TEST_TYPES_RAW="$TEST_TYPES"
    SCAN_COVERAGE_CONFIG_RAW="$COVERAGE_CONFIG"
    SCAN_CI_RAW="$CI"
    SCAN_DOMAIN_RAW="$DOMAIN"
    SCAN_SOURCE_DIR_STATE_OVERRIDE=$(printf '%s' "$SCAN_JSON" | json_get_stdin 'data.confidence_map?.source_dir || ""')
    SCAN_TEST_DIR_STATE_OVERRIDE=$(printf '%s' "$SCAN_JSON" | json_get_stdin 'data.confidence_map?.test_dir || ""')
    SCAN_TEST_FRAMEWORK_STATE_OVERRIDE=$(printf '%s' "$SCAN_JSON" | json_get_stdin 'data.confidence_map?.test_framework || ""')
    SCAN_TEST_COMMAND_STATE_OVERRIDE=$(printf '%s' "$SCAN_JSON" | json_get_stdin 'data.confidence_map?.test_command || ""')
    SCAN_LINT_COMMAND_STATE_OVERRIDE=$(printf '%s' "$SCAN_JSON" | json_get_stdin 'data.confidence_map?.lint_command || ""')
    SCAN_TYPECHECK_COMMAND_STATE_OVERRIDE=$(printf '%s' "$SCAN_JSON" | json_get_stdin 'data.confidence_map?.typecheck_command || ""')
    SCAN_SINGLE_TEST_COMMAND_STATE_OVERRIDE=$(printf '%s' "$SCAN_JSON" | json_get_stdin 'data.confidence_map?.single_test_command || ""')
    SCAN_BUILD_COMMAND_STATE_OVERRIDE=$(printf '%s' "$SCAN_JSON" | json_get_stdin 'data.confidence_map?.build_command || ""')
    SCAN_DEPLOYMENT_SETUP_STATE_OVERRIDE=$(printf '%s' "$SCAN_JSON" | json_get_stdin 'data.confidence_map?.deployment_setup || ""')
    SCAN_DATABASES_STATE_OVERRIDE=$(printf '%s' "$SCAN_JSON" | json_get_stdin 'data.confidence_map?.databases || ""')
    SCAN_CACHE_LAYER_STATE_OVERRIDE=$(printf '%s' "$SCAN_JSON" | json_get_stdin 'data.confidence_map?.cache_layer || ""')
    SCAN_TEST_DURATION_STATE_OVERRIDE=$(printf '%s' "$SCAN_JSON" | json_get_stdin 'data.confidence_map?.test_duration || ""')
    SCAN_TEST_TYPES_STATE_OVERRIDE=$(printf '%s' "$SCAN_JSON" | json_get_stdin 'data.confidence_map?.test_types || ""')
    SCAN_COVERAGE_CONFIG_STATE_OVERRIDE=$(printf '%s' "$SCAN_JSON" | json_get_stdin 'data.confidence_map?.coverage_config || ""')
    SCAN_CI_STATE_OVERRIDE=$(printf '%s' "$SCAN_JSON" | json_get_stdin 'data.confidence_map?.ci || ""')
    SCAN_DOMAIN_STATE_OVERRIDE=$(printf '%s' "$SCAN_JSON" | json_get_stdin 'data.confidence_map?.domain || ""')
    ADAPTER_VERSION=$(cat "$SCRIPT_DIR/UPSTREAM_VERSION" 2>/dev/null | tr -d '[:space:]')
    INSTALLED_AT_VALUE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    SETUP_DATE=$(date -u +%Y-%m-%d)
    COMPLETED_STEPS="step-0.4, step-1, step-9"
    GIT_WORKFLOW="solo"
    RESPONSE_DETAIL="concise"
    TESTING_APPROACH="strict-tdd"
    MOCKING_PHILOSOPHY="minimal"
    CI_SHEPHERD="disabled"
fi

package_script_exists() {
    local script_name="$1"

    if [ ! -f "package.json" ]; then
        return 1
    fi

    json_get_file "package.json" "typeof data.scripts?.[\"$script_name\"] === \"string\" ? data.scripts[\"$script_name\"] : \"\"" | grep -q .
}

package_script_matches() {
    local script_name="$1"
    local pattern="$2"

    if [ ! -f "package.json" ]; then
        return 1
    fi

    json_get_file "package.json" "typeof data.scripts?.[\"$script_name\"] === \"string\" ? data.scripts[\"$script_name\"] : \"\"" | grep -Eqi -- "$pattern"
}

test_framework_state() {
    if [ -z "$TEST_FRAMEWORK" ]; then
        printf 'unresolved'
    elif ls jest.config.* 2>/dev/null | head -1 | grep -q . \
        || ls vitest.config.* 2>/dev/null | head -1 | grep -q . \
        || [ -f "pytest.ini" ] \
        || [ -f ".rspec" ] \
        || [ -f "Cargo.toml" ] \
        || [ -f "go.mod" ]; then
        printf 'detected'
    else
        printf 'inferred'
    fi
}

test_command_state() {
    if [ -z "$TEST_COMMAND" ]; then
        printf 'unresolved'
    elif package_script_exists "test"; then
        printf 'detected'
    else
        printf 'inferred'
    fi
}

lint_command_state() {
    if [ -z "$LINT_COMMAND" ]; then
        printf 'unresolved'
    elif package_script_exists "lint"; then
        printf 'detected'
    else
        printf 'inferred'
    fi
}

typecheck_command_state() {
    if [ -z "$TYPECHECK_COMMAND" ]; then
        printf 'unresolved'
    elif package_script_exists "typecheck" || package_script_exists "check-types" \
        || [ -f "tsconfig.json" ] \
        || [ -f "mypy.ini" ] \
        || { [ -f "pyproject.toml" ] && grep -q "mypy" "pyproject.toml" 2>/dev/null; } \
        || [ -f "Cargo.toml" ]; then
        printf 'detected'
    else
        printf 'inferred'
    fi
}

single_test_command_state() {
    if [ -z "$SINGLE_TEST_COMMAND" ]; then
        printf 'unresolved'
    else
        printf 'inferred'
    fi
}

build_command_state() {
    if [ -z "$BUILD_COMMAND" ]; then
        printf 'unresolved'
    elif package_script_exists "build" || [ -f "Makefile" ] || [ -f "Cargo.toml" ] || [ -f "go.mod" ]; then
        printf 'detected'
    else
        printf 'inferred'
    fi
}

deployment_setup_state() {
    if [ -z "$DEPLOYMENT_SETUP" ]; then
        printf 'unresolved'
    else
        printf 'detected'
    fi
}

databases_state() {
    if [ -z "$DATABASES" ]; then
        printf 'unresolved'
    else
        printf 'detected'
    fi
}

cache_layer_state() {
    if [ -z "$CACHE_LAYER" ]; then
        printf 'unresolved'
    else
        printf 'detected'
    fi
}

test_duration_state() {
    if [ -z "$TEST_DURATION" ]; then
        printf 'unresolved'
    else
        printf 'inferred'
    fi
}

test_types_state() {
    if [ -z "$TEST_TYPES" ]; then
        printf 'unresolved'
    else
        printf 'detected'
    fi
}

coverage_config_state() {
    if [ -z "$COVERAGE_CONFIG" ]; then
        printf 'unresolved'
    elif package_script_exists "coverage" || package_script_matches "test" '--coverage' \
        || ls .nycrc* 2>/dev/null | head -1 | grep -q . \
        || [ -f "coverage.py" ] \
        || [ -f ".coveragerc" ] \
        || { [ -f "pyproject.toml" ] && grep -q "pytest-cov" "pyproject.toml" 2>/dev/null; }; then
        printf 'detected'
    else
        printf 'inferred'
    fi
}

domain_state() {
    if [ "$DOMAIN" = "web" ]; then
        printf 'inferred'
    else
        printf 'detected'
    fi
}

if [ "$SETUP_MODE" != "regenerate" ]; then
    SOURCE_DIR_STATE=$(preferred_state "${SCAN_SOURCE_DIR_STATE_OVERRIDE:-}" "$([ -n "$SOURCE_DIR" ] && printf 'detected' || printf 'unresolved')")
    TEST_DIR_STATE=$(preferred_state "${SCAN_TEST_DIR_STATE_OVERRIDE:-}" "$([ -n "$TEST_DIR" ] && printf 'detected' || printf 'unresolved')")
    TEST_FRAMEWORK_STATE=$(preferred_state "${SCAN_TEST_FRAMEWORK_STATE_OVERRIDE:-}" "$(test_framework_state)")
    TEST_COMMAND_STATE=$(preferred_state "${SCAN_TEST_COMMAND_STATE_OVERRIDE:-}" "$(test_command_state)")
    LINT_COMMAND_STATE=$(preferred_state "${SCAN_LINT_COMMAND_STATE_OVERRIDE:-}" "$(lint_command_state)")
    TYPECHECK_COMMAND_STATE=$(preferred_state "${SCAN_TYPECHECK_COMMAND_STATE_OVERRIDE:-}" "$(typecheck_command_state)")
    SINGLE_TEST_COMMAND_STATE=$(preferred_state "${SCAN_SINGLE_TEST_COMMAND_STATE_OVERRIDE:-}" "$(single_test_command_state)")
    BUILD_COMMAND_STATE=$(preferred_state "${SCAN_BUILD_COMMAND_STATE_OVERRIDE:-}" "$(build_command_state)")
    DEPLOYMENT_SETUP_STATE=$(preferred_state "${SCAN_DEPLOYMENT_SETUP_STATE_OVERRIDE:-}" "$(deployment_setup_state)")
    DATABASES_STATE=$(preferred_state "${SCAN_DATABASES_STATE_OVERRIDE:-}" "$(databases_state)")
    CACHE_LAYER_STATE=$(preferred_state "${SCAN_CACHE_LAYER_STATE_OVERRIDE:-}" "$(cache_layer_state)")
    TEST_DURATION_STATE=$(preferred_state "${SCAN_TEST_DURATION_STATE_OVERRIDE:-}" "$(test_duration_state)")
    TEST_TYPES_STATE=$(preferred_state "${SCAN_TEST_TYPES_STATE_OVERRIDE:-}" "$(test_types_state)")
    COVERAGE_CONFIG_STATE=$(preferred_state "${SCAN_COVERAGE_CONFIG_STATE_OVERRIDE:-}" "$(coverage_config_state)")
    CI_STATE=$(preferred_state "${SCAN_CI_STATE_OVERRIDE:-}" "$([ -n "$CI" ] && printf 'detected' || printf 'unresolved')")
    DOMAIN_STATE=$(preferred_state "${SCAN_DOMAIN_STATE_OVERRIDE:-}" "$(domain_state)")
fi

echo ""
if [ "$SETUP_MODE" = "regenerate" ]; then
    echo "Loaded setup state:"
else
    echo "Detected:"
fi
echo "  Language:       $LANGUAGE"
echo "  Source dir:     ${SOURCE_DIR:-<none>}"
echo "  Test dir:       ${TEST_DIR:-<none>}"
echo "  Test framework: ${TEST_FRAMEWORK:-<none>}"
echo "  Test command:   ${TEST_COMMAND:-<none>}"
echo "  Lint command:   ${LINT_COMMAND:-<none>}"
echo "  Typecheck:      ${TYPECHECK_COMMAND:-<none>}"
echo "  Single test:    ${SINGLE_TEST_COMMAND:-<none>}"
echo "  Build command:  ${BUILD_COMMAND:-<none>}"
echo "  Deployment:     ${DEPLOYMENT_SETUP:-<none>}"
echo "  Databases:      ${DATABASES:-<none>}"
echo "  Cache layer:    ${CACHE_LAYER:-<none>}"
echo "  Test duration:  ${TEST_DURATION:-<none>}"
echo "  Test types:     ${TEST_TYPES:-<none>}"
echo "  Coverage:       ${COVERAGE_CONFIG:-<none>}"
echo "  CI:             ${CI:-<none>}"
echo "  Domain:         $DOMAIN"
echo ""

prompt_with_default() {
    local label="$1"
    local default_value="${2-}"
    local answer=""

    if [ -n "$default_value" ]; then
        printf "%s [%s]: " "$label" "$default_value" >&2
    else
        printf "%s: " "$label" >&2
    fi

    IFS= read -r answer || answer=""

    if [ -n "$answer" ]; then
        printf '%s' "$answer"
    else
        printf '%s' "$default_value"
    fi
}

choose_model_profile() {
    local answer=""

    if [ "$MODEL_PROFILE_SET" = "true" ]; then
        return 0
    fi

    printf "Model profile [maximum/mixed] (recommended/default for setup: maximum): " >&2
    IFS= read -r answer || answer=""
    case "$answer" in
        ""|maximum)
            MODEL_PROFILE="maximum"
            ;;
        mixed)
            MODEL_PROFILE="mixed"
            ;;
        *)
            echo "Unsupported model profile: $answer (expected: mixed or maximum)" >&2
            exit 1
            ;;
    esac
}

refresh_setup_template_values() {
    local known=()
    local unresolved=()
    local joined=""

    [ -n "$LANGUAGE" ] && known+=("language=$LANGUAGE") || unresolved+=("language")
    [ -n "$SOURCE_DIR" ] && known+=("source_dir=$SOURCE_DIR") || unresolved+=("source_dir")
    [ -n "$TEST_DIR" ] && known+=("test_dir=$TEST_DIR") || unresolved+=("test_dir")
    [ -n "$TEST_FRAMEWORK" ] && known+=("test_framework=$TEST_FRAMEWORK") || unresolved+=("test_framework")
    [ -n "$TEST_COMMAND" ] && known+=("test_command=$TEST_COMMAND") || unresolved+=("test_command")
    [ -n "$LINT_COMMAND" ] && known+=("lint_command=$LINT_COMMAND") || unresolved+=("lint_command")
    [ -n "$BUILD_COMMAND" ] && known+=("build_command=$BUILD_COMMAND") || unresolved+=("build_command")
    [ -n "$DOMAIN" ] && known+=("domain=$DOMAIN") || unresolved+=("domain")

    REPO_SHAPE="${LANGUAGE:-unknown}/${DOMAIN:-unknown}"
    SETUP_CONFIDENCE=$([ "${#unresolved[@]}" -eq 0 ] && printf 'high' || printf 'partial')

    if [ "${#known[@]}" -eq 0 ]; then
        SETUP_KNOWN_SUMMARY="none"
    else
        joined=""
        local item
        for item in "${known[@]}"; do
            if [ -n "$joined" ]; then
                joined="$joined; "
            fi
            joined="$joined$item"
        done
        SETUP_KNOWN_SUMMARY="$joined"
    fi

    if [ "${#unresolved[@]}" -eq 0 ]; then
        SETUP_UNRESOLVED_SUMMARY="none"
    else
        joined=""
        local missing_item
        for missing_item in "${unresolved[@]}"; do
            if [ -n "$joined" ]; then
                joined="$joined; "
            fi
            joined="$joined$missing_item"
        done
        SETUP_UNRESOLVED_SUMMARY="$joined"
    fi
}

show_setup_resolution_map() {
    echo "Resolved (detected):"
    echo "  - Language: ${LANGUAGE:-<none>}"
    [ "$SOURCE_DIR_STATE" = "detected" ] && echo "  - Source dir: $SOURCE_DIR"
    [ "$TEST_DIR_STATE" = "detected" ] && echo "  - Test dir: $TEST_DIR"
    [ "$TEST_FRAMEWORK_STATE" = "detected" ] && echo "  - Test framework: $TEST_FRAMEWORK"
    [ "$TEST_COMMAND_STATE" = "detected" ] && echo "  - Test command: $TEST_COMMAND"
    [ "$LINT_COMMAND_STATE" = "detected" ] && echo "  - Lint command: $LINT_COMMAND"
    [ "$TYPECHECK_COMMAND_STATE" = "detected" ] && echo "  - Type-check command: $TYPECHECK_COMMAND"
    [ "$SINGLE_TEST_COMMAND_STATE" = "detected" ] && echo "  - Single test command: $SINGLE_TEST_COMMAND"
    [ "$BUILD_COMMAND_STATE" = "detected" ] && echo "  - Build command: $BUILD_COMMAND"
    [ "$DEPLOYMENT_SETUP_STATE" = "detected" ] && echo "  - Deployment setup: $DEPLOYMENT_SETUP"
    [ "$DATABASES_STATE" = "detected" ] && echo "  - Databases: $DATABASES"
    [ "$CACHE_LAYER_STATE" = "detected" ] && echo "  - Cache layer: $CACHE_LAYER"
    [ "$TEST_DURATION_STATE" = "detected" ] && echo "  - Test duration: $TEST_DURATION"
    [ "$TEST_TYPES_STATE" = "detected" ] && echo "  - Test types: $TEST_TYPES"
    [ "$COVERAGE_CONFIG_STATE" = "detected" ] && echo "  - Coverage config: $COVERAGE_CONFIG"
    [ "$CI_STATE" = "detected" ] && echo "  - CI: $CI"
    [ "$DOMAIN_STATE" = "detected" ] && echo "  - Domain: $DOMAIN"
    echo ""

    echo "Resolved (inferred):"
    [ "$SOURCE_DIR_STATE" = "inferred" ] && echo "  - Source dir: $SOURCE_DIR"
    [ "$TEST_DIR_STATE" = "inferred" ] && echo "  - Test dir: $TEST_DIR"
    [ "$TEST_FRAMEWORK_STATE" = "inferred" ] && echo "  - Test framework: $TEST_FRAMEWORK"
    [ "$TEST_COMMAND_STATE" = "inferred" ] && echo "  - Test command: $TEST_COMMAND"
    [ "$LINT_COMMAND_STATE" = "inferred" ] && echo "  - Lint command: $LINT_COMMAND"
    [ "$TYPECHECK_COMMAND_STATE" = "inferred" ] && echo "  - Type-check command: $TYPECHECK_COMMAND"
    [ "$SINGLE_TEST_COMMAND_STATE" = "inferred" ] && echo "  - Single test command: $SINGLE_TEST_COMMAND"
    [ "$BUILD_COMMAND_STATE" = "inferred" ] && echo "  - Build command: $BUILD_COMMAND"
    [ "$TEST_DURATION_STATE" = "inferred" ] && echo "  - Test duration: $TEST_DURATION"
    [ "$COVERAGE_CONFIG_STATE" = "inferred" ] && echo "  - Coverage config: $COVERAGE_CONFIG"
    [ "$DOMAIN_STATE" = "inferred" ] && echo "  - Domain: $DOMAIN"
    echo ""

    echo "Unresolved:"
    [ -z "$SOURCE_DIR" ] && echo "  - Source directory"
    [ -z "$TEST_DIR" ] && echo "  - Test directory"
    [ -z "$TEST_FRAMEWORK" ] && echo "  - Test framework"
    [ -z "$TEST_COMMAND" ] && echo "  - Test command"
    [ -z "$LINT_COMMAND" ] && echo "  - Lint command"
    [ -z "$TYPECHECK_COMMAND" ] && echo "  - Type-check command"
    [ -z "$SINGLE_TEST_COMMAND" ] && echo "  - Single test command"
    [ -z "$BUILD_COMMAND" ] && echo "  - Build command"
    [ -z "$DEPLOYMENT_SETUP" ] && echo "  - Deployment setup"
    [ -z "$DATABASES" ] && echo "  - Database(s)"
    [ -z "$CACHE_LAYER" ] && echo "  - Cache layer"
    [ -z "$TEST_DURATION" ] && echo "  - Test duration"
    [ -z "$TEST_TYPES" ] && echo "  - Test types"
    [ -z "$COVERAGE_CONFIG" ] && echo "  - Coverage config"
    echo "  - Response detail preference"
    echo "  - Testing approach preference"
    echo "  - Mocking philosophy preference"
    [ -n "$CI" ] && echo "  - CI shepherd preference"
    echo ""

    echo "I'll keep detected values automatically."
    echo "I'll ask only about inferred guesses or missing core repo facts."
    echo "Optional unknowns stay blank for now unless you choose to review everything."
    echo ""
}

collect_detected_overrides() {
    [ "$SOURCE_DIR_STATE" != "unresolved" ] && SOURCE_DIR=$(prompt_with_default "Source directory" "$SOURCE_DIR")
    [ "$TEST_DIR_STATE" != "unresolved" ] && TEST_DIR=$(prompt_with_default "Test directory" "$TEST_DIR")
    [ "$TEST_FRAMEWORK_STATE" != "unresolved" ] && TEST_FRAMEWORK=$(prompt_with_default "Test framework" "$TEST_FRAMEWORK")
    [ "$TEST_COMMAND_STATE" != "unresolved" ] && TEST_COMMAND=$(prompt_with_default "Test command" "$TEST_COMMAND")
    [ "$LINT_COMMAND_STATE" != "unresolved" ] && LINT_COMMAND=$(prompt_with_default "Lint command" "$LINT_COMMAND")
    [ "$TYPECHECK_COMMAND_STATE" != "unresolved" ] && TYPECHECK_COMMAND=$(prompt_with_default "Type-check command" "$TYPECHECK_COMMAND")
    [ "$SINGLE_TEST_COMMAND_STATE" != "unresolved" ] && SINGLE_TEST_COMMAND=$(prompt_with_default "Single test command" "$SINGLE_TEST_COMMAND")
    [ "$BUILD_COMMAND_STATE" != "unresolved" ] && BUILD_COMMAND=$(prompt_with_default "Build command" "$BUILD_COMMAND")
    [ "$DEPLOYMENT_SETUP_STATE" != "unresolved" ] && DEPLOYMENT_SETUP=$(prompt_with_default "Deployment setup" "$DEPLOYMENT_SETUP")
    [ "$DATABASES_STATE" != "unresolved" ] && DATABASES=$(prompt_with_default "Database(s)" "$DATABASES")
    [ "$CACHE_LAYER_STATE" != "unresolved" ] && CACHE_LAYER=$(prompt_with_default "Cache layer" "$CACHE_LAYER")
    [ "$TEST_DURATION_STATE" != "unresolved" ] && TEST_DURATION=$(prompt_with_default "Test duration" "$TEST_DURATION")
    [ "$TEST_TYPES_STATE" != "unresolved" ] && TEST_TYPES=$(prompt_with_default "Test types" "$TEST_TYPES")
    [ "$COVERAGE_CONFIG_STATE" != "unresolved" ] && COVERAGE_CONFIG=$(prompt_with_default "Coverage config" "$COVERAGE_CONFIG")
    [ "$CI_STATE" != "unresolved" ] && CI=$(prompt_with_default "CI provider" "$CI")
    [ "$DOMAIN_STATE" != "unresolved" ] && DOMAIN=$(prompt_with_default "Project domain" "$DOMAIN")
    return 0
}

prompt_inferred_value() {
    local description="$1"
    local label="$2"
    local var_name="$3"
    local state="$4"
    local current_value="${!var_name}"
    local updated_value=""

    [ "$state" = "inferred" ] || return 0

    echo "I inferred the $description from the repo. Press Enter to keep it or type a different value."
    updated_value=$(prompt_with_default "$label" "$current_value")
    case "$updated_value" in
        edit|EDIT|Edit|e|E)
            collect_detected_overrides
            updated_value="${!var_name}"
            ;;
    esac
    printf -v "$var_name" '%s' "$updated_value"
}

review_inferred_values_one_by_one() {
    prompt_inferred_value "source directory" "Source directory" SOURCE_DIR "$SOURCE_DIR_STATE"
    prompt_inferred_value "test directory" "Test directory" TEST_DIR "$TEST_DIR_STATE"
    prompt_inferred_value "test framework" "Test framework" TEST_FRAMEWORK "$TEST_FRAMEWORK_STATE"
    prompt_inferred_value "test command" "Test command" TEST_COMMAND "$TEST_COMMAND_STATE"
    prompt_inferred_value "lint command" "Lint command" LINT_COMMAND "$LINT_COMMAND_STATE"
    prompt_inferred_value "type-check command" "Type-check command" TYPECHECK_COMMAND "$TYPECHECK_COMMAND_STATE"
    prompt_inferred_value "single test command" "Single test command" SINGLE_TEST_COMMAND "$SINGLE_TEST_COMMAND_STATE"
    prompt_inferred_value "build command" "Build command" BUILD_COMMAND "$BUILD_COMMAND_STATE"
    prompt_inferred_value "test duration expectation" "Test duration expectation" TEST_DURATION "$TEST_DURATION_STATE"
    prompt_inferred_value "coverage config" "Coverage config" COVERAGE_CONFIG "$COVERAGE_CONFIG_STATE"
    prompt_inferred_value "project domain" "Project domain" DOMAIN "$DOMAIN_STATE"
}

has_inferred_values() {
    local state=""
    for state in \
        "$SOURCE_DIR_STATE" \
        "$TEST_DIR_STATE" \
        "$TEST_FRAMEWORK_STATE" \
        "$TEST_COMMAND_STATE" \
        "$LINT_COMMAND_STATE" \
        "$TYPECHECK_COMMAND_STATE" \
        "$SINGLE_TEST_COMMAND_STATE" \
        "$BUILD_COMMAND_STATE" \
        "$TEST_DURATION_STATE" \
        "$COVERAGE_CONFIG_STATE" \
        "$DOMAIN_STATE"; do
        [ "$state" = "inferred" ] && return 0
    done
    return 1
}

confirm_inferred_values() {
    local answer=""

    has_inferred_values || return 0

    printf "Press Enter to keep the inferred values above, or type edit to review them one by one: " >&2
    IFS= read -r answer || answer=""
    case "$answer" in
        edit|EDIT|Edit|e|E)
            review_inferred_values_one_by_one
            ;;
    esac
}

prompt_missing_core_value() {
    local description="$1"
    local label="$2"
    local var_name="$3"
    local current_value="${!var_name}"
    local updated_value=""

    [ -z "$current_value" ] || return 0

    echo "I couldn't determine the $description from the repo, so I need your input."
    updated_value=$(prompt_with_default "$label")
    case "$updated_value" in
        edit|EDIT|Edit|e|E)
            collect_detected_overrides
            updated_value="${!var_name}"
            ;;
    esac
    printf -v "$var_name" '%s' "$updated_value"
}

collect_missing_core_facts() {
    if [ -z "$SOURCE_DIR" ] && [ -z "$TEST_DIR" ] && [ -z "$TEST_FRAMEWORK" ] && [ -z "$TEST_COMMAND" ]; then
        prompt_missing_core_value "source directory" "Source directory" SOURCE_DIR
    fi
    prompt_missing_core_value "test directory" "Test directory" TEST_DIR
    prompt_missing_core_value "test framework" "Test framework" TEST_FRAMEWORK
    prompt_missing_core_value "test command" "Test command" TEST_COMMAND
}

offer_detected_review() {
    local answer=""

    printf "If any detected values are wrong, type edit to review them now. Otherwise press Enter to keep them: " >&2
    IFS= read -r answer || answer=""
    case "$answer" in
        edit|EDIT|Edit|e|E)
            collect_detected_overrides
            ;;
    esac
}

apply_auto_yes_defaults() {
    [ -z "$TYPECHECK_COMMAND" ] && TYPECHECK_COMMAND="none"
    [ -z "$SINGLE_TEST_COMMAND" ] && SINGLE_TEST_COMMAND="none"
    [ -z "$DEPLOYMENT_SETUP" ] && DEPLOYMENT_SETUP="none"
    [ -z "$DATABASES" ] && DATABASES="none"
    [ -z "$CACHE_LAYER" ] && CACHE_LAYER="none"
    [ -z "$TEST_DURATION" ] && TEST_DURATION="unknown"
    [ -z "$TEST_TYPES" ] && TEST_TYPES="none"
    [ -z "$COVERAGE_CONFIG" ] && COVERAGE_CONFIG="none"
    return 0
}

customize_workflow_preferences() {
    choose_model_profile
    GIT_WORKFLOW=$(prompt_with_default "Git workflow preference [solo/prs]" "$GIT_WORKFLOW")
    RESPONSE_DETAIL=$(prompt_with_default "Response detail preference [concise/detailed]" "$RESPONSE_DETAIL")
    TESTING_APPROACH=$(prompt_with_default "Testing approach preference [strict-tdd/mixed/test-after/minimal]" "$TESTING_APPROACH")
    MOCKING_PHILOSOPHY=$(prompt_with_default "Mocking philosophy preference [minimal/heavy/none/not-sure]" "$MOCKING_PHILOSOPHY")

    if [ -n "$CI" ]; then
        CI_SHEPHERD=$(prompt_with_default "CI shepherd preference [enabled/disabled]" "$CI_SHEPHERD")
    fi
}

confirm_workflow_defaults() {
    local answer=""
    local defaults_line=""

    echo ""
    echo "Last thing: I can tailor the generated docs, but the workflow defaults are usually fine."
    defaults_line="Defaults: model profile=$MODEL_PROFILE, git workflow=$GIT_WORKFLOW, response detail=$RESPONSE_DETAIL, testing approach=$TESTING_APPROACH, mocking=$MOCKING_PHILOSOPHY"
    if [ -n "$CI" ]; then
        defaults_line="$defaults_line, ci shepherd=$CI_SHEPHERD"
    fi
    echo "$defaults_line"
    printf "Press Enter to keep these workflow defaults, or type edit to customize them: " >&2
    IFS= read -r answer || answer=""
    case "$answer" in
        edit|EDIT|Edit|e|E)
            customize_workflow_preferences
            ;;
    esac
}

collect_setup_answers() {
    if [ "$AUTO_YES" = "true" ]; then
        apply_auto_yes_defaults
        return 0
    fi

    show_setup_resolution_map
    confirm_inferred_values
    collect_missing_core_facts
    offer_detected_review
    confirm_workflow_defaults
}

# ---- Step 2: Confirm and fill gaps ----
if [ "$SETUP_MODE" = "normal" ]; then
    collect_setup_answers
fi

refresh_setup_template_values

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
        -e "s|{{TYPECHECK_COMMAND}}|${TYPECHECK_COMMAND:-N/A}|g" \
        -e "s|{{SINGLE_TEST_COMMAND}}|${SINGLE_TEST_COMMAND:-N/A}|g" \
        -e "s|{{BUILD_COMMAND}}|${BUILD_COMMAND:-N/A}|g" \
        -e "s|{{DEPLOYMENT_SETUP}}|${DEPLOYMENT_SETUP:-N/A}|g" \
        -e "s|{{DATABASES}}|${DATABASES:-N/A}|g" \
        -e "s|{{CACHE_LAYER}}|${CACHE_LAYER:-N/A}|g" \
        -e "s|{{TEST_DURATION}}|${TEST_DURATION:-N/A}|g" \
        -e "s|{{TEST_TYPES}}|${TEST_TYPES:-N/A}|g" \
        -e "s|{{COVERAGE_CONFIG}}|${COVERAGE_CONFIG:-N/A}|g" \
        -e "s|{{CI}}|${CI:-N/A}|g" \
        -e "s|{{DOMAIN}}|${DOMAIN}|g" \
        -e "s|{{REPO_SHAPE}}|${REPO_SHAPE}|g" \
        -e "s|{{SETUP_CONFIDENCE}}|${SETUP_CONFIDENCE}|g" \
        -e "s|{{SETUP_KNOWN_SUMMARY}}|${SETUP_KNOWN_SUMMARY}|g" \
        -e "s|{{SETUP_UNRESOLVED_SUMMARY}}|${SETUP_UNRESOLVED_SUMMARY}|g" \
        -e "s|{{MODEL_PROFILE}}|${MODEL_PROFILE}|g" \
        -e "s|{{WIZARD_VERSION}}|${ADAPTER_VERSION}|g" \
        -e "s|{{SETUP_DATE}}|${SETUP_DATE}|g" \
        -e "s|{{COMPLETED_STEPS}}|${COMPLETED_STEPS}|g" \
        -e "s|{{GIT_WORKFLOW}}|${GIT_WORKFLOW}|g" \
        -e "s|{{RESPONSE_DETAIL}}|${RESPONSE_DETAIL}|g" \
        -e "s|{{TESTING_APPROACH}}|${TESTING_APPROACH}|g" \
        -e "s|{{MOCKING_PHILOSOPHY}}|${MOCKING_PHILOSOPHY}|g" \
        -e "s|{{CI_SHEPHERD}}|${CI_SHEPHERD}|g" \
        "$template"
}

# Generate AGENTS.md
generate_file() {
    local target="$1"
    local template="$2"
    local label="$3"
    local allow_overwrite=false

    if [ "$FORCE" = "true" ]; then
        allow_overwrite=true
    fi

    if [ -f "$target" ] && [ "$allow_overwrite" = "false" ]; then
        echo "$label exists — skipping (pass --force to overwrite)"
        return
    fi
    substitute_template "$template" > "$target"
    echo "Generated $label"
}

generate_file "AGENTS.md" "$SCRIPT_DIR/templates/AGENTS.md.tmpl" "AGENTS.md"
generate_file "ARCHITECTURE.md" "$SCRIPT_DIR/templates/ARCHITECTURE.md.tmpl" "ARCHITECTURE.md"
generate_file "SDLC.md" "$SCRIPT_DIR/templates/SDLC.md.tmpl" "SDLC.md"

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
if [ "$SETUP_MODE" != "regenerate" ]; then
    echo ""
    bash "$SCRIPT_DIR/install.sh" --model-profile "$MODEL_PROFILE"
fi

# ---- Step 5: Write manifest ----
mkdir -p .codex-sdlc

compute_hash() {
    local target="$1"
    local hash=""

    if [ ! -f "$target" ]; then
        echo ""
        return 0
    fi

    if command -v shasum >/dev/null 2>&1; then
        hash=$(shasum -a 256 "$target" 2>/dev/null | cut -d' ' -f1 || true)
    fi

    if ! printf '%s' "$hash" | grep -Eqi '^[0-9a-f]{64}$'; then
        if command -v sha256sum >/dev/null 2>&1; then
            hash=$(sha256sum "$target" 2>/dev/null | cut -d' ' -f1 || true)
        fi
    fi

    if ! printf '%s' "$hash" | grep -Eqi '^[0-9a-f]{64}$'; then
        hash=$(FILE_TO_HASH="$target" node -e '
const crypto = require("crypto");
const fs = require("fs");
const file = process.env.FILE_TO_HASH;
const digest = crypto.createHash("sha256").update(fs.readFileSync(file)).digest("hex");
process.stdout.write(digest);
' 2>/dev/null || true)
    fi

    if printf '%s' "$hash" | grep -Eqi '^[0-9a-f]{64}$'; then
        printf 'sha256:%s\n' "$(printf '%s' "$hash" | tr '[:upper:]' '[:lower:]')"
    else
        echo ""
    fi
}

MANIFEST=".codex-sdlc/manifest.json"

ADAPTER_VERSION="$ADAPTER_VERSION" \
INSTALLED_AT="$INSTALLED_AT_VALUE" \
SCAN_LANGUAGE="$LANGUAGE" \
SCAN_SOURCE_DIR="$SCAN_SOURCE_DIR_RAW" \
SCAN_TEST_DIR="$SCAN_TEST_DIR_RAW" \
SCAN_TEST_FRAMEWORK="$SCAN_TEST_FRAMEWORK_RAW" \
SCAN_TEST_COMMAND="$SCAN_TEST_COMMAND_RAW" \
SCAN_LINT_COMMAND="$SCAN_LINT_COMMAND_RAW" \
SCAN_TYPECHECK_COMMAND="$SCAN_TYPECHECK_COMMAND_RAW" \
SCAN_SINGLE_TEST_COMMAND="$SCAN_SINGLE_TEST_COMMAND_RAW" \
SCAN_BUILD_COMMAND="$SCAN_BUILD_COMMAND_RAW" \
SCAN_DEPLOYMENT_SETUP="$SCAN_DEPLOYMENT_SETUP_RAW" \
SCAN_DATABASES="$SCAN_DATABASES_RAW" \
SCAN_CACHE_LAYER="$SCAN_CACHE_LAYER_RAW" \
SCAN_TEST_DURATION="$SCAN_TEST_DURATION_RAW" \
SCAN_TEST_TYPES="$SCAN_TEST_TYPES_RAW" \
SCAN_COVERAGE_CONFIG="$SCAN_COVERAGE_CONFIG_RAW" \
SCAN_CI="$SCAN_CI_RAW" \
SCAN_DOMAIN="$SCAN_DOMAIN_RAW" \
SETUP_RESPONSE_DETAIL="$RESPONSE_DETAIL" \
SETUP_TESTING_APPROACH="$TESTING_APPROACH" \
SETUP_MOCKING_PHILOSOPHY="$MOCKING_PHILOSOPHY" \
SETUP_CI_SHEPHERD="$CI_SHEPHERD" \
SETUP_GIT_WORKFLOW="$GIT_WORKFLOW" \
RESOLVED_SOURCE_DIR="$SOURCE_DIR" \
RESOLVED_TEST_DIR="$TEST_DIR" \
RESOLVED_TEST_FRAMEWORK="$TEST_FRAMEWORK" \
RESOLVED_TEST_COMMAND="$TEST_COMMAND" \
RESOLVED_LINT_COMMAND="$LINT_COMMAND" \
RESOLVED_TYPECHECK_COMMAND="$TYPECHECK_COMMAND" \
RESOLVED_SINGLE_TEST_COMMAND="$SINGLE_TEST_COMMAND" \
RESOLVED_BUILD_COMMAND="$BUILD_COMMAND" \
RESOLVED_DEPLOYMENT_SETUP="$DEPLOYMENT_SETUP" \
RESOLVED_DATABASES="$DATABASES" \
RESOLVED_CACHE_LAYER="$CACHE_LAYER" \
RESOLVED_TEST_DURATION="$TEST_DURATION" \
RESOLVED_TEST_TYPES="$TEST_TYPES" \
RESOLVED_COVERAGE_CONFIG="$COVERAGE_CONFIG" \
RESOLVED_CI="$CI" \
RESOLVED_DOMAIN="$DOMAIN" \
CONF_SOURCE_DIR="$SOURCE_DIR_STATE" \
CONF_TEST_DIR="$TEST_DIR_STATE" \
CONF_TEST_FRAMEWORK="$TEST_FRAMEWORK_STATE" \
CONF_TEST_COMMAND="$TEST_COMMAND_STATE" \
CONF_LINT_COMMAND="$LINT_COMMAND_STATE" \
CONF_TYPECHECK_COMMAND="$TYPECHECK_COMMAND_STATE" \
CONF_SINGLE_TEST_COMMAND="$SINGLE_TEST_COMMAND_STATE" \
CONF_BUILD_COMMAND="$BUILD_COMMAND_STATE" \
CONF_DEPLOYMENT_SETUP="$DEPLOYMENT_SETUP_STATE" \
CONF_DATABASES="$DATABASES_STATE" \
CONF_CACHE_LAYER="$CACHE_LAYER_STATE" \
CONF_TEST_DURATION="$TEST_DURATION_STATE" \
CONF_TEST_TYPES="$TEST_TYPES_STATE" \
CONF_COVERAGE_CONFIG="$COVERAGE_CONFIG_STATE" \
CONF_CI="$CI_STATE" \
CONF_DOMAIN="$DOMAIN_STATE" \
MODEL_PROFILE_SELECTED="$MODEL_PROFILE" \
AGENTS_HASH="$(compute_hash AGENTS.md)" \
SDLC_HASH="$(compute_hash SDLC.md)" \
TESTING_HASH="$(compute_hash TESTING.md)" \
ARCH_HASH="$(compute_hash ARCHITECTURE.md)" \
SDLC_LOOP_HASH="$(compute_hash SDLC-LOOP.md)" \
START_SDLC_HASH="$(compute_hash START-SDLC.md)" \
PROVE_IT_HASH="$(compute_hash PROVE-IT.md)" \
CONFIG_HASH="$(compute_hash .codex/config.toml)" \
HOOKS_JSON_HASH="$(compute_hash .codex/hooks.json)" \
MODEL_PROFILE_HASH="$(compute_hash .codex-sdlc/model-profile.json)" \
BASH_GUARD_HASH="$(compute_hash .codex/hooks/bash-guard.sh)" \
SESSION_START_HASH="$(compute_hash .codex/hooks/session-start.sh)" \
GIT_GUARD_PS1_HASH="$(compute_hash .codex/hooks/git-guard.ps1)" \
SESSION_START_PS1_HASH="$(compute_hash .codex/hooks/session-start.ps1)" \
node -e '
const manifest = {
  adapter_version: process.env.ADAPTER_VERSION || "",
  installed_at: process.env.INSTALLED_AT || "",
  scan: {
    language: process.env.SCAN_LANGUAGE || "",
    source_dir: process.env.SCAN_SOURCE_DIR || "",
    test_dir: process.env.SCAN_TEST_DIR || "",
    test_framework: process.env.SCAN_TEST_FRAMEWORK || "",
    domain: process.env.SCAN_DOMAIN || "",
    test_command: process.env.SCAN_TEST_COMMAND || "",
    lint_command: process.env.SCAN_LINT_COMMAND || "",
    build_command: process.env.SCAN_BUILD_COMMAND || "",
    typecheck_command: process.env.SCAN_TYPECHECK_COMMAND || "",
    single_test_command: process.env.SCAN_SINGLE_TEST_COMMAND || "",
    deployment_setup: process.env.SCAN_DEPLOYMENT_SETUP || "",
    databases: process.env.SCAN_DATABASES || "",
    cache_layer: process.env.SCAN_CACHE_LAYER || "",
    test_duration: process.env.SCAN_TEST_DURATION || "",
    test_types: process.env.SCAN_TEST_TYPES || "",
    coverage_config: process.env.SCAN_COVERAGE_CONFIG || "",
    ci: process.env.SCAN_CI || ""
  },
  setup_answers: {
    git_workflow: process.env.SETUP_GIT_WORKFLOW || "",
    response_detail: process.env.SETUP_RESPONSE_DETAIL || "",
    testing_approach: process.env.SETUP_TESTING_APPROACH || "",
    mocking_philosophy: process.env.SETUP_MOCKING_PHILOSOPHY || "",
    ci_shepherd: process.env.SETUP_CI_SHEPHERD || ""
  },
  resolved_values: {
    source_dir: process.env.RESOLVED_SOURCE_DIR || "",
    test_dir: process.env.RESOLVED_TEST_DIR || "",
    test_framework: process.env.RESOLVED_TEST_FRAMEWORK || "",
    test_command: process.env.RESOLVED_TEST_COMMAND || "",
    lint_command: process.env.RESOLVED_LINT_COMMAND || "",
    typecheck_command: process.env.RESOLVED_TYPECHECK_COMMAND || "",
    single_test_command: process.env.RESOLVED_SINGLE_TEST_COMMAND || "",
    build_command: process.env.RESOLVED_BUILD_COMMAND || "",
    deployment_setup: process.env.RESOLVED_DEPLOYMENT_SETUP || "",
    databases: process.env.RESOLVED_DATABASES || "",
    cache_layer: process.env.RESOLVED_CACHE_LAYER || "",
    test_duration: process.env.RESOLVED_TEST_DURATION || "",
    test_types: process.env.RESOLVED_TEST_TYPES || "",
    coverage_config: process.env.RESOLVED_COVERAGE_CONFIG || "",
    ci: process.env.RESOLVED_CI || "",
    domain: process.env.RESOLVED_DOMAIN || ""
  },
  confidence_map: {
    source_dir: process.env.CONF_SOURCE_DIR || "",
    test_dir: process.env.CONF_TEST_DIR || "",
    test_framework: process.env.CONF_TEST_FRAMEWORK || "",
    test_command: process.env.CONF_TEST_COMMAND || "",
    lint_command: process.env.CONF_LINT_COMMAND || "",
    typecheck_command: process.env.CONF_TYPECHECK_COMMAND || "",
    single_test_command: process.env.CONF_SINGLE_TEST_COMMAND || "",
    build_command: process.env.CONF_BUILD_COMMAND || "",
    deployment_setup: process.env.CONF_DEPLOYMENT_SETUP || "",
    databases: process.env.CONF_DATABASES || "",
    cache_layer: process.env.CONF_CACHE_LAYER || "",
    test_duration: process.env.CONF_TEST_DURATION || "",
    test_types: process.env.CONF_TEST_TYPES || "",
    coverage_config: process.env.CONF_COVERAGE_CONFIG || "",
    ci: process.env.CONF_CI || "",
    domain: process.env.CONF_DOMAIN || ""
  },
  model_profile: {
    selected_profile: process.env.MODEL_PROFILE_SELECTED || ""
  },
  managed_files: {
    "AGENTS.md": process.env.AGENTS_HASH || "",
    "SDLC.md": process.env.SDLC_HASH || "",
    "TESTING.md": process.env.TESTING_HASH || "",
    "ARCHITECTURE.md": process.env.ARCH_HASH || "",
    "SDLC-LOOP.md": process.env.SDLC_LOOP_HASH || "",
    "START-SDLC.md": process.env.START_SDLC_HASH || "",
    "PROVE-IT.md": process.env.PROVE_IT_HASH || "",
    ".codex/config.toml": process.env.CONFIG_HASH || "",
    ".codex/hooks.json": process.env.HOOKS_JSON_HASH || "",
    ".codex-sdlc/model-profile.json": process.env.MODEL_PROFILE_HASH || "",
    ".codex/hooks/bash-guard.sh": process.env.BASH_GUARD_HASH || "",
    ".codex/hooks/session-start.sh": process.env.SESSION_START_HASH || "",
    ".codex/hooks/git-guard.ps1": process.env.GIT_GUARD_PS1_HASH || "",
    ".codex/hooks/session-start.ps1": process.env.SESSION_START_PS1_HASH || ""
  }
};

process.stdout.write(`${JSON.stringify(manifest, null, 2)}\n`);
' > "$MANIFEST"

echo ""
echo "Created $MANIFEST"

# ---- Step 6: Verify ----
verify_installation
