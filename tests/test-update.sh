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

    run_setup_local_args "$ws" --model-profile mixed
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

    grep -q 'node \.codex/hooks/git-guard\.cjs' "$ws/.codex/hooks.json" 2>/dev/null || valid=false
    grep -q 'powershell\.exe' "$ws/.codex/hooks.json" 2>/dev/null && valid=false
    if grep -q 'bash-guard\.sh' "$ws/.codex/hooks.json" 2>/dev/null; then
        valid=false
    fi
    echo "$output" | grep -q '.codex/hooks.json' 2>/dev/null || valid=false
    json_text_equals "$check_output" 'data.managed_files[".codex/hooks.json"].status' "match" || valid=false
    rm -rf "$ws"

    if [ "$valid" = "true" ]; then
        pass "update repairs Windows hook drift with universal Node hooks by default"
    else
        fail "update did not repair the Windows hook drift"
    fi
}

# ---- Test 7: update repairs legacy .js Node hook commands ----
test_update_repairs_legacy_js_node_hooks() {
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
            "command": "node .codex/hooks/git-guard.js"
          }
        ]
      }
    ],
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "node .codex/hooks/session-start.js"
          }
        ]
      }
    ]
  }
}
EOF
    touch "$ws/.codex/hooks/git-guard.js" "$ws/.codex/hooks/session-start.js"

    local output check_output valid=true
    output=$(run_update "$ws")
    check_output=$(run_check "$ws")

    grep -q 'node \.codex/hooks/git-guard\.cjs' "$ws/.codex/hooks.json" 2>/dev/null || valid=false
    grep -q 'node \.codex/hooks/session-start\.cjs' "$ws/.codex/hooks.json" 2>/dev/null || valid=false
    [ ! -e "$ws/.codex/hooks/git-guard.js" ] || valid=false
    [ ! -e "$ws/.codex/hooks/session-start.js" ] || valid=false
    echo "$output" | grep -q '.codex/hooks.json' 2>/dev/null || valid=false
    json_text_equals "$check_output" 'data.managed_files[".codex/hooks.json"].status' "match" || valid=false
    rm -rf "$ws"

    if [ "$valid" = "true" ]; then
        pass "update repairs legacy .js Node hook commands"
    else
        fail "update did not repair legacy .js Node hook commands"
    fi
}

# ---- Test 8: update repairs legacy .js hook manifest entries ----
test_update_repairs_legacy_js_hook_manifest_entries() {
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
            "command": "node .codex/hooks/git-guard.js"
          }
        ]
      }
    ],
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "node .codex/hooks/session-start.js"
          }
        ]
      }
    ]
  }
}
EOF
    MANIFEST_PATH="$ws/.codex-sdlc/manifest.json" node <<'NODE'
const fs = require("fs");

const manifestPath = process.env.MANIFEST_PATH;
const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
delete manifest.managed_files[".codex/hooks/git-guard.cjs"];
delete manifest.managed_files[".codex/hooks/session-start.cjs"];
manifest.managed_files[".codex/hooks/git-guard.js"] = "sha256:0000000000000000000000000000000000000000000000000000000000000000";
manifest.managed_files[".codex/hooks/session-start.js"] = "sha256:0000000000000000000000000000000000000000000000000000000000000000";
fs.writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
NODE
    rm -f "$ws/.codex/hooks/git-guard.js" "$ws/.codex/hooks/session-start.js"

    local output check_output valid=true
    output=$(run_update "$ws" 2>&1) || valid=false
    check_output=$(run_check "$ws")

    grep -q 'node \.codex/hooks/git-guard\.cjs' "$ws/.codex/hooks.json" 2>/dev/null || valid=false
    grep -q 'node \.codex/hooks/session-start\.cjs' "$ws/.codex/hooks.json" 2>/dev/null || valid=false
    [ -f "$ws/.codex/hooks/git-guard.cjs" ] || valid=false
    [ -f "$ws/.codex/hooks/session-start.cjs" ] || valid=false
    [ ! -e "$ws/.codex/hooks/git-guard.js" ] || valid=false
    [ ! -e "$ws/.codex/hooks/session-start.js" ] || valid=false
    grep -q 'git-guard\.js' "$ws/.codex-sdlc/manifest.json" 2>/dev/null && valid=false
    grep -q 'session-start\.js' "$ws/.codex-sdlc/manifest.json" 2>/dev/null && valid=false
    json_text_equals "$check_output" 'data.managed_files[".codex/hooks.json"].status' "match" || valid=false
    rm -rf "$ws"

    if [ "$valid" = "true" ]; then
        pass "update repairs legacy .js hook manifest entries"
    else
        echo "$output" >&2
        fail "update did not repair legacy .js hook manifest entries"
    fi
}

