#!/bin/bash
# Project scanner — detects language, dirs, framework, domain
# Pure bash + jq. Runs from project root, outputs JSON to stdout.
# No API tokens needed. Deterministic.

set -euo pipefail

# ---- Language Detection ----
detect_language() {
    if [ -f "package.json" ]; then
        echo "javascript"
    elif [ -f "Cargo.toml" ]; then
        echo "rust"
    elif [ -f "go.mod" ]; then
        echo "go"
    elif [ -f "pyproject.toml" ] || [ -f "setup.py" ] || [ -f "requirements.txt" ]; then
        echo "python"
    elif [ -f "Gemfile" ]; then
        echo "ruby"
    elif [ -f "pom.xml" ] || [ -f "build.gradle" ]; then
        echo "java"
    else
        echo "unknown"
    fi
}

# ---- Source Directory ----
detect_source_dir() {
    local dirs=("src/" "app/" "lib/" "pkg/" "cmd/")
    for d in "${dirs[@]}"; do
        if [ -d "$d" ]; then
            echo "$d"
            return
        fi
    done
    echo ""
}

# ---- Test Directory ----
detect_test_dir() {
    local dirs=("tests/" "__tests__/" "spec/" "test/")
    for d in "${dirs[@]}"; do
        if [ -d "$d" ]; then
            echo "$d"
            return
        fi
    done
    echo ""
}

# ---- Test Framework ----
detect_test_framework() {
    # Config file detection (most reliable)
    if ls jest.config.* 2>/dev/null | head -1 | grep -q .; then
        echo "jest"
    elif ls vitest.config.* 2>/dev/null | head -1 | grep -q .; then
        echo "vitest"
    elif [ -f "pytest.ini" ] || { [ -f "pyproject.toml" ] && grep -q "pytest" "pyproject.toml" 2>/dev/null; }; then
        echo "pytest"
    elif [ -f ".rspec" ]; then
        echo "rspec"
    elif [ -f "package.json" ]; then
        # Fallback: check scripts.test in package.json
        local test_script
        test_script=$(jq -r '.scripts.test // ""' package.json 2>/dev/null)
        case "$test_script" in
            *jest*) echo "jest" ;;
            *vitest*) echo "vitest" ;;
            *mocha*) echo "mocha" ;;
            *ava*) echo "ava" ;;
            *) echo "" ;;
        esac
    elif [ -f "Cargo.toml" ]; then
        echo "cargo-test"
    elif [ -f "go.mod" ]; then
        echo "go-test"
    else
        echo ""
    fi
}

# ---- Test Command ----
detect_test_command() {
    local language="$1"
    local framework="$2"

    if [ -f "package.json" ]; then
        local test_script
        test_script=$(jq -r '.scripts.test // ""' package.json 2>/dev/null)
        if [ -n "$test_script" ]; then
            echo "npm test"
            return
        fi
    fi

    case "$framework" in
        pytest) echo "pytest" ;;
        rspec) echo "bundle exec rspec" ;;
        cargo-test) echo "cargo test" ;;
        go-test) echo "go test ./..." ;;
        *) echo "" ;;
    esac
}

# ---- Lint Command ----
detect_lint_command() {
    if [ -f "package.json" ]; then
        local lint_script
        lint_script=$(jq -r '.scripts.lint // ""' package.json 2>/dev/null)
        if [ -n "$lint_script" ]; then
            echo "npm run lint"
            return
        fi
    fi
    if ls .eslintrc* 2>/dev/null | head -1 | grep -q . || [ -f "eslint.config.js" ] || [ -f "eslint.config.mjs" ]; then
        echo "npx eslint ."
    elif [ -f "biome.json" ] || [ -f "biome.jsonc" ]; then
        echo "npx biome check ."
    elif [ -f "pyproject.toml" ] && grep -q "ruff" "pyproject.toml" 2>/dev/null; then
        echo "ruff check ."
    else
        echo ""
    fi
}

# ---- Build Command ----
detect_build_command() {
    if [ -f "package.json" ]; then
        local build_script
        build_script=$(jq -r '.scripts.build // ""' package.json 2>/dev/null)
        if [ -n "$build_script" ]; then
            echo "npm run build"
            return
        fi
    fi
    if [ -f "Makefile" ]; then
        echo "make"
    elif [ -f "Cargo.toml" ]; then
        echo "cargo build"
    elif [ -f "go.mod" ]; then
        echo "go build ./..."
    else
        echo ""
    fi
}

# ---- CI Detection ----
detect_ci() {
    if [ -d ".github/workflows" ]; then
        echo "github-actions"
    elif [ -f ".gitlab-ci.yml" ]; then
        echo "gitlab-ci"
    elif [ -f "Jenkinsfile" ]; then
        echo "jenkins"
    else
        echo ""
    fi
}

# ---- Domain Detection ----
detect_domain() {
    # Firmware: Makefile with flash/burn/openocd target
    if [ -f "Makefile" ] && grep -qE '^(flash|burn|upload|openocd)\s*:' Makefile 2>/dev/null; then
        echo "firmware"
        return
    fi

    # Data science: .ipynb files present (find for bash 3.x compat — ** not recursive)
    if find . -maxdepth 3 -name '*.ipynb' -print -quit 2>/dev/null | grep -q .; then
        echo "data-science"
        return
    fi

    # CLI: package.json with bin field and no React
    if [ -f "package.json" ]; then
        local has_bin="no" has_react="no"
        jq -e '.bin' package.json >/dev/null 2>&1 && has_bin="yes"
        jq -e '.dependencies.react // .devDependencies.react' package.json >/dev/null 2>&1 && has_react="yes"
        if [ "$has_bin" = "yes" ] && [ "$has_react" = "no" ]; then
            echo "cli"
            return
        fi
    fi

    echo "web"
}

