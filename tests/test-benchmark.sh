#!/bin/bash
# Benchmark tests — keep model experiment tracking measurable

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$SCRIPT_DIR/.."
LEDGER="$REPO_DIR/benchmarks/model-experiment.csv"
SUMMARY_SCRIPT="$REPO_DIR/scripts/summarize-model-experiment.sh"
PILOT_LEDGER="$REPO_DIR/benchmarks/pilot-rollout.csv"
PILOT_SUMMARY_SCRIPT="$REPO_DIR/scripts/summarize-pilot-rollout.sh"
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

echo "=== Benchmark Tests ==="
echo ""

test_benchmark_ledger_exists_with_required_headers() {
    local has_file=true
    local has_headers=true
    local header

    [ -f "$LEDGER" ] || has_file=false
    header="$(head -n 1 "$LEDGER" 2>/dev/null || true)"

    for column in slice_id mode category complexity cycle_minutes end_to_end_success follow_up_required main_model main_reasoning review_model review_reasoning; do
        echo "$header" | grep -q "$column" || has_headers=false
    done

    if [ "$has_file" = "true" ] && [ "$has_headers" = "true" ]; then
        pass "Benchmark ledger exists with the required schema"
    else
        fail "Benchmark ledger is missing or does not have the required schema"
    fi
}

test_benchmark_summary_script_exists() {
    if [ -x "$SUMMARY_SCRIPT" ]; then
        pass "Benchmark summary script exists and is executable"
    else
        fail "Benchmark summary script is missing or not executable"
    fi
}

test_benchmark_summary_script_reports_thresholds_and_recommendation() {
    local ws fixture output
    ws="$(mktemp -d)"
    fixture="$ws/model-experiment.csv"

    cat > "$fixture" <<'CSV'
slice_id,mode,category,complexity,cycle_minutes,end_to_end_success,follow_up_required,main_model,main_reasoning,review_model,review_reasoning,notes
mx-001,mixed,feature,routine,24,1,0,gpt-5.4-mini,medium,gpt-5.4,xhigh,good
mx-002,mixed,bugfix,routine,25,1,0,gpt-5.4-mini,medium,gpt-5.4,xhigh,good
mx-003,mixed,feature,routine,26,1,0,gpt-5.4-mini,medium,gpt-5.4,xhigh,good
mx-004,mixed,bugfix,routine,24,1,0,gpt-5.4-mini,medium,gpt-5.4,xhigh,good
mx-005,mixed,feature,routine,25,1,0,gpt-5.4-mini,medium,gpt-5.4,xhigh,good
mx-006,mixed,bugfix,routine,26,1,0,gpt-5.4-mini,medium,gpt-5.4,xhigh,good
mx-007,mixed,feature,routine,24,1,0,gpt-5.4-mini,medium,gpt-5.4,xhigh,good
mx-008,mixed,bugfix,routine,25,1,0,gpt-5.4-mini,medium,gpt-5.4,xhigh,good
mx-009,mixed,feature,routine,26,1,0,gpt-5.4-mini,medium,gpt-5.4,xhigh,good
mx-010,mixed,bugfix,routine,24,1,0,gpt-5.4-mini,medium,gpt-5.4,xhigh,good
mx-011,mixed,feature,routine,25,1,0,gpt-5.4-mini,medium,gpt-5.4,xhigh,good
mx-012,mixed,bugfix,routine,26,1,0,gpt-5.4-mini,medium,gpt-5.4,xhigh,good
mx-013,mixed,feature,routine,24,1,0,gpt-5.4-mini,medium,gpt-5.4,xhigh,good
mx-014,mixed,bugfix,routine,25,1,0,gpt-5.4-mini,medium,gpt-5.4,xhigh,good
mx-015,mixed,feature,routine,26,1,0,gpt-5.4-mini,medium,gpt-5.4,xhigh,good
mx-016,mixed,bugfix,routine,24,1,0,gpt-5.4-mini,medium,gpt-5.4,xhigh,good
mx-017,mixed,feature,routine,25,1,0,gpt-5.4-mini,medium,gpt-5.4,xhigh,good
mx-018,mixed,bugfix,routine,26,1,0,gpt-5.4-mini,medium,gpt-5.4,xhigh,good
mx-019,mixed,feature,routine,24,1,0,gpt-5.4-mini,medium,gpt-5.4,xhigh,good
mx-020,mixed,bugfix,routine,25,1,0,gpt-5.4-mini,medium,gpt-5.4,xhigh,good
xh-001,all-xhigh,feature,routine,32,1,0,gpt-5.4,xhigh,gpt-5.4,xhigh,baseline
xh-002,all-xhigh,bugfix,routine,33,1,0,gpt-5.4,xhigh,gpt-5.4,xhigh,baseline
xh-003,all-xhigh,feature,routine,34,1,0,gpt-5.4,xhigh,gpt-5.4,xhigh,baseline
xh-004,all-xhigh,bugfix,routine,32,1,0,gpt-5.4,xhigh,gpt-5.4,xhigh,baseline
xh-005,all-xhigh,feature,routine,33,1,0,gpt-5.4,xhigh,gpt-5.4,xhigh,baseline
CSV

    output="$("$SUMMARY_SCRIPT" "$fixture")"

    if echo "$output" | grep -q 'mode: mixed' &&
       echo "$output" | grep -q 'sample_size: 20' &&
       echo "$output" | grep -q 'success_rate: 100.00%' &&
       echo "$output" | grep -q 'follow_up_rate: 0.00%' &&
       echo "$output" | grep -q 'cycle_time_improvement_vs_all_xhigh: 24.24%' &&
       echo "$output" | grep -q 'recommendation: recommend-mixed-default'; then
        pass "Benchmark summary script reports threshold metrics and the mixed-mode recommendation"
    else
        fail "Benchmark summary script does not report threshold metrics and recommendation clearly"
    fi

    rm -rf "$ws"
}

