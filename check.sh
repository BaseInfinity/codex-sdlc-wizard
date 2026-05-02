#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/json-node.sh"

require_node

node - <<'NODE'
const crypto = require("crypto");
const fs = require("fs");
const path = require("path");

const cwd = process.cwd();
const manifestPath = path.join(cwd, ".codex-sdlc", "manifest.json");

function printJson(value) {
  process.stdout.write(`${JSON.stringify(value, null, 2)}\n`);
}

function sha256File(filePath) {
  const hash = crypto.createHash("sha256");
  hash.update(fs.readFileSync(filePath));
  return `sha256:${hash.digest("hex")}`;
}

if (!fs.existsSync(manifestPath)) {
  printJson({
    repo_state: "uninitialized",
    reason: "manifest_missing",
    managed_files: {}
  });
  process.exit(0);
}

let manifest;
try {
  manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
} catch (error) {
  printJson({
    repo_state: "broken",
    reason: "manifest_invalid",
    error: error.message,
    managed_files: {}
  });
  process.exit(0);
}

function hasPlatformHookDrift(relativePath, absolutePath) {
  if (relativePath !== ".codex/hooks.json") {
    return false;
  }

  const content = fs.readFileSync(absolutePath, "utf8");

  if (process.platform === "win32") {
    return content.includes("bash-guard.sh") || content.includes("session-start.sh");
  }

  return content.includes("powershell.exe");
}

const managedFiles = {};
const summary = {
  match: 0,
  missing: 0,
  customized: 0,
  "drift / broken": 0
};

for (const [relativePath, expectedHash] of Object.entries(manifest.managed_files || {})) {
  if (!expectedHash) {
    continue;
  }

  const absolutePath = path.join(cwd, relativePath);
  let actualHash = "";
  let status;

  if (!fs.existsSync(absolutePath)) {
    status = "missing";
  } else {
    actualHash = sha256File(absolutePath);
    if (hasPlatformHookDrift(relativePath, absolutePath)) {
      status = "drift / broken";
    } else if (actualHash === expectedHash) {
      status = "match";
    } else {
      status = "customized";
    }
  }

  managedFiles[relativePath] = {
    status,
    expected_hash: expectedHash,
    actual_hash: actualHash
  };

  summary[status] += 1;
}

printJson({
  repo_state: "initialized",
  adapter_version: manifest.adapter_version || "",
  scan: manifest.scan || {},
  summary,
  managed_files: managedFiles
});
NODE