# ---- Existing Docs ----
detect_existing_docs() {
    local docs=""
    [ -f "AGENTS.md" ] && docs="$docs AGENTS.md"
    [ -f "TESTING.md" ] && docs="$docs TESTING.md"
    [ -f "ARCHITECTURE.md" ] && docs="$docs ARCHITECTURE.md"

    if [ -z "$docs" ]; then
        echo "[]"
    else
        echo "$docs" | tr ' ' '\n' | grep . | jq -R . | jq -s .
    fi
}

# ---- File Counts ----
count_files_under() {
    local dir="${1:-}"

    if [ -z "$dir" ] || [ ! -d "$dir" ]; then
        echo "0"
        return
    fi

    find "$dir" -type f \
        ! -path '*/.git/*' \
        ! -path '*/node_modules/*' \
        2>/dev/null | wc -l | tr -d ' '
}

# ---- Repo Shape ----
detect_repo_shape() {
    local existing_docs="$1"
    local source_dir="$2"
    local test_dir="$3"
    local docs_count source_file_count test_file_count

    docs_count=$(printf '%s\n' "$existing_docs" | jq 'length')
    source_file_count=$(count_files_under "$source_dir")
    test_file_count=$(count_files_under "$test_dir")

    if [ "$docs_count" -ge 3 ] &&
       [ "$source_file_count" -le 3 ] &&
       [ "$test_file_count" -le 1 ]; then
        echo "docs-strong-scaffold"
    elif [ "$docs_count" -ge 3 ]; then
        echo "docs-strong"
    elif [ "$source_file_count" -le 1 ] && [ "$test_file_count" -eq 0 ]; then
        echo "scaffold"
    else
        echo "standard"
    fi
}

# ---- Confidence Map ----
build_confidence_map() {
    local repo_shape="$1"
    local test_command="$2"
    local overall known unresolved

    case "$repo_shape" in
        docs-strong-scaffold)
            overall="medium"
            known=$(jq -cn '[
                "Planning/docs already exist",
                "Code/test tree is still mostly scaffold"
            ]')
            if [ -n "$test_command" ]; then
                unresolved=$(jq -cn '[
                    "Test harness shape needs explicit repo-specific interpretation"
                ]')
            else
                unresolved=$(jq -cn '[
                    "Test command is still missing",
                    "Test harness shape needs explicit repo-specific interpretation"
                ]')
            fi
            ;;
        docs-strong)
            overall="high"
            known=$(jq -cn '[
                "Planning/docs already exist",
                "Implementation tree looks more substantial than a pure scaffold"
            ]')
            unresolved=$(jq -cn '[]')
            ;;
        scaffold)
            overall="medium"
            known=$(jq -cn '[
                "Repository is still mostly scaffold"
            ]')
            if [ -n "$test_command" ]; then
                unresolved=$(jq -cn '[
                    "Detected test command likely needs confirmation against the scaffolded repo shape"
                ]')
            else
                unresolved=$(jq -cn '[
                    "Test command is still missing"
                ]')
            fi
            ;;
        *)
            overall="high"
            known=$(jq -cn '[
                "Repository shape looks standard"
            ]')
            unresolved=$(jq -cn '[]')
            ;;
    esac

    jq -cn \
        --arg overall "$overall" \
        --argjson known "$known" \
        --argjson unresolved "$unresolved" \
        '{
            overall: $overall,
            known: $known,
            unresolved: $unresolved
        }'
}

# ---- Main: run all detections, output JSON ----
main() {
    local language source_dir test_dir test_framework test_command
    local lint_command build_command ci domain existing_docs repo_shape confidence_map

    language=$(detect_language)
    source_dir=$(detect_source_dir)
    test_dir=$(detect_test_dir)
    test_framework=$(detect_test_framework)
    test_command=$(detect_test_command "$language" "$test_framework")
    lint_command=$(detect_lint_command)
    build_command=$(detect_build_command)
    ci=$(detect_ci)
    domain=$(detect_domain)
    existing_docs=$(detect_existing_docs)
    repo_shape=$(detect_repo_shape "$existing_docs" "$source_dir" "$test_dir")
    confidence_map=$(build_confidence_map "$repo_shape" "$test_command")

    jq -n \
        --arg language "$language" \
        --arg source_dir "$source_dir" \
        --arg test_dir "$test_dir" \
        --arg test_framework "$test_framework" \
        --arg test_command "$test_command" \
        --arg lint_command "$lint_command" \
        --arg build_command "$build_command" \
        --arg ci "$ci" \
        --arg domain "$domain" \
        --arg repo_shape "$repo_shape" \
        --argjson existing_docs "$existing_docs" \
        --argjson confidence_map "$confidence_map" \
        '{
            language: $language,
            source_dir: $source_dir,
            test_dir: $test_dir,
            test_framework: $test_framework,
            test_command: $test_command,
            lint_command: $lint_command,
            build_command: $build_command,
            ci: $ci,
            domain: $domain,
            existing_docs: $existing_docs,
            repo_shape: $repo_shape,
            confidence_map: $confidence_map
        }'
}

main
