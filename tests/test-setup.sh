#!/bin/bash
# Test setup.sh scan logic — detects language, dirs, framework, domain
# TDD: These tests are written BEFORE lib/scan.sh exists

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$SCRIPT_DIR/.."
SCAN_SH="$REPO_DIR/lib/scan.sh"
SETUP_SH="$REPO_DIR/setup.sh"
PASSED=0
FAILED=0

# Use TMPDIR if set (sandbox-friendly), fallback to /tmp
MKTEMP_DIR="${TMPDIR:-/tmp}"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() { echo -e "${GREEN}PASS${NC}: $1"; PASSED=$((PASSED + 1)); }
fail() { echo -e "${RED}FAIL${NC}: $1"; FAILED=$((FAILED + 1)); }

# Helper: create a temp project dir, run scan, return JSON
run_scan() {
    local project_dir="$1"
    (cd "$project_dir" && bash "$SCAN_SH" 2>/dev/null) || true
}

echo "=== Setup Scan Tests ==="
echo ""

# ---- Test 1: Detects Node.js project (package.json) ----
test_detect_nodejs() {
    local ws
    ws=$(mktemp -d "$MKTEMP_DIR/sdlc-test.XXXXXX")
    echo '{"name":"test-app","scripts":{"test":"jest"}}' > "$ws/package.json"
    mkdir -p "$ws/src"

    local output
    output=$(run_scan "$ws")
    rm -rf "$ws"

    if echo "$output" | jq -e '.language == "javascript"' >/dev/null 2>&1; then
        pass "Detects Node.js project (package.json)"
    else
        fail "Did not detect Node.js project (got: $(echo "$output" | jq -r '.language' 2>/dev/null))"
    fi
}

# ---- Test 2: Detects Rust project (Cargo.toml) ----
test_detect_rust() {
    local ws
    ws=$(mktemp -d "$MKTEMP_DIR/sdlc-test.XXXXXX")
    printf '[package]\nname = "test-app"\nversion = "0.1.0"\n' > "$ws/Cargo.toml"
    mkdir -p "$ws/src"

    local output
    output=$(run_scan "$ws")
    rm -rf "$ws"

    if echo "$output" | jq -e '.language == "rust"' >/dev/null 2>&1; then
        pass "Detects Rust project (Cargo.toml)"
    else
        fail "Did not detect Rust project (got: $(echo "$output" | jq -r '.language' 2>/dev/null))"
    fi
}

# ---- Test 3: Detects Go project (go.mod) ----
test_detect_go() {
    local ws
    ws=$(mktemp -d "$MKTEMP_DIR/sdlc-test.XXXXXX")
    echo 'module example.com/test' > "$ws/go.mod"
    mkdir -p "$ws/cmd"

    local output
    output=$(run_scan "$ws")
    rm -rf "$ws"

    if echo "$output" | jq -e '.language == "go"' >/dev/null 2>&1; then
        pass "Detects Go project (go.mod)"
    else
        fail "Did not detect Go project (got: $(echo "$output" | jq -r '.language' 2>/dev/null))"
    fi
}

# ---- Test 4: Detects Python project (pyproject.toml) ----
test_detect_python() {
    local ws
    ws=$(mktemp -d "$MKTEMP_DIR/sdlc-test.XXXXXX")
    printf '[project]\nname = "test-app"\n' > "$ws/pyproject.toml"
    mkdir -p "$ws/src"

    local output
    output=$(run_scan "$ws")
    rm -rf "$ws"

    if echo "$output" | jq -e '.language == "python"' >/dev/null 2>&1; then
        pass "Detects Python project (pyproject.toml)"
    else
        fail "Did not detect Python project (got: $(echo "$output" | jq -r '.language' 2>/dev/null))"
    fi
}

# ---- Test 5: Finds src/ directory ----
test_find_src_dir() {
    local ws
    ws=$(mktemp -d "$MKTEMP_DIR/sdlc-test.XXXXXX")
    echo '{"name":"test"}' > "$ws/package.json"
    mkdir -p "$ws/src"

    local output
    output=$(run_scan "$ws")
    rm -rf "$ws"

    if echo "$output" | jq -e '.source_dir == "src/"' >/dev/null 2>&1; then
        pass "Finds src/ directory"
    else
        fail "Did not find src/ (got: $(echo "$output" | jq -r '.source_dir' 2>/dev/null))"
    fi
}

