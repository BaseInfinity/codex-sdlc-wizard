#!/bin/bash
# Roadmap tests — keep the repo's next release/issue sequence explicit

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$SCRIPT_DIR/.."
ROADMAP="$REPO_DIR/ROADMAP.md"
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

echo "=== Roadmap Tests ==="
echo ""

test_roadmap_exists() {
    if [ -f "$ROADMAP" ]; then
        pass "ROADMAP.md exists"
    else
        fail "ROADMAP.md is missing"
    fi
}

test_roadmap_states_current_release_status() {
    local has_heading=true
    local has_current_release=true
    local has_trusted_publishing=true
    local current_state_section

    current_state_section=$(awk '
        /^## Current State$/ { in_section=1; next }
        /^## / && in_section { exit }
        in_section { print }
    ' "$ROADMAP")

    grep -q '^## Current State$' "$ROADMAP" || has_heading=false
    echo "$current_state_section" | grep -Eq '0\.3\.1|v0\.3\.1' || has_current_release=false
    echo "$current_state_section" | grep -qi 'trusted publishing' || has_trusted_publishing=false

    if [ "$has_heading" = "true" ] &&
       [ "$has_current_release" = "true" ] &&
       [ "$has_trusted_publishing" = "true" ]; then
        pass "Roadmap captures the current shipped release and publish path"
    else
        fail "Roadmap does not capture the current shipped release state"
    fi
}

test_roadmap_lists_next_release_cycle() {
    local has_heading=true
    local has_minor_release=true
    local has_issue14=true
    local next_release_section

    next_release_section=$(awk '
        /^## Next Release Cycle$/ { in_section=1; next }
        /^## / && in_section { exit }
        in_section { print }
    ' "$ROADMAP")

    grep -q '^## Next Release Cycle$' "$ROADMAP" || has_heading=false
    echo "$next_release_section" | grep -q '0.4.0' || has_minor_release=false
    echo "$next_release_section" | grep -q '#14' || has_issue14=false

    if [ "$has_heading" = "true" ] &&
       [ "$has_minor_release" = "true" ] &&
       [ "$has_issue14" = "true" ]; then
        pass "Roadmap lists the next release proof and main engineering item"
    else
        fail "Roadmap does not list the next release sequence clearly"
    fi
}

test_roadmap_calls_out_stale_issue_cleanup() {
    local has_heading=true
    local has_issue11=true
    local has_issue12=true
    local has_issue13=true

    grep -q '^## Tracker Cleanup$' "$ROADMAP" || has_heading=false
    grep -q '#11' "$ROADMAP" || has_issue11=false
    grep -q '#12' "$ROADMAP" || has_issue12=false
    grep -q '#13' "$ROADMAP" || has_issue13=false

    if [ "$has_heading" = "true" ] &&
       [ "$has_issue11" = "true" ] &&
       [ "$has_issue12" = "true" ] &&
       [ "$has_issue13" = "true" ]; then
        pass "Roadmap calls out stale shipped issues for cleanup"
    else
        fail "Roadmap does not call out tracker cleanup clearly"
    fi
}

test_roadmap_exists
test_roadmap_states_current_release_status
test_roadmap_lists_next_release_cycle
test_roadmap_calls_out_stale_issue_cleanup

echo ""
echo "=== Results: $PASSED passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
    exit 1
fi
