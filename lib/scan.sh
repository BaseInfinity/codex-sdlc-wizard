#!/bin/bash
# Project scanner — detects language, dirs, framework, domain
# Bash + Node. Runs from project root, outputs JSON to stdout.
# No API tokens needed. Deterministic.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/json-node.sh"

require_node

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
    elif ls playwright.config.* 2>/dev/null | head -1 | grep -q .; then
        echo "playwright"
    elif ls cypress.config.* 2>/dev/null | head -1 | grep -q .; then
        echo "cypress"
    elif [ -f "pytest.ini" ] || { [ -f "pyproject.toml" ] && grep -q "pytest" "pyproject.toml" 2>/dev/null; }; then
        echo "pytest"
    elif [ -f ".rspec" ]; then
        echo "rspec"
    elif [ -f "package.json" ]; then
        # Fallback: check scripts.test in package.json
        local test_script
        test_script=$(json_get_file "package.json" 'typeof data.scripts?.test === "string" ? data.scripts.test : ""')
        case "$test_script" in
            *jest*) echo "jest" ;;
            *vitest*) echo "vitest" ;;
            *playwright*) echo "playwright" ;;
            *cypress*) echo "cypress" ;;
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
        test_script=$(json_get_file "package.json" 'typeof data.scripts?.test === "string" ? data.scripts.test : ""')
        if [ -n "$test_script" ]; then
            echo "npm test"
            return
        fi
    fi

    case "$framework" in
        playwright) echo "npx playwright test" ;;
        cypress) echo "npx cypress run" ;;
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
        lint_script=$(json_get_file "package.json" 'typeof data.scripts?.lint === "string" ? data.scripts.lint : ""')
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

# ---- Typecheck Command ----
detect_typecheck_command() {
    if [ -f "package.json" ]; then
        local typecheck_script check_types_script
        typecheck_script=$(json_get_file "package.json" 'typeof data.scripts?.typecheck === "string" ? data.scripts.typecheck : ""')
        check_types_script=$(json_get_file "package.json" 'typeof data.scripts?.["check-types"] === "string" ? data.scripts["check-types"] : ""')

        if [ -n "$typecheck_script" ]; then
            echo "npm run typecheck"
            return
        fi

        if [ -n "$check_types_script" ]; then
            echo "npm run check-types"
            return
        fi
    fi

    if [ -f "tsconfig.json" ]; then
        echo "npx tsc --noEmit"
    elif [ -f "mypy.ini" ] || { [ -f "pyproject.toml" ] && grep -q "mypy" "pyproject.toml" 2>/dev/null; }; then
        echo "mypy ."
    elif [ -f "Cargo.toml" ]; then
        echo "cargo check"
    else
        echo ""
    fi
}

# ---- Single Test Command ----
detect_single_test_command() {
    local framework="$1"

    case "$framework" in
        jest|vitest|mocha|ava)
            if [ -f "package.json" ]; then
                echo "npm test -- <test-file>"
            else
                echo "npx $framework <test-file>"
            fi
            ;;
        playwright) echo "npx playwright test <test-file>" ;;
        cypress) echo "npx cypress run --spec <test-file>" ;;
        pytest) echo "pytest path/to/test_file.py" ;;
        rspec) echo "bundle exec rspec path/to/spec.rb" ;;
        cargo-test) echo "cargo test <test_name>" ;;
        go-test) echo "go test ./... -run TestName" ;;
        *) echo "" ;;
    esac
}

