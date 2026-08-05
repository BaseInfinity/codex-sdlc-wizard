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

node - "$SCRIPT_DIR/lib/merge-hooks.cjs" "$SCRIPT_DIR/lib/managed-file-hash.cjs" <<'NODE'
const fs = require("fs");
const os = require("os");
const path = require("path");
const { directoryFoldsCase, validateHooksDocument, wizardCommandPath } = require(process.argv[2]);
const { inspectManagedFile } = require(process.argv[3]);

const cwd = process.cwd();
const manifestPath = path.join(cwd, ".codex-sdlc", "manifest.json");

function printJson(value) {
  process.stdout.write(`${JSON.stringify(value, null, 2)}\n`);
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

function parseTomlSectionKey(rawValue) {
  const value = rawValue.trim();
  if (value.startsWith("'") && value.endsWith("'")) {
    return value.slice(1, -1);
  }
  if (value.startsWith('"') && value.endsWith('"')) {
    try {
      return JSON.parse(value);
    } catch (_error) {
      return "";
    }
  }
  return value;
}

function normalizedHookStatePath(value, foldCase) {
  const normalized = value.replace(/\\/g, "/").replace(/\/+$/, "");
  return foldCase ? normalized.toLowerCase() : normalized;
}

function disabledManagedHookEvents() {
  const codexHome = process.env.CODEX_HOME || path.join(os.homedir(), ".codex");
  const configPath = path.join(codexHome, "config.toml");
  const hooksPath = path.resolve(cwd, ".codex", "hooks.json");
  if (!fs.existsSync(configPath) || !fs.existsSync(hooksPath)) {
    return [];
  }

  const foldCase = directoryFoldsCase(path.dirname(hooksPath));
  const expectedPath = normalizedHookStatePath(hooksPath, foldCase);
  const eventNames = {
    pre_tool_use: "PreToolUse",
    session_start: "SessionStart",
    pre_compact: "PreCompact",
    post_compact: "PostCompact"
  };
  const disabled = new Map();
  let currentState = null;

  for (const line of fs.readFileSync(configPath, "utf8").replace(/^\uFEFF/, "").split(/\r?\n/)) {
    const section = line.match(/^\s*\[hooks\.state\.(.+)\]\s*$/);
    if (section) {
      const stateKey = parseTomlSectionKey(section[1]);
      const match = stateKey.match(/^(.*):([a-z_]+):(\d+):(\d+)$/i);
      currentState = match && normalizedHookStatePath(match[1], foldCase) === expectedPath
        ? { event: eventNames[match[2].toLowerCase()] || match[2] }
        : null;
      continue;
    }

    if (/^\s*\[/.test(line)) {
      currentState = null;
      continue;
    }

    if (currentState && /^\s*enabled\s*=\s*false\s*(?:#.*)?$/i.test(line)) {
      disabled.set(currentState.event, { event: currentState.event });
    }
  }

  return [...disabled.values()];
}

const disabledHookEvents = disabledManagedHookEvents();

function resolvedModelPolicy() {
  const profilePath = path.join(cwd, ".codex-sdlc", "model-profile.json");
  if (!fs.existsSync(profilePath)) {
    return null;
  }

  try {
    const metadata = JSON.parse(fs.readFileSync(profilePath, "utf8"));
    const selectedProfile = metadata.selected_profile || manifest.model_profile?.selected_profile;
    const selected = metadata.profiles?.[selectedProfile];
    if (!selected) {
      return null;
    }

    const allowedModels = new Set();
    for (const profile of Object.values(metadata.profiles || {})) {
      if (typeof profile?.main_model === "string") allowedModels.add(profile.main_model.toLowerCase());
      if (typeof profile?.review_model === "string") allowedModels.add(profile.review_model.toLowerCase());
    }
    if (typeof metadata.policy?.default_driver === "string") {
      allowedModels.add(metadata.policy.default_driver.toLowerCase());
    }

    return {
      selected_profile: selectedProfile,
      main_model: selected.main_model || "",
      main_reasoning: selected.main_reasoning || manifest.model_profile?.baseline_reasoning || "",
      allowed_models: allowedModels
    };
  } catch (_error) {
    return null;
  }
}

const modelPolicy = resolvedModelPolicy();

function customizedDocumentPolicyWarnings(relativePath, absolutePath, status) {
  if (status !== "customized" || !relativePath.toLowerCase().endsWith(".md") || !modelPolicy) {
    return [];
  }

  const content = fs.readFileSync(absolutePath, "utf8");
  const warnings = [];
  const modelReferences = new Set(content.match(/\bgpt-[a-z0-9][a-z0-9.-]*\b/gi) || []);
  for (const modelReference of modelReferences) {
    if (!modelPolicy.allowed_models.has(modelReference.toLowerCase())) {
      warnings.push({
        path: relativePath,
        kind: "stale_model_reference",
        stale_value: modelReference,
        expected_main_model: modelPolicy.main_model,
        message: "Customized managed document references a model outside the resolved profile metadata; review manually"
      });
    }
  }

  const reasoningClaims = new Set();
  const effort = "(low|medium|high|xhigh)";
  const defaultRole = "(?:default|baseline|normal(?: standing)? root driver|standing root driver)";
  const patterns = [
    new RegExp(`\\b${effort}\\b[^.\\r\\n]{0,80}\\b(?:is|as)\\s+(?:the\\s+)?${defaultRole}\\b`, "i"),
    new RegExp(`\\b${defaultRole}\\b[^.\\r\\n]{0,80}\\b${effort}\\b`, "i"),
    new RegExp(`\\b${effort}\\b[^.\\r\\n]{0,40}\\bby default\\b`, "i")
  ];
  for (const line of content.split(/\r?\n/)) {
    for (const pattern of patterns) {
      const match = line.match(pattern);
      if (match) {
        const claim = match.slice(1).find((value) => /^(?:low|medium|high|xhigh)$/i.test(value || ""));
        if (claim) reasoningClaims.add(claim.toLowerCase());
        break;
      }
    }
  }
  for (const claim of reasoningClaims) {
    if (modelPolicy.main_reasoning && claim !== modelPolicy.main_reasoning.toLowerCase()) {
      warnings.push({
        path: relativePath,
        kind: "stale_default_reasoning",
        stale_value: claim,
        expected_main_reasoning: modelPolicy.main_reasoning,
        selected_profile: modelPolicy.selected_profile,
        message: "Customized managed document claims a default reasoning effort that conflicts with the resolved profile; review manually"
      });
    }
  }

  return warnings;
}

const managedFiles = {};
const policyWarnings = [];
const summary = {
  match: 0,
  missing: 0,
  customized: 0,
  warning: 0,
  policy_warnings: 0,
  "drift / broken": 0
};

for (const [relativePath, expectedHash] of Object.entries(manifest.managed_files || {})) {
  if (!expectedHash) {
    continue;
  }

  const absolutePath = path.join(cwd, relativePath);
  let actualHash = "";
  let canonicalHash = "";
  let hashMode = "";
  let carriageReturns = 0;
  let manifestHashMigration = false;
  let contentStatus;
  let status;

  if (!fs.existsSync(absolutePath)) {
    status = "missing";
  } else {
    const hashInfo = inspectManagedFile(absolutePath, expectedHash);
    actualHash = hashInfo.raw_hash;
    canonicalHash = hashInfo.canonical_hash;
    hashMode = hashInfo.hash_mode;
    carriageReturns = hashInfo.carriage_returns;
    manifestHashMigration = hashInfo.manifest_hash_migration;
    if (hashMode === "raw" && relativePath.toLowerCase().endsWith(".sh") && carriageReturns > 0) {
      status = "drift / broken";
    } else if (isRetiredManagedPath(relativePath) || hasPlatformHookDrift(relativePath, absolutePath)) {
      status = "drift / broken";
    } else if (hashInfo.matches_expected) {
      status = hasManagedHookSurfaceDrift(relativePath, absolutePath) ? "drift / broken" : "match";
    } else {
      status = "customized";
    }
  }

  contentStatus = status;
  if (relativePath === ".codex/hooks.json" && status === "match" && disabledHookEvents.length > 0) {
    status = "warning";
  }

  const documentPolicyWarnings = fs.existsSync(absolutePath)
    ? customizedDocumentPolicyWarnings(relativePath, absolutePath, status)
    : [];
  policyWarnings.push(...documentPolicyWarnings);

  managedFiles[relativePath] = {
    status,
    ...(status === "warning" ? {
      content_status: contentStatus,
      warning: "Codex user hook state explicitly disables one or more managed events",
      disabled_events: disabledHookEvents
    } : {}),
    ...(documentPolicyWarnings.length > 0 ? { policy_warnings: documentPolicyWarnings } : {}),
    expected_hash: expectedHash,
    actual_hash: actualHash,
    canonical_hash: canonicalHash,
    hash_mode: hashMode,
    carriage_returns: carriageReturns,
    ...(manifestHashMigration ? { manifest_hash_migration: true } : {})
  };

  summary[status] += 1;
  summary.policy_warnings += documentPolicyWarnings.length;
}

printJson({
  repo_state: "initialized",
  adapter_version: manifest.adapter_version || "",
  scan: manifest.scan || {},
  summary,
  hook_activation: {
    status: disabledHookEvents.length > 0 ? "warning" : "no_disabled_state_detected",
    disabled_events: disabledHookEvents
  },
  policy_warnings: policyWarnings,
  managed_files: managedFiles
});
NODE
