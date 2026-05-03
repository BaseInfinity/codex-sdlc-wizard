#!/bin/bash
# Test setup.sh scan logic — detects language, dirs, framework, domain
# TDD: These tests are written BEFORE lib/scan.sh exists

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$SCRIPT_DIR/.."
SCAN_SH="$REPO_DIR/lib/scan.sh"
SETUP_SH="$REPO_DIR/setup.sh"
CHECK_SH="$REPO_DIR/check.sh"
UPDATE_SH="$REPO_DIR/update.sh"
PASSED=0
FAILED=0

# Use TMPDIR if set (sandbox-friendly), fallback to /tmp
MKTEMP_DIR="${TMPDIR:-/tmp}"

case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) IS_WINDOWS=true ;;
    *) IS_WINDOWS=false ;;
esac

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() { echo -e "${GREEN}PASS${NC}: $1"; PASSED=$((PASSED + 1)); }
fail() { echo -e "${RED}FAIL${NC}: $1"; FAILED=$((FAILED + 1)); }

# JSON helpers use Node because the setup regression is specifically about missing jq.
json_eval_stdin() {
    local expr="$1"
    JSON_EXPR="$expr" node -e '
const fs = require("fs");
const expr = process.env.JSON_EXPR;
const input = fs.readFileSync(0, "utf8");
if (!input.trim()) {
  process.exit(1);
}

const data = JSON.parse(input);
const value = Function("data", `return (${expr});`)(data);
if (value === undefined || value === null) {
  process.exit(1);
}

if (typeof value === "object") {
  process.stdout.write(JSON.stringify(value));
} else {
  process.stdout.write(String(value));
}
' 2>/dev/null
}

json_text_equals() {
    local json="$1"
    local expr="$2"
    local expected="$3"
    local actual

    actual=$(printf '%s' "$json" | json_eval_stdin "$expr" || true)
    [ "$actual" = "$expected" ]
}

json_text_get() {
    local json="$1"
    local expr="$2"

    printf '%s' "$json" | json_eval_stdin "$expr" || true
}

# Helper: create a temp project dir, run scan, return JSON
run_scan() {
    local project_dir="$1"
    (cd "$project_dir" && bash "$SCAN_SH" 2>/dev/null) || true
}

echo "=== Setup Scan Tests ==="
echo ""

# ---- Test 1: Detects Node.js project without jq installed ----
test_detect_nodejs() {
    local ws
    ws=$(mktemp -d "$MKTEMP_DIR/sdlc-test.XXXXXX")
    echo '{"name":"test-app","scripts":{"test":"jest"}}' > "$ws/package.json"
    mkdir -p "$ws/src"

    local output
    output=$(run_scan "$ws")
    rm -rf "$ws"

    if json_text_equals "$output" 'data.language' "javascript"; then
        pass "Detects Node.js project without jq installed"
    else
        fail "Did not detect Node.js project (got: $(json_text_get "$output" 'data.language'))"
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

    if json_text_equals "$output" 'data.language' "rust"; then
        pass "Detects Rust project (Cargo.toml)"
    else
        fail "Did not detect Rust project (got: $(json_text_get "$output" 'data.language'))"
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

    if json_text_equals "$output" 'data.language' "go"; then
        pass "Detects Go project (go.mod)"
    else
        fail "Did not detect Go project (got: $(json_text_get "$output" 'data.language'))"
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

    if json_text_equals "$output" 'data.language' "python"; then
        pass "Detects Python project (pyproject.toml)"
    else
        fail "Did not detect Python project (got: $(json_text_get "$output" 'data.language'))"
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

    if json_text_equals "$output" 'data.source_dir' "src/"; then
        pass "Finds src/ directory"
    else
        fail "Did not find src/ (got: $(json_text_get "$output" 'data.source_dir'))"
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

    if json_text_equals "$output" 'data.test_dir' "__tests__/"; then
        pass "Finds __tests__/ directory"
    else
        fail "Did not find __tests__/ (got: $(json_text_get "$output" 'data.test_dir'))"
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

    if json_text_equals "$output" 'data.test_framework' "jest"; then
        pass "Detects jest test framework from config file"
    else
        fail "Did not detect jest (got: $(json_text_get "$output" 'data.test_framework'))"
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

    if json_text_equals "$output" 'data.domain' "firmware"; then
        pass "Detects firmware domain (Makefile + flash target)"
    else
        fail "Did not detect firmware domain (got: $(json_text_get "$output" 'data.domain'))"
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

    if json_text_equals "$output" 'data.domain' "data-science"; then
        pass "Detects data-science domain (.ipynb)"
    else
        fail "Did not detect data-science domain (got: $(json_text_get "$output" 'data.domain'))"
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

    if json_text_equals "$output" 'data.domain' "cli"; then
        pass "Detects CLI domain (package.json with bin, no React)"
    else
        fail "Did not detect CLI domain (got: $(json_text_get "$output" 'data.domain'))"
    fi
}

# Helper: run setup.sh in a project dir
run_setup() {
    local project_dir="$1"
    (cd "$project_dir" && CODEX_SDLC_DISABLE_REASONING=1 CODEX_HOME="$project_dir/.codex-home" bash "$SETUP_SH" --yes 2>/dev/null) || true
}

run_setup_interactive() {
    local project_dir="$1"
    local input_text="$2"
    (cd "$project_dir" && printf '%s' "$input_text" | CODEX_SDLC_DISABLE_REASONING=1 CODEX_HOME="$project_dir/.codex-home" bash "$SETUP_SH" 2>&1) || true
}

run_setup_args() {
    local project_dir="$1"
    shift
    (cd "$project_dir" && CODEX_SDLC_DISABLE_REASONING=1 CODEX_HOME="$project_dir/.codex-home" bash "$SETUP_SH" "$@" 2>&1)
}

