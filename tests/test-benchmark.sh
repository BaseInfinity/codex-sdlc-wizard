#!/bin/bash
# Benchmark tests — keep model experiment tracking measurable

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$SCRIPT_DIR/.."
LEDGER="$REPO_DIR/benchmarks/model-experiment.csv"
SUMMARY_SCRIPT="$REPO_DIR/scripts/summarize-model-experiment.sh"
PILOT_LEDGER="$REPO_DIR/benchmarks/pilot-rollout.csv"
PILOT_SUMMARY_SCRIPT="$REPO_DIR/scripts/summarize-pilot-rollout.sh"
REVIEW_LEDGER="$REPO_DIR/benchmarks/review-cadence.csv"
REVIEW_SUMMARY_SCRIPT="$REPO_DIR/scripts/summarize-review-cadence.sh"
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
mx-001,mixed,feature,routine,24,1,0,gpt-5.6-terra,medium,gpt-5.6-sol,high,good
mx-002,mixed,bugfix,routine,25,1,0,gpt-5.6-terra,medium,gpt-5.6-sol,high,good
mx-003,mixed,feature,routine,26,1,0,gpt-5.6-terra,medium,gpt-5.6-sol,high,good
mx-004,mixed,bugfix,routine,24,1,0,gpt-5.6-terra,medium,gpt-5.6-sol,high,good
mx-005,mixed,feature,routine,25,1,0,gpt-5.6-terra,medium,gpt-5.6-sol,high,good
mx-006,mixed,bugfix,routine,26,1,0,gpt-5.6-terra,medium,gpt-5.6-sol,high,good
mx-007,mixed,feature,routine,24,1,0,gpt-5.6-terra,medium,gpt-5.6-sol,high,good
mx-008,mixed,bugfix,routine,25,1,0,gpt-5.6-terra,medium,gpt-5.6-sol,high,good
mx-009,mixed,feature,routine,26,1,0,gpt-5.6-terra,medium,gpt-5.6-sol,high,good
mx-010,mixed,bugfix,routine,24,1,0,gpt-5.6-terra,medium,gpt-5.6-sol,high,good
mx-011,mixed,feature,routine,25,1,0,gpt-5.6-terra,medium,gpt-5.6-sol,high,good
mx-012,mixed,bugfix,routine,26,1,0,gpt-5.6-terra,medium,gpt-5.6-sol,high,good
mx-013,mixed,feature,routine,24,1,0,gpt-5.6-terra,medium,gpt-5.6-sol,high,good
mx-014,mixed,bugfix,routine,25,1,0,gpt-5.6-terra,medium,gpt-5.6-sol,high,good
mx-015,mixed,feature,routine,26,1,0,gpt-5.6-terra,medium,gpt-5.6-sol,high,good
mx-016,mixed,bugfix,routine,24,1,0,gpt-5.6-terra,medium,gpt-5.6-sol,high,good
mx-017,mixed,feature,routine,25,1,0,gpt-5.6-terra,medium,gpt-5.6-sol,high,good
mx-018,mixed,bugfix,routine,26,1,0,gpt-5.6-terra,medium,gpt-5.6-sol,high,good
mx-019,mixed,feature,routine,24,1,0,gpt-5.6-terra,medium,gpt-5.6-sol,high,good
mx-020,mixed,bugfix,routine,25,1,0,gpt-5.6-terra,medium,gpt-5.6-sol,high,good
sl-001,maximum,feature,routine,32,1,0,gpt-5.6-sol,high,gpt-5.6-sol,high,baseline
sl-002,maximum,bugfix,routine,33,1,0,gpt-5.6-sol,high,gpt-5.6-sol,high,baseline
sl-003,maximum,feature,routine,34,1,0,gpt-5.6-sol,high,gpt-5.6-sol,high,baseline
sl-004,maximum,bugfix,routine,32,1,0,gpt-5.6-sol,high,gpt-5.6-sol,high,baseline
sl-005,maximum,feature,routine,33,1,0,gpt-5.6-sol,high,gpt-5.6-sol,high,baseline
CSV

    output="$("$SUMMARY_SCRIPT" "$fixture")"

    if echo "$output" | grep -q 'mode: mixed' &&
       echo "$output" | grep -q 'sample_size: 20' &&
       echo "$output" | grep -q 'success_rate: 100.00%' &&
       echo "$output" | grep -q 'follow_up_rate: 0.00%' &&
       echo "$output" | grep -q 'cycle_time_improvement_vs_maximum: 24.24%' &&
       echo "$output" | grep -q 'recommendation: recommend-mixed-for-routine'; then
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
mx-001,mixed,feature,routine,30,1,0,gpt-5.6-terra,medium,gpt-5.6-sol,high,good
mx-002,mixed,feature,routine,31,1,0,gpt-5.6-terra,medium,gpt-5.6-sol,high,good
sl-001,maximum,feature,routine,32,1,0,gpt-5.6-sol,high,gpt-5.6-sol,high,baseline
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