# ---- Test 9: update repairs legacy .js hook manifest entries even when stale files match ----
test_update_repairs_matching_legacy_js_hook_manifest_entries() {
    local ws
    ws=$(mktemp -d "$MKTEMP_DIR/update-test.XXXXXX")
    echo '{"name":"test-app","scripts":{"test":"jest"}}' > "$ws/package.json"
    mkdir -p "$ws/src"

    run_setup_local "$ws"
    printf '%s\n' 'legacy git guard' > "$ws/.codex/hooks/git-guard.js"
    printf '%s\n' 'legacy session start' > "$ws/.codex/hooks/session-start.js"
    MANIFEST_PATH="$ws/.codex-sdlc/manifest.json" \
    GIT_GUARD_PATH="$ws/.codex/hooks/git-guard.js" \
    SESSION_START_PATH="$ws/.codex/hooks/session-start.js" \
    node <<'NODE'
const crypto = require("crypto");
const fs = require("fs");

function hash(filePath) {
  return `sha256:${crypto.createHash("sha256").update(fs.readFileSync(filePath)).digest("hex")}`;
}

const manifestPath = process.env.MANIFEST_PATH;
const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
delete manifest.managed_files[".codex/hooks/git-guard.cjs"];
delete manifest.managed_files[".codex/hooks/session-start.cjs"];
manifest.managed_files[".codex/hooks/git-guard.js"] = hash(process.env.GIT_GUARD_PATH);
manifest.managed_files[".codex/hooks/session-start.js"] = hash(process.env.SESSION_START_PATH);
fs.writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
NODE

    local output check_output valid=true
    output=$(run_update "$ws" 2>&1) || valid=false
    check_output=$(run_check "$ws")

    grep -q 'node \.codex/hooks/git-guard\.cjs' "$ws/.codex/hooks.json" 2>/dev/null || valid=false
    grep -q 'node \.codex/hooks/session-start\.cjs' "$ws/.codex/hooks.json" 2>/dev/null || valid=false
    [ -f "$ws/.codex/hooks/git-guard.cjs" ] || valid=false
    [ -f "$ws/.codex/hooks/session-start.cjs" ] || valid=false
    [ ! -e "$ws/.codex/hooks/git-guard.js" ] || valid=false
    [ ! -e "$ws/.codex/hooks/session-start.js" ] || valid=false
    grep -q 'git-guard\.js' "$ws/.codex-sdlc/manifest.json" 2>/dev/null && valid=false
    grep -q 'session-start\.js' "$ws/.codex-sdlc/manifest.json" 2>/dev/null && valid=false
    json_text_equals "$check_output" 'data.managed_files[".codex/hooks.json"].status' "match" || valid=false
    rm -rf "$ws"

    if [ "$valid" = "true" ]; then
        pass "update repairs matching legacy .js hook manifest entries"
    else
        echo "$output" >&2
        fail "update did not repair matching legacy .js hook manifest entries"
    fi
}

# ---- Test 10: update repairs old managed hook configs missing compact lifecycle hooks ----
test_update_repairs_matching_hook_surface_without_compact_lifecycle() {
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
            "command": "node .codex/hooks/git-guard.cjs"
          }
        ]
      }
    ],
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "node .codex/hooks/session-start.cjs"
          }
        ]
      }
    ]
  }
}
EOF
    rm -f "$ws/.codex/hooks/compact-guard.cjs"
    MANIFEST_PATH="$ws/.codex-sdlc/manifest.json" \
    HOOKS_JSON_PATH="$ws/.codex/hooks.json" \
    node <<'NODE'
const crypto = require("crypto");
const fs = require("fs");

const manifestPath = process.env.MANIFEST_PATH;
const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
delete manifest.managed_files[".codex/hooks/compact-guard.cjs"];
manifest.managed_files[".codex/hooks.json"] = `sha256:${crypto
  .createHash("sha256")
  .update(fs.readFileSync(process.env.HOOKS_JSON_PATH))
  .digest("hex")}`;
fs.writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
NODE

    local output check_output valid=true
    output=$(run_update "$ws" 2>&1) || valid=false
    check_output=$(run_check "$ws")

    grep -q 'node \.codex/hooks/compact-guard\.cjs' "$ws/.codex/hooks.json" 2>/dev/null || valid=false
    grep -q '"PreCompact"' "$ws/.codex/hooks.json" 2>/dev/null || valid=false
    grep -q '"PostCompact"' "$ws/.codex/hooks.json" 2>/dev/null || valid=false
    [ -f "$ws/.codex/hooks/compact-guard.cjs" ] || valid=false
    grep -q 'compact-guard\.cjs' "$ws/.codex-sdlc/manifest.json" 2>/dev/null || valid=false
    echo "$output" | grep -q '.codex/hooks.json' 2>/dev/null || valid=false
    json_text_equals "$check_output" 'data.managed_files[".codex/hooks.json"].status' "match" || valid=false
    json_text_equals "$check_output" 'data.managed_files[".codex/hooks/compact-guard.cjs"].status' "match" || valid=false
    rm -rf "$ws"

    if [ "$valid" = "true" ]; then
        pass "update repairs old managed hook configs missing compact lifecycle hooks"
    else
        echo "$output" >&2
        fail "update did not repair old managed hook configs missing compact lifecycle hooks"
    fi
}

# ---- Test 11: update repairs missing compact guard without overwriting customized hooks ----
test_update_repairs_missing_compact_guard_without_overwriting_custom_hooks() {
    local ws
    ws=$(mktemp -d "$MKTEMP_DIR/update-test.XXXXXX")
    echo '{"name":"test-app","scripts":{"test":"jest"}}' > "$ws/package.json"
    mkdir -p "$ws/src"

    run_setup_local "$ws"
    HOOKS_JSON_PATH="$ws/.codex/hooks.json" node <<'NODE'
const fs = require("fs");

const hooksPath = process.env.HOOKS_JSON_PATH;
const hooks = JSON.parse(fs.readFileSync(hooksPath, "utf8"));
hooks.hooks.CustomEvent = [
  {
    hooks: [
      {
        type: "command",
        command: "echo custom",
      },
    ],
  },
];
fs.writeFileSync(hooksPath, `${JSON.stringify(hooks, null, 2)}\n`);
NODE
    rm -f "$ws/.codex/hooks/compact-guard.cjs"

    local output check_output valid=true
    output=$(run_update "$ws" 2>&1) || valid=false
    check_output=$(run_check "$ws")

    [ -f "$ws/.codex/hooks/compact-guard.cjs" ] || valid=false
    grep -q '"CustomEvent"' "$ws/.codex/hooks.json" 2>/dev/null || valid=false
    echo "$output" | grep -q '.codex/hooks/compact-guard.cjs' 2>/dev/null || valid=false
    json_text_equals "$check_output" 'data.managed_files[".codex/hooks.json"].status' "customized" || valid=false
    json_text_equals "$check_output" 'data.managed_files[".codex/hooks/compact-guard.cjs"].status' "match" || valid=false
    rm -rf "$ws"

    if [ "$valid" = "true" ]; then
        pass "update repairs missing compact guard without overwriting customized hooks"
    else
        echo "$output" >&2
        fail "update overwrote customized hooks while repairing the compact guard"
    fi
}