# Helper: run check.sh in a project dir
run_check() {
    local project_dir="$1"
    (cd "$project_dir" && bash "$CHECK_SH" 2>/dev/null) || true
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

# ---- Test 15: setup.sh generates SDLC.md with metadata and default preferences ----
test_setup_generates_sdlc_md() {
    local ws
    ws=$(mktemp -d "$MKTEMP_DIR/sdlc-test.XXXXXX")
    echo '{"name":"test-app","scripts":{"test":"jest","lint":"eslint .","build":"tsc"}}' > "$ws/package.json"
    mkdir -p "$ws/src" "$ws/__tests__"
    touch "$ws/jest.config.js"

    run_setup "$ws"

    local valid=true
    if [ ! -f "$ws/SDLC.md" ]; then
        valid=false
    else
        grep -q '<!-- SDLC Wizard Version:' "$ws/SDLC.md" 2>/dev/null || valid=false
        grep -q '<!-- Setup Date:' "$ws/SDLC.md" 2>/dev/null || valid=false
        grep -q '<!-- Completed Steps:' "$ws/SDLC.md" 2>/dev/null || valid=false
        grep -q '<!-- Response Detail:' "$ws/SDLC.md" 2>/dev/null || valid=false
        grep -q '<!-- Testing Approach:' "$ws/SDLC.md" 2>/dev/null || valid=false
        grep -q '<!-- Mocking Philosophy:' "$ws/SDLC.md" 2>/dev/null || valid=false
        grep -q '<!-- CI Shepherd:' "$ws/SDLC.md" 2>/dev/null || valid=false
        grep -q 'npm test' "$ws/SDLC.md" 2>/dev/null || valid=false
        grep -q 'strict-tdd' "$ws/SDLC.md" 2>/dev/null || valid=false
        grep -q 'minimal' "$ws/SDLC.md" 2>/dev/null || valid=false
        grep -q 'Task Routing Gate' "$ws/SDLC.md" 2>/dev/null || valid=false
        grep -q 'Identify the execution lane before giving instructions' "$ws/SDLC.md" 2>/dev/null || valid=false
        grep -q 'CLI, Desktop/computer-use, browser automation, or human-only setup' "$ws/SDLC.md" 2>/dev/null || valid=false
        grep -q 'Microsoft browser sign-in' "$ws/SDLC.md" 2>/dev/null || valid=false
        grep -q 'developer program qualification' "$ws/SDLC.md" 2>/dev/null || valid=false
        grep -q 'Desktop/computer-use' "$ws/SDLC.md" 2>/dev/null || valid=false
        grep -q 'credentials, MFA, tenant consent' "$ws/SDLC.md" 2>/dev/null || valid=false
    fi
    rm -rf "$ws"

    if [ "$valid" = "true" ]; then
        pass "setup.sh generates SDLC.md with metadata and default preferences"
    else
        fail "setup.sh did not generate SDLC.md with the expected metadata/defaults"
    fi
}

# ---- Test 16: interactive setup keeps detected values and offers one-shot inferred/default acceptance ----
test_setup_interactive_only_asks_preferences() {
    local ws
    ws=$(mktemp -d "$MKTEMP_DIR/sdlc-test.XXXXXX")
    cat > "$ws/package.json" <<'EOF'
{"name":"test-app","bin":{"test-app":"./bin/cli.js"},"scripts":{"test":"jest","lint":"eslint .","build":"tsc","typecheck":"tsc --noEmit"}}
EOF
    mkdir -p "$ws/src" "$ws/__tests__" "$ws/bin"
    touch "$ws/jest.config.js" "$ws/tsconfig.json" "$ws/bin/cli.js"

    local output
    output=$(run_setup_interactive "$ws" $'\n\n\n\n\n')
    rm -rf "$ws"

    if echo "$output" | grep -q "I'll keep detected values automatically" \
        && echo "$output" | grep -q 'Press Enter to keep the inferred values above' \
        && echo "$output" | grep -q 'Press Enter to keep these workflow defaults' \
        && ! echo "$output" | grep -q 'Use scan results above and continue' \
        && ! echo "$output" | grep -q '^Source directory:' \
        && ! echo "$output" | grep -q '^Test directory:' \
        && ! echo "$output" | grep -q '^Test command:' \
        && ! echo "$output" | grep -q 'Single test command \[' \
        && ! echo "$output" | grep -q '^Response detail preference' \
        && ! echo "$output" | grep -q '^Testing approach preference' \
        && ! echo "$output" | grep -q '^Mocking philosophy preference' \
        && ! echo "$output" | grep -q 'CI shepherd'; then
        pass "interactive setup keeps detected values and offers one-shot inferred/default acceptance"
    else
        fail "interactive setup did not stay on the conversational fast path"
    fi
}

# ---- Test 17: interactive setup explains the scan plan and skips unresolved optional blanks ----
test_setup_interactive_accepts_scan_without_prompting_optional_blanks() {
    local ws
    ws=$(mktemp -d "$MKTEMP_DIR/sdlc-test.XXXXXX")
    cat > "$ws/package.json" <<'EOF'
{"name":"test-app","scripts":{"test":"npm test"}}
EOF
    mkdir -p "$ws/tests"
    touch "$ws/playwright.config.js"
    touch "$ws/tests/app.e2e.ts"

    local output
    output=$(run_setup_interactive "$ws" $'\n\n\n\n\n')
    rm -rf "$ws"

    if echo "$output" | grep -q "I'll keep detected values automatically" \
        && echo "$output" | grep -q "I'll ask only about inferred guesses or missing core repo facts" \
        && echo "$output" | grep -q 'Resolved (inferred):' \
        && echo "$output" | grep -q 'Press Enter to keep the inferred values above' \
        && echo "$output" | grep -q 'Press Enter to keep these workflow defaults' \
        && ! echo "$output" | grep -q 'Use scan results above and continue' \
        && ! echo "$output" | grep -q '^Source directory:' \
        && ! echo "$output" | grep -q '^Lint command:' \
        && ! echo "$output" | grep -q '^Type-check command:' \
        && ! echo "$output" | grep -q '^Build command:' \
        && ! echo "$output" | grep -q 'Test framework \[' \
        && ! echo "$output" | grep -q 'Single test command \[' \
        && ! echo "$output" | grep -q '^Response detail preference'; then
        pass "interactive setup explains the scan plan and skips unresolved optional blanks"
    else
        fail "interactive setup still felt confusing or asked optional blanks on the fast path"
    fi
}

# ---- Test 18: interactive setup asks missing core facts directly without an edit gate ----
test_setup_interactive_asks_missing_core_facts() {
    local ws
    ws=$(mktemp -d "$MKTEMP_DIR/sdlc-test.XXXXXX")
    echo '{"name":"test-app"}' > "$ws/package.json"

    local output
    output=$(run_setup_interactive "$ws" $'\n\n\n\n\n\n\n')
    rm -rf "$ws"

    if echo "$output" | grep -q "I'll ask only about inferred guesses or missing core repo facts" \
        && ! echo "$output" | grep -q 'Use scan results above and continue' \
        && echo "$output" | grep -q '^Source directory:' \
        && echo "$output" | grep -q '^Test directory:' \
        && echo "$output" | grep -q '^Test framework:' \
        && echo "$output" | grep -q '^Test command:'; then
        pass "interactive setup asks missing core facts directly without an edit gate"
    else
        fail "interactive setup did not ask for unresolved core facts"
    fi
}

# ---- Test 19: interactive setup asks CI shepherd only when CI is detected ----
test_setup_interactive_ci_shepherd_is_conditional() {
    local ws
    ws=$(mktemp -d "$MKTEMP_DIR/sdlc-test.XXXXXX")
    echo '{"name":"test-app","scripts":{"test":"jest"}}' > "$ws/package.json"
    mkdir -p "$ws/src" "$ws/.github/workflows"
    touch "$ws/.github/workflows/ci.yml"
    touch "$ws/jest.config.js"

    local output
    output=$(run_setup_interactive "$ws" $'\n\n\n\n\n\n')
    rm -rf "$ws"

    if echo "$output" | grep -q 'ci shepherd=disabled'; then
        pass "interactive setup asks CI shepherd only when CI is detected"
    else
        fail "interactive setup did not ask about CI shepherd when CI was detected"
    fi
}

# ---- Test 20: interactive setup explains why it is asking the remaining questions ----
test_setup_interactive_shows_inferred_values() {
    local ws
    ws=$(mktemp -d "$MKTEMP_DIR/sdlc-test.XXXXXX")
    echo '{"name":"test-app","scripts":{"test":"jest"}}' > "$ws/package.json"

    local output
    output=$(run_setup_interactive "$ws" $'\n\n\n\n\n\n\n')
    rm -rf "$ws"

    if echo "$output" | grep -q 'Resolved (inferred):' \
        && echo "$output" | grep -q 'Test framework: jest' \
        && echo "$output" | grep -q 'Domain: web' \
        && echo "$output" | grep -q "I'll keep detected values automatically" \
        && echo "$output" | grep -q 'Press Enter to keep the inferred values above' \
        && echo "$output" | grep -q 'Press Enter to keep these workflow defaults'; then
        pass "interactive setup explains why it is asking the remaining questions"
    else
        fail "interactive setup did not explain its adaptive questioning clearly"
    fi
}

# ---- Test 20: manifest.json created with correct hashes and scan snapshot ----
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
        if ! json_eval_stdin 'data.scan.language' < "$ws/.codex-sdlc/manifest.json" >/dev/null 2>&1; then
            valid=false
        fi
        if ! json_eval_stdin 'data.managed_files["AGENTS.md"]' < "$ws/.codex-sdlc/manifest.json" >/dev/null 2>&1; then
            valid=false
        fi
        if ! json_eval_stdin 'data.managed_files["SDLC.md"]' < "$ws/.codex-sdlc/manifest.json" >/dev/null 2>&1; then
            valid=false
        fi
        if ! json_eval_stdin 'data.managed_files["SDLC-LOOP.md"]' < "$ws/.codex-sdlc/manifest.json" >/dev/null 2>&1; then
            valid=false
        fi
        if ! json_eval_stdin 'data.managed_files["START-SDLC.md"]' < "$ws/.codex-sdlc/manifest.json" >/dev/null 2>&1; then
            valid=false
        fi
        if ! json_eval_stdin 'data.managed_files["PROVE-IT.md"]' < "$ws/.codex-sdlc/manifest.json" >/dev/null 2>&1; then
            valid=false
        fi
        if ! json_eval_stdin 'data.managed_files[".codex/config.toml"]' < "$ws/.codex-sdlc/manifest.json" >/dev/null 2>&1; then
            valid=false
        fi
        # Hash should be a sha256 string
        local hash
        hash=$(json_eval_stdin 'data.managed_files["AGENTS.md"]' < "$ws/.codex-sdlc/manifest.json" || true)
        if ! echo "$hash" | grep -q '^sha256:'; then
            valid=false
        fi
        if ! json_eval_stdin 'data.managed_files[".codex/hooks/git-guard.cjs"]' < "$ws/.codex-sdlc/manifest.json" >/dev/null 2>&1; then
            valid=false
        fi
    fi
    [ -f "$ws/.agents/skills/sdlc/SKILL.md" ] || valid=false
    [ ! -e "$ws/.agents/skills/adlc/SKILL.md" ] || valid=false
    rm -rf "$ws"

    if [ "$valid" = "true" ]; then
        pass "manifest.json tracks the managed SDLC surface with scan snapshot and sha256 hashes"
    else
        fail "manifest.json missing, incomplete, or malformed"
    fi
}