# ---- Build Command ----
detect_build_command() {
    if [ -f "package.json" ]; then
        local build_script
        build_script=$(json_get_file "package.json" 'typeof data.scripts?.build === "string" ? data.scripts.build : ""')
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

# ---- Deployment Detection ----
detect_deployment_setup() {
    local deployments=()
    local item joined

    [ -f "Dockerfile" ] && deployments+=("docker")
    { [ -f "docker-compose.yml" ] || [ -f "docker-compose.yaml" ]; } && deployments+=("docker-compose")
    [ -f "vercel.json" ] && deployments+=("vercel")
    [ -f "fly.toml" ] && deployments+=("fly.io")
    [ -f "netlify.toml" ] && deployments+=("netlify")
    [ -f "Procfile" ] && deployments+=("procfile")
    { [ -d "k8s" ] || [ -d "kubernetes" ]; } && deployments+=("kubernetes")
    if find .github/workflows -maxdepth 1 -type f \( -iname '*deploy*.yml' -o -iname '*deploy*.yaml' \) -print -quit 2>/dev/null | grep -q .; then
        deployments+=("github-actions")
    fi

    if [ "${#deployments[@]}" -eq 0 ]; then
        echo ""
        return
    fi

    joined=$(IFS=', '; echo "${deployments[*]}")
    printf '%s\n' "$joined"
}

# ---- Database Detection ----
detect_databases() {
    local databases=()
    local provider joined compose_file

    if [ -f "prisma/schema.prisma" ]; then
        provider=$(sed -n 's/.*provider *= *"\([^"]*\)".*/\1/p' "prisma/schema.prisma" | head -1)
        case "$provider" in
            postgresql|postgres) databases+=("postgresql") ;;
            mysql|sqlite|mongodb) databases+=("$provider") ;;
        esac
    fi

    if [ -f ".env" ]; then
        grep -Eqi 'DATABASE_URL=.*postgres(ql)?://' ".env" && databases+=("postgresql")
        grep -Eqi 'DATABASE_URL=.*mysql://' ".env" && databases+=("mysql")
        grep -Eqi 'DATABASE_URL=.*sqlite:' ".env" && databases+=("sqlite")
        grep -Eqi 'DATABASE_URL=.*mongodb(\+srv)?://' ".env" && databases+=("mongodb")
    fi

    for compose_file in docker-compose.yml docker-compose.yaml; do
        if [ -f "$compose_file" ]; then
            grep -Eqi 'image:\s*postgres' "$compose_file" && databases+=("postgresql")
            grep -Eqi 'image:\s*mysql|image:\s*mariadb' "$compose_file" && databases+=("mysql")
            grep -Eqi 'image:\s*mongo' "$compose_file" && databases+=("mongodb")
        fi
    done

    if [ "${#databases[@]}" -eq 0 ]; then
        echo ""
        return
    fi

    joined=$(printf '%s\n' "${databases[@]}" | awk '!seen[$0]++ { printf("%s%s", sep, $0); sep=", " }')
    printf '%s\n' "$joined"
}

# ---- Cache Detection ----
detect_cache_layer() {
    local caches=()
    local joined compose_file

    if [ -f ".env" ]; then
        grep -Eqi 'REDIS_URL=|REDIS_HOST=' ".env" && caches+=("redis")
        grep -Eqi 'MEMCACHED_URL=|MEMCACHED_HOST=' ".env" && caches+=("memcached")
    fi

    for compose_file in docker-compose.yml docker-compose.yaml; do
        if [ -f "$compose_file" ]; then
            grep -Eqi 'image:\s*redis' "$compose_file" && caches+=("redis")
            grep -Eqi 'image:\s*memcached' "$compose_file" && caches+=("memcached")
        fi
    done

    if [ "${#caches[@]}" -eq 0 ]; then
        echo ""
        return
    fi

    joined=$(printf '%s\n' "${caches[@]}" | awk '!seen[$0]++ { printf("%s%s", sep, $0); sep=", " }')
    printf '%s\n' "$joined"
}

# ---- Test Duration ----
detect_test_duration() {
    local test_count

    test_count=$(find . -maxdepth 5 -type f \( -name '*.test.*' -o -name '*.spec.*' -o -name '*_test.*' -o -name '*.e2e.*' -o -name '*.integration.*' \) | wc -l | tr -d ' ')

    if [ "$test_count" -eq 0 ]; then
        echo ""
    elif [ "$test_count" -le 25 ]; then
        echo "<1 minute"
    elif [ "$test_count" -le 150 ]; then
        echo "1-5 minutes"
    else
        echo "5+ minutes"
    fi
}