# ---- Test 6: Finds test directory (tests/, __tests__/, spec/) ----
test_find_test_dir() {
    local ws
    ws=$(mktemp -d "$MKTEMP_DIR/sdlc-test.XXXXXX")
    echo '{"name":"test"}' > "$ws/package.json"
    mkdir -p "$ws/__tests__"

    local output
    output=$(run_scan "$ws")
    rm -rf "$ws"

    if echo "$output" | jq -e '.test_dir == "__tests__/"' >/dev/null 2>&1; then
        pass "Finds __tests__/ directory"
    else
        fail "Did not find __tests__/ (got: $(echo "$output" | jq -r '.test_dir' 2>/dev/null))"
    fi
}

# ---- Test 7: Detects test framework from config (jest.config.js) ----
test_detect_test_framework() {
    local ws
    ws=$(mktemp -d "$MKTEMP_DIR/sdlc-test.XXXXXX")
    echo '{"name":"test","scripts":{"test":"jest"}}' > "$ws/package.json"
    touch "$ws/jest.config.js"
    mkdir -p "$ws/src"

    local output
    output=$(run_scan "$ws")
    rm -rf "$ws"

    if echo "$output" | jq -e '.test_framework == "jest"' >/dev/null 2>&1; then
        pass "Detects jest test framework from config file"
    else
        fail "Did not detect jest (got: $(echo "$output" | jq -r '.test_framework' 2>/dev/null))"
    fi
}

# ---- Test 8: Detects domain: firmware (Makefile with flash target) ----
test_detect_domain_firmware() {
    local ws
    ws=$(mktemp -d "$MKTEMP_DIR/sdlc-test.XXXXXX")
    printf 'all:\n\tgcc -o main main.c\n\nflash:\n\topenocd -f flash.cfg\n' > "$ws/Makefile"

    local output
    output=$(run_scan "$ws")
    rm -rf "$ws"

    if echo "$output" | jq -e '.domain == "firmware"' >/dev/null 2>&1; then
        pass "Detects firmware domain (Makefile + flash target)"
    else
        fail "Did not detect firmware domain (got: $(echo "$output" | jq -r '.domain' 2>/dev/null))"
    fi
}

# ---- Test 9: Detects domain: data-science (.ipynb files) ----
test_detect_domain_data_science() {
    local ws
    ws=$(mktemp -d "$MKTEMP_DIR/sdlc-test.XXXXXX")
    printf '[project]\nname = "ml-pipeline"\n' > "$ws/pyproject.toml"
    touch "$ws/analysis.ipynb"

    local output
    output=$(run_scan "$ws")
    rm -rf "$ws"

    if echo "$output" | jq -e '.domain == "data-science"' >/dev/null 2>&1; then
        pass "Detects data-science domain (.ipynb)"
    else
        fail "Did not detect data-science domain (got: $(echo "$output" | jq -r '.domain' 2>/dev/null))"
    fi
}

# ---- Test 10: Detects domain: CLI (package.json with bin, no React) ----
test_detect_domain_cli() {
    local ws
    ws=$(mktemp -d "$MKTEMP_DIR/sdlc-test.XXXXXX")
    echo '{"name":"my-cli","bin":{"mycli":"./bin/cli.js"},"scripts":{"test":"jest"}}' > "$ws/package.json"
    mkdir -p "$ws/src"

    local output
    output=$(run_scan "$ws")
    rm -rf "$ws"

    if echo "$output" | jq -e '.domain == "cli"' >/dev/null 2>&1; then
        pass "Detects CLI domain (package.json with bin, no React)"
    else
        fail "Did not detect CLI domain (got: $(echo "$output" | jq -r '.domain' 2>/dev/null))"
    fi
}