# ---- Test 12: update merges managed hook config into existing config.toml ----
test_update_merges_config_without_dropping_other_settings() {
    local ws
    ws=$(mktemp -d "$MKTEMP_DIR/update-test.XXXXXX")
    echo '{"name":"test-app","scripts":{"test":"jest"}}' > "$ws/package.json"
    mkdir -p "$ws/src"

    run_setup_local "$ws"
    cat > "$ws/.codex/config.toml" <<'EOF'
model = "gpt-5.6-luna"
model_reasoning_effort = "xhigh"

[features]
codex_hooks = false

[model]
name = "o3"
EOF

    local output check_output valid=true
    output=$(run_update "$ws")
    check_output=$(run_check "$ws")

    grep -q '^hooks = true' "$ws/.codex/config.toml" 2>/dev/null || valid=false
    grep -v '^[[:space:]]*#' "$ws/.codex/config.toml" | grep -q '^codex_hooks\s*=' 2>/dev/null && valid=false
    grep -q '^model = "gpt-5.6-sol"' "$ws/.codex/config.toml" 2>/dev/null || valid=false
    grep -q '^model_reasoning_effort = "high"' "$ws/.codex/config.toml" 2>/dev/null || valid=false
    grep -q '^review_model = "gpt-5.6-sol"' "$ws/.codex/config.toml" 2>/dev/null || valid=false
    grep -q 'name = "o3"' "$ws/.codex/config.toml" 2>/dev/null || valid=false
    echo "$output" | grep -q '.codex/config.toml' 2>/dev/null || valid=false
    echo "$output" | grep -qi 'merge\|repair' 2>/dev/null || valid=false
    json_text_equals "$check_output" 'data.managed_files[".codex/config.toml"].status' "match" || valid=false
    rm -rf "$ws"

    if [ "$valid" = "true" ]; then
        pass "update migrates codex_hooks to hooks while preserving other config.toml settings"
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
    echo "$output" | grep -q '^- skills/sdlc:' 2>/dev/null && valid=false
    rm -rf "$ws"

    if [ "$valid" = "true" ]; then
        pass "update preserves user-owned global sdlc skill"
    else
        fail "update removed or reported a user-owned global sdlc skill"
    fi
}

# ---- Test 11: update repairs mixed profile drift to medium main reasoning ----
test_update_repairs_mixed_profile_reasoning_drift() {
    local ws
    ws=$(mktemp -d "$MKTEMP_DIR/update-test.XXXXXX")
    echo '{"name":"test-app","scripts":{"test":"jest"}}' > "$ws/package.json"
    mkdir -p "$ws/src"

    run_setup_local_args "$ws" --model-profile mixed
    cat > "$ws/.codex/config.toml" <<'EOF'
model = "gpt-5.6-luna"
model_reasoning_effort = "medium"
review_model = "gpt-5.6-terra"

[features]
codex_hooks = true
EOF

    local output check_output valid=true
    output=$(run_update "$ws")
    check_output=$(run_check "$ws")

    grep -q '^model = "gpt-5.6-terra"' "$ws/.codex/config.toml" 2>/dev/null || valid=false
    grep -q '^model_reasoning_effort = "medium"' "$ws/.codex/config.toml" 2>/dev/null || valid=false
    grep -q '^review_model = "gpt-5.6-sol"' "$ws/.codex/config.toml" 2>/dev/null || valid=false
    grep -q '^hooks = true' "$ws/.codex/config.toml" 2>/dev/null || valid=false
    grep -v '^[[:space:]]*#' "$ws/.codex/config.toml" | grep -q '^codex_hooks\s*=' 2>/dev/null && valid=false
    echo "$output" | grep -q '.codex/config.toml' 2>/dev/null || valid=false
    json_text_equals "$check_output" 'data.managed_files[".codex/config.toml"].status' "match" || valid=false
    rm -rf "$ws"

    if [ "$valid" = "true" ]; then
        pass "update repairs mixed profile drift to medium main reasoning"
    else
        fail "update did not repair mixed profile drift to medium main reasoning"
    fi
}

# ---- Test 12: profile-less updates restore the quality-first default ----
test_update_defaults_profile_less_repo_to_sol_high() {
    local ws
    ws=$(mktemp -d "$MKTEMP_DIR/update-test.XXXXXX")
    echo '{"name":"test-app","scripts":{"test":"jest"}}' > "$ws/package.json"
    mkdir -p "$ws/src"

    run_setup_local "$ws"
    node - "$ws/.codex-sdlc/manifest.json" <<'NODE'
const fs = require("fs");
const file = process.argv[2];
const manifest = JSON.parse(fs.readFileSync(file, "utf8"));
delete manifest.model_profile;
fs.writeFileSync(file, `${JSON.stringify(manifest, null, 2)}\n`);
NODE
    rm -f "$ws/.codex-sdlc/model-profile.json"
    cat > "$ws/.codex/config.toml" <<'EOF'
model = "gpt-5.6-terra"
model_reasoning_effort = "medium"
review_model = "gpt-5.6-sol"

[features]
hooks = true
EOF

    local output update_status valid=true
    set +e
    output=$(run_update "$ws")
    update_status=$?
    set -e

    [ "$update_status" -eq 0 ] || valid=false
    grep -q '^model = "gpt-5.6-sol"' "$ws/.codex/config.toml" 2>/dev/null || valid=false
    grep -q '^model_reasoning_effort = "high"' "$ws/.codex/config.toml" 2>/dev/null || valid=false
    grep -q '^review_model = "gpt-5.6-sol"' "$ws/.codex/config.toml" 2>/dev/null || valid=false
    json_text_equals "$(cat "$ws/.codex-sdlc/model-profile.json")" 'data.selected_profile' "maximum" || valid=false
    grep -Fq 'Selected profile: maximum' "$ws/AGENTS.md" 2>/dev/null || valid=false
    grep -Fq 'Baseline reasoning: `high`' "$ws/AGENTS.md" 2>/dev/null || valid=false
    grep -Fq 'Selected profile: mixed' "$ws/AGENTS.md" 2>/dev/null && valid=false
    echo "$output" | grep -q '.codex/config.toml' 2>/dev/null || valid=false
    echo "$output" | grep -Fq 'Prepared for regeneration: AGENTS.md' || valid=false
    rm -rf "$ws"

    if [ "$valid" = "true" ]; then
        pass "profile-less update restores the Sol-high maximum profile"
    else
        fail "profile-less update did not restore the Sol-high maximum profile"
    fi
}

