#!/bin/bash
# Roadmap tests — keep the repo's next release/issue sequence explicit

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$SCRIPT_DIR/.."
ROADMAP="$REPO_DIR/ROADMAP.md"
PACKAGE_JSON="$REPO_DIR/package.json"
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
    local package_version
    local has_heading=true
    local has_current_release=true
    local has_trusted_publishing=true
    local current_state_section

    package_version=$(sed -n 's/.*"version": "\(.*\)".*/\1/p' "$PACKAGE_JSON" | head -n1)

    current_state_section=$(awk '
        /^## Current State$/ { in_section=1; next }
        /^## / && in_section { exit }
        in_section { print }
    ' "$ROADMAP")

    grep -q '^## Current State$' "$ROADMAP" || has_heading=false
    echo "$current_state_section" | grep -Eq "${package_version}|v${package_version}" || has_current_release=false
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
    local has_semver_heading=true
    local has_heading=true
    local has_pilot_rollout=true
    local has_stabilization_rule=true
    local next_release_section
    local next_release_heading

    next_release_section=$(awk '
        /^## Next Release Cycle$/ { in_section=1; next }
        /^## / && in_section { exit }
        in_section { print }
    ' "$ROADMAP")
    next_release_heading=$(echo "$next_release_section" | awk '/^### / { print $2; exit }')

    grep -q '^## Next Release Cycle$' "$ROADMAP" || has_heading=false
    echo "$next_release_heading" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || has_semver_heading=false
    echo "$next_release_section" | grep -Eqi 'pilot repos|pilot rollout|default use|default path' || has_pilot_rollout=false
    echo "$next_release_section" | grep -Eqi 'reusable wizard bug|stabiliz|only if pilots surface' || has_stabilization_rule=false

    if [ "$has_heading" = "true" ] &&
       [ "$has_semver_heading" = "true" ] &&
       [ "$has_pilot_rollout" = "true" ] &&
       [ "$has_stabilization_rule" = "true" ]; then
        pass "Roadmap lists the next release proof and main engineering item"
    else
        fail "Roadmap does not list the next release sequence clearly"
    fi
}

test_roadmap_calls_out_stale_issue_cleanup() {
    local has_heading=true
    local has_active_packaging_issue=true
    local has_new_issue_rule=true
    local avoids_active_issue_refs=true
    local cleanup_section

    cleanup_section=$(awk '
        /^## Tracker Cleanup$/ { in_section=1; next }
        /^## / && in_section { exit }
        in_section { print }
    ' "$ROADMAP")

    grep -q '^## Tracker Cleanup$' "$ROADMAP" || has_heading=false
    echo "$cleanup_section" | grep -Eqi '#61.*(packaging|duplicate skills)|packaging.*#61' || has_active_packaging_issue=false
    echo "$cleanup_section" | grep -Eqi 'open a new issue|pilot consumption exposes' || has_new_issue_rule=false
    echo "$cleanup_section" | grep -Eq '#15|#16|#17|#21|#22' && avoids_active_issue_refs=false

    if [ "$has_heading" = "true" ] &&
       [ "$has_active_packaging_issue" = "true" ] &&
       [ "$has_new_issue_rule" = "true" ] &&
       [ "$avoids_active_issue_refs" = "true" ]; then
        pass "Roadmap tracks the active packaging fix and the rule for opening new issues from real consumption"
    else
        fail "Roadmap does not call out the active packaging fix and tracker cleanup policy"
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

test_roadmap_tracks_goal_mode_guidance() {
    local has_goal_command=true
    local has_sdlc_anchor=true
    local has_manual_guidance=true
    local keeps_automation_future=true
    local goal_lines

    goal_lines=$(grep -F '/goal' "$ROADMAP" 2>/dev/null || true)
    [ -n "$goal_lines" ] || has_goal_command=false
    echo "$goal_lines" | grep -Fq '$sdlc' || has_sdlc_anchor=false
    echo "$goal_lines" | grep -Eqi 'manual|guidance|SDLC-backed' || has_manual_guidance=false
    echo "$goal_lines" | grep -Eqi 'programmatic|automation|unassumed|not assume' || keeps_automation_future=false

    if [ "$has_goal_command" = "true" ] &&
       [ "$has_sdlc_anchor" = "true" ] &&
       [ "$has_manual_guidance" = "true" ] &&
       [ "$keeps_automation_future" = "true" ]; then
        pass "Roadmap tracks manual /goal guidance as SDLC-backed work and keeps automation unassumed"
    else
        fail "Roadmap does not track SDLC-backed /goal guidance clearly enough"
    fi
}

test_roadmap_tracks_official_codex_plugin_distribution_plan() {
    local has_official_distribution=true
    local has_plugin_manifest=true
    local has_marketplace=true
    local has_publish_boundary=true
    local has_no_endorsement_rule=true

    grep -Eqi 'official Codex.*distribution|Codex plugin distribution' "$ROADMAP" || has_official_distribution=false
    grep -q '.codex-plugin/plugin.json' "$ROADMAP" || has_plugin_manifest=false
    grep -q '.agents/plugins/marketplace.json' "$ROADMAP" || has_marketplace=false
    grep -Eqi 'self-serve plugin publishing.*coming soon|official public plugin.*coming soon|coming soon.*plugin publishing' "$ROADMAP" || has_publish_boundary=false
    grep -Eqi 'do not imply official OpenAI endorsement|no official OpenAI endorsement|without official OpenAI endorsement' "$ROADMAP" || has_no_endorsement_rule=false

    if [ "$has_official_distribution" = "true" ] &&
       [ "$has_plugin_manifest" = "true" ] &&
       [ "$has_marketplace" = "true" ] &&
       [ "$has_publish_boundary" = "true" ] &&
       [ "$has_no_endorsement_rule" = "true" ]; then
        pass "Roadmap tracks the official Codex plugin distribution plan and publish boundary"
    else
        fail "Roadmap does not track the official Codex plugin distribution plan and publish boundary"
    fi
}

test_roadmap_tracks_review_model_measurement() {
    local has_terra=true
    local has_sol=true
    local has_medium_main=true
    local has_high_review=true
    local has_measurement_language=true
    local has_toggle_language=true
    local has_experimental_framing=true
    local has_explicit_opt_in=true

    grep -qi 'gpt-5\.6-terra' "$ROADMAP" || has_terra=false
    grep -qi 'gpt-5\.6-sol' "$ROADMAP" || has_sol=false
    grep -Eqi 'terra.{0,20}medium|mixed.{0,40}medium' "$ROADMAP" || has_medium_main=false
    grep -Eqi 'high review|review.*high|cross-model review.*high' "$ROADMAP" || has_high_review=false
    grep -Eqi 'measure|measurement|compare|validate|data collection' "$ROADMAP" || has_measurement_language=false
    grep -Eqi 'toggle|profile|switch between|mixed.*maximum|maximum.*mixed' "$ROADMAP" || has_toggle_language=false
    grep -Eqi 'experiment|experimental|experimentation' "$ROADMAP" || has_experimental_framing=false
    grep -Eqi 'explicit opt-in|opt in explicitly|explicitly opt' "$ROADMAP" || has_explicit_opt_in=false

    if [ "$has_terra" = "true" ] &&
       [ "$has_sol" = "true" ] &&
       [ "$has_medium_main" = "true" ] &&
       [ "$has_high_review" = "true" ] &&
       [ "$has_measurement_language" = "true" ] &&
       [ "$has_toggle_language" = "true" ] &&
       [ "$has_experimental_framing" = "true" ] &&
       [ "$has_explicit_opt_in" = "true" ]; then
        pass "Roadmap tracks mixed-profile measurement as an explicit experiment"
    else
        fail "Roadmap does not frame Terra-medium versus Sol-high measurement as an explicit opt-in experiment"
    fi
}

test_roadmap_sets_numeric_model_profile_targets() {
    local has_sample_size=true
    local has_success_rate=true
    local has_speed_delta=true
    local has_reopen_rate=true
    local has_complex_xhigh_rule=true
    local has_high_vs_xhigh_gate=true
    local preserves_xhigh_baseline=true

    grep -Eqi '20 slices|sample of 20|n=20' "$ROADMAP" || has_sample_size=false
    grep -Eqi '95%|>= ?95%' "$ROADMAP" || has_success_rate=false
    grep -Eqi '15% faster|>= ?15%|15% improvement' "$ROADMAP" || has_speed_delta=false
    grep -Eqi '10% reopen|<= ?10%|follow-up rate <= ?10%' "$ROADMAP" || has_reopen_rate=false
    grep -Eqi 'abstract|complex|high-blast-radius' "$ROADMAP" || has_complex_xhigh_rule=false
    grep -Eqi 'Sol `?high`?.*Sol `?xhigh`?|high-vs-xhigh|high vs xhigh|one level lower' "$ROADMAP" || has_high_vs_xhigh_gate=false
    grep -Eqi 'preserve.*xhigh|keep.*xhigh.*baseline|do not.*switch.*high|do not.*downgrade.*high' "$ROADMAP" || preserves_xhigh_baseline=false

    if [ "$has_sample_size" = "true" ] &&
       [ "$has_success_rate" = "true" ] &&
       [ "$has_speed_delta" = "true" ] &&
       [ "$has_reopen_rate" = "true" ] &&
       [ "$has_complex_xhigh_rule" = "true" ] &&
       [ "$has_high_vs_xhigh_gate" = "true" ] &&
       [ "$preserves_xhigh_baseline" = "true" ]; then
        pass "Roadmap sets numeric targets for profile measurement and preserves the maintainer high-versus-xhigh gate"
    else
        fail "Roadmap does not set numeric targets for model-profile measurement clearly enough"
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

test_roadmap_prioritizes_pilot_rollout_before_creator_investigation() {
    local order_section
    local line_pilot_rollout
    local line_creator_investigation

    order_section=$(awk '
        /^## Working Order$/ { in_section=1; next }
        /^## / && in_section { exit }
        in_section { print }
    ' "$ROADMAP")

    line_pilot_rollout=$(echo "$order_section" | nl -ba | grep -Ei 'pilot repos|pilot rollout|default use' | awk '{print $1}' | head -n1)
    line_creator_investigation=$(echo "$order_section" | nl -ba | grep -Ei 'creator-tool|creator' | awk '{print $1}' | head -n1)

    if [ -n "${line_pilot_rollout:-}" ] &&
       [ -n "${line_creator_investigation:-}" ] &&
       [ "$line_pilot_rollout" -lt "$line_creator_investigation" ]; then
        pass "Roadmap prioritizes pilot rollout before later creator-tool investigation"
    else
        fail "Roadmap does not prioritize pilot rollout ahead of later creator-tool investigation"
    fi
}

test_roadmap_exists
test_roadmap_states_current_release_status
test_roadmap_lists_next_release_cycle
test_roadmap_calls_out_stale_issue_cleanup
test_roadmap_tracks_late_creator_investigation
test_roadmap_tracks_goal_mode_guidance
test_roadmap_tracks_official_codex_plugin_distribution_plan
test_roadmap_tracks_review_model_measurement
test_roadmap_sets_numeric_model_profile_targets
test_roadmap_tracks_default_use_pilot_gate
test_roadmap_prioritizes_pilot_rollout_before_creator_investigation

echo ""
echo "=== Results: $PASSED passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
    exit 1
fi