# ---- Test 11: Detects docs-strong scaffold repos and reports a confidence map ----
test_detect_docs_strong_scaffold() {
    local ws
    ws=$(mktemp -d "$MKTEMP_DIR/sdlc-test.XXXXXX")
    echo '{"name":"test-app","scripts":{"test":"jest"}}' > "$ws/package.json"
    mkdir -p "$ws/src"
    echo 'console.log("scaffold");' > "$ws/src/index.js"
    echo '# Existing agent guidance' > "$ws/AGENTS.md"
    echo '# Existing testing contract' > "$ws/TESTING.md"
    echo '# Existing architecture notes' > "$ws/ARCHITECTURE.md"

    local output
    output=$(run_scan "$ws")
    rm -rf "$ws"

    if echo "$output" | jq -e '.repo_shape == "docs-strong-scaffold"' >/dev/null 2>&1 &&
       echo "$output" | jq -e '.confidence_map.overall == "medium"' >/dev/null 2>&1 &&
       echo "$output" | jq -e '.confidence_map.unresolved[] | select(. == "Test harness shape needs explicit repo-specific interpretation")' >/dev/null 2>&1; then
        pass "Detects docs-strong scaffold repos and reports a confidence map"
    else
        fail "Did not classify docs-strong scaffold repo shape and confidence map correctly"
    fi
}

# Helper: run setup.sh in a project dir
run_setup() {
    local project_dir="$1"
    shift
    (cd "$project_dir" && bash "$SETUP_SH" --yes "$@" 2>/dev/null) || true
}

run_setup_capture() {
    local project_dir="$1"
    shift
    (cd "$project_dir" && bash "$SETUP_SH" --yes "$@" 2>&1) || true
}

run_setup_interactive_capture() {
    local project_dir="$1"
    local input="$2"
    shift 2
    (cd "$project_dir" && printf '%s' "$input" | bash "$SETUP_SH" "$@" 2>&1) || true
}

# ---- Test 11: Template substitution produces valid AGENTS.md under 32KiB ----
test_template_agents_md_valid() {
    local ws
    ws=$(mktemp -d "$MKTEMP_DIR/sdlc-test.XXXXXX")
    echo '{"name":"test-app","scripts":{"test":"jest","lint":"eslint .","build":"tsc"}}' > "$ws/package.json"
    mkdir -p "$ws/src" "$ws/__tests__"
    touch "$ws/jest.config.js"

    run_setup "$ws"

    local size=0
    if [ -f "$ws/AGENTS.md" ]; then
        size=$(wc -c < "$ws/AGENTS.md" | tr -d ' ')
    fi
    rm -rf "$ws"

    if [ "$size" -gt 0 ] && [ "$size" -lt 32768 ]; then
        pass "Template produces valid AGENTS.md (${size} bytes, under 32KiB)"
    else
        fail "AGENTS.md invalid or too large (size: ${size:-missing})"
    fi
}

# ---- Test 12: Template picks correct domain section for TESTING.md ----
test_template_testing_md_domain() {
    local ws
    ws=$(mktemp -d "$MKTEMP_DIR/sdlc-test.XXXXXX")
    printf '[package]\nname = "test-app"\nversion = "0.1.0"\n' > "$ws/Cargo.toml"
    mkdir -p "$ws/src"

    run_setup "$ws"

    local has_domain=false
    # Rust project should NOT get firmware or data-science testing guidance
    if [ -f "$ws/TESTING.md" ]; then
        if grep -qi "web\|integration\|unit" "$ws/TESTING.md" 2>/dev/null; then
            has_domain=true
        fi
    fi
    rm -rf "$ws"

    if [ "$has_domain" = "true" ]; then
        pass "TESTING.md has domain-appropriate testing guidance"
    else
        fail "TESTING.md missing or lacks domain-appropriate content"
    fi
}

# ---- Test 13: Generated files contain project-specific values (not placeholders) ----
test_generated_no_placeholders() {
    local ws
    ws=$(mktemp -d "$MKTEMP_DIR/sdlc-test.XXXXXX")
    echo '{"name":"test-app","scripts":{"test":"jest","lint":"eslint ."}}' > "$ws/package.json"
    mkdir -p "$ws/src" "$ws/tests"
    touch "$ws/jest.config.js"

    run_setup "$ws"

    local has_placeholders=false
    for f in "$ws/AGENTS.md" "$ws/TESTING.md" "$ws/ARCHITECTURE.md"; do
        if [ -f "$f" ] && grep -q '{{' "$f" 2>/dev/null; then
            has_placeholders=true
        fi
    done
    rm -rf "$ws"

    if [ "$has_placeholders" = "false" ]; then
        pass "Generated files contain no {{PLACEHOLDER}} markers"
    else
        fail "Generated files still contain {{PLACEHOLDER}} markers"
    fi
}

