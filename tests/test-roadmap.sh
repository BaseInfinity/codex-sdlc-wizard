#!/bin/bash
# Roadmap tests — keep GitHub as source of truth and list work in priority order.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$SCRIPT_DIR/.."
ROADMAP="$REPO_DIR/ROADMAP.md"
PACKAGE_JSON="$REPO_DIR/package.json"
REPOSITORY_URL_REGEX='https://github[.]com/BaseInfinity/codex-sdlc-wizard'
OPEN_ISSUES="58 65 66 71 72 77 79 82 84 86 88 92 93 95 96 97 99 100 101 104 105 106 107 108 109 111 112 113 114 115 116"
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
    grep -nE "$REPOSITORY_URL_REGEX/issues/$issue_number([^0-9]|$)" "$ROADMAP" | cut -d: -f1 | head -n1 || true
}

roadmap_has_issue() {
    local issue_number="$1"
    grep -Eq "$REPOSITORY_URL_REGEX/issues/$issue_number([^0-9]|$)" "$ROADMAP"
}

priority_section() {
    awk '
        /^## Priority queue$/ { in_queue = 1; next }
        /^## / { if (in_queue) exit }
        in_queue { print }
    ' "$ROADMAP"
}

priority_lines() {
    priority_section | grep -E '^[0-9]+[.] ' || true
}

priority_has_issue() {
    local issue_number="$1"
    priority_lines | grep -Eq "$REPOSITORY_URL_REGEX/issues/$issue_number([^0-9]|$)"
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
    grep -Eqi 'GOALS\.md.*consumer repo|consumer repo.*GOALS\.md' "$ROADMAP" || has_goals_boundary=false
    grep -Eqi 'GOALS\.md.*(never|does not).*override|never overrides.*priority queue' "$ROADMAP" || has_goals_boundary=false

    if [ "$has_source_of_truth" = "true" ] &&
       [ "$has_priority_contract" = "true" ] &&
       [ "$has_goals_boundary" = "true" ]; then
        pass "Roadmap declares its GitHub-backed priority contract"
    else
        fail "Roadmap does not clearly separate project priority from optional consumer execution scope"
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

test_roadmap_links_post_merge_open_issue_snapshot() {
    local issue_number
    local missing=0
    # Offline completeness snapshot. Update this list in the same change that
    # reconciles GitHub issue state and ROADMAP priority.
    for issue_number in $OPEN_ISSUES; do
        if ! priority_has_issue "$issue_number"; then
            echo "Missing open issue link: #$issue_number"
            missing=$((missing + 1))
        fi
    done

    if [ "$missing" -eq 0 ]; then
        pass "Roadmap links the post-merge open-issue snapshot"
    else
        fail "Roadmap is missing $missing current open issue link(s)"
    fi
}

test_roadmap_rejects_unknown_issue_links() {
    local issue_number
    local unexpected=0

    while IFS= read -r issue_number; do
        [ -n "$issue_number" ] || continue
        case " $OPEN_ISSUES " in
            *" $issue_number "*) ;;
            *)
                echo "Unexpected issue link in priority queue: #$issue_number"
                unexpected=$((unexpected + 1))
                ;;
        esac
    done < <(priority_lines | grep -Eo "$REPOSITORY_URL_REGEX/issues/[0-9]+" | sed 's#.*/##' || true)

    if [ "$unexpected" -eq 0 ]; then
        pass "Roadmap priority queue contains only current open issues"
    else
        fail "Roadmap contains $unexpected stale or unknown issue link(s)"
    fi
}

test_roadmap_priority_section_contains_only_numbered_items() {
    local invalid=0
    local line

    while IFS= read -r line; do
        [ -n "$line" ] || continue
        if ! grep -Eq '^[0-9]+[.] ' <<<"$line"; then
            echo "Malformed priority item: $line"
            invalid=$((invalid + 1))
        fi
    done < <(priority_section)

    if [ "$invalid" -eq 0 ]; then
        pass "Roadmap priority section contains only numbered items"
    else
        fail "Roadmap has $invalid malformed priority item(s)"
    fi
}

test_roadmap_excludes_resolved_issues() {
    local issue_number
    local stale=0
    local closed_issues="64 67 73 81 91 98 110"

    for issue_number in $closed_issues; do
        if roadmap_has_issue "$issue_number"; then
            echo "Roadmap retains resolved issue: #$issue_number"
            stale=$((stale + 1))
        fi
    done

    if [ "$stale" -eq 0 ]; then
        pass "Roadmap excludes resolved issues"
    else
        fail "Roadmap retains $stale resolved issue(s)"
    fi
}

test_roadmap_priority_numbers_are_contiguous() {
    local expected=1
    local actual
    local inspected=0
    local line

    while IFS= read -r line; do
        inspected=$((inspected + 1))
        actual="${line%%.*}"
        if [ "$actual" -ne "$expected" ]; then
            fail "Roadmap priority numbering is not contiguous at item $actual"
            return
        fi
        expected=$((expected + 1))
    done < <(priority_lines)

    if [ "$inspected" -eq 0 ]; then
        fail "Roadmap has no numbered priorities"
        return
    fi

    pass "Roadmap priority numbering is contiguous"
}

test_roadmap_head_order_matches_priority() {
    local previous=0
    local current
    local issue_number
    local ordered_issues="116 111 115 109 92 93 79 88 112 84 86 95 100 106 82 66 108 99 65 113 105 104 101 107 114 72 71 77 97 58 96"

    for issue_number in $ordered_issues; do
        current=$(issue_line "$issue_number")
        if [ -z "$current" ] || [ "$current" -le "$previous" ]; then
            fail "Roadmap priority order is wrong at issue #$issue_number"
            return
        fi
        previous="$current"
    done

    pass "Roadmap orders the release and distribution queue by priority"
}

test_roadmap_does_not_duplicate_issue_owners() {
    local issue_number
    local line
    local seen=""

    while IFS= read -r line; do
        while IFS= read -r issue_number; do
            [ -n "$issue_number" ] || continue
            case " $seen " in
                *" $issue_number "*)
                    fail "Roadmap duplicates issue #$issue_number across priorities"
                    return
                    ;;
            esac
            seen="$seen $issue_number"
        done < <(grep -Eo "$REPOSITORY_URL_REGEX/issues/[0-9]+" <<<"$line" | sed 's#.*/##' || true)
    done < <(priority_lines)

    pass "Roadmap assigns each issue to at most one priority"
}

test_roadmap_requires_issue_owner_for_every_priority() {
    local missing_owner=0
    local line

    while IFS= read -r line; do
        if ! grep -Eq "$REPOSITORY_URL_REGEX/issues/[0-9]+([^0-9]|$)" <<<"$line"; then
            echo "Priority item has no GitHub issue: $line"
            missing_owner=$((missing_owner + 1))
        fi
    done < <(priority_lines)

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
test_roadmap_links_post_merge_open_issue_snapshot
test_roadmap_rejects_unknown_issue_links
test_roadmap_excludes_resolved_issues
test_roadmap_priority_section_contains_only_numbered_items
test_roadmap_priority_numbers_are_contiguous
test_roadmap_head_order_matches_priority
test_roadmap_does_not_duplicate_issue_owners
test_roadmap_requires_issue_owner_for_every_priority
test_roadmap_removes_stale_prose_sections

echo ""
echo "=== Results: $PASSED passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
    exit 1
fi
