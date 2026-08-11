#!/bin/bash
# Summarize the bounded ten-delivery review-cadence pilot.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CSV_PATH="${1:-$REPO_DIR/benchmarks/review-cadence.csv}"
EXPECTED_HEADER='delivery_id,repo,issue_id,strategy,eligible,stable_base,candidate_tree,diff_files,broad_proof_runs,duplicate_broad_proof_runs,sol_review_minutes,fable_review_minutes,sol_pre_confidence,fable_pre_confidence,sol_post_confidence,fable_post_confidence,sol_pre_disposition,fable_pre_disposition,sol_post_disposition,fable_post_disposition,sol_disposition_change_reason,fable_disposition_change_reason,reconciliation_rounds,reconciliation_skipped,reconciliation_ledger_entries,unique_second_reviewer_blockers,corrective_rounds,tripwire_count,red_on_main,sol_quota_cost,fable_quota_cost,sol_token_cost,fable_token_cost,issue_closed,milestone_closed,release_shipped,delivery_minutes,notes'

if [ ! -f "$CSV_PATH" ]; then
    echo "missing ledger: $CSV_PATH" >&2
    exit 1
fi

IFS= read -r actual_header < "$CSV_PATH"
if [ "$actual_header" != "$EXPECTED_HEADER" ]; then
    echo "review cadence ledger header does not match the required schema" >&2
    exit 2
fi

awk -F, -v expected_header="$EXPECTED_HEADER" '
    NR == 1 {
        expected_fields = split(expected_header, required_header, ",")
        for (field_index = 1; field_index <= NF; field_index++) column[$field_index] = field_index
        next
    }

    NF != expected_fields {
        printf "malformed review cadence row %d: expected %d fields, got %d; free-text fields must not contain commas\n", NR, expected_fields, NF > "/dev/stderr"
        exit 2
    }

    $(column["eligible"]) == 1 {
        strategy = $(column["strategy"])
        strategies[strategy] = 1
        strategy_count[strategy]++
        eligible++
        delivered += $(column["issue_closed"])
        milestone_closed += $(column["milestone_closed"])
        release_shipped += $(column["release_shipped"])
        duplicate_proof += $(column["duplicate_broad_proof_runs"])
        unique_blockers += $(column["unique_second_reviewer_blockers"])
        corrective_rounds += $(column["corrective_rounds"])
        tripwires += $(column["tripwire_count"])
        red_on_main += $(column["red_on_main"])

        strategy_review_minutes[strategy] += $(column["sol_review_minutes"]) + $(column["fable_review_minutes"])
        strategy_reconciliation_rounds[strategy] += $(column["reconciliation_rounds"])
        strategy_quota_cost[strategy] += $(column["sol_quota_cost"]) + $(column["fable_quota_cost"])
        strategy_token_cost[strategy] += $(column["sol_token_cost"]) + $(column["fable_token_cost"])

        if ($(column["delivery_minutes"]) != "") {
            delivery_minutes += $(column["delivery_minutes"])
            delivery_minutes_count++
        }

        if ($(column["sol_pre_confidence"]) != "" && $(column["sol_post_confidence"]) != "" &&
            $(column["fable_pre_confidence"]) != "" && $(column["fable_post_confidence"]) != "") {
            strategy_confidence_delta[strategy] += (($(column["sol_post_confidence"]) - $(column["sol_pre_confidence"])) + ($(column["fable_post_confidence"]) - $(column["fable_pre_confidence"]))) / 2
            strategy_confidence_count[strategy]++
        }
    }

    END {
        printf "eligible_delivery_count: %d\n", eligible
        printf "delivered_count: %d\n", delivered
        if (eligible == 0) print "delivery_rate: n/a"
        else printf "delivery_rate: %.2f%%\n", (delivered / eligible) * 100
        printf "milestone_closed_count: %d\n", milestone_closed
        printf "release_shipped_count: %d\n", release_shipped
        printf "duplicate_broad_proof_runs: %d\n", duplicate_proof
        printf "unique_second_reviewer_blockers: %d\n", unique_blockers
        printf "corrective_round_count: %d\n", corrective_rounds
        printf "tripwire_count: %d\n", tripwires
        printf "red_on_main_count: %d\n", red_on_main
        if (delivery_minutes_count == 0) print "average_delivery_minutes: n/a"
        else printf "average_delivery_minutes: %.2f\n", delivery_minutes / delivery_minutes_count

        strategy_total = 0
        for (strategy in strategies) {
            strategy_total++
            printf "strategy.%s.eligible_delivery_count: %d\n", strategy, strategy_count[strategy]
            printf "strategy.%s.average_review_minutes: %.2f\n", strategy, strategy_review_minutes[strategy] / strategy_count[strategy]
            printf "strategy.%s.reconciliation_round_count: %d\n", strategy, strategy_reconciliation_rounds[strategy]
            if (strategy_confidence_count[strategy] == 0) printf "strategy.%s.average_confidence_delta: n/a\n", strategy
            else printf "strategy.%s.average_confidence_delta: %.2f\n", strategy, strategy_confidence_delta[strategy] / strategy_confidence_count[strategy]
            printf "strategy.%s.total_quota_cost: %.2f\n", strategy, strategy_quota_cost[strategy]
            printf "strategy.%s.total_token_cost: %.0f\n", strategy, strategy_token_cost[strategy]
        }

        if (eligible >= 10 && strategy_total >= 2) {
            print "recommendation: human-evaluate-pilot"
            print "reason: ten eligible deliveries across at least two strategies are recorded; a human must choose keep, tune, or sunset"
        } else {
            print "recommendation: continue-pilot"
            print "reason: record at least ten eligible deliveries across at least two strategies"
        }
    }
' "$CSV_PATH"