# ---- Test 14: AGENTS.md contains read directives for TESTING.md and ARCHITECTURE.md ----
test_agents_md_read_directives() {
    local ws
    ws=$(mktemp -d "$MKTEMP_DIR/sdlc-test.XXXXXX")
    echo '{"name":"test-app","scripts":{"test":"jest"}}' > "$ws/package.json"
    mkdir -p "$ws/src"

    run_setup "$ws"

    local has_testing=false has_arch=false
    if [ -f "$ws/AGENTS.md" ]; then
        grep -qi "TESTING.md" "$ws/AGENTS.md" 2>/dev/null && has_testing=true
        grep -qi "ARCHITECTURE.md" "$ws/AGENTS.md" 2>/dev/null && has_arch=true
    fi
    rm -rf "$ws"

    if [ "$has_testing" = "true" ] && [ "$has_arch" = "true" ]; then
        pass "AGENTS.md references both TESTING.md and ARCHITECTURE.md"
    else
        fail "AGENTS.md missing read directives (TESTING.md=$has_testing, ARCHITECTURE.md=$has_arch)"
    fi
}

# ---- Test 15: manifest.json created with correct hashes and scan snapshot ----
test_manifest_created() {
    local ws
    ws=$(mktemp -d "$MKTEMP_DIR/sdlc-test.XXXXXX")
    echo '{"name":"test-app","scripts":{"test":"jest"}}' > "$ws/package.json"
    mkdir -p "$ws/src"

    run_setup "$ws"

    local valid=true
    if [ ! -f "$ws/.codex-sdlc/manifest.json" ]; then
        valid=false
    else
        # Check required fields exist
        if ! jq -e '.scan.language' "$ws/.codex-sdlc/manifest.json" >/dev/null 2>&1; then
            valid=false
        fi
        if ! jq -e '.managed_files["AGENTS.md"]' "$ws/.codex-sdlc/manifest.json" >/dev/null 2>&1; then
            valid=false
        fi
        # Hash should be a sha256 string
        local hash
        hash=$(jq -r '.managed_files["AGENTS.md"]' "$ws/.codex-sdlc/manifest.json" 2>/dev/null)
        if ! echo "$hash" | grep -q '^sha256:'; then
            valid=false
        fi
    fi
    rm -rf "$ws"

    if [ "$valid" = "true" ]; then
        pass "manifest.json created with scan snapshot and sha256 hashes"
    else
        fail "manifest.json missing, incomplete, or malformed"
    fi
}

test_setup_prints_confidence_map_for_docs_strong_scaffold() {
    local ws
    ws=$(mktemp -d "$MKTEMP_DIR/sdlc-test.XXXXXX")
    echo '{"name":"test-app","scripts":{"test":"jest"}}' > "$ws/package.json"
    mkdir -p "$ws/src"
    echo 'console.log("scaffold");' > "$ws/src/index.js"
    echo '# Existing agent guidance' > "$ws/AGENTS.md"
    echo '# Existing testing contract' > "$ws/TESTING.md"
    echo '# Existing architecture notes' > "$ws/ARCHITECTURE.md"

    local output
    output=$(run_setup_capture "$ws")
    rm -rf "$ws"

    if echo "$output" | grep -q 'Confidence map:' &&
       echo "$output" | grep -q 'docs-strong-scaffold' &&
       echo "$output" | grep -q 'Test harness shape needs explicit repo-specific interpretation'; then
        pass "setup.sh prints a confidence map for docs-strong scaffold repos"
    else
        fail "setup.sh does not print a strong-enough confidence map for docs-strong scaffold repos"
    fi
}