# ---- Test 21: setup.sh repairs stale Bash hook wiring on Windows ----
test_setup_repairs_stale_windows_hooks() {
    if [ "$IS_WINDOWS" != "true" ]; then
        return
    fi

    local ws
    ws=$(mktemp -d "$MKTEMP_DIR/sdlc-test.XXXXXX")
    echo '{"name":"test-app","scripts":{"test":"jest"}}' > "$ws/package.json"
    mkdir -p "$ws/src" "$ws/.codex/hooks"
    cat > "$ws/.codex/hooks.json" <<'EOF'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "^Bash$",
        "hooks": [
          {
            "type": "command",
            "command": ".codex/hooks/bash-guard.sh"
          }
        ]
      }
    ],
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": ".codex/hooks/session-start.sh"
          }
        ]
      }
    ]
  }
}
EOF

    run_setup "$ws"

    local repaired=false
    if grep -q 'node \.codex/hooks/git-guard\.cjs' "$ws/.codex/hooks.json" 2>/dev/null \
        && ! grep -q 'bash-guard\.sh' "$ws/.codex/hooks.json" 2>/dev/null \
        && ! grep -q 'powershell\.exe' "$ws/.codex/hooks.json" 2>/dev/null; then
        repaired=true
    fi
    rm -rf "$ws"

    if [ "$repaired" = "true" ]; then
        pass "setup.sh repairs stale Windows Bash hooks with universal Node hooks"
    else
        fail "setup.sh left stale Windows Bash hooks in place"
    fi
}