# ---- Test Types ----
detect_test_types() {
    local test_types=()
    local joined

    if find . -maxdepth 5 -type f \( -name '*.test.*' -o -name '*.spec.*' -o -name '*_test.*' \) \
        ! -path '*/integration/*' ! -path '*/e2e/*' ! -name '*.integration.*' ! -name '*.e2e.*' -print -quit 2>/dev/null | grep -q .; then
        test_types+=("unit")
    fi

    if find . -maxdepth 5 \( -type d -name 'integration' -o -type f -name '*.integration.*' \) -print -quit 2>/dev/null | grep -q .; then
        test_types+=("integration")
    fi

    if find . -maxdepth 5 \( -type d -name 'e2e' -o -type f -name '*.e2e.*' \) -print -quit 2>/dev/null | grep -q . \
        || ls playwright.config.* 2>/dev/null | head -1 | grep -q . \
        || ls cypress.config.* 2>/dev/null | head -1 | grep -q .; then
        test_types+=("e2e")
    fi

    if find . -maxdepth 5 \( -type d -name 'api' -o -type f -name '*.api.*' \) -print -quit 2>/dev/null | grep -q .; then
        test_types+=("api")
    fi

    if [ "${#test_types[@]}" -eq 0 ]; then
        echo ""
        return
    fi

    joined=$(printf '%s\n' "${test_types[@]}" | awk '{ printf("%s%s", sep, $0); sep=", " }')
    printf '%s\n' "$joined"
}

# ---- Coverage Detection ----
detect_coverage_config() {
    if [ -f "package.json" ]; then
        local coverage_script test_script
        coverage_script=$(json_get_file "package.json" 'typeof data.scripts?.coverage === "string" ? data.scripts.coverage : ""')
        test_script=$(json_get_file "package.json" 'typeof data.scripts?.test === "string" ? data.scripts.test : ""')

        if [ -n "$coverage_script" ]; then
            echo "npm run coverage"
            return
        fi

        case "$test_script" in
            *--coverage*)
                if printf '%s' "$test_script" | grep -qi 'jest'; then
                    echo "jest --coverage"
                elif printf '%s' "$test_script" | grep -qi 'vitest'; then
                    echo "vitest --coverage"
                else
                    echo "$test_script"
                fi
                return
                ;;
        esac
    fi

    if ls .nycrc* 2>/dev/null | head -1 | grep -q .; then
        echo "nyc"
    elif [ -f "coverage.py" ] || [ -f ".coveragerc" ]; then
        echo "coverage.py"
    elif [ -f "pyproject.toml" ] && grep -q "pytest-cov" "pyproject.toml" 2>/dev/null; then
        echo "pytest --cov"
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
        json_has_truthy_file "package.json" 'data.bin' && has_bin="yes"
        json_has_truthy_file "package.json" 'data.dependencies?.react || data.devDependencies?.react' && has_react="yes"
        if [ "$has_bin" = "yes" ] && [ "$has_react" = "no" ]; then
            echo "cli"
            return
        fi
    fi

    echo "web"
}

# ---- Existing Docs ----
detect_existing_docs() {
    local docs=()
    [ -f "AGENTS.md" ] && docs+=('"AGENTS.md"')
    [ -f "TESTING.md" ] && docs+=('"TESTING.md"')
    [ -f "ARCHITECTURE.md" ] && docs+=('"ARCHITECTURE.md"')

    if [ "${#docs[@]}" -eq 0 ]; then
        echo "[]"
    else
        local joined
        joined=$(IFS=,; echo "${docs[*]}")
        printf '[%s]\n' "$joined"
    fi
}

# ---- MCP Browser Detection ----
detect_mcp_browser_tooling() {
    if [ -f ".mcp.json" ] && grep -Eiq '@playwright/mcp|playwright' ".mcp.json" 2>/dev/null; then
        echo "playwright-mcp"
        return
    fi

    if [ -f "package.json" ] && json_has_truthy_file "package.json" 'data.dependencies?.["@playwright/mcp"] || data.devDependencies?.["@playwright/mcp"]'; then
        echo "playwright-mcp"
        return
    fi

    echo ""
}

detect_mcp_browser_profile_policy() {
    local tooling="$1"

    if [ "$tooling" != "playwright-mcp" ]; then
        echo ""
        return
    fi

    if [ -f ".mcp.json" ] && grep -Eiq -- '--isolated|isolated' ".mcp.json" 2>/dev/null; then
        echo "isolated"
    elif [ -f ".mcp.json" ] && grep -Eiq -- 'userDataDir|user-data-dir|persistent|profile|browser-state' ".mcp.json" 2>/dev/null; then
        echo "shared/persistent"
    else
        echo "unknown"
    fi
}

