#!/bin/bash

require_node() {
    if ! command -v node >/dev/null 2>&1; then
        echo "Error: node is required for JSON processing." >&2
        exit 1
    fi
}

json_eval_file() {
    local file="$1"
    local expr="$2"

    JSON_FILE="$file" JSON_EXPR="$expr" node -e '
const fs = require("fs");
const file = process.env.JSON_FILE;
const expr = process.env.JSON_EXPR;

const data = JSON.parse(fs.readFileSync(file, "utf8"));
const value = Function("data", `return (${expr});`)(data);
if (value === undefined || value === null) {
  process.exit(1);
}

if (typeof value === "object") {
  process.stdout.write(JSON.stringify(value));
} else {
  process.stdout.write(String(value));
}
'
}

json_get_file() {
    json_eval_file "$1" "$2" 2>/dev/null || true
}

json_has_truthy_file() {
    local file="$1"
    local expr="$2"

    JSON_FILE="$file" JSON_EXPR="$expr" node -e '
const fs = require("fs");
const file = process.env.JSON_FILE;
const expr = process.env.JSON_EXPR;

const data = JSON.parse(fs.readFileSync(file, "utf8"));
const value = Function("data", `return (${expr});`)(data);
process.exit(value ? 0 : 1);
' >/dev/null 2>&1
}

json_eval_stdin() {
    local expr="$1"

    JSON_EXPR="$expr" node -e '
const fs = require("fs");
const expr = process.env.JSON_EXPR;
const input = fs.readFileSync(0, "utf8");
if (!input.trim()) {
  process.exit(1);
}

const data = JSON.parse(input);
const value = Function("data", `return (${expr});`)(data);
if (value === undefined || value === null) {
  process.exit(1);
}

if (typeof value === "object") {
  process.stdout.write(JSON.stringify(value));
} else {
  process.stdout.write(String(value));
}
'
}

json_get_stdin() {
    json_eval_stdin "$1" 2>/dev/null || true
}
