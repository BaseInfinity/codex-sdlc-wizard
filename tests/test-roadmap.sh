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
    echo "$current_state_section" | grep -Eq '0\.5\.0|v0\.5\.0' || has_current_release=false
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
    local has_backlog_window=true
    local next_release_section

    next_release_section=$(awk '
        /^## Next Release Cycle$/ { in_section=1; next }
        /^## / && in_section { exit }
        in_section { print }
    ' "$ROADMAP")

    grep -q '^## Next Release Cycle$' "$ROADMAP" || has_heading=false
    echo "$next_release_section" | grep -q '0.6.0' || has_minor_release=false
    echo "$next_release_section" | grep -Eq '#7|#8|#9|#10' || has_backlog_window=false

    if [ "$has_heading" = "true" ] &&
       [ "$has_minor_release" = "true" ] &&
       [ "$has_backlog_window" = "true" ]; then
        pass "Roadmap lists the next release proof and main engineering item"
    else
        fail "Roadmap does not list the next release sequence clearly"
    fi
}

test_roadmap_calls_out_stale_issue_cleanup() {
    local has_heading=true
    local has_issue14=true
    local has_issue7=true
    local has_issue8=true
    local cleanup_section

    cleanup_section=$(awk '
        /^## Tracker Cleanup$/ { in_section=1; next }
        /^## / && in_section { exit }
        in_section { print }
    ' "$ROADMAP")

    grep -q '^## Tracker Cleanup$' "$ROADMAP" || has_heading=false
    echo "$cleanup_section" | grep -q '#14' || has_issue14=false
    echo "$cleanup_section" | grep -q '#7' || has_issue7=false
    echo "$cleanup_section" | grep -q '#8' || has_issue8=false

    if [ "$has_heading" = "true" ] &&
       [ "$has_issue14" = "true" ] &&
       [ "$has_issue7" = "true" ] &&
       [ "$has_issue8" = "true" ]; then
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

test_roadmap_tracks_review_model_experiment() {
    local has_mini=true
    local has_xhigh_review=true
    local has_experiment_language=true

    grep -qi 'gpt-5\.4-mini' "$ROADMAP" || has_mini=false
    grep -Eqi 'xhigh review|review.*xhigh|cross-model review.*xhigh' "$ROADMAP" || has_xhigh_review=false
    grep -Eqi 'experiment|test against|compare' "$ROADMAP" || has_experiment_language=false

    if [ "$has_mini" = "true" ] &&
       [ "$has_xhigh_review" = "true" ] &&
       [ "$has_experiment_language" = "true" ]; then
        pass "Roadmap tracks the gpt-5.4-mini vs xhigh-review experiment as later work"
    else
        fail "Roadmap does not track the gpt-5.4-mini vs xhigh-review experiment"
    fi
}

test_roadmap_sets_numeric_model_experiment_targets() {
    local has_sample_size=true
    local has_success_rate=true
    local has_speed_delta=true
    local has_reopen_rate=true
    local has_complex_xhigh_rule=true

    grep -Eqi '20 slices|sample of 20|n=20' "$ROADMAP" || has_sample_size=false
    grep -Eqi '95%|>= ?95%' "$ROADMAP" || has_success_rate=false
    grep -Eqi '15% faster|>= ?15%|15% improvement' "$ROADMAP" || has_speed_delta=false
    grep -Eqi '10% reopen|<= ?10%|follow-up rate <= ?10%' "$ROADMAP" || has_reopen_rate=false
    grep -Eqi 'abstract|complex|high-blast-radius' "$ROADMAP" || has_complex_xhigh_rule=false

    if [ "$has_sample_size" = "true" ] &&
       [ "$has_success_rate" = "true" ] &&
       [ "$has_speed_delta" = "true" ] &&
       [ "$has_reopen_rate" = "true" ] &&
       [ "$has_complex_xhigh_rule" = "true" ]; then
        pass "Roadmap sets numeric targets for the model experiment and keeps complex work on xhigh for now"
    else
        fail "Roadmap does not set numeric targets for the model experiment clearly enough"
    fi
}

test_roadmap_tracks_default_use_pilot_gate() {
    local has_pilot_sample=true
    local has_success_threshold=true
    local has_reusable_bug_threshold=true
    local has_default_use_language=true

    grep -Eqi '3-5 pilot repos|3 to 5 pilot repos|five pilot repos' "$ROADMAP" || has_pilot_sample=false
    grep -Eqi '>= ?95% pilot success|95% pilot success|pilot success >= ?95%' "$ROADMAP" || has_success_threshold=false
    grep -Eqi '<=? ?1 reusable wizard bug|no more than 1 reusable wizard bug|1 reusable wizard bug' "$ROADMAP" || has_reusable_bug_threshold=false
    grep -Eqi 'default use|default rollout|default path' "$ROADMAP" || has_default_use_language=false

    if [ "$has_pilot_sample" = "true" ] &&
       [ "$has_success_threshold" = "true" ] &&
       [ "$has_reusable_bug_threshold" = "true" ] &&
       [ "$has_default_use_language" = "true" ]; then
        pass "Roadmap tracks a measurable pilot gate before default use"
    else
        fail "Roadmap does not track a measurable pilot gate before default use"
    fi
}

test_roadmap_prioritizes_discovery_bridge_before_docs_process_backlog() {
    local order_section
    local line_docs_backlog
    local line_creator_investigation

    order_section=$(awk '
        /^## Working Order$/ { in_section=1; next }
        /^## / && in_section { exit }
        in_section { print }
    ' "$ROADMAP")

    line_docs_backlog=$(echo "$order_section" | nl -ba | grep '#7.*#10' | awk '{print $1}' | head -n1)
    line_creator_investigation=$(echo "$order_section" | nl -ba | grep -Ei 'creator-tool|creator' | awk '{print $1}' | head -n1)

    if [ -n "${line_docs_backlog:-}" ] &&
       [ -n "${line_creator_investigation:-}" ] &&
       [ "$line_docs_backlog" -lt "$line_creator_investigation" ]; then
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
test_roadmap_tracks_review_model_experiment
test_roadmap_sets_numeric_model_experiment_targets
test_roadmap_tracks_default_use_pilot_gate
test_roadmap_prioritizes_discovery_bridge_before_docs_process_backlog

echo ""
echo "=== Results: $PASSED passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
    exit 1
fi
