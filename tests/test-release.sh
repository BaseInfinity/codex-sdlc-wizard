#!/bin/bash
# Release tests — keep versioned distribution aligned with the documented flow

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$SCRIPT_DIR/.."
README="$REPO_DIR/README.md"
WORKFLOW="$REPO_DIR/.github/workflows/release.yml"
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

echo "=== Release Tests ==="
echo ""

test_release_workflow_exists() {
    if [ -f "$WORKFLOW" ]; then
        pass "Release workflow exists"
    else
        fail "Release workflow is missing"
    fi
}

test_release_workflow_triggers_on_semver_tags() {
    if [ -f "$WORKFLOW" ] &&
       grep -Eq "tags:[[:space:]]*$" "$WORKFLOW" &&
       grep -Eq -- "-[[:space:]]*'v\\*'|-[[:space:]]*\"v\\*\"" "$WORKFLOW"; then
        pass "Release workflow triggers on v* tags"
    else
        fail "Release workflow does not trigger on semver-like tags"
    fi
}

test_release_workflow_supports_manual_dispatch() {
    if [ -f "$WORKFLOW" ] && grep -q '^  workflow_dispatch:' "$WORKFLOW"; then
        pass "Release workflow supports manual dispatch"
    else
        fail "Release workflow is missing workflow_dispatch"
    fi
}

test_release_workflow_can_publish_release() {
    if [ -f "$WORKFLOW" ] &&
       grep -Eq 'contents:[[:space:]]*write' "$WORKFLOW" &&
       grep -Eq 'gh release create|softprops/action-gh-release' "$WORKFLOW"; then
        pass "Release workflow has permission and logic to publish a GitHub Release"
    else
        fail "Release workflow does not clearly publish a GitHub Release"
    fi
}

test_release_workflow_can_publish_npm() {
    local has_node_setup=true
    local has_oidc_permission=true
    local has_npm_publish=true
    local has_no_npm_token=true
    local has_no_token_auth_check=true

    grep -Eq 'actions/setup-node@v[0-9]+' "$WORKFLOW" || has_node_setup=false
    grep -Eq 'id-token:[[:space:]]*write' "$WORKFLOW" || has_oidc_permission=false
    grep -Eq 'npm publish --access public|npm publish[[:space:]]*$' "$WORKFLOW" || has_npm_publish=false
    grep -Eq 'NODE_AUTH_TOKEN:[[:space:]]*\$\{\{ secrets\.NPM_TOKEN \}\}|NPM_TOKEN:[[:space:]]*\$\{\{ secrets\.NPM_TOKEN \}\}' "$WORKFLOW" && has_no_npm_token=false
    grep -Eq 'npm whoami|Require NPM_TOKEN secret' "$WORKFLOW" && has_no_token_auth_check=false

    if [ "$has_node_setup" = "true" ] &&
       [ "$has_oidc_permission" = "true" ] &&
       [ "$has_npm_publish" = "true" ] &&
       [ "$has_no_npm_token" = "true" ] &&
       [ "$has_no_token_auth_check" = "true" ]; then
        pass "Release workflow can publish the npm package with trusted publishing"
    else
        fail "Release workflow does not clearly automate npm trusted publishing"
    fi
}

test_readme_documents_versioned_release_path() {
    local has_section=true
    local has_releases_url=true
    local has_versioned_install=true

    grep -q '^## Releases$' "$README" || has_section=false
    grep -q 'https://github.com/BaseInfinity/codex-sdlc-wizard/releases' "$README" || has_releases_url=false
    grep -Eq 'git clone --branch vX\.Y\.Z|git checkout vX\.Y\.Z' "$README" || has_versioned_install=false

    if [ "$has_section" = "true" ] &&
       [ "$has_releases_url" = "true" ] &&
       [ "$has_versioned_install" = "true" ]; then
        pass "README documents the versioned release install path"
    else
        fail "README does not document versioned release consumption"
    fi
}

test_readme_documents_maintainer_release_steps() {
    local has_heading=true
    local has_tag_step=true
    local has_push_step=true

    grep -q '^### Maintainer Release Flow$' "$README" || has_heading=false
    grep -Eq 'git tag vX\.Y\.Z' "$README" || has_tag_step=false
    grep -Eq 'git push origin vX\.Y\.Z' "$README" || has_push_step=false

    if [ "$has_heading" = "true" ] &&
       [ "$has_tag_step" = "true" ] &&
       [ "$has_push_step" = "true" ]; then
        pass "README documents the maintainer release flow"
    else
        fail "README does not document the maintainer release flow"
    fi
}

test_release_workflow_exists
test_release_workflow_triggers_on_semver_tags
test_release_workflow_supports_manual_dispatch
test_release_workflow_can_publish_release
test_release_workflow_can_publish_npm
test_readme_documents_versioned_release_path
test_readme_documents_maintainer_release_steps

echo ""
echo "=== Results: $PASSED passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
    exit 1
fi