# ---- Test 22: check.sh reports uninitialized repo when manifest is missing ----
test_check_reports_uninitialized() {
    local ws
    ws=$(mktemp -d "$MKTEMP_DIR/sdlc-test.XXXXXX")
    echo '{"name":"test-app"}' > "$ws/package.json"

    local output
    output=$(run_check "$ws")
    rm -rf "$ws"

    if json_text_equals "$output" 'data.repo_state' "uninitialized"; then
        pass "check.sh reports uninitialized repo when manifest is missing"
    else
        fail "check.sh did not report uninitialized repo (got: $(json_text_get "$output" 'data.repo_state'))"
    fi
}

# ---- Test 23: check.sh reports managed files as match after setup ----
test_check_reports_matches() {
    local ws
    ws=$(mktemp -d "$MKTEMP_DIR/sdlc-test.XXXXXX")
    echo '{"name":"test-app","scripts":{"test":"jest"}}' > "$ws/package.json"
    mkdir -p "$ws/src"

    run_setup "$ws"

    local output
    output=$(run_check "$ws")
    rm -rf "$ws"

    local hook_expr='data.managed_files[".codex/hooks/git-guard.cjs"].status'

    if json_text_equals "$output" 'data.repo_state' "initialized" \
        && json_text_equals "$output" 'data.managed_files["AGENTS.md"].status' "match" \
        && json_text_equals "$output" 'data.managed_files["SDLC.md"].status' "match" \
        && json_text_equals "$output" 'data.managed_files["SDLC-LOOP.md"].status' "match" \
        && json_text_equals "$output" 'data.managed_files[".codex/config.toml"].status' "match" \
        && json_text_equals "$output" 'data.managed_files[".codex/hooks.json"].status' "match" \
        && json_text_equals "$output" "$hook_expr" "match"; then
        pass "check.sh reports managed files as match after setup"
    else
        fail "check.sh did not report matches correctly (state=$(json_text_get "$output" 'data.repo_state'), agents=$(json_text_get "$output" 'data.managed_files[\"AGENTS.md\"].status'), sdlc=$(json_text_get "$output" 'data.managed_files[\"SDLC.md\"].status'), loop=$(json_text_get "$output" 'data.managed_files[\"SDLC-LOOP.md\"].status'), config=$(json_text_get "$output" 'data.managed_files[\".codex/config.toml\"].status'), hooks=$(json_text_get "$output" 'data.managed_files[\".codex/hooks.json\"].status'), hook_script=$(json_text_get "$output" "$hook_expr"))"
    fi
}

# ---- Test 24: check.sh reports customized files when hashes drift ----
test_check_reports_customized() {
    local ws
    ws=$(mktemp -d "$MKTEMP_DIR/sdlc-test.XXXXXX")
    echo '{"name":"test-app","scripts":{"test":"jest"}}' > "$ws/package.json"
    mkdir -p "$ws/src"

    run_setup "$ws"
    echo "CUSTOM CHANGE" >> "$ws/AGENTS.md"

    local output
    output=$(run_check "$ws")
    rm -rf "$ws"

    if json_text_equals "$output" 'data.managed_files["AGENTS.md"].status' "customized"; then
        pass "check.sh reports customized files when hashes drift"
    else
        fail "check.sh did not report customized file (got: $(json_text_get "$output" 'data.managed_files[\"AGENTS.md\"].status'))"
    fi
}

# ---- Test 25: check.sh reports missing files when managed docs are deleted ----
test_check_reports_missing() {
    local ws
    ws=$(mktemp -d "$MKTEMP_DIR/sdlc-test.XXXXXX")
    echo '{"name":"test-app","scripts":{"test":"jest"}}' > "$ws/package.json"
    mkdir -p "$ws/src"

    run_setup "$ws"
    rm -f "$ws/TESTING.md"

    local output
    output=$(run_check "$ws")
    rm -rf "$ws"

    if json_text_equals "$output" 'data.managed_files["TESTING.md"].status' "missing"; then
        pass "check.sh reports missing files when managed docs are deleted"
    else
        fail "check.sh did not report missing file (got: $(json_text_get "$output" 'data.managed_files[\"TESTING.md\"].status'))"
    fi
}

# ---- Test 26: check.sh reports stale Windows Bash hook wiring as drift / broken ----
test_check_reports_windows_hook_drift() {
    if [ "$IS_WINDOWS" != "true" ]; then
        return
    fi

    local ws
    ws=$(mktemp -d "$MKTEMP_DIR/sdlc-test.XXXXXX")
    echo '{"name":"test-app","scripts":{"test":"jest"}}' > "$ws/package.json"
    mkdir -p "$ws/src"

    run_setup "$ws"
    cat > "$ws/.codex/hooks.json" <<'EOF'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "^Bash$",
        "hooks": [
          {
            "type": "command",
            "command": ".codex/hooks/bash-guard.sh"
          }
        ]
      }
    ],
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": ".codex/hooks/session-start.sh"
          }
        ]
      }
    ]
  }
}
EOF

    local output
    output=$(run_check "$ws")
    rm -rf "$ws"

    if json_text_equals "$output" 'data.managed_files[".codex/hooks.json"].status' "drift / broken"; then
        pass "check.sh reports stale Windows Bash hook wiring as drift / broken"
    else
        fail "check.sh did not report Windows hook drift (got: $(json_text_get "$output" 'data.managed_files[\".codex/hooks.json\"].status'))"
    fi
}

