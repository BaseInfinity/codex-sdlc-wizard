#!/bin/bash
# Summarize the gpt-5.4-mini + xhigh-review experiment against all-xhigh.

set -euo pipefail

CSV_PATH="${1:-benchmarks/model-experiment.csv}"

if [ ! -f "$CSV_PATH" ]; then
    echo "missing ledger: $CSV_PATH" >&2
    exit 1
fi

sample_size_for_mode() {
    local mode="$1"
    awk -F, -v mode="$mode" 'NR > 1 && $2 == mode { count++ } END { print count + 0 }' "$CSV_PATH"
}

sum_column_for_mode() {
    local mode="$1"
    local column="$2"
    awk -F, -v mode="$mode" -v column="$column" 'NR > 1 && $2 == mode { sum += $column } END { print sum + 0 }' "$CSV_PATH"
}

average_cycle_for_mode() {
    local mode="$1"
    awk -F, -v mode="$mode" '
        NR > 1 && $2 == mode { sum += $5; count++ }
        END {
            if (count == 0) {
                print "n/a"
            } else {
                printf "%.2f\n", sum / count
            }
        }
    ' "$CSV_PATH"
}

median_cycle_for_mode() {
    local mode="$1"
    local values

    values="$(awk -F, -v mode="$mode" 'NR > 1 && $2 == mode { print $5 }' "$CSV_PATH" | sort -n)"

    if [ -z "$values" ]; then
        echo "n/a"
        return
    fi

    echo "$values" | awk '
        { a[NR] = $1 }
        END {
            if (NR % 2 == 1) {
                printf "%.2f\n", a[(NR + 1) / 2]
            } else {
                printf "%.2f\n", (a[NR / 2] + a[(NR / 2) + 1]) / 2
            }
        }
    '
}

percent() {
    local numerator="$1"
    local denominator="$2"

    awk -v numerator="$numerator" -v denominator="$denominator" '
        BEGIN {
            if (denominator == 0) {
                print "n/a"
            } else {
                printf "%.2f%%\n", (numerator / denominator) * 100
            }
        }
    '
}

mixed_sample_size="$(sample_size_for_mode mixed)"
mixed_success_count="$(sum_column_for_mode mixed 6)"
mixed_follow_up_count="$(sum_column_for_mode mixed 7)"
mixed_success_rate="$(percent "$mixed_success_count" "$mixed_sample_size")"
mixed_follow_up_rate="$(percent "$mixed_follow_up_count" "$mixed_sample_size")"
mixed_average_cycle="$(average_cycle_for_mode mixed)"
mixed_median_cycle="$(median_cycle_for_mode mixed)"

all_xhigh_sample_size="$(sample_size_for_mode all-xhigh)"
all_xhigh_success_count="$(sum_column_for_mode all-xhigh 6)"
all_xhigh_follow_up_count="$(sum_column_for_mode all-xhigh 7)"
all_xhigh_success_rate="$(percent "$all_xhigh_success_count" "$all_xhigh_sample_size")"
all_xhigh_follow_up_rate="$(percent "$all_xhigh_follow_up_count" "$all_xhigh_sample_size")"
all_xhigh_average_cycle="$(average_cycle_for_mode all-xhigh)"
all_xhigh_median_cycle="$(median_cycle_for_mode all-xhigh)"

cycle_time_improvement="n/a"
if [ "$mixed_median_cycle" != "n/a" ] && [ "$all_xhigh_median_cycle" != "n/a" ]; then
    cycle_time_improvement="$(
        awk -v mixed="$mixed_median_cycle" -v baseline="$all_xhigh_median_cycle" '
            BEGIN {
                if (baseline == 0) {
                    print "n/a"
                } else {
                    printf "%.2f%%\n", ((baseline - mixed) / baseline) * 100
                }
            }
        '
    )"
fi

recommendation="hold-default"
reason="mixed sample size is below 20"

if [ "$mixed_sample_size" -ge 20 ]; then
    recommendation="recommend-mixed-default"
    reason="mixed mode meets the sample, success, follow-up, and speed thresholds"

    if ! awk -v rate="${mixed_success_rate%%%}" 'BEGIN { exit !(rate >= 95) }'; then
        recommendation="hold-default"
        reason="mixed success rate is below 95%"
    elif ! awk -v rate="${mixed_follow_up_rate%%%}" 'BEGIN { exit !(rate <= 10) }'; then
        recommendation="hold-default"
        reason="mixed follow-up rate is above 10%"
    elif [ "$cycle_time_improvement" = "n/a" ]; then
        recommendation="hold-default"
        reason="all-xhigh baseline data is missing"
    elif ! awk -v improvement="${cycle_time_improvement%%%}" 'BEGIN { exit !(improvement >= 15) }'; then
        recommendation="hold-default"
        reason="cycle time improvement versus all-xhigh is below 15%"
    fi
fi

cat <<EOF
mode: mixed
sample_size: $mixed_sample_size
success_rate: $mixed_success_rate
follow_up_rate: $mixed_follow_up_rate
average_cycle_minutes: $mixed_average_cycle
median_cycle_minutes: $mixed_median_cycle
mode: all-xhigh
sample_size: $all_xhigh_sample_size
success_rate: $all_xhigh_success_rate
follow_up_rate: $all_xhigh_follow_up_rate
average_cycle_minutes: $all_xhigh_average_cycle
median_cycle_minutes: $all_xhigh_median_cycle
cycle_time_improvement_vs_all_xhigh: $cycle_time_improvement
recommendation: $recommendation
reason: $reason
EOF
