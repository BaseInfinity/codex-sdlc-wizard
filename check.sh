#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/json-node.sh"

require_node

print_help() {
    cat <<'EOF'
Usage: check.sh

Report managed-file drift for the current repo.
EOF
}

for arg in "$@"; do
    case "$arg" in
        --help|-h) print_help; exit 0 ;;
        *)
            echo "Unknown argument: $arg" >&2
            print_help >&2
            exit 1
            ;;
    esac
done

node - "$SCRIPT_DIR/lib/merge-hooks.cjs" <<'NODE'
const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
const { directoryFoldsCase, validateHooksDocument, wizardCommandPath } = require(process.argv[2]);

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

  let document;
  try {
    const content = fs.readFileSync(absolutePath, "utf8").replace(/^\uFEFF/, "");
    document = JSON.parse(content);
    validateHooksDocument(document, relativePath);
  } catch (_error) {
    return true;
  }
  if (!document || typeof document !== "object" || Array.isArray(document)) {
    return true;
  }

  const foldPathCase = directoryFoldsCase(path.dirname(absolutePath));
  const commands = Object.values(document.hooks || {}).flatMap((entries) =>
    Array.isArray(entries) ? entries.flatMap((entry) =>
      Array.isArray(entry?.hooks) ? entry.hooks.map((hook) => hook?.command) : []) : [],
  );
  const scriptPaths = commands
    .map((command) => wizardCommandPath(command, foldPathCase))
    .filter(Boolean);

  if (scriptPaths.some((scriptPath) => /\/(?:git-guard|session-start)\.js$/.test(scriptPath))) {
    return true;
  }
  if (process.platform === "win32") {
    return scriptPaths.some((scriptPath) => /\/(?:bash-guard|session-start)\.sh$/.test(scriptPath));
  }
  return scriptPaths.some((scriptPath) => /\/(?:git-guard|session-start)\.ps1$/.test(scriptPath));
}

function hasManagedHookSurfaceDrift(relativePath, absolutePath) {
  if (relativePath !== ".codex/hooks.json") {
    return false;
  }

  const content = fs.readFileSync(absolutePath, "utf8");

  return !content.includes('"PreCompact"') ||
    !content.includes('"PostCompact"') ||
    !content.includes("node .codex/hooks/compact-guard.cjs");
}

function isRetiredManagedPath(relativePath) {
  return relativePath === ".codex/hooks/git-guard.js" || relativePath === ".codex/hooks/session-start.js";
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
    if (isRetiredManagedPath(relativePath) || hasPlatformHookDrift(relativePath, absolutePath)) {
      status = "drift / broken";
    } else if (actualHash === expectedHash) {
      status = hasManagedHookSurfaceDrift(relativePath, absolutePath) ? "drift / broken" : "match";
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