# ---- Test 12: update refreshes Playwright MCP policy for old manifests ----
test_update_refreshes_playwright_mcp_policy_for_old_manifest() {
    local ws
    ws=$(mktemp -d "$MKTEMP_DIR/update-test.XXXXXX")
    echo '{"name":"test-app","scripts":{"test":"playwright test"}}' > "$ws/package.json"
    mkdir -p "$ws/tests"

    run_setup_local "$ws"
    cat > "$ws/ARCHITECTURE.md" <<'EOF'
# Architecture

## Tech Stack

- **Language:** javascript

## Overview

Older generated architecture document without MCP browser policy guidance.
EOF
    MANIFEST_PATH="$ws/.codex-sdlc/manifest.json" ARCH_PATH="$ws/ARCHITECTURE.md" node - <<'NODE'
const crypto = require("crypto");
const fs = require("fs");

const manifestPath = process.env.MANIFEST_PATH;
const archPath = process.env.ARCH_PATH;
const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
const hash = crypto.createHash("sha256").update(fs.readFileSync(archPath)).digest("hex");

manifest.managed_files["ARCHITECTURE.md"] = `sha256:${hash}`;
delete manifest.scan.mcp_browser_tooling;
delete manifest.scan.mcp_browser_profile_policy;
delete manifest.resolved_values.mcp_browser_tooling;
delete manifest.resolved_values.mcp_browser_profile_policy;
delete manifest.confidence_map.mcp_browser_tooling;
delete manifest.confidence_map.mcp_browser_profile_policy;

fs.writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
NODE
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

    local output check_output valid=true
    output=$(run_update "$ws")
    check_output=$(run_check "$ws")

    echo "$output" | grep -qi 'MCP browser policy\|mcp browser policy' 2>/dev/null || valid=false
    json_text_equals "$(cat "$ws/.codex-sdlc/manifest.json")" 'data.scan.mcp_browser_tooling' "playwright-mcp" || valid=false
    json_text_equals "$(cat "$ws/.codex-sdlc/manifest.json")" 'data.scan.mcp_browser_profile_policy' "shared/persistent" || valid=false
    grep -qi 'profile-lock collision' "$ws/ARCHITECTURE.md" 2>/dev/null || valid=false
    grep -qi 'explicit opt-in isolation' "$ws/ARCHITECTURE.md" 2>/dev/null || valid=false
    [ "$(cat "$ws/.mcp.json")" = "$mcp_before" ] || valid=false
    json_text_equals "$check_output" 'data.managed_files["ARCHITECTURE.md"].status' "match" || valid=false
    rm -rf "$ws"

    if [ "$valid" = "true" ]; then
        pass "update refreshes Playwright MCP profile policy for old manifests without overwriting .mcp.json"
    else
        fail "update did not refresh Playwright MCP profile policy for an old manifest"
    fi
}

# ---- Test 13: update refreshes changed Playwright MCP policy ----
test_update_refreshes_changed_playwright_mcp_policy() {
    local ws
    ws=$(mktemp -d "$MKTEMP_DIR/update-test.XXXXXX")
    echo '{"name":"test-app","scripts":{"test":"playwright test"}}' > "$ws/package.json"
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

    run_setup_local "$ws"
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

    local check_output valid=true
    run_update "$ws" >/dev/null
    check_output=$(run_check "$ws")

    json_text_equals "$(cat "$ws/.codex-sdlc/manifest.json")" 'data.scan.mcp_browser_profile_policy' "shared/persistent" || valid=false
    grep -q 'Detected browser profile policy: `shared/persistent`' "$ws/ARCHITECTURE.md" 2>/dev/null || valid=false
    [ "$(cat "$ws/.mcp.json")" = "$mcp_before" ] || valid=false
    json_text_equals "$check_output" 'data.managed_files["ARCHITECTURE.md"].status' "match" || valid=false
    rm -rf "$ws"

    if [ "$valid" = "true" ]; then
        pass "update refreshes changed Playwright MCP profile policy without overwriting .mcp.json"
    else
        fail "update did not refresh a changed Playwright MCP profile policy"
    fi
}

