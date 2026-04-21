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
    echo "$current_state_section" | grep -Eq '0\.4\.0|v0\.4\.0' || has_current_release=false
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
    echo "$next_release_section" | grep -q '0.5.0' || has_minor_release=false
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
    local has_issue4=true
    local has_issue5=true
    local has_issue6=true
    local cleanup_section

    cleanup_section=$(awk '
        /^## Tracker Cleanup$/ { in_section=1; next }
        /^## / && in_section { exit }
        in_section { print }
    ' "$ROADMAP")

    grep -q '^## Tracker Cleanup$' "$ROADMAP" || has_heading=false
    echo "$cleanup_section" | grep -q '#4' || has_issue4=false
    echo "$cleanup_section" | grep -q '#5' || has_issue5=false
    echo "$cleanup_section" | grep -q '#6' || has_issue6=false

    if [ "$has_heading" = "true" ] &&
       [ "$has_issue4" = "true" ] &&
       [ "$has_issue5" = "true" ] &&
       [ "$has_issue6" = "true" ]; then
        pass "Roadmap calls out the consumer-path release issues for cleanup"
    else
        fail "Roadmap does not call out tracker cleanup clearly"
    fi
}

test_roadmap_tracks_late_creator_investigation() {
    local has_skill_creator=true
    local has_plugin_creator=true
    local has_later_priority=true

    grep -qi 'Skill Creator' "$ROADMAP" || has_skill_creator=false
    grep -qi 'Plugin Creator' "$ROADMAP" || has_plugin_creator=false
    grep -Eqi 'later|down the road|after' "$ROADMAP" || has_later_priority=false

    if [ "$has_skill_creator" = "true" ] &&
       [ "$has_plugin_creator" = "true" ] &&
       [ "$has_later_priority" = "true" ]; then
        pass "Roadmap tracks Skill Creator / Plugin Creator investigation as later work"
    else
        fail "Roadmap does not track the later Skill Creator / Plugin Creator investigation"
    fi
}

test_roadmap_prioritizes_discovery_bridge_before_docs_process_backlog() {
    local order_section
    local line_issue14
    local line_docs_backlog

    order_section=$(awk '
        /^## Working Order$/ { in_section=1; next }
        /^## / && in_section { exit }
        in_section { print }
    ' "$ROADMAP")

    line_issue14=$(echo "$order_section" | nl -ba | grep '#14' | awk '{print $1}' | head -n1)
    line_docs_backlog=$(echo "$order_section" | nl -ba | grep '#7.*#10' | awk '{print $1}' | head -n1)

    if [ -n "${line_issue14:-}" ] &&
       [ -n "${line_docs_backlog:-}" ] &&
       [ "$line_issue14" -lt "$line_docs_backlog" ]; then
        pass "Roadmap prioritizes the Codex discovery bridge (#14) before the docs/process backlog (#7-#10)"
    else
        fail "Roadmap does not prioritize #14 ahead of the remaining docs/process backlog"
    fi
}

test_roadmap_exists
test_roadmap_states_current_release_status
test_roadmap_lists_next_release_cycle
test_roadmap_calls_out_stale_issue_cleanup
test_roadmap_tracks_late_creator_investigation
test_roadmap_prioritizes_discovery_bridge_before_docs_process_backlog

echo ""
echo "=== Results: $PASSED passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
    exit 1
fi