# ---- Test 27: check.sh reports platform-specific hook wiring as drift / broken even when hashes match ----
test_check_reports_platform_hook_drift() {
    local ws
    ws=$(mktemp -d "$MKTEMP_DIR/sdlc-test.XXXXXX")
    echo '{"name":"test-app","scripts":{"test":"jest"}}' > "$ws/package.json"
    mkdir -p "$ws/src"

    run_setup "$ws"

    if [ "$IS_WINDOWS" = "true" ]; then
        cat > "$ws/.codex/hooks.json" <<'EOF'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "^Bash$",
        "hooks": [
          {
            "type": "command",
            "command": ".codex/hooks/bash-guard.sh"
          }
        ]
      }
    ]
  }
}
EOF
    else
        cat > "$ws/.codex/hooks.json" <<'EOF'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "^Bash$",
        "hooks": [
          {
            "type": "command",
            "command": "powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .codex/hooks/git-guard.ps1"
          }
        ]
      }
    ]
  }
}
EOF
    fi

    MANIFEST_PATH="$ws/.codex-sdlc/manifest.json" HOOKS_PATH="$ws/.codex/hooks.json" node - <<'NODE'
const crypto = require("crypto");
const fs = require("fs");

const manifestPath = process.env.MANIFEST_PATH;
const hooksPath = process.env.HOOKS_PATH;
const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
const hash = crypto.createHash("sha256").update(fs.readFileSync(hooksPath)).digest("hex");
manifest.managed_files[".codex/hooks.json"] = `sha256:${hash}`;
fs.writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
NODE

    local output
    output=$(run_check "$ws")
    rm -rf "$ws"

    if json_text_equals "$output" 'data.managed_files[".codex/hooks.json"].status' "drift / broken"; then
        pass "check.sh reports platform-specific hook wiring as drift / broken"
    else
        fail "check.sh did not report platform-specific hook drift (got: $(json_text_get "$output" 'data.managed_files[\".codex/hooks.json\"].status'))"
    fi
}

# ---- Test 27: scan detects extended setup fields used by adaptive setup parity ----
test_detect_extended_setup_fields() {
    local ws
    ws=$(mktemp -d "$MKTEMP_DIR/sdlc-test.XXXXXX")
    cat > "$ws/package.json" <<'EOF'
{"name":"test-app","scripts":{"test":"jest --coverage","lint":"eslint .","build":"tsc -p tsconfig.json","typecheck":"tsc --noEmit"}}
EOF
    echo '{}' > "$ws/tsconfig.json"
    echo 'FROM node:20' > "$ws/Dockerfile"
    cat > "$ws/.env" <<'EOF'
DATABASE_URL=postgres://localhost/test
REDIS_URL=redis://localhost:6379
EOF
    mkdir -p "$ws/src" "$ws/tests/integration" "$ws/e2e"
    touch "$ws/jest.config.js" "$ws/playwright.config.js"
    touch "$ws/tests/unit.test.js" "$ws/tests/integration/orders.integration.test.js" "$ws/e2e/app.e2e.ts"

    local output
    output=$(run_scan "$ws")
    rm -rf "$ws"

    if json_text_equals "$output" 'data.typecheck_command' "npm run typecheck" \
        && json_text_equals "$output" 'data.single_test_command' "npm test -- <test-file>" \
        && json_text_equals "$output" 'data.deployment_setup' "docker" \
        && json_text_equals "$output" 'data.databases' "postgresql" \
        && json_text_equals "$output" 'data.cache_layer' "redis" \
        && json_text_equals "$output" 'data.coverage_config' "jest --coverage" \
        && json_text_equals "$output" 'data.test_duration' "<1 minute" \
        && json_text_equals "$output" 'data.test_types' "unit, integration, e2e"; then
        pass "scan detects extended setup fields for commands, infra, coverage, and test shape"
    else
        fail "scan missed extended setup fields"
    fi
}

# ---- Test 28: scan detects Playwright MCP browser profile policy ----
test_detect_playwright_mcp_policy() {
    local ws
    ws=$(mktemp -d "$MKTEMP_DIR/sdlc-test.XXXXXX")
    cat > "$ws/package.json" <<'EOF'
{"name":"mcp-app","scripts":{"test":"playwright test"}}
EOF
    mkdir -p "$ws/tests"
    cat > "$ws/.mcp.json" <<'EOF'
{
  "mcpServers": {
    "playwright": {
      "command": "npx",
      "args": ["@playwright/mcp@latest"]
    }
  }
}
EOF

    local output
    output=$(run_scan "$ws")
    rm -rf "$ws"

    if json_text_equals "$output" 'data.mcp_browser_tooling' "playwright-mcp" \
        && json_text_equals "$output" 'data.mcp_browser_profile_policy' "unknown"; then
        pass "scan detects Playwright MCP browser profile policy"
    else
        fail "scan did not detect Playwright MCP browser profile policy"
    fi
}