# ---- Test 14: update repairs optional GOALS.md when the manifest tracks it ----
test_update_repairs_missing_goals_doc_when_manifest_tracks_it() {
    local ws
    ws=$(mktemp -d "$MKTEMP_DIR/update-test.XXXXXX")
    echo '{"name":"test-app","scripts":{"test":"jest"}}' > "$ws/package.json"
    mkdir -p "$ws/src"

    run_setup_local_args "$ws" --goals
    rm -f "$ws/GOALS.md"

    local output check_output valid=true
    output=$(run_update "$ws")
    check_output=$(run_check "$ws")

    echo "$output" | grep -q 'GOALS.md' 2>/dev/null || valid=false
    [ -f "$ws/GOALS.md" ] || valid=false
    grep -q 'complete everything in GOALS.md until the user says stop' "$ws/GOALS.md" 2>/dev/null || valid=false
    json_text_equals "$check_output" 'data.managed_files["GOALS.md"].status' "match" || valid=false

    rm -rf "$ws"

    if [ "$valid" = "true" ]; then
        pass "update repairs optional GOALS.md when the manifest tracks it"
    else
        fail "update did not repair optional GOALS.md from the manifest"
    fi
}

# ---- Test 15: unsupported Codex versions cannot partially mutate updates ----
test_update_rejects_unsupported_codex_version_before_mutation() {
    local ws fakebin output status config_before manifest_before profile_before valid=true
    ws=$(mktemp -d "$MKTEMP_DIR/update-test.XXXXXX")
    fakebin=$(mktemp -d "$MKTEMP_DIR/update-test.XXXXXX")
    echo '{"name":"test-app","scripts":{"test":"jest"}}' > "$ws/package.json"
    mkdir -p "$ws/src"

    run_setup_local "$ws"
    cat > "$ws/.codex/config.toml" <<'EOF'
model = "gpt-5.6-luna"
model_reasoning_effort = "xhigh"

[features]
hooks = true
EOF

    cat > "$fakebin/codex" <<'EOF'
#!/bin/sh
if [ "${1:-}" = "--version" ]; then
    echo "codex-cli 0.143.9"
    exit 0
fi
exit 99
EOF
    chmod +x "$fakebin/codex"

    config_before=$(cat "$ws/.codex/config.toml")
    manifest_before=$(cat "$ws/.codex-sdlc/manifest.json")
    profile_before=$(cat "$ws/.codex-sdlc/model-profile.json")

    set +e
    output=$(PATH="$fakebin:$PATH" run_update "$ws")
    status=$?
    set -e

    [ "$status" -ne 0 ] || valid=false
    echo "$output" | grep -Fq 'Codex CLI 0.144.0 or newer' || valid=false
    [ "$(cat "$ws/.codex/config.toml")" = "$config_before" ] || valid=false
    [ "$(cat "$ws/.codex-sdlc/manifest.json")" = "$manifest_before" ] || valid=false
    [ "$(cat "$ws/.codex-sdlc/model-profile.json")" = "$profile_before" ] || valid=false

    rm -rf "$ws" "$fakebin"

    if [ "$valid" = "true" ]; then
        pass "update rejects unsupported Codex versions before mutating managed files"
    else
        echo "$output" >&2
        fail "update partially mutated the repo before rejecting an unsupported Codex version"
    fi
}

# ---- Test 16: matching legacy metadata migrates without losing explicit profile choice ----
test_update_refreshes_matching_legacy_model_profile_metadata() {
    local ws output check_output valid=true
    ws=$(mktemp -d "$MKTEMP_DIR/update-test.XXXXXX")
    echo '{"name":"test-app","scripts":{"test":"jest"}}' > "$ws/package.json"
    mkdir -p "$ws/src"

    run_setup_local_args "$ws" --model-profile mixed
    cat > "$ws/AGENTS.md" <<'EOF'
# Old generated model policy

- Selected profile: mixed
- Baseline reasoning: `xhigh`
- `mixed`: `legacy-mini` plus `legacy-flagship` review.
EOF
    cat > "$ws/.codex-sdlc/model-profile.json" <<'EOF'
{
  "selected_profile": "mixed",
  "profiles": {
    "mixed": {
      "main_model": "legacy-mini",
      "main_reasoning": "high",
      "review_model": "legacy-flagship",
      "review_reasoning": "xhigh"
    },
    "maximum": {
      "main_model": "legacy-flagship",
      "main_reasoning": "xhigh",
      "review_model": "legacy-flagship",
      "review_reasoning": "xhigh"
    }
  }
}

EOF
    MANIFEST_PATH="$ws/.codex-sdlc/manifest.json" \
    PROFILE_PATH="$ws/.codex-sdlc/model-profile.json" \
    AGENTS_PATH="$ws/AGENTS.md" \
    node <<'NODE'
const crypto = require("crypto");
const fs = require("fs");

const manifestPath = process.env.MANIFEST_PATH;
const profilePath = process.env.PROFILE_PATH;
const agentsPath = process.env.AGENTS_PATH;
const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
const hash = crypto.createHash("sha256").update(fs.readFileSync(profilePath)).digest("hex");
manifest.managed_files[".codex-sdlc/model-profile.json"] = `sha256:${hash}`;
manifest.managed_files["AGENTS.md"] = `sha256:${crypto.createHash("sha256").update(fs.readFileSync(agentsPath)).digest("hex")}`;
manifest.model_profile.selected_profile = "mixed";
fs.writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
NODE

    output=$(run_update "$ws") || valid=false
    check_output=$(run_check "$ws")

    json_text_equals "$(cat "$ws/.codex-sdlc/model-profile.json")" 'data.schema_version' "2" || valid=false
    json_text_equals "$(cat "$ws/.codex-sdlc/model-profile.json")" 'data.selected_profile' "mixed" || valid=false
    json_text_equals "$(cat "$ws/.codex-sdlc/model-profile.json")" 'data.profiles.mixed.main_model' "gpt-5.6-terra" || valid=false
    json_text_equals "$(cat "$ws/.codex-sdlc/model-profile.json")" 'data.profiles.mixed.review_model' "gpt-5.6-sol" || valid=false
    json_text_equals "$(cat "$ws/.codex-sdlc/model-profile.json")" 'data.profiles.mixed.review_effort_source' "explicit command override" || valid=false
    grep -Fq 'Selected profile: mixed' "$ws/AGENTS.md" || valid=false
    grep -Fq 'Baseline reasoning: `medium`' "$ws/AGENTS.md" || valid=false
    grep -Fq 'legacy-mini' "$ws/AGENTS.md" && valid=false
    json_text_equals "$check_output" 'data.managed_files[".codex-sdlc/model-profile.json"].status' "match" || valid=false
    echo "$output" | grep -Fq '.codex-sdlc/model-profile.json' || valid=false
    echo "$output" | grep -Fq 'Prepared for regeneration: AGENTS.md' || valid=false
    echo "$output" | grep -Eqi 'refresh|migrat' || valid=false

    rm -rf "$ws"

    if [ "$valid" = "true" ]; then
        pass "update refreshes matching legacy model metadata and preserves explicit mixed selection"
    else
        echo "$output" >&2
        fail "update left matching legacy model metadata stale or lost the selected profile"
    fi
}