test_benchmark_summary_script_holds_when_data_is_insufficient() {
    local ws fixture output
    ws="$(mktemp -d)"
    fixture="$ws/model-experiment.csv"

    cat > "$fixture" <<'CSV'
slice_id,mode,category,complexity,cycle_minutes,end_to_end_success,follow_up_required,main_model,main_reasoning,review_model,review_reasoning,notes
mx-001,mixed,feature,routine,30,1,0,gpt-5.4-mini,medium,gpt-5.4,xhigh,good
mx-002,mixed,feature,routine,31,1,0,gpt-5.4-mini,medium,gpt-5.4,xhigh,good
xh-001,all-xhigh,feature,routine,32,1,0,gpt-5.4,xhigh,gpt-5.4,xhigh,baseline
CSV

    output="$("$SUMMARY_SCRIPT" "$fixture")"

    if echo "$output" | grep -q 'recommendation: hold-default' &&
       echo "$output" | grep -q 'reason: mixed sample size is below 20'; then
        pass "Benchmark summary script holds the default when the mixed sample is too small"
    else
        fail "Benchmark summary script does not hold the default clearly when the sample is too small"
    fi

    rm -rf "$ws"
}

test_pilot_rollout_ledger_exists_with_required_headers() {
    local has_file=true
    local has_headers=true
    local header

    [ -f "$PILOT_LEDGER" ] || has_file=false
    header="$(head -n 1 "$PILOT_LEDGER" 2>/dev/null || true)"

    for column in repo_name install_version install_success reusable_wizard_bug confidence_after_install recommended_next_step; do
        echo "$header" | grep -q "$column" || has_headers=false
    done

    if [ "$has_file" = "true" ] && [ "$has_headers" = "true" ]; then
        pass "Pilot rollout ledger exists with the required schema"
    else
        fail "Pilot rollout ledger is missing or does not have the required schema"
    fi
}

test_pilot_rollout_summary_script_exists() {
    if [ -x "$PILOT_SUMMARY_SCRIPT" ]; then
        pass "Pilot rollout summary script exists and is executable"
    else
        fail "Pilot rollout summary script is missing or not executable"
    fi
}

test_pilot_rollout_summary_recommends_default_use_when_gate_is_met() {
    local ws fixture output
    ws="$(mktemp -d)"
    fixture="$ws/pilot-rollout.csv"

    cat > "$fixture" <<'CSV'
repo_name,install_version,install_success,reusable_wizard_bug,confidence_after_install,recommended_next_step,notes
repo-1,0.7.1,1,0,high,continue,clean
repo-2,0.7.1,1,0,high,continue,clean
repo-3,0.7.1,1,1,high,continue,one reusable bug captured
repo-4,0.7.1,1,0,high,continue,clean
repo-5,0.7.1,1,0,high,continue,clean
CSV

    output="$("$PILOT_SUMMARY_SCRIPT" "$fixture")"

    if echo "$output" | grep -q 'pilot_repo_count: 5' &&
       echo "$output" | grep -q 'pilot_success_rate: 100.00%' &&
       echo "$output" | grep -q 'reusable_wizard_bug_count: 1' &&
       echo "$output" | grep -q 'recommendation: recommend-default-use'; then
        pass "Pilot rollout summary recommends default use when the pilot gate is met"
    else
        fail "Pilot rollout summary does not recommend default use clearly when the pilot gate is met"
    fi

    rm -rf "$ws"
}

test_pilot_rollout_summary_holds_default_use_when_reusable_bug_count_is_too_high() {
    local ws fixture output
    ws="$(mktemp -d)"
    fixture="$ws/pilot-rollout.csv"

    cat > "$fixture" <<'CSV'
repo_name,install_version,install_success,reusable_wizard_bug,confidence_after_install,recommended_next_step,notes
repo-1,0.7.1,1,0,high,continue,clean
repo-2,0.7.1,1,1,high,continue,bug one
repo-3,0.7.1,1,1,medium,stabilize,bug two
CSV

    output="$("$PILOT_SUMMARY_SCRIPT" "$fixture")"

    if echo "$output" | grep -q 'recommendation: hold-default-use' &&
       echo "$output" | grep -q 'reason: reusable wizard bug count is above 1'; then
        pass "Pilot rollout summary holds default use when reusable bug count is too high"
    else
        fail "Pilot rollout summary does not hold default use clearly when reusable bug count is too high"
    fi

    rm -rf "$ws"
}

test_benchmark_ledger_exists_with_required_headers
test_benchmark_summary_script_exists
test_benchmark_summary_script_reports_thresholds_and_recommendation
test_benchmark_summary_script_holds_when_data_is_insufficient
test_pilot_rollout_ledger_exists_with_required_headers
test_pilot_rollout_summary_script_exists
test_pilot_rollout_summary_recommends_default_use_when_gate_is_met
test_pilot_rollout_summary_holds_default_use_when_reusable_bug_count_is_too_high

echo ""
echo "=== Results: $PASSED passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
    exit 1
fi