# ---- Test 29: setup documents Playwright MCP profile isolation policy ----
test_setup_documents_playwright_mcp_profile_policy() {
    local ws
    ws=$(mktemp -d "$MKTEMP_DIR/sdlc-test.XXXXXX")
    cat > "$ws/package.json" <<'EOF'
{"name":"mcp-app","scripts":{"test":"playwright test"}}
EOF
    mkdir -p "$ws/tests"
    cat > "$ws/.mcp.json" <<'EOF'
{
  "mcpServers": {
    "playwright": {
      "command": "npx",
      "args": ["@playwright/mcp@latest", "--user-data-dir=.browser-state/playwright-mcp"]
    }
  }
}
EOF
    local mcp_before
    mcp_before=$(cat "$ws/.mcp.json")

    run_setup "$ws"
    (
        cd "$ws"
        CODEX_HOME="$ws/.codex-home" bash "$UPDATE_SH" force-all >/dev/null 2>&1
    )

    local valid=true
    json_text_equals "$(cat "$ws/.codex-sdlc/manifest.json")" 'data.scan.mcp_browser_tooling' "playwright-mcp" || valid=false
    json_text_equals "$(cat "$ws/.codex-sdlc/manifest.json")" 'data.scan.mcp_browser_profile_policy' "shared/persistent" || valid=false
    grep -qi 'profile-lock collision' "$ws/ARCHITECTURE.md" 2>/dev/null || valid=false
    grep -qi 'explicit opt-in isolation' "$ws/ARCHITECTURE.md" 2>/dev/null || valid=false
    grep -qi 'stateful.*auth-heavy\|auth-heavy.*stateful' "$ws/ARCHITECTURE.md" 2>/dev/null || valid=false
    [ "$(cat "$ws/.mcp.json")" = "$mcp_before" ] || valid=false
    rm -rf "$ws"

    if [ "$valid" = "true" ]; then
        pass "setup documents Playwright MCP profile isolation policy without overwriting .mcp.json"
    else
        fail "setup did not document Playwright MCP isolation policy or changed .mcp.json"
    fi
}

# ---- Test 30: setup writes extended commands and infra into generated docs ----
test_setup_generates_extended_setup_docs() {
    local ws
    ws=$(mktemp -d "$MKTEMP_DIR/sdlc-test.XXXXXX")
    cat > "$ws/package.json" <<'EOF'
{"name":"test-app","scripts":{"test":"jest --coverage","lint":"eslint .","build":"tsc -p tsconfig.json","typecheck":"tsc --noEmit"}}
EOF
    echo '{}' > "$ws/tsconfig.json"
    echo 'FROM node:20' > "$ws/Dockerfile"
    cat > "$ws/.env" <<'EOF'
DATABASE_URL=postgres://localhost/test
REDIS_URL=redis://localhost:6379
EOF
    mkdir -p "$ws/src" "$ws/tests/integration" "$ws/e2e"
    touch "$ws/jest.config.js" "$ws/playwright.config.js"
    touch "$ws/tests/unit.test.js" "$ws/tests/integration/orders.integration.test.js" "$ws/e2e/app.e2e.ts"

    run_setup "$ws"

    local valid=true
    grep -q 'Type-check' "$ws/SDLC.md" 2>/dev/null || valid=false
    grep -q 'npm run typecheck' "$ws/SDLC.md" 2>/dev/null || valid=false
    grep -q 'Single test file' "$ws/SDLC.md" 2>/dev/null || valid=false
    grep -q 'npm test -- <test-file>' "$ws/SDLC.md" 2>/dev/null || valid=false
    grep -q 'Coverage' "$ws/TESTING.md" 2>/dev/null || valid=false
    grep -q 'jest --coverage' "$ws/TESTING.md" 2>/dev/null || valid=false
    grep -q 'Test types' "$ws/TESTING.md" 2>/dev/null || valid=false
    grep -q 'unit, integration, e2e' "$ws/TESTING.md" 2>/dev/null || valid=false
    grep -q 'docker' "$ws/ARCHITECTURE.md" 2>/dev/null || valid=false
    grep -q 'postgresql' "$ws/ARCHITECTURE.md" 2>/dev/null || valid=false
    grep -q 'redis' "$ws/ARCHITECTURE.md" 2>/dev/null || valid=false
    rm -rf "$ws"

    if [ "$valid" = "true" ]; then
        pass "setup writes extended commands and infra into generated docs"
    else
        fail "setup docs did not include the extended setup fields"
    fi
}

# ---- Test 31: interactive setup allows overriding detected values instead of aborting ----
test_setup_interactive_allows_overriding_detected_values() {
    local ws
    ws=$(mktemp -d "$MKTEMP_DIR/sdlc-test.XXXXXX")
    cat > "$ws/package.json" <<'EOF'
{"name":"test-app","scripts":{"test":"jest","lint":"eslint .","build":"tsc","typecheck":"tsc --noEmit"}}
EOF
    mkdir -p "$ws/src" "$ws/__tests__"
    touch "$ws/jest.config.js" "$ws/tsconfig.json"

    local output
    output=$(run_setup_interactive "$ws" $'\nedit\napp/\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n')

    local valid=true
    echo "$output" | grep -q 'If any detected values are wrong, type edit to review them now' 2>/dev/null || valid=false
    echo "$output" | grep -q 'Source directory \[src/\]' 2>/dev/null || valid=false
    echo "$output" | grep -vq 'Aborted\.' 2>/dev/null || valid=false
    grep -q 'Source directory: `app/`' "$ws/SDLC.md" 2>/dev/null || valid=false
    if ! json_text_equals "$(cat "$ws/.codex-sdlc/manifest.json")" 'data.resolved_values.source_dir' "app/"; then
        valid=false
    fi
    rm -rf "$ws"

    if [ "$valid" = "true" ]; then
        pass "interactive setup allows overriding detected values instead of aborting"
    else
        fail "interactive setup still aborts or ignores overrides for detected values"
    fi
}

# ---- Test 30: verify-only reports missing managed files without regenerating them ----
test_setup_verify_only_reports_missing_files() {
    local ws
    ws=$(mktemp -d "$MKTEMP_DIR/sdlc-test.XXXXXX")
    echo '{"name":"test-app","scripts":{"test":"jest"}}' > "$ws/package.json"
    mkdir -p "$ws/src"

    run_setup "$ws"
    rm -f "$ws/TESTING.md"

    local output status
    set +e
    output=$(run_setup_args "$ws" verify-only)
    status=$?
    set -e

    local valid=true
    [ "$status" -ne 0 ] || valid=false
    echo "$output" | grep -q 'Verifying installation' 2>/dev/null || valid=false
    echo "$output" | grep -q 'MISSING: TESTING.md' 2>/dev/null || valid=false
    [ ! -f "$ws/TESTING.md" ] || valid=false
    rm -rf "$ws"

    if [ "$valid" = "true" ]; then
        pass "verify-only reports missing managed files without regenerating them"
    else
        fail "verify-only did not stay read-only or did not report the missing managed file"
    fi
}

