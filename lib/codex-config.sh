#!/bin/bash
set -euo pipefail

profile_model() {
    case "$1" in
        mixed) printf '%s\n' "gpt-5.4-mini" ;;
        maximum) printf '%s\n' "gpt-5.4" ;;
        *) return 1 ;;
    esac
}

profile_reasoning() {
    case "$1" in
        mixed) printf '%s\n' "xhigh" ;;
        maximum) printf '%s\n' "xhigh" ;;
        *) return 1 ;;
    esac
}

profile_review_model() {
    case "$1" in
        mixed) printf '%s\n' "gpt-5.4" ;;
        maximum) printf '%s\n' "" ;;
        *) return 1 ;;
    esac
}

merge_codex_config_profile() {
    local config_path="$1"
    local model_profile="$2"

    mkdir -p "$(dirname "$config_path")"

    CODEX_CONFIG_PATH="$config_path" CODEX_MODEL_PROFILE="$model_profile" node <<'NODE'
const fs = require("fs");

const configPath = process.env.CODEX_CONFIG_PATH;
const profile = process.env.CODEX_MODEL_PROFILE;

const profiles = {
  mixed: {
    model: "gpt-5.4-mini",
    model_reasoning_effort: "xhigh",
    review_model: "gpt-5.4"
  },
  maximum: {
    model: "gpt-5.4",
    model_reasoning_effort: "xhigh",
    review_model: null
  }
};

const desired = profiles[profile];
if (!desired) {
  throw new Error(`Unsupported model profile: ${profile}`);
}

const original = fs.existsSync(configPath)
  ? fs.readFileSync(configPath, "utf8").replace(/\r\n/g, "\n").replace(/\r/g, "\n")
  : "";

let lines = original.length > 0 ? original.split("\n") : [];
if (lines.length > 0 && lines[lines.length - 1] === "") {
  lines.pop();
}

const isTableHeader = (line) => /^\s*\[[^\]]+\]\s*(#.*)?$/.test(line);
const isActiveKey = (line, key) => new RegExp(`^\\s*${key}\\s*=`).test(line);

function stripTopLevelProfileKeys(inputLines) {
  let tableName = null;
  const output = [];

  for (const line of inputLines) {
    const tableMatch = line.match(/^\s*\[([^\]]+)\]\s*(#.*)?$/);
    if (tableMatch) {
      tableName = tableMatch[1].trim();
      output.push(line);
      continue;
    }

    if (
      tableName === null &&
      (isActiveKey(line, "model") ||
        isActiveKey(line, "model_reasoning_effort") ||
        isActiveKey(line, "review_model"))
    ) {
      continue;
    }

    output.push(line);
  }

  return output;
}

function insertTopLevelProfileKeys(inputLines) {
  const profileLines = [
    `model = "${desired.model}"`,
    `model_reasoning_effort = "${desired.model_reasoning_effort}"`
  ];

  if (desired.review_model) {
    profileLines.push(`review_model = "${desired.review_model}"`);
  }

  const firstTableIndex = inputLines.findIndex(isTableHeader);
  const insertAt = firstTableIndex === -1 ? inputLines.length : firstTableIndex;
  const before = inputLines.slice(0, insertAt);
  const after = inputLines.slice(insertAt);
  const merged = [...before];

  if (merged.length > 0 && merged[merged.length - 1] !== "") {
    merged.push("");
  }

  merged.push(...profileLines);

  if (after.length > 0) {
    merged.push("");
    merged.push(...after);
  }

  return merged;
}

function ensureFeatureHooks(inputLines) {
  const output = [];
  let inFeatures = false;
  let sawFeatures = false;
  let insertedHooks = false;

  for (const line of inputLines) {
    const tableMatch = line.match(/^\s*\[([^\]]+)\]\s*(#.*)?$/);
    if (tableMatch) {
      if (inFeatures && !insertedHooks) {
        output.push("codex_hooks = true");
        insertedHooks = true;
      }

      inFeatures = tableMatch[1].trim() === "features";
      if (inFeatures) {
        sawFeatures = true;
        insertedHooks = false;
      }

      output.push(line);

      if (inFeatures) {
        output.push("codex_hooks = true");
        insertedHooks = true;
      }
      continue;
    }

    if (inFeatures && isActiveKey(line, "codex_hooks")) {
      continue;
    }

    output.push(line);
  }

  if (inFeatures && !insertedHooks) {
    output.push("codex_hooks = true");
  }

  if (!sawFeatures) {
    if (output.length > 0 && output[output.length - 1] !== "") {
      output.push("");
    }
    output.push("[features]");
    output.push("codex_hooks = true");
  }

  return output;
}

lines = stripTopLevelProfileKeys(lines);
lines = insertTopLevelProfileKeys(lines);
lines = ensureFeatureHooks(lines);

fs.writeFileSync(configPath, `${lines.join("\n")}\n`);
NODE
}

codex_config_needs_profile_repair() {
    local config_path="$1"
    local model_profile="$2"

    [ -f "$config_path" ] || return 0

    CODEX_CONFIG_PATH="$config_path" CODEX_MODEL_PROFILE="$model_profile" node <<'NODE'
const fs = require("fs");

const configPath = process.env.CODEX_CONFIG_PATH;
const profile = process.env.CODEX_MODEL_PROFILE;
const profiles = {
  mixed: {
    model: "gpt-5.4-mini",
    model_reasoning_effort: "xhigh",
    review_model: "gpt-5.4"
  },
  maximum: {
    model: "gpt-5.4",
    model_reasoning_effort: "xhigh",
    review_model: null
  }
};

const desired = profiles[profile];
if (!desired) {
  process.exit(0);
}

const content = fs.readFileSync(configPath, "utf8").replace(/\r\n/g, "\n").replace(/\r/g, "\n");
let tableName = null;
const top = {};
const features = {};

for (const line of content.split("\n")) {
  const tableMatch = line.match(/^\s*\[([^\]]+)\]\s*(#.*)?$/);
  if (tableMatch) {
    tableName = tableMatch[1].trim();
    continue;
  }

  if (/^\s*#/.test(line)) {
    continue;
  }

  const keyMatch = line.match(/^\s*([A-Za-z0-9_.-]+)\s*=\s*(.+?)\s*(#.*)?$/);
  if (!keyMatch) {
    continue;
  }

  const key = keyMatch[1];
  let value = keyMatch[2].trim();
  value = value.replace(/^"|"$/g, "");

  if (tableName === null) {
    top[key] = value;
  } else if (tableName === "features") {
    features[key] = value;
  }
}

let needsRepair = false;
if (top.model !== desired.model) needsRepair = true;
if (top.model_reasoning_effort !== desired.model_reasoning_effort) needsRepair = true;
if (desired.review_model) {
  if (top.review_model !== desired.review_model) needsRepair = true;
} else if (Object.prototype.hasOwnProperty.call(top, "review_model")) {
  needsRepair = true;
}
if (features.codex_hooks !== "true") needsRepair = true;

process.exit(needsRepair ? 0 : 1);
NODE
}