test_manifest_records_confidence_map_for_docs_strong_scaffold() {
    local ws
    ws=$(mktemp -d "$MKTEMP_DIR/sdlc-test.XXXXXX")
    echo '{"name":"test-app","scripts":{"test":"jest"}}' > "$ws/package.json"
    mkdir -p "$ws/src"
    echo 'console.log("scaffold");' > "$ws/src/index.js"
    echo '# Existing agent guidance' > "$ws/AGENTS.md"
    echo '# Existing testing contract' > "$ws/TESTING.md"
    echo '# Existing architecture notes' > "$ws/ARCHITECTURE.md"

    run_setup "$ws"

    local valid=true
    if [ ! -f "$ws/.codex-sdlc/manifest.json" ]; then
        valid=false
    else
        if ! jq -e '.scan.repo_shape == "docs-strong-scaffold"' "$ws/.codex-sdlc/manifest.json" >/dev/null 2>&1; then
            valid=false
        fi
        if ! jq -e '.confidence_map.overall == "medium"' "$ws/.codex-sdlc/manifest.json" >/dev/null 2>&1; then
            valid=false
        fi
        if ! jq -e '.confidence_map.unresolved[] | select(. == "Test harness shape needs explicit repo-specific interpretation")' "$ws/.codex-sdlc/manifest.json" >/dev/null 2>&1; then
            valid=false
        fi
    fi
    rm -rf "$ws"

    if [ "$valid" = "true" ]; then
        pass "manifest.json records the confidence map for docs-strong scaffold repos"
    else
        fail "manifest.json does not persist the docs-strong scaffold confidence map"
    fi
}

test_setup_recommends_full_auto() {
    local ws
    ws=$(mktemp -d "$MKTEMP_DIR/sdlc-test.XXXXXX")
    echo '{"name":"test-app","scripts":{"test":"jest"}}' > "$ws/package.json"
    mkdir -p "$ws/src"

    local output
    output=$(run_setup_capture "$ws")
    rm -rf "$ws"

    if echo "$output" | grep -q "codex --full-auto"; then
        pass "setup.sh recommends codex --full-auto after installation"
    else
        fail "setup.sh does not recommend codex --full-auto"
    fi
}

test_setup_calls_out_auth_heavy_boundary() {
    local ws
    ws=$(mktemp -d "$MKTEMP_DIR/sdlc-test.XXXXXX")
    echo '{"name":"test-app","scripts":{"test":"jest"}}' > "$ws/package.json"
    mkdir -p "$ws/src"

    local output
    output=$(run_setup_capture "$ws")
    rm -rf "$ws"

    if echo "$output" | grep -qi 'Windows / WAM / MFA' &&
       echo "$output" | grep -qi 'user-owned' &&
       echo "$output" | grep -qi 'resume'; then
        pass "setup.sh explains the user-owned auth boundary for Windows / WAM / MFA flows"
    else
        fail "setup.sh does not explain the auth-heavy boundary clearly enough"
    fi
}

test_generated_agents_md_encourages_capability_detectors() {
    local ws
    ws=$(mktemp -d "$MKTEMP_DIR/sdlc-test.XXXXXX")
    echo '{"name":"test-app","scripts":{"test":"jest"}}' > "$ws/package.json"
    mkdir -p "$ws/src"

    run_setup "$ws"

    local has_detector_pattern=false
    if [ -f "$ws/AGENTS.md" ] &&
       grep -Eqi 'doctor|check-capability|Test-.*Access|capability detector' "$ws/AGENTS.md" 2>/dev/null; then
        has_detector_pattern=true
    fi
    rm -rf "$ws"

    if [ "$has_detector_pattern" = "true" ]; then
        pass "Generated AGENTS.md encourages repo-local capability detectors for auth / license-sensitive work"
    else
        fail "Generated AGENTS.md does not encourage capability-detector helpers"
    fi
}

test_setup_output_encourages_capability_detectors() {
    local ws
    ws=$(mktemp -d "$MKTEMP_DIR/sdlc-test.XXXXXX")
    echo '{"name":"test-app","scripts":{"test":"jest"}}' > "$ws/package.json"
    mkdir -p "$ws/src"

    local output
    output=$(run_setup_capture "$ws")
    rm -rf "$ws"

    if echo "$output" | grep -Eqi 'doctor|check-capability|Test-.*Access' &&
       echo "$output" | grep -Eqi 'one-command classification|single command classification|one command classification'; then
        pass "setup.sh output encourages capability-detector helpers over raw provider commands"
    else
        fail "setup.sh output does not encourage capability-detector helpers clearly enough"
    fi
}

