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

# Helper: run setup.sh in a project dir
run_setup() {
    local project_dir="$1"
    (cd "$project_dir" && bash "$SETUP_SH" --yes 2>/dev/null) || true
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
test_template_agents_md_valid
test_template_testing_md_domain
test_generated_no_placeholders
test_agents_md_read_directives
test_manifest_created

echo ""
echo "=== Results: $PASSED passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
    exit 1
fi