# ---- Test 17: missing managed metadata refreshes matching generated model policy ----
test_update_refreshes_generated_policy_when_profile_metadata_is_missing() {
    local ws output valid=true
    ws=$(mktemp -d "$MKTEMP_DIR/update-test.XXXXXX")
    echo '{"name":"test-app","scripts":{"test":"jest"}}' > "$ws/package.json"
    mkdir -p "$ws/src"

    run_setup_local_args "$ws" --model-profile mixed
    cat > "$ws/AGENTS.md" <<'EOF'
# Old generated model policy

- Selected profile: mixed
- Baseline reasoning: `xhigh`
- `mixed`: `legacy-mini` plus `legacy-flagship` review.
EOF
    MANIFEST_PATH="$ws/.codex-sdlc/manifest.json" \
    AGENTS_PATH="$ws/AGENTS.md" \
    node <<'NODE'
const crypto = require("crypto");
const fs = require("fs");

const manifestPath = process.env.MANIFEST_PATH;
const agentsPath = process.env.AGENTS_PATH;
const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
manifest.managed_files["AGENTS.md"] = `sha256:${crypto.createHash("sha256").update(fs.readFileSync(agentsPath)).digest("hex")}`;
manifest.model_profile.selected_profile = "mixed";
fs.writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
NODE
    rm -f "$ws/.codex-sdlc/model-profile.json"

    output=$(run_update "$ws") || valid=false

    json_text_equals "$(cat "$ws/.codex-sdlc/model-profile.json")" 'data.schema_version' "2" || valid=false
    json_text_equals "$(cat "$ws/.codex-sdlc/model-profile.json")" 'data.selected_profile' "mixed" || valid=false
    grep -Fq 'Selected profile: mixed' "$ws/AGENTS.md" || valid=false
    grep -Fq 'Baseline reasoning: `medium`' "$ws/AGENTS.md" || valid=false
    grep -Fq 'legacy-mini' "$ws/AGENTS.md" && valid=false
    echo "$output" | grep -Fq 'Prepared for regeneration: AGENTS.md' || valid=false

    rm -rf "$ws"

    if [ "$valid" = "true" ]; then
        pass "update refreshes matching generated policy when managed profile metadata is missing"
    else
        echo "$output" >&2
        fail "update repaired missing profile metadata but left matching generated model policy stale"
    fi
}