# ---- Test 31: regenerate rebuilds docs from stored setup state without interactive prompts ----
test_setup_regenerate_rebuilds_docs_from_manifest() {
    local ws
    ws=$(mktemp -d "$MKTEMP_DIR/sdlc-test.XXXXXX")
    echo '{"name":"test-app","scripts":{"test":"jest","lint":"eslint .","build":"tsc"}}' > "$ws/package.json"
    mkdir -p "$ws/src" "$ws/__tests__"
    touch "$ws/jest.config.js"

    run_setup "$ws"

    MANIFEST_PATH="$ws/.codex-sdlc/manifest.json" node -e '
const fs = require("fs");
const file = process.env.MANIFEST_PATH;
const data = JSON.parse(fs.readFileSync(file, "utf8"));
data.resolved_values.source_dir = "app/";
fs.writeFileSync(file, `${JSON.stringify(data, null, 2)}\n`);
'
    rm -f "$ws/SDLC.md" "$ws/TESTING.md" "$ws/ARCHITECTURE.md"

    local output status
    set +e
    output=$(run_setup_args "$ws" regenerate)
    status=$?
    set -e

    local valid=true
    [ "$status" -eq 0 ] || valid=false
    echo "$output" | grep -vq 'Use scan results above and continue' 2>/dev/null || valid=false
    [ -f "$ws/SDLC.md" ] || valid=false
    [ -f "$ws/TESTING.md" ] || valid=false
    [ -f "$ws/ARCHITECTURE.md" ] || valid=false
    grep -q 'Source directory: `app/`' "$ws/SDLC.md" 2>/dev/null || valid=false
    rm -rf "$ws"

    if [ "$valid" = "true" ]; then
        pass "regenerate rebuilds docs from stored setup state without interactive prompts"
    else
        fail "regenerate did not rebuild docs from manifest-backed setup state"
    fi
}

# ---- Test 32: setup falls back to Node hashing when shell hash tools are unavailable ----
test_setup_hashes_manifest_without_shell_hash_tools() {
    local ws
    local fakebin
    ws=$(mktemp -d "$MKTEMP_DIR/sdlc-test.XXXXXX")
    fakebin=$(mktemp -d "$MKTEMP_DIR/sdlc-test.XXXXXX")
    echo '{"name":"test-app","scripts":{"test":"jest"}}' > "$ws/package.json"
    mkdir -p "$ws/src"

    printf '#!/bin/sh\nexit 127\n' > "$fakebin/shasum"
    printf '#!/bin/sh\nexit 127\n' > "$fakebin/sha256sum"
    chmod +x "$fakebin/shasum" "$fakebin/sha256sum"

    local output status hash valid=true
    set +e
    output=$(cd "$ws" && CODEX_SDLC_DISABLE_REASONING=1 CODEX_HOME="$ws/.codex-home" PATH="$fakebin:$PATH" bash "$SETUP_SH" --yes 2>&1)
    status=$?
    set -e

    [ "$status" -eq 0 ] || valid=false
    [ -f "$ws/.codex-sdlc/manifest.json" ] || valid=false
    hash=$(json_eval_stdin 'data.managed_files["AGENTS.md"]' < "$ws/.codex-sdlc/manifest.json" || true)
    printf '%s' "$hash" | grep -Eq '^sha256:[0-9a-f]{64}$' || valid=false
    echo "$output" | grep -q 'command not found' && valid=false

    rm -rf "$ws" "$fakebin"

    if [ "$valid" = "true" ]; then
        pass "setup falls back to Node hashing when shell hash tools are unavailable"
    else
        fail "setup did not produce valid manifest hashes without shell hash tools"
    fi
}

