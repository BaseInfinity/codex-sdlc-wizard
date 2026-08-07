#!/bin/bash
# Roadmap tests — keep GitHub as source of truth and list work in priority order.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$SCRIPT_DIR/.."
ROADMAP="$REPO_DIR/ROADMAP.md"
PACKAGE_JSON="$REPO_DIR/package.json"
REPOSITORY_URL="https://github.com/BaseInfinity/codex-sdlc-wizard"
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

issue_line() {
    local issue_number="$1"
    grep -nF "$REPOSITORY_URL/issues/$issue_number" "$ROADMAP" | cut -d: -f1 | head -n1 || true
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

test_roadmap_declares_order_as_priority() {
    local has_source_of_truth=true
    local has_priority_contract=true
    local has_goals_boundary=true

    grep -Eqi 'GitHub issues.*source of truth|source of truth.*GitHub issues' "$ROADMAP" || has_source_of_truth=false
    grep -Eqi 'order.*priority|top.*next' "$ROADMAP" || has_priority_contract=false
    grep -Eqi 'GOALS\.md.*active|active.*GOALS\.md' "$ROADMAP" || has_goals_boundary=false

    if [ "$has_source_of_truth" = "true" ] &&
       [ "$has_priority_contract" = "true" ] &&
       [ "$has_goals_boundary" = "true" ]; then
        pass "Roadmap declares its GitHub-backed priority contract"
    else
        fail "Roadmap does not clearly define source of truth, priority order, and active-goal boundaries"
    fi
}

test_roadmap_states_current_release() {
    local package_version
    package_version=$(sed -n 's/.*"version": "\([^"]*\)".*/\1/p' "$PACKAGE_JSON" | head -n1)

    if grep -Eq "GitHub release.*${package_version}|${package_version}.*GitHub release" "$ROADMAP" &&
       grep -Eq "npm.*${package_version}|${package_version}.*npm" "$ROADMAP"; then
        pass "Roadmap states the package-aligned current release"
    else
        fail "Roadmap does not state the package-aligned GitHub and npm release"
    fi
}

test_roadmap_links_every_open_issue() {
    local issue_number
    local missing=0
    local post_merge_open_issues="58 64 65 66 67 71 72 73 77 79 81 82 84 86 88 92"

    for issue_number in $post_merge_open_issues; do
        if ! grep -Fq "$REPOSITORY_URL/issues/$issue_number" "$ROADMAP"; then
            echo "Missing issue link: #$issue_number"
            missing=$((missing + 1))
        fi
    done

    if [ "$missing" -eq 0 ]; then
        pass "Roadmap links every GitHub issue that remains open after this change"
    else
        fail "Roadmap is missing $missing open issue link(s)"
    fi
}

test_roadmap_top_order_matches_release_priority() {
    local previous=0
    local current
    local issue_number
    local ordered_issues="79 92 73 65 67 84 88 66"

    for issue_number in $ordered_issues; do
        current=$(issue_line "$issue_number")
        if [ -z "$current" ] || [ "$current" -le "$previous" ]; then
            fail "Roadmap priority order is wrong at issue #$issue_number"
            return
        fi
        previous="$current"
    done

    pass "Roadmap orders the 0.7.36 release queue by priority"
}

test_roadmap_keeps_upstream_issues_together() {
    local line_65
    local line_81

    line_65=$(issue_line 65)
    line_81=$(issue_line 81)

    if [ -n "$line_65" ] && [ "$line_65" = "$line_81" ]; then
        pass "Roadmap consolidates the cumulative upstream audit links"
    else
        fail "Roadmap does not keep issues #65 and #81 in one timeboxed priority item"
    fi
}

test_roadmap_requires_issue_owner_for_every_priority() {
    local missing_owner=0
    local line

    while IFS= read -r line; do
        if ! grep -Eq "$REPOSITORY_URL/issues/[0-9]+" <<<"$line"; then
            echo "Priority item has no GitHub issue: $line"
            missing_owner=$((missing_owner + 1))
        fi
    done < <(grep -E '^[0-9]+\. ' "$ROADMAP")

    if [ "$missing_owner" -eq 0 ]; then
        pass "Every roadmap priority has a GitHub issue owner"
    else
        fail "Roadmap has $missing_owner priority item(s) without a GitHub issue owner"
    fi
}

test_roadmap_removes_stale_prose_sections() {
    local stale=false

    grep -q '^## Tracker Cleanup$' "$ROADMAP" && stale=true
    grep -q '^## Remaining Backlog$' "$ROADMAP" && stale=true
    grep -q '^## Working Order$' "$ROADMAP" && stale=true
    grep -q '^## Later Research$' "$ROADMAP" && stale=true

    if [ "$stale" = "false" ]; then
        pass "Roadmap removes duplicated historical and priority prose"
    else
        fail "Roadmap still contains obsolete prose sections that duplicate GitHub"
    fi
}

test_roadmap_exists
test_roadmap_declares_order_as_priority
test_roadmap_states_current_release
test_roadmap_links_every_open_issue
test_roadmap_top_order_matches_release_priority
test_roadmap_keeps_upstream_issues_together
test_roadmap_requires_issue_owner_for_every_priority
test_roadmap_removes_stale_prose_sections

echo ""
echo "=== Results: $PASSED passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
    exit 1
fi