# ---- Test 18: legacy model migration refreshes unchanged policy surfaces only ----
test_update_refreshes_legacy_policy_surfaces_without_overwriting_customizations() {
    local ws output valid=true
    ws=$(mktemp -d "$MKTEMP_DIR/update-test.XXXXXX")
    echo '{"name":"test-app","scripts":{"test":"jest"}}' > "$ws/package.json"
    mkdir -p "$ws/src"

    run_setup_local_args "$ws" --model-profile mixed

    cat > "$ws/AGENTS.md" <<'EOF'
# Old generated model policy

- Selected profile: mixed
- Baseline reasoning: `xhigh`
EOF
    cat > "$ws/SDLC-LOOP.md" <<'EOF'
# Old SDLC Loop

Default to `xhigh` in every repo.
EOF
    cat > "$ws/START-SDLC.md" <<'EOF'
# Customized old start policy

Use xhigh reasoning by default for this repo.
EOF
    cp "$SCRIPT_DIR/fixtures/v0.7.31-sdlc-skill.md" "$ws/.agents/skills/sdlc/SKILL.md"
    SKILL_PATH="$ws/.agents/skills/sdlc/SKILL.md" node <<'NODE'
const fs = require("fs");
const file = process.env.SKILL_PATH;
fs.writeFileSync(file, fs.readFileSync(file, "utf8").replace(/\n/g, "\r\n"));
NODE
    echo '# USER CUSTOM SETUP HELPER' > "$ws/.codex-home/skills/setup-wizard/SKILL.md"
    echo '# USER CUSTOM UPDATE HELPER' > "$ws/.codex-home/skills/update-wizard/SKILL.md"

    cat > "$ws/.codex-sdlc/model-profile.json" <<'EOF'
{
  "selected_profile": "mixed",
  "profiles": {
    "mixed": {
      "main_model": "legacy-mini",
      "main_reasoning": "high",
      "review_model": "legacy-flagship",
      "review_reasoning": "xhigh"
    }
  }
}
EOF

    MANIFEST_PATH="$ws/.codex-sdlc/manifest.json" \
    PROFILE_PATH="$ws/.codex-sdlc/model-profile.json" \
    AGENTS_PATH="$ws/AGENTS.md" \
    LOOP_PATH="$ws/SDLC-LOOP.md" \
    START_PATH="$ws/START-SDLC.md" \
    node <<'NODE'
const crypto = require("crypto");
const fs = require("fs");

const hash = (file) => `sha256:${crypto.createHash("sha256").update(fs.readFileSync(file)).digest("hex")}`;
const manifest = JSON.parse(fs.readFileSync(process.env.MANIFEST_PATH, "utf8"));
manifest.managed_files[".codex-sdlc/model-profile.json"] = hash(process.env.PROFILE_PATH);
manifest.managed_files["AGENTS.md"] = hash(process.env.AGENTS_PATH);
manifest.managed_files["SDLC-LOOP.md"] = hash(process.env.LOOP_PATH);
manifest.managed_files["START-SDLC.md"] = hash(process.env.START_PATH);
delete manifest.managed_files[".agents/skills/sdlc/SKILL.md"];
manifest.model_profile.selected_profile = "mixed";
fs.writeFileSync(process.env.MANIFEST_PATH, `${JSON.stringify(manifest, null, 2)}\n`);
NODE
    echo 'USER CUSTOM POLICY' >> "$ws/START-SDLC.md"

    output=$(run_update "$ws") || valid=false

    grep -Fq 'Default to `high`' "$ws/SDLC-LOOP.md" || valid=false
    grep -Fq 'USER CUSTOM POLICY' "$ws/START-SDLC.md" || valid=false
    grep -Fq 'Use xhigh reasoning by default for this repo.' "$ws/START-SDLC.md" || valid=false
    grep -Fq 'model_reasoning_effort="high"' "$ws/.agents/skills/sdlc/SKILL.md" || valid=false
    grep -Fq 'USER CUSTOM SETUP HELPER' "$ws/.codex-home/skills/setup-wizard/SKILL.md" || valid=false
    grep -Fq 'USER CUSTOM UPDATE HELPER' "$ws/.codex-home/skills/update-wizard/SKILL.md" || valid=false
    json_text_equals "$(cat "$ws/.codex-sdlc/manifest.json")" 'data.managed_files[".agents/skills/sdlc/SKILL.md"].startsWith("sha256:")' "true" || valid=false
    echo "$output" | grep -Fq 'SDLC-LOOP.md' || valid=false
    echo "$output" | grep -Fq '.agents/skills/sdlc/SKILL.md' || valid=false
    echo "$output" | grep -Fq 'skills/setup-wizard: customized -> skip' || valid=false
    echo "$output" | grep -Fq 'skills/update-wizard: customized -> skip' || valid=false
    echo "$output" | grep -Fq 'START-SDLC.md: customized -> skip' || valid=false

    rm -rf "$ws"

    if [ "$valid" = "true" ]; then
        pass "legacy model migration refreshes unchanged policy surfaces and preserves customizations"
    else
        echo "$output" >&2
        fail "legacy model migration left policy surfaces stale or overwrote customization"
    fi
}

# ---- Test 19: customized legacy metadata still migrates unchanged policy surfaces ----
test_update_migrates_legacy_policy_around_customized_profile_metadata() {
    local ws output second_output profile_before check_output valid=true
    ws=$(mktemp -d "$MKTEMP_DIR/update-test.XXXXXX")
    echo '{"name":"test-app","scripts":{"test":"jest"}}' > "$ws/package.json"
    mkdir -p "$ws/src"

    run_setup_local_args "$ws" --model-profile mixed
    cat > "$ws/SDLC-LOOP.md" <<'EOF'
# Old SDLC Loop

Default to `xhigh` in every repo.
EOF
    LOOP_PATH="$ws/SDLC-LOOP.md" MANIFEST_PATH="$ws/.codex-sdlc/manifest.json" node <<'NODE'
const crypto = require("crypto");
const fs = require("fs");
const manifest = JSON.parse(fs.readFileSync(process.env.MANIFEST_PATH, "utf8"));
const hash = crypto.createHash("sha256").update(fs.readFileSync(process.env.LOOP_PATH)).digest("hex");
manifest.managed_files["SDLC-LOOP.md"] = `sha256:${hash}`;
manifest.model_profile.policy_schema_version = 1;
fs.writeFileSync(process.env.MANIFEST_PATH, `${JSON.stringify(manifest, null, 2)}\n`);
NODE
    cat > "$ws/.codex-sdlc/model-profile.json" <<'EOF'
{
  "selected_profile": "mixed",
  "custom_policy": "KEEP ME",
  "profiles": {
    "mixed": {
      "main_model": "legacy-custom-driver",
      "review_model": "legacy-custom-review"
    }
  }
}
EOF
    profile_before=$(cat "$ws/.codex-sdlc/model-profile.json")

    output=$(run_update "$ws") || valid=false
    check_output=$(run_check "$ws")
    second_output=$(run_update "$ws") || valid=false

    grep -Fq 'Default to `high`' "$ws/SDLC-LOOP.md" || valid=false
    [ "$(cat "$ws/.codex-sdlc/model-profile.json")" = "$profile_before" ] || valid=false
    echo "$output" | grep -Fq '.codex-sdlc/model-profile.json: customized -> skip' || valid=false
    json_text_equals "$check_output" 'data.managed_files[".codex-sdlc/model-profile.json"].status' "customized" || valid=false
    json_text_equals "$(cat "$ws/.codex-sdlc/manifest.json")" 'data.model_profile.policy_schema_version' "2" || valid=false
    echo "$second_output" | grep -Fq 'No changes applied.' || valid=false
    echo "$second_output" | grep -Fq 'refresh model policy' && valid=false
    echo "$second_output" | grep -Fq 'refresh generated model policy' && valid=false

    rm -rf "$ws"

    if [ "$valid" = "true" ]; then
        pass "customized legacy metadata migration preserves policy and converges after one update"
    else
        echo "$output" >&2
        echo "$second_output" >&2
        fail "customized legacy metadata migration did not preserve policy or converge"
    fi
}