test_setup_scaffolds_repo_scope_skills() {
    local ws
    ws=$(mktemp -d "$MKTEMP_DIR/sdlc-test.XXXXXX")
    echo '{"name":"test-app","scripts":{"test":"jest"}}' > "$ws/package.json"
    mkdir -p "$ws/src"

    run_setup "$ws"

    local has_sdlc_skill=false
    local has_adlc_skill=false
    [ -f "$ws/.agents/skills/sdlc/SKILL.md" ] && has_sdlc_skill=true
    [ -f "$ws/.agents/skills/adlc/SKILL.md" ] && has_adlc_skill=true
    rm -rf "$ws"

    if [ "$has_sdlc_skill" = "true" ] && [ "$has_adlc_skill" = "true" ]; then
        pass "setup.sh scaffolds repo-scope Codex sdlc and adlc skills"
    else
        fail "setup.sh did not scaffold repo-scope Codex sdlc/adlc skills"
    fi
}

test_manifest_tracks_repo_scope_skills() {
    local ws
    ws=$(mktemp -d "$MKTEMP_DIR/sdlc-test.XXXXXX")
    echo '{"name":"test-app","scripts":{"test":"jest"}}' > "$ws/package.json"
    mkdir -p "$ws/src"

    run_setup "$ws"

    local valid=true
    if [ ! -f "$ws/.codex-sdlc/manifest.json" ]; then
        valid=false
    else
        if ! jq -e '.managed_files[".agents/skills/sdlc/SKILL.md"]' "$ws/.codex-sdlc/manifest.json" >/dev/null 2>&1; then
            valid=false
        fi
        if ! jq -e '.managed_files[".agents/skills/adlc/SKILL.md"]' "$ws/.codex-sdlc/manifest.json" >/dev/null 2>&1; then
            valid=false
        fi
    fi
    rm -rf "$ws"

    if [ "$valid" = "true" ]; then
        pass "manifest.json tracks the repo-scope Codex sdlc/adlc skills"
    else
        fail "manifest.json does not track the repo-scope Codex skills"
    fi
}

test_setup_writes_bootstrap_maximum_model_profile_by_default() {
    local ws
    ws=$(mktemp -d "$MKTEMP_DIR/sdlc-test.XXXXXX")
    echo '{"name":"test-app","scripts":{"test":"jest"}}' > "$ws/package.json"
    mkdir -p "$ws/src"

    run_setup "$ws"

    local valid=true
    if [ ! -f "$ws/.codex-sdlc/model-profile.json" ]; then
        valid=false
    else
        if ! jq -e '.selected_profile == "maximum"' "$ws/.codex-sdlc/model-profile.json" >/dev/null 2>&1; then
            valid=false
        fi
        if ! jq -e '.profiles.mixed.main_model == "gpt-5.4-mini"' "$ws/.codex-sdlc/model-profile.json" >/dev/null 2>&1; then
            valid=false
        fi
        if ! jq -e '.profiles.maximum.main_reasoning == "xhigh"' "$ws/.codex-sdlc/model-profile.json" >/dev/null 2>&1; then
            valid=false
        fi
    fi
    rm -rf "$ws"

    if [ "$valid" = "true" ]; then
        pass "setup.sh defaults bootstrap work to the maximum model profile while keeping mixed available"
    else
        fail "setup.sh did not default bootstrap work to the maximum model profile"
    fi
}

test_setup_accepts_maximum_model_profile() {
    local ws
    ws=$(mktemp -d "$MKTEMP_DIR/sdlc-test.XXXXXX")
    echo '{"name":"test-app","scripts":{"test":"jest"}}' > "$ws/package.json"
    mkdir -p "$ws/src"

    run_setup "$ws" --model-profile maximum

    local valid=true
    if [ ! -f "$ws/.codex-sdlc/model-profile.json" ]; then
        valid=false
    else
        if ! jq -e '.selected_profile == "maximum"' "$ws/.codex-sdlc/model-profile.json" >/dev/null 2>&1; then
            valid=false
        fi
    fi
    rm -rf "$ws"

    if [ "$valid" = "true" ]; then
        pass "setup.sh accepts an explicit maximum model profile"
    else
        fail "setup.sh did not honor --model-profile maximum"
    fi
}