# ---- Main: run all detections, output JSON ----
main() {
    local language source_dir test_dir test_framework test_command
    local lint_command typecheck_command single_test_command build_command deployment_setup
    local databases cache_layer test_duration test_types coverage_config ci domain existing_docs
    local mcp_browser_tooling mcp_browser_profile_policy

    language=$(detect_language)
    source_dir=$(detect_source_dir)
    test_dir=$(detect_test_dir)
    test_framework=$(detect_test_framework)
    test_command=$(detect_test_command "$language" "$test_framework")
    lint_command=$(detect_lint_command)
    typecheck_command=$(detect_typecheck_command)
    single_test_command=$(detect_single_test_command "$test_framework")
    build_command=$(detect_build_command)
    deployment_setup=$(detect_deployment_setup)
    databases=$(detect_databases)
    cache_layer=$(detect_cache_layer)
    test_duration=$(detect_test_duration)
    test_types=$(detect_test_types)
    coverage_config=$(detect_coverage_config)
    ci=$(detect_ci)
    domain=$(detect_domain)
    existing_docs=$(detect_existing_docs)
    mcp_browser_tooling=$(detect_mcp_browser_tooling)
    mcp_browser_profile_policy=$(detect_mcp_browser_profile_policy "$mcp_browser_tooling")

    SCAN_LANGUAGE="$language" \
    SCAN_SOURCE_DIR="$source_dir" \
    SCAN_TEST_DIR="$test_dir" \
    SCAN_TEST_FRAMEWORK="$test_framework" \
    SCAN_TEST_COMMAND="$test_command" \
    SCAN_LINT_COMMAND="$lint_command" \
    SCAN_TYPECHECK_COMMAND="$typecheck_command" \
    SCAN_SINGLE_TEST_COMMAND="$single_test_command" \
    SCAN_BUILD_COMMAND="$build_command" \
    SCAN_DEPLOYMENT_SETUP="$deployment_setup" \
    SCAN_DATABASES="$databases" \
    SCAN_CACHE_LAYER="$cache_layer" \
    SCAN_TEST_DURATION="$test_duration" \
    SCAN_TEST_TYPES="$test_types" \
    SCAN_COVERAGE_CONFIG="$coverage_config" \
    SCAN_CI="$ci" \
    SCAN_DOMAIN="$domain" \
    SCAN_EXISTING_DOCS="$existing_docs" \
    SCAN_MCP_BROWSER_TOOLING="$mcp_browser_tooling" \
    SCAN_MCP_BROWSER_PROFILE_POLICY="$mcp_browser_profile_policy" \
    node -e '
const data = {
  language: process.env.SCAN_LANGUAGE || "",
  source_dir: process.env.SCAN_SOURCE_DIR || "",
  test_dir: process.env.SCAN_TEST_DIR || "",
  test_framework: process.env.SCAN_TEST_FRAMEWORK || "",
  test_command: process.env.SCAN_TEST_COMMAND || "",
  lint_command: process.env.SCAN_LINT_COMMAND || "",
  typecheck_command: process.env.SCAN_TYPECHECK_COMMAND || "",
  single_test_command: process.env.SCAN_SINGLE_TEST_COMMAND || "",
  build_command: process.env.SCAN_BUILD_COMMAND || "",
  deployment_setup: process.env.SCAN_DEPLOYMENT_SETUP || "",
  databases: process.env.SCAN_DATABASES || "",
  cache_layer: process.env.SCAN_CACHE_LAYER || "",
  test_duration: process.env.SCAN_TEST_DURATION || "",
  test_types: process.env.SCAN_TEST_TYPES || "",
  coverage_config: process.env.SCAN_COVERAGE_CONFIG || "",
  ci: process.env.SCAN_CI || "",
  domain: process.env.SCAN_DOMAIN || "",
  existing_docs: JSON.parse(process.env.SCAN_EXISTING_DOCS || "[]"),
  mcp_browser_tooling: process.env.SCAN_MCP_BROWSER_TOOLING || "",
  mcp_browser_profile_policy: process.env.SCAN_MCP_BROWSER_PROFILE_POLICY || ""
};

process.stdout.write(`${JSON.stringify(data)}\n`);
'
}

main