test_review_cadence_ledger_exists_with_required_headers() {
    local has_file=true
    local has_headers=true
    local header

    [ -f "$REVIEW_LEDGER" ] || has_file=false
    header="$(head -n 1 "$REVIEW_LEDGER" 2>/dev/null || true)"

    for column in delivery_id repo issue_id strategy eligible stable_base candidate_tree diff_files broad_proof_runs duplicate_broad_proof_runs sol_review_minutes fable_review_minutes sol_pre_confidence fable_pre_confidence sol_post_confidence fable_post_confidence sol_pre_disposition fable_pre_disposition sol_post_disposition fable_post_disposition sol_disposition_change_reason fable_disposition_change_reason reconciliation_rounds reconciliation_skipped reconciliation_ledger_entries unique_second_reviewer_blockers corrective_rounds tripwire_count red_on_main sol_quota_cost fable_quota_cost sol_token_cost fable_token_cost issue_closed milestone_closed release_shipped delivery_minutes; do
        echo "$header" | grep -q "$column" || has_headers=false
    done

    if [ "$has_file" = "true" ] && [ "$has_headers" = "true" ]; then
        pass "Review cadence ledger exists with the ten-delivery pilot schema"
    else
        fail "Review cadence ledger is missing or does not have the required pilot schema"
    fi
}

test_review_cadence_summary_script_exists() {
    if [ -x "$REVIEW_SUMMARY_SCRIPT" ]; then
        pass "Review cadence summary script exists and is executable"
    else
        fail "Review cadence summary script is missing or not executable"
    fi
}

test_review_cadence_summary_reports_delivery_outcomes() {
    local ws fixture output
    ws="$(mktemp -d)"
    fixture="$ws/review-cadence.csv"

    cat > "$fixture" <<'CSV'
delivery_id,repo,issue_id,strategy,eligible,stable_base,candidate_tree,diff_files,broad_proof_runs,duplicate_broad_proof_runs,sol_review_minutes,fable_review_minutes,sol_pre_confidence,fable_pre_confidence,sol_post_confidence,fable_post_confidence,sol_pre_disposition,fable_pre_disposition,sol_post_disposition,fable_post_disposition,sol_disposition_change_reason,fable_disposition_change_reason,reconciliation_rounds,reconciliation_skipped,reconciliation_ledger_entries,unique_second_reviewer_blockers,corrective_rounds,tripwire_count,red_on_main,sol_quota_cost,fable_quota_cost,sol_token_cost,fable_token_cost,issue_closed,milestone_closed,release_shipped,delivery_minutes,notes
d01,repo,1,monolithic,1,a,b,4,1,0,4,3,90,91,90,91,clean,clean,clean,clean,,,0,1,,0,0,0,0,1,1,1000,800,1,0,0,30,clean
d02,repo,2,incremental,1,a,b,4,1,0,2,2,80,70,87,85,block,block,clean,clean,fixed-a,fixed-b,1,0,ledger-1,1,1,0,0,1,1,900,700,1,0,0,25,reconciled
d03,repo,3,monolithic,1,a,b,4,1,0,4,3,,,,,clean,clean,clean,clean,,,0,1,,0,0,0,0,1,1,1000,800,1,0,0,31,clean
d04,repo,4,incremental,1,a,b,4,1,0,2,2,,,,,clean,clean,clean,clean,,,0,1,,0,0,0,0,1,1,900,700,1,0,0,22,clean
d05,repo,5,incremental,1,a,b,4,1,0,2,2,,,,,clean,clean,clean,clean,,,0,1,,0,0,0,0,1,1,900,700,1,0,0,23,clean
d06,repo,6,incremental,1,a,b,4,1,0,2,2,,,,,clean,clean,clean,clean,,,0,1,,0,0,0,0,1,1,900,700,1,0,0,24,clean
d07,repo,7,incremental,1,a,b,4,1,0,2,2,,,,,clean,clean,clean,clean,,,0,1,,0,0,0,0,1,1,900,700,1,0,0,25,clean
d08,repo,8,incremental,1,a,b,4,1,0,2,2,,,,,clean,clean,clean,clean,,,0,1,,0,0,0,0,1,1,900,700,1,0,0,26,clean
d09,repo,9,incremental,1,a,b,4,1,0,2,2,,,,,clean,clean,clean,clean,,,0,1,,0,0,0,0,1,1,900,700,1,0,0,27,clean
d10,repo,10,incremental,1,a,b,4,1,0,2,2,,,,,block,block,block,block,,,0,1,,0,2,1,0,1,1,900,700,0,0,0,30,breaker
CSV

    output="$("$REVIEW_SUMMARY_SCRIPT" "$fixture")"

    if echo "$output" | grep -q 'eligible_delivery_count: 10' &&
       echo "$output" | grep -q 'delivered_count: 9' &&
       echo "$output" | grep -q 'duplicate_broad_proof_runs: 0' &&
       echo "$output" | grep -q 'red_on_main_count: 0' &&
       echo "$output" | grep -q 'tripwire_count: 1' &&
       echo "$output" | grep -q 'strategy.monolithic.eligible_delivery_count: 2' &&
       echo "$output" | grep -q 'strategy.monolithic.average_review_minutes: 7.00' &&
       echo "$output" | grep -q 'strategy.incremental.eligible_delivery_count: 8' &&
       echo "$output" | grep -q 'strategy.incremental.average_review_minutes: 4.00' &&
       echo "$output" | grep -q 'strategy.incremental.reconciliation_round_count: 1' &&
       echo "$output" | grep -q 'strategy.incremental.average_confidence_delta: 11.00' &&
       echo "$output" | grep -q 'recommendation: human-evaluate-pilot'; then
        pass "Review cadence summary reports delivery, waste, and termination outcomes"
    else
        fail "Review cadence summary does not report the ten-delivery decision metrics"
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
test_review_cadence_ledger_exists_with_required_headers
test_review_cadence_summary_script_exists
test_review_cadence_summary_reports_delivery_outcomes

echo ""
echo "=== Results: $PASSED passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
    exit 1
fi