# ---- Test 20: customized policy surfaces still record one-time migration completion ----
test_update_records_schema_only_migration_when_all_policy_surfaces_are_customized() {
    local ws output second_output profile_before agents_before loop_before start_before skill_before valid=true
    ws=$(mktemp -d "$MKTEMP_DIR/update-test.XXXXXX")
    echo '{"name":"test-app","scripts":{"test":"jest"}}' > "$ws/package.json"
    mkdir -p "$ws/src"

    run_setup_local_args "$ws" --model-profile mixed
    printf '\nUSER CUSTOM AGENTS POLICY\n' >> "$ws/AGENTS.md"
    printf '\nUSER CUSTOM LOOP POLICY\n' >> "$ws/SDLC-LOOP.md"
    printf '\nUSER CUSTOM START POLICY\n' >> "$ws/START-SDLC.md"
    printf '\nUSER CUSTOM SDLC SKILL POLICY\n' >> "$ws/.agents/skills/sdlc/SKILL.md"
    printf '\n# USER CUSTOM CONFIG\n' >> "$ws/.codex/config.toml"
    printf '\nUSER CUSTOM SETUP HELPER\n' >> "$ws/.codex-home/skills/setup-wizard/SKILL.md"
    printf '\nUSER CUSTOM UPDATE HELPER\n' >> "$ws/.codex-home/skills/update-wizard/SKILL.md"
    cat > "$ws/.codex-sdlc/model-profile.json" <<'EOF'
{
  "selected_profile": "mixed",
  "custom_policy": "KEEP ME",
  "profiles": {
    "mixed": {
      "main_model": "legacy-custom-driver",
      "review_model": "legacy-custom-review"
    }
  }
}
EOF
    MANIFEST_PATH="$ws/.codex-sdlc/manifest.json" node <<'NODE'
const fs = require("fs");
const manifest = JSON.parse(fs.readFileSync(process.env.MANIFEST_PATH, "utf8"));
manifest.model_profile.policy_schema_version = 1;
fs.writeFileSync(process.env.MANIFEST_PATH, `${JSON.stringify(manifest, null, 2)}\n`);
NODE

    profile_before=$(cat "$ws/.codex-sdlc/model-profile.json")
    agents_before=$(cat "$ws/AGENTS.md")
    loop_before=$(cat "$ws/SDLC-LOOP.md")
    start_before=$(cat "$ws/START-SDLC.md")
    skill_before=$(cat "$ws/.agents/skills/sdlc/SKILL.md")

    output=$(run_update "$ws") || valid=false
    second_output=$(run_update "$ws") || valid=false

    json_text_equals "$(cat "$ws/.codex-sdlc/manifest.json")" 'data.model_profile.policy_schema_version' "2" || valid=false
    [ "$(cat "$ws/.codex-sdlc/model-profile.json")" = "$profile_before" ] || valid=false
    [ "$(cat "$ws/AGENTS.md")" = "$agents_before" ] || valid=false
    [ "$(cat "$ws/SDLC-LOOP.md")" = "$loop_before" ] || valid=false
    [ "$(cat "$ws/START-SDLC.md")" = "$start_before" ] || valid=false
    [ "$(cat "$ws/.agents/skills/sdlc/SKILL.md")" = "$skill_before" ] || valid=false
    grep -Fq 'USER CUSTOM SETUP HELPER' "$ws/.codex-home/skills/setup-wizard/SKILL.md" || valid=false
    grep -Fq 'USER CUSTOM UPDATE HELPER' "$ws/.codex-home/skills/update-wizard/SKILL.md" || valid=false
    echo "$output" | grep -Fq '.codex-sdlc/manifest.json' || valid=false
    echo "$output" | grep -Fq 'record model policy migration completion' || valid=false
    echo "$second_output" | grep -Fq 'No changes applied.' || valid=false
    echo "$second_output" | grep -Fq 'record model policy migration completion' && valid=false

    rm -rf "$ws"

    if [ "$valid" = "true" ]; then
        pass "schema-only migration records completion and preserves every customized policy surface"
    else
        echo "$output" >&2
        echo "$second_output" >&2
        fail "schema-only migration did not converge without overwriting customized policy surfaces"
    fi
}

test_update_reports_uninitialized_repo
test_update_check_only_reports_missing_without_repair
test_update_repairs_missing_generated_docs
test_update_skips_customized_docs_by_default
test_update_force_all_replaces_customized_docs
test_update_repairs_windows_hook_drift
test_update_repairs_legacy_js_node_hooks
test_update_repairs_legacy_js_hook_manifest_entries
test_update_repairs_matching_legacy_js_hook_manifest_entries
test_update_repairs_matching_hook_surface_without_compact_lifecycle
test_update_repairs_missing_compact_guard_without_overwriting_custom_hooks
test_update_merges_config_without_dropping_other_settings
test_update_repairs_missing_native_skills
test_update_removes_legacy_codex_sdlc_skill
test_update_preserves_user_owned_global_sdlc_skill
test_update_repairs_mixed_profile_reasoning_drift
test_update_defaults_profile_less_repo_to_sol_high
test_update_refreshes_playwright_mcp_policy_for_old_manifest
test_update_refreshes_changed_playwright_mcp_policy
test_update_repairs_missing_goals_doc_when_manifest_tracks_it
test_update_rejects_unsupported_codex_version_before_mutation
test_update_refreshes_matching_legacy_model_profile_metadata
test_update_refreshes_generated_policy_when_profile_metadata_is_missing
test_update_refreshes_legacy_policy_surfaces_without_overwriting_customizations
test_update_migrates_legacy_policy_around_customized_profile_metadata
test_update_records_schema_only_migration_when_all_policy_surfaces_are_customized

echo ""
echo "=== Results: $PASSED passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
    exit 1
fi