test_setup_interactive_prompts_for_model_profile() {
    local ws
    ws=$(mktemp -d "$MKTEMP_DIR/sdlc-test.XXXXXX")
    echo '{"name":"test-app","scripts":{"test":"jest"}}' > "$ws/package.json"
    mkdir -p "$ws/src"

    local output
    output=$(run_setup_interactive_capture "$ws" $'maximum\nY\n')

    local valid=true
    if ! echo "$output" | grep -qi 'model profile'; then
        valid=false
    fi
    if ! echo "$output" | grep -Eqi 'default: maximum|recommended: maximum|setup.*maximum|maximum.*setup|bootstrap.*maximum|maximum.*bootstrap'; then
        valid=false
    fi
    if [ ! -f "$ws/.codex-sdlc/model-profile.json" ] ||
       ! jq -e '.selected_profile == "maximum"' "$ws/.codex-sdlc/model-profile.json" >/dev/null 2>&1; then
        valid=false
    fi

    rm -rf "$ws"

    if [ "$valid" = "true" ]; then
        pass "interactive setup prompts for a model profile, recommends maximum, and honors the user's choice"
    else
        fail "interactive setup did not recommend maximum or honor the model-profile choice"
    fi
}

test_setup_output_recommends_mixed_after_bootstrap() {
    local ws
    ws=$(mktemp -d "$MKTEMP_DIR/sdlc-test.XXXXXX")
    echo '{"name":"test-app","scripts":{"test":"jest"}}' > "$ws/package.json"
    mkdir -p "$ws/src"

    local output
    output=$(run_setup_capture "$ws")

    local valid=true
    echo "$output" | grep -Eqi 'setup/update.*maximum|bootstrap.*maximum' || valid=false
    echo "$output" | grep -Eqi 'routine work.*mixed|day-to-day.*mixed|after bootstrap.*mixed' || valid=false

    rm -rf "$ws"

    if [ "$valid" = "true" ]; then
        pass "setup.sh output recommends maximum for bootstrap and mixed for routine work"
    else
        fail "setup.sh output does not explain the bootstrap-versus-routine profile policy clearly enough"
    fi
}

test_setup_offers_issue_ready_feedback_on_wizard_failure() {
    local adapter_clone
    local ws
    local output
    adapter_clone=$(mktemp -d "$MKTEMP_DIR/sdlc-adapter-clone.XXXXXX")
    ws=$(mktemp -d "$MKTEMP_DIR/sdlc-test.XXXXXX")

    cp -R "$REPO_DIR/." "$adapter_clone/"
    rm -f "$adapter_clone/install.sh"
    echo '{"name":"test-app","scripts":{"test":"jest"}}' > "$ws/package.json"
    mkdir -p "$ws/src"

    output=$(
        cd "$ws" &&
        bash "$adapter_clone/setup.sh" --yes 2>&1
    ) || true

    rm -rf "$adapter_clone" "$ws"

    if echo "$output" | grep -qi 'Likely wizard-level failure' &&
       echo "$output" | grep -qi 'codex-sdlc-wizard' &&
       echo "$output" | grep -qi 'No issue will be posted automatically' &&
       echo "$output" | grep -qi 'wizard version:' &&
       echo "$output" | grep -qi 'command:' &&
       echo "$output" | grep -qi 'repo shape:' &&
       echo "$output" | grep -qi 'failure point:'; then
        pass "setup.sh offers issue-ready feedback when wizard bootstrap files are missing"
    else
        fail "setup.sh does not offer issue-ready feedback for obvious wizard-level failures"
    fi
}

test_manifest_tracks_selected_model_profile() {
    local ws
    ws=$(mktemp -d "$MKTEMP_DIR/sdlc-test.XXXXXX")
    echo '{"name":"test-app","scripts":{"test":"jest"}}' > "$ws/package.json"
    mkdir -p "$ws/src"

    run_setup "$ws" --model-profile maximum

    local valid=true
    if [ ! -f "$ws/.codex-sdlc/manifest.json" ]; then
        valid=false
    else
        if ! jq -e '.model_profile.selected_profile == "maximum"' "$ws/.codex-sdlc/manifest.json" >/dev/null 2>&1; then
            valid=false
        fi
        if ! jq -e '.managed_files[".codex-sdlc/model-profile.json"]' "$ws/.codex-sdlc/manifest.json" >/dev/null 2>&1; then
            valid=false
        fi
    fi
    rm -rf "$ws"

    if [ "$valid" = "true" ]; then
        pass "manifest.json tracks the selected model profile and profile file"
    else
        fail "manifest.json does not track the selected model profile cleanly"
    fi
}