# ---- Test 33: interactive setup uses codex exec with gpt-5.5 xhigh reasoning when available ----
test_setup_uses_codex_xhigh_reasoning_when_available() {
    local ws
    local fakebin
    local args_file
    ws=$(mktemp -d "$MKTEMP_DIR/sdlc-test.XXXXXX")
    fakebin=$(mktemp -d "$MKTEMP_DIR/sdlc-test.XXXXXX")
    args_file="$ws/codex-args.txt"

    cat > "$ws/package.json" <<'EOF'
{"name":"test-app","scripts":{"test":"npm test"}}
EOF
    mkdir -p "$ws/tests"
    touch "$ws/playwright.config.js" "$ws/tests/app.e2e.ts"

    cat > "$fakebin/codex" <<'EOF'
#!/bin/sh
set -eu
args_file="${FAKE_CODEX_ARGS_FILE:-}"
output_file=""
previous=""

for arg in "$@"; do
    if [ -n "$args_file" ]; then
        printf '%s\n' "$arg" >> "$args_file"
    fi
    if [ "$previous" = "-o" ]; then
        output_file="$arg"
    fi
    previous="$arg"
done

if [ -z "$output_file" ]; then
    echo "missing output file" >&2
    exit 64
fi

cat > "$output_file" <<'JSON'
{
  "language": "javascript",
  "source_dir": "app/",
  "test_dir": "tests/",
  "test_framework": "playwright",
  "test_command": "npm test",
  "lint_command": "npm run lint",
  "typecheck_command": "",
  "single_test_command": "npx playwright test <test-file>",
  "build_command": "",
  "deployment_setup": "",
  "databases": "",
  "cache_layer": "",
  "test_duration": "<1 minute",
  "test_types": "unit, e2e, api",
  "coverage_config": "",
  "ci": "",
  "domain": "web",
  "confidence_map": {
    "source_dir": "inferred",
    "test_dir": "detected",
    "test_framework": "detected",
    "test_command": "detected",
    "lint_command": "inferred",
    "typecheck_command": "unresolved",
    "single_test_command": "inferred",
    "build_command": "unresolved",
    "deployment_setup": "unresolved",
    "databases": "unresolved",
    "cache_layer": "unresolved",
    "test_duration": "inferred",
    "test_types": "detected",
    "coverage_config": "unresolved",
    "ci": "unresolved",
    "domain": "inferred"
  }
}
JSON
EOF
    chmod +x "$fakebin/codex"

    local output valid=true
    output=$(cd "$ws" && printf '\n\n\n\n\n' | CODEX_HOME="$ws/.codex-home" FAKE_CODEX_ARGS_FILE="$args_file" PATH="$fakebin:$PATH" bash "$SETUP_SH" 2>&1)

    grep -qx 'exec' "$args_file" 2>/dev/null || valid=false
    grep -qx -- '-s' "$args_file" 2>/dev/null || valid=false
    grep -qx 'read-only' "$args_file" 2>/dev/null || valid=false
    grep -qx -- '--skip-git-repo-check' "$args_file" 2>/dev/null || valid=false
    grep -qx -- '--output-schema' "$args_file" 2>/dev/null || valid=false
    grep -qx 'model="gpt-5.5"' "$args_file" 2>/dev/null || valid=false
    grep -qx 'model_reasoning_effort="xhigh"' "$args_file" 2>/dev/null || valid=false
    echo "$output" | grep -vq 'Set source directory' 2>/dev/null || valid=false
    grep -q 'Source directory: `app/`' "$ws/SDLC.md" 2>/dev/null || valid=false
    if ! json_text_equals "$(cat "$ws/.codex-sdlc/manifest.json")" 'data.resolved_values.source_dir' "app/"; then
        valid=false
    fi

    rm -rf "$ws" "$fakebin"

    if [ "$valid" = "true" ]; then
        pass "interactive setup uses codex exec with gpt-5.5 xhigh reasoning when available"
    else
        fail "interactive setup did not use the codex xhigh reasoning path correctly"
    fi
}

# ---- Test 34: setup writes mixed profile with xhigh main reasoning ----
test_setup_writes_mixed_profile_with_xhigh_reasoning() {
    local ws
    ws=$(mktemp -d "$MKTEMP_DIR/sdlc-test.XXXXXX")
    echo '{"name":"test-app","scripts":{"test":"jest"}}' > "$ws/package.json"
    mkdir -p "$ws/src"

    run_setup_args "$ws" --yes --model-profile mixed >/dev/null 2>&1

    local valid=true
    grep -q '^model = "gpt-5.4-mini"' "$ws/.codex/config.toml" 2>/dev/null || valid=false
    grep -q '^model_reasoning_effort = "xhigh"' "$ws/.codex/config.toml" 2>/dev/null || valid=false
    grep -q '^review_model = "gpt-5.5"' "$ws/.codex/config.toml" 2>/dev/null || valid=false
    if ! json_text_equals "$(cat "$ws/.codex-sdlc/model-profile.json")" 'data.profiles.mixed.main_reasoning' "xhigh"; then
        valid=false
    fi

    rm -rf "$ws"

    if [ "$valid" = "true" ]; then
        pass "setup writes mixed profile with xhigh main reasoning"
    else
        fail "setup did not write mixed profile with xhigh main reasoning"
    fi
}

# ---- Test 35: setup falls back to deterministic scan when codex reasoning fails ----
test_setup_falls_back_when_codex_reasoning_fails() {
    local ws
    local fakebin
    ws=$(mktemp -d "$MKTEMP_DIR/sdlc-test.XXXXXX")
    fakebin=$(mktemp -d "$MKTEMP_DIR/sdlc-test.XXXXXX")

    echo '{"name":"test-app","scripts":{"test":"jest"}}' > "$ws/package.json"
    mkdir -p "$ws/src" "$ws/__tests__"
    touch "$ws/jest.config.js"

    cat > "$fakebin/codex" <<'EOF'
#!/bin/sh
exit 42
EOF
    chmod +x "$fakebin/codex"

    local output status valid=true
    set +e
    output=$(cd "$ws" && CODEX_HOME="$ws/.codex-home" PATH="$fakebin:$PATH" bash "$SETUP_SH" --yes 2>&1)
    status=$?
    set -e

    [ "$status" -eq 0 ] || valid=false
    [ -f "$ws/AGENTS.md" ] || valid=false
    [ -f "$ws/.codex-sdlc/manifest.json" ] || valid=false
    grep -q 'Scanning project' <<< "$output" 2>/dev/null || valid=false

    rm -rf "$ws" "$fakebin"

    if [ "$valid" = "true" ]; then
        pass "setup falls back to deterministic scan when codex reasoning fails"
    else
        fail "setup did not fall back cleanly when codex reasoning failed"
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
test_setup_generates_sdlc_md
test_setup_interactive_only_asks_preferences
test_setup_interactive_accepts_scan_without_prompting_optional_blanks
test_setup_interactive_asks_missing_core_facts
test_setup_interactive_ci_shepherd_is_conditional
test_setup_interactive_shows_inferred_values
test_manifest_created
test_setup_repairs_stale_windows_hooks
test_check_reports_uninitialized
test_check_reports_matches
test_check_reports_customized
test_check_reports_missing
test_check_reports_windows_hook_drift
test_check_reports_platform_hook_drift
test_detect_extended_setup_fields
test_detect_playwright_mcp_policy
test_setup_documents_playwright_mcp_profile_policy
test_setup_generates_extended_setup_docs
test_setup_interactive_allows_overriding_detected_values
test_setup_verify_only_reports_missing_files
test_setup_regenerate_rebuilds_docs_from_manifest
test_setup_hashes_manifest_without_shell_hash_tools
test_setup_uses_codex_xhigh_reasoning_when_available
test_setup_writes_mixed_profile_with_xhigh_reasoning
test_setup_falls_back_when_codex_reasoning_fails

echo ""
echo "=== Results: $PASSED passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
    exit 1
fi
