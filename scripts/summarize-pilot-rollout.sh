#!/bin/bash
# Summarize pilot-repo rollout results before recommending default use.

set -euo pipefail

CSV_PATH="${1:-benchmarks/pilot-rollout.csv}"

if [ ! -f "$CSV_PATH" ]; then
    echo "missing ledger: $CSV_PATH" >&2
    exit 1
fi

pilot_repo_count="$(awk -F, 'NR > 1 { count++ } END { print count + 0 }' "$CSV_PATH")"
successful_repo_count="$(awk -F, 'NR > 1 { sum += $3 } END { print sum + 0 }' "$CSV_PATH")"
reusable_wizard_bug_count="$(awk -F, 'NR > 1 { sum += $4 } END { print sum + 0 }' "$CSV_PATH")"

pilot_success_rate="$(
    awk -v successes="$successful_repo_count" -v total="$pilot_repo_count" '
        BEGIN {
            if (total == 0) {
                print "n/a"
            } else {
                printf "%.2f%%\n", (successes / total) * 100
            }
        }
    '
)"

recommendation="hold-default-use"
reason="pilot repo count is below 3"

if [ "$pilot_repo_count" -ge 3 ]; then
    recommendation="recommend-default-use"
    reason="pilot rollout meets repo-count, success-rate, and reusable-bug thresholds"

    if ! awk -v rate="${pilot_success_rate%%%}" 'BEGIN { exit !(rate >= 95) }'; then
        recommendation="hold-default-use"
        reason="pilot success rate is below 95%"
    elif [ "$reusable_wizard_bug_count" -gt 1 ]; then
        recommendation="hold-default-use"
        reason="reusable wizard bug count is above 1"
    fi
fi

cat <<EOF
pilot_repo_count: $pilot_repo_count
successful_repo_count: $successful_repo_count
pilot_success_rate: $pilot_success_rate
reusable_wizard_bug_count: $reusable_wizard_bug_count
recommendation: $recommendation
reason: $reason
EOF
