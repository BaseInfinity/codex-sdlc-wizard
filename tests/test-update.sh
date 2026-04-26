#!/bin/bash
# Test update.sh selective update behavior

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$SCRIPT_DIR/.."
SETUP_SH="$REPO_DIR/setup.sh"
UPDATE_SH="$REPO_DIR/update.sh"
CHECK_SH="$REPO_DIR/check.sh"
PASSED=0
FAILED=0

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

json_eval_stdin() {
    local expr="$1"
    JSON_EXPR="$expr" node -e '
const fs = require("fs");
const expr = process.env.JSON_EXPR;
const input = fs.readFileSync(0, "utf8");
if (!input.trim()) process.exit(1);
const data = JSON.parse(input);
const value = Function("data", `return (${expr});`)(data);
if (value === undefined || value === null) process.exit(1);
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

run_setup_local() {
    local project_dir="$1"
    (cd "$project_dir" && CODEX_SDLC_DISABLE_REASONING=1 CODEX_HOME="$project_dir/.codex-home" bash "$SETUP_SH" --yes >/dev/null 2>&1)
}

run_setup_local_args() {
    local project_dir="$1"
    shift
    (cd "$project_dir" && CODEX_SDLC_DISABLE_REASONING=1 CODEX_HOME="$project_dir/.codex-home" bash "$SETUP_SH" --yes "$@" >/dev/null 2>&1)
}

run_update() {
    local project_dir="$1"
    shift
    (cd "$project_dir" && CODEX_HOME="$project_dir/.codex-home" bash "$UPDATE_SH" "$@" 2>&1)
}

run_check() {
    local project_dir="$1"
    (cd "$project_dir" && bash "$CHECK_SH" 2>/dev/null)
}

echo "=== Update Tests ==="
echo ""

# ---- Test 1: update suggests setup on uninitialized repos ----
test_update_reports_uninitialized_repo() {
    local ws
    ws=$(mktemp -d "$MKTEMP_DIR/update-test.XXXXXX")
    echo '{"name":"test-app"}' > "$ws/package.json"

    local output status valid=true
    set +e
    output=$(run_update "$ws" check-only)
    status=$?
    set -e

    [ "$status" -ne 0 ] || valid=false
    echo "$output" | grep -qi 'uninitialized' 2>/dev/null || valid=false
    echo "$output" | grep -q '\$setup-wizard' 2>/dev/null || valid=false
    rm -rf "$ws"

    if [ "$valid" = "true" ]; then
        pass "update suggests setup on uninitialized repos"
    else
        fail "update did not recommend setup for an uninitialized repo"
    fi
}

# ---- Test 2: check-only reports missing managed files without repairing them ----
test_update_check_only_reports_missing_without_repair() {
    local ws
    ws=$(mktemp -d "$MKTEMP_DIR/update-test.XXXXXX")
    echo '{"name":"test-app","scripts":{"test":"jest"}}' > "$ws/package.json"
    mkdir -p "$ws/src"

    run_setup_local "$ws"
    rm -f "$ws/TESTING.md"

    local output status valid=true
    set +e
    output=$(run_update "$ws" check-only)
    status=$?
    set -e

    [ "$status" -eq 0 ] || valid=false
    echo "$output" | grep -q 'TESTING.md' 2>/dev/null || valid=false
    echo "$output" | grep -qi 'missing' 2>/dev/null || valid=false
    [ ! -f "$ws/TESTING.md" ] || valid=false
    rm -rf "$ws"

    if [ "$valid" = "true" ]; then
        pass "check-only reports missing managed files without repairing them"
    else
        fail "check-only repaired files or failed to report the missing managed file"
    fi
}

# ---- Test 3: update repairs missing generated docs by default ----
test_update_repairs_missing_generated_docs() {
    local ws
    ws=$(mktemp -d "$MKTEMP_DIR/update-test.XXXXXX")
    echo '{"name":"test-app","scripts":{"test":"jest"}}' > "$ws/package.json"
    mkdir -p "$ws/src"

    run_setup_local "$ws"
    rm -f "$ws/TESTING.md"

    local output check_output valid=true
    output=$(run_update "$ws")
    check_output=$(run_check "$ws")

    [ -f "$ws/TESTING.md" ] || valid=false
    echo "$output" | grep -q 'TESTING.md' 2>/dev/null || valid=false
    echo "$output" | grep -qi 'repair\|create\|apply' 2>/dev/null || valid=false
    json_text_equals "$check_output" 'data.managed_files["TESTING.md"].status' "match" || valid=false
    rm -rf "$ws"

    if [ "$valid" = "true" ]; then
        pass "update repairs missing generated docs by default"
    else
        fail "update did not repair the missing generated doc"
    fi
}

# ---- Test 4: update skips customized generated docs by default ----
test_update_skips_customized_docs_by_default() {
    local ws
    ws=$(mktemp -d "$MKTEMP_DIR/update-test.XXXXXX")
    echo '{"name":"test-app","scripts":{"test":"jest"}}' > "$ws/package.json"
    mkdir -p "$ws/src"

    run_setup_local "$ws"
    echo "CUSTOM UPDATE CONTENT" >> "$ws/SDLC.md"

    local output check_output valid=true
    output=$(run_update "$ws")
    check_output=$(run_check "$ws")

    grep -q 'CUSTOM UPDATE CONTENT' "$ws/SDLC.md" 2>/dev/null || valid=false
    echo "$output" | grep -q 'SDLC.md' 2>/dev/null || valid=false
    echo "$output" | grep -qi 'skip' 2>/dev/null || valid=false
    json_text_equals "$check_output" 'data.managed_files["SDLC.md"].status' "customized" || valid=false
    rm -rf "$ws"

    if [ "$valid" = "true" ]; then
        pass "update skips customized generated docs by default"
    else
        fail "update did not preserve the customized generated doc"
    fi
}

# ---- Test 5: force-all replaces customized generated docs ----
test_update_force_all_replaces_customized_docs() {
    local ws
    ws=$(mktemp -d "$MKTEMP_DIR/update-test.XXXXXX")
    echo '{"name":"test-app","scripts":{"test":"jest"}}' > "$ws/package.json"
    mkdir -p "$ws/src"

    run_setup_local "$ws"
    echo "CUSTOM UPDATE CONTENT" >> "$ws/SDLC.md"

    local output check_output valid=true
    output=$(run_update "$ws" force-all)
    check_output=$(run_check "$ws")

    if grep -q 'CUSTOM UPDATE CONTENT' "$ws/SDLC.md" 2>/dev/null; then
        valid=false
    fi
    echo "$output" | grep -q 'SDLC.md' 2>/dev/null || valid=false
    echo "$output" | grep -qi 'replace\|force' 2>/dev/null || valid=false
    json_text_equals "$check_output" 'data.managed_files["SDLC.md"].status' "match" || valid=false
    rm -rf "$ws"

    if [ "$valid" = "true" ]; then
        pass "force-all replaces customized generated docs"
    else
        fail "force-all did not replace the customized generated doc"
    fi
}

# ---- Test 6: update repairs Windows hook drift by default ----
test_update_repairs_windows_hook_drift() {
    if [ "$IS_WINDOWS" != "true" ]; then
        return
    fi

    local ws
    ws=$(mktemp -d "$MKTEMP_DIR/update-test.XXXXXX")
    echo '{"name":"test-app","scripts":{"test":"jest"}}' > "$ws/package.json"
    mkdir -p "$ws/src"

    run_setup_local "$ws"
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

    local output check_output valid=true
    output=$(run_update "$ws")
    check_output=$(run_check "$ws")

    grep -q 'git-guard\.ps1' "$ws/.codex/hooks.json" 2>/dev/null || valid=false
    if grep -q 'bash-guard\.sh' "$ws/.codex/hooks.json" 2>/dev/null; then
        valid=false
    fi
    echo "$output" | grep -q '.codex/hooks.json' 2>/dev/null || valid=false
    json_text_equals "$check_output" 'data.managed_files[".codex/hooks.json"].status' "match" || valid=false
    rm -rf "$ws"

    if [ "$valid" = "true" ]; then
        pass "update repairs Windows hook drift by default"
    else
        fail "update did not repair the Windows hook drift"
    fi
}

# ---- Test 7: update merges managed hook config into existing config.toml ----
test_update_merges_config_without_dropping_other_settings() {
    local ws
    ws=$(mktemp -d "$MKTEMP_DIR/update-test.XXXXXX")
    echo '{"name":"test-app","scripts":{"test":"jest"}}' > "$ws/package.json"
    mkdir -p "$ws/src"

    run_setup_local "$ws"
    cat > "$ws/.codex/config.toml" <<'EOF'
model = "gpt-5.5"
model_reasoning_effort = "xhigh"

[features]
codex_hooks = false

[model]
name = "o3"
EOF

    local output check_output valid=true
    output=$(run_update "$ws")
    check_output=$(run_check "$ws")

    grep -q 'codex_hooks = true' "$ws/.codex/config.toml" 2>/dev/null || valid=false
    grep -q '^model = "gpt-5.5"' "$ws/.codex/config.toml" 2>/dev/null || valid=false
    grep -q '^model_reasoning_effort = "xhigh"' "$ws/.codex/config.toml" 2>/dev/null || valid=false
    grep -q '^review_model =' "$ws/.codex/config.toml" 2>/dev/null && valid=false
    grep -q 'name = "o3"' "$ws/.codex/config.toml" 2>/dev/null || valid=false
    echo "$output" | grep -q '.codex/config.toml' 2>/dev/null || valid=false
    echo "$output" | grep -qi 'merge\|repair' 2>/dev/null || valid=false
    json_text_equals "$check_output" 'data.managed_files[".codex/config.toml"].status' "match" || valid=false
    rm -rf "$ws"

    if [ "$valid" = "true" ]; then
        pass "update merges model profile and codex_hooks into existing config.toml without dropping other settings"
    else
        fail "update did not merge the managed model/hook config into config.toml safely"
    fi
}

# ---- Test 8: update installs missing native skills into CODEX_HOME ----
test_update_repairs_missing_native_skills() {
    local ws
    ws=$(mktemp -d "$MKTEMP_DIR/update-test.XXXXXX")
    echo '{"name":"test-app","scripts":{"test":"jest"}}' > "$ws/package.json"
    mkdir -p "$ws/src"

    run_setup_local "$ws"
    rm -rf "$ws/.codex-home/skills/feedback"

    local output valid=true
    output=$(run_update "$ws")

    [ -f "$ws/.codex-home/skills/feedback/SKILL.md" ] || valid=false
    echo "$output" | grep -q 'skills/feedback' 2>/dev/null || valid=false
    echo "$output" | grep -qi 'install\|repair' 2>/dev/null || valid=false
    rm -rf "$ws"

    if [ "$valid" = "true" ]; then
        pass "update repairs missing native skills in CODEX_HOME"
    else
        fail "update did not repair the missing native skill"
    fi
}

# ---- Test 9: update removes legacy codex-sdlc skill after canonical sdlc is installed ----
test_update_removes_legacy_codex_sdlc_skill() {
    local ws
    ws=$(mktemp -d "$MKTEMP_DIR/update-test.XXXXXX")
    echo '{"name":"test-app","scripts":{"test":"jest"}}' > "$ws/package.json"
    mkdir -p "$ws/src"

    run_setup_local "$ws"
    rm -rf "$ws/.codex-home/skills/sdlc"
    cp -R "$REPO_DIR/skills/sdlc" "$ws/.codex-home/skills/sdlc"
    mkdir -p "$ws/.codex-home/skills/codex-sdlc"
    echo "LEGACY" > "$ws/.codex-home/skills/codex-sdlc/marker.txt"

    local check_output output valid=true
    check_output=$(run_update "$ws" check-only)
    echo "$check_output" | grep -q 'skills/sdlc' 2>/dev/null || valid=false
    echo "$check_output" | grep -qi 'same-name\|collision\|repo-scoped' 2>/dev/null || valid=false

    output=$(run_update "$ws")

    [ ! -d "$ws/.codex-home/skills/sdlc" ] || valid=false
    [ ! -d "$ws/.codex-home/skills/codex-sdlc" ] || valid=false
    find "$ws/.codex-home/backups/skills" -maxdepth 1 -name 'sdlc.bak.*' 2>/dev/null | grep -q . || valid=false
    find "$ws/.codex-home/backups/skills" -maxdepth 1 -name 'codex-sdlc.bak.*' 2>/dev/null | grep -q . || valid=false
    echo "$output" | grep -qi 'legacy.*codex-sdlc\|codex-sdlc.*legacy' 2>/dev/null || valid=false
    echo "$output" | grep -qi 'same-name\|collision\|repo-scoped' 2>/dev/null || valid=false
    rm -rf "$ws"

    if [ "$valid" = "true" ]; then
        pass "update removes wizard-managed global sdlc collisions and legacy codex-sdlc"
    else
        fail "update left duplicate global/repo sdlc skills or legacy codex-sdlc"
    fi
}

# ---- Test 10: update preserves user-owned global sdlc skill ----
test_update_preserves_user_owned_global_sdlc_skill() {
    local ws
    ws=$(mktemp -d "$MKTEMP_DIR/update-test.XXXXXX")
    echo '{"name":"test-app","scripts":{"test":"jest"}}' > "$ws/package.json"
    mkdir -p "$ws/src"

    run_setup_local "$ws"
    rm -rf "$ws/.codex-home/skills/sdlc"
    mkdir -p "$ws/.codex-home/skills/sdlc"
    cat > "$ws/.codex-home/skills/sdlc/SKILL.md" <<'EOF'
---
name: sdlc
description: User-owned SDLC skill that is intentionally not managed by codex-sdlc-wizard.
---

# User SDLC
EOF

    local output valid=true
    output=$(run_update "$ws")

    grep -q 'User-owned SDLC' "$ws/.codex-home/skills/sdlc/SKILL.md" 2>/dev/null || valid=false
    echo "$output" | grep -q 'skills/sdlc' 2>/dev/null && valid=false
    rm -rf "$ws"

    if [ "$valid" = "true" ]; then
        pass "update preserves user-owned global sdlc skill"
    else
        fail "update removed or reported a user-owned global sdlc skill"
    fi
}

# ---- Test 11: update repairs mixed profile drift to xhigh main reasoning ----
test_update_repairs_mixed_profile_reasoning_drift() {
    local ws
    ws=$(mktemp -d "$MKTEMP_DIR/update-test.XXXXXX")
    echo '{"name":"test-app","scripts":{"test":"jest"}}' > "$ws/package.json"
    mkdir -p "$ws/src"

    run_setup_local_args "$ws" --model-profile mixed
    cat > "$ws/.codex/config.toml" <<'EOF'
model = "gpt-5.4-mini"
model_reasoning_effort = "medium"
review_model = "gpt-5.4"

[features]
codex_hooks = true
EOF

    local output check_output valid=true
    output=$(run_update "$ws")
    check_output=$(run_check "$ws")

    grep -q '^model = "gpt-5.4-mini"' "$ws/.codex/config.toml" 2>/dev/null || valid=false
    grep -q '^model_reasoning_effort = "xhigh"' "$ws/.codex/config.toml" 2>/dev/null || valid=false
    grep -q '^review_model = "gpt-5.5"' "$ws/.codex/config.toml" 2>/dev/null || valid=false
    echo "$output" | grep -q '.codex/config.toml' 2>/dev/null || valid=false
    json_text_equals "$check_output" 'data.managed_files[".codex/config.toml"].status' "match" || valid=false
    rm -rf "$ws"

    if [ "$valid" = "true" ]; then
        pass "update repairs mixed profile drift to xhigh main reasoning"
    else
        fail "update did not repair mixed profile drift to xhigh main reasoning"
    fi
}

test_update_reports_uninitialized_repo
test_update_check_only_reports_missing_without_repair
test_update_repairs_missing_generated_docs
test_update_skips_customized_docs_by_default
test_update_force_all_replaces_customized_docs
test_update_repairs_windows_hook_drift
test_update_merges_config_without_dropping_other_settings
test_update_repairs_missing_native_skills
test_update_removes_legacy_codex_sdlc_skill
test_update_preserves_user_owned_global_sdlc_skill
test_update_repairs_mixed_profile_reasoning_drift

echo ""
echo "=== Results: $PASSED passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
    exit 1
fi