test_generated_agents_md_documents_profile_policy() {
    local ws
    ws=$(mktemp -d "$MKTEMP_DIR/sdlc-test.XXXXXX")
    echo '{"name":"test-app","scripts":{"test":"jest"}}' > "$ws/package.json"
    mkdir -p "$ws/src"

    run_setup "$ws"

    local valid=true
    if [ ! -f "$ws/AGENTS.md" ]; then
        valid=false
    else
        grep -q 'Model Profile' "$ws/AGENTS.md" || valid=false
        grep -q 'mixed' "$ws/AGENTS.md" || valid=false
        grep -q 'maximum' "$ws/AGENTS.md" || valid=false
        grep -Eqi '95%|research more first' "$ws/AGENTS.md" || valid=false
        grep -Eqi 'xhigh review|xhigh' "$ws/AGENTS.md" || valid=false
    fi
    rm -rf "$ws"

    if [ "$valid" = "true" ]; then
        pass "Generated AGENTS.md documents the model-profile tradeoff and low-confidence escalation rule"
    else
        fail "Generated AGENTS.md does not document the model-profile policy clearly enough"
    fi
}

test_generated_agents_md_documents_codex_shape_and_repo_focus() {
    local ws
    ws=$(mktemp -d "$MKTEMP_DIR/sdlc-test.XXXXXX")
    echo '{"name":"test-app","scripts":{"test":"jest"}}' > "$ws/package.json"
    mkdir -p "$ws/src"

    run_setup "$ws"

    local valid=true
    if [ ! -f "$ws/AGENTS.md" ]; then
        valid=false
    else
        grep -q 'skills = explicit workflow layer' "$ws/AGENTS.md" || valid=false
        grep -q 'hooks = silent event enforcement' "$ws/AGENTS.md" || valid=false
        grep -q 'repo docs = source of local truth' "$ws/AGENTS.md" || valid=false
        grep -qi 'always state confidence' "$ws/AGENTS.md" || valid=false
        grep -qi 'direct GitHub issue' "$ws/AGENTS.md" || valid=false
        grep -qi 'product repo' "$ws/AGENTS.md" || valid=false
        grep -qi 'actually blocked' "$ws/AGENTS.md" || valid=false
    fi
    rm -rf "$ws"

    if [ "$valid" = "true" ]; then
        pass "Generated AGENTS.md documents the honest Codex shape, confidence rule, and repo-focus feedback loop"
    else
        fail "Generated AGENTS.md does not document the Codex shape and repo-focus feedback loop clearly enough"
    fi
}

# ---- Run all tests ----
test_detect_nodejs
test_detect_rust
test_detect_go
test_detect_python
test_find_src_dir
test_find_test_dir
test_detect_test_framework
test_detect_domain_firmware
test_detect_domain_data_science
test_detect_domain_cli
test_detect_docs_strong_scaffold
test_template_agents_md_valid
test_template_testing_md_domain
test_generated_no_placeholders
test_agents_md_read_directives
test_manifest_created
test_setup_prints_confidence_map_for_docs_strong_scaffold
test_manifest_records_confidence_map_for_docs_strong_scaffold
test_setup_recommends_full_auto
test_setup_calls_out_auth_heavy_boundary
test_generated_agents_md_encourages_capability_detectors
test_setup_output_encourages_capability_detectors
test_setup_scaffolds_repo_scope_skills
test_manifest_tracks_repo_scope_skills
test_setup_writes_bootstrap_maximum_model_profile_by_default
test_setup_accepts_maximum_model_profile
test_setup_interactive_prompts_for_model_profile
test_setup_output_recommends_mixed_after_bootstrap
test_setup_offers_issue_ready_feedback_on_wizard_failure
test_manifest_tracks_selected_model_profile
test_generated_agents_md_documents_profile_policy
test_generated_agents_md_documents_codex_shape_and_repo_focus

echo ""
echo "=== Results: $PASSED passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
    exit 1
fi
