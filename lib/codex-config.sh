#!/bin/bash
set -euo pipefail

MINIMUM_GPT56_CODEX_VERSION="${MINIMUM_GPT56_CODEX_VERSION:-0.144.0}"
MODEL_POLICY_SCHEMA_VERSION=2

require_gpt56_codex_version() {
    local version_output=""
    local parsed_version=""
    local codex_bin="${CODEX_SDLC_CODEX_BIN:-codex}"

    if ! command -v "$codex_bin" >/dev/null 2>&1; then
        echo "GPT-5.6 profiles require Codex CLI $MINIMUM_GPT56_CODEX_VERSION or newer (Codex CLI is not installed or is unavailable: $codex_bin)." >&2
        echo "Update with: npm install -g @openai/codex@latest" >&2
        return 1
    fi

    if ! version_output=$("$codex_bin" --version 2>&1); then
        echo "GPT-5.6 profiles require Codex CLI $MINIMUM_GPT56_CODEX_VERSION or newer (the configured Codex binary could not report its version: $codex_bin)." >&2
        echo "Update with: npm install -g @openai/codex@latest" >&2
        return 1
    fi

    parsed_version=$(CODEX_VERSION_OUTPUT="$version_output" node -e '
const match = (process.env.CODEX_VERSION_OUTPUT || "").match(/(?:^|\n)\s*(?:OpenAI\s+)?Codex(?:-CLI)?\s+v?(\d+)\.(\d+)\.(\d+)(-[0-9A-Za-z.-]+)?(?:\s|$)/i);
if (match) process.stdout.write(`${match.slice(1, 4).join(".")}${match[4] || ""}`);
')

    if [ -z "$parsed_version" ] || ! CODEX_VERSION="$parsed_version" MINIMUM_CODEX_VERSION="$MINIMUM_GPT56_CODEX_VERSION" node -e '
const [currentCore, prerelease = ""] = process.env.CODEX_VERSION.split(/-(.+)/, 2);
const current = currentCore.split(".").map(Number);
const minimum = process.env.MINIMUM_CODEX_VERSION.split(".").map(Number);
for (let index = 0; index < Math.max(current.length, minimum.length); index += 1) {
  const difference = (current[index] || 0) - (minimum[index] || 0);
  if (difference > 0) process.exit(0);
  if (difference < 0) process.exit(1);
}
if (prerelease) process.exit(1);
'; then
        local found_version="${parsed_version:-an unparseable version}"
        echo "GPT-5.6 profiles require Codex CLI $MINIMUM_GPT56_CODEX_VERSION or newer (found $found_version)." >&2
        echo "Update with: npm install -g @openai/codex@latest" >&2
        return 1
    fi
}

profile_model() {
    case "$1" in
        mixed) printf '%s\n' "gpt-5.6-terra" ;;
        maximum) printf '%s\n' "gpt-5.6-sol" ;;
        *) return 1 ;;
    esac
}

profile_reasoning() {
    case "$1" in
        mixed) printf '%s\n' "medium" ;;
        maximum) printf '%s\n' "high" ;;
        *) return 1 ;;
    esac
}

profile_review_model() {
    case "$1" in
        mixed) printf '%s\n' "gpt-5.6-sol" ;;
        maximum) printf '%s\n' "gpt-5.6-sol" ;;
        *) return 1 ;;
    esac
}

write_model_profile_metadata() {
    local output_path="$1"
    local model_profile="$2"

    case "$model_profile" in
        mixed|maximum) ;;
        *) return 1 ;;
    esac

    mkdir -p "$(dirname "$output_path")"
    CODEX_MODEL_PROFILE_PATH="$output_path" CODEX_MODEL_PROFILE="$model_profile" node <<'NODE'
const fs = require("fs");

const outputPath = process.env.CODEX_MODEL_PROFILE_PATH;
const selectedProfile = process.env.CODEX_MODEL_PROFILE;
const metadata = {
  schema_version: 2,
  selected_profile: selectedProfile,
  profiles: {
    mixed: {
      main_model: "gpt-5.6-terra",
      main_reasoning: "medium",
      review_model: "gpt-5.6-sol",
      review_reasoning: "high",
      review_effort_source: "explicit command override",
      review_command: "codex -c 'model_reasoning_effort=\"high\"' review",
      tradeoff: "Experimental explicit opt-in efficiency profile for measured, bounded work; not the normal quality-first driver."
    },
    maximum: {
      main_model: "gpt-5.6-sol",
      main_reasoning: "high",
      review_model: "gpt-5.6-sol",
      review_reasoning: "high",
      review_effort_source: "profile baseline",
      review_command: "codex review",
      tradeoff: "Default quality-first profile with Sol high as the standing root driver."
    }
  },
  policy: {
    high_confidence_threshold_percent: 95,
    default_profile: "maximum",
    default_driver: "gpt-5.6-sol",
    default_reasoning: "high",
    low_confidence_rule: "Research more first. If confidence stays below 95%, escalate the difficult slice or review to xhigh.",
    reasoning_effort_rule: "Use Sol high as the normal root driver for meaningful SDLC work. Escalate only difficult or high-risk slices to xhigh.",
    mixed_profile_rule: "Mixed is experimental and requires explicit opt-in. Preserve an existing explicit selection, but do not select it automatically.",
    review_effort_rule: "review_model selects the review model only. Mixed reviews must explicitly override model_reasoning_effort to high.",
    lightweight_rule: "Use Terra or Luna only for bounded support work when the task and verification boundary make the tradeoff explicit.",
    escalation_rule: "Max is single-task reasoning; Ultra is subagent-backed parallel work. Most tasks do not need either, and neither is a default wizard profile."
  }
};

fs.writeFileSync(outputPath, `${JSON.stringify(metadata, null, 2)}\n`);
NODE
}

model_profile_metadata_needs_refresh() {
    local profile_path="$1"
    local selected_profile="$2"

    [ -f "$profile_path" ] || return 0

    CODEX_MODEL_PROFILE_PATH="$profile_path" CODEX_MODEL_PROFILE="$selected_profile" node <<'NODE'
const fs = require("fs");

const profilePath = process.env.CODEX_MODEL_PROFILE_PATH;
const selectedProfile = process.env.CODEX_MODEL_PROFILE;
let metadata;

try {
  metadata = JSON.parse(fs.readFileSync(profilePath, "utf8"));
} catch {
  process.exit(0);
}

const mixed = metadata.profiles?.mixed || {};
const maximum = metadata.profiles?.maximum || {};
const needsRefresh =
  metadata.schema_version !== 2 ||
  metadata.selected_profile !== selectedProfile ||
  mixed.main_model !== "gpt-5.6-terra" ||
  mixed.main_reasoning !== "medium" ||
  mixed.review_model !== "gpt-5.6-sol" ||
  mixed.review_reasoning !== "high" ||
  mixed.review_effort_source !== "explicit command override" ||
  maximum.main_model !== "gpt-5.6-sol" ||
  maximum.main_reasoning !== "high" ||
  maximum.review_model !== "gpt-5.6-sol" ||
  maximum.review_reasoning !== "high" ||
  metadata.policy?.default_profile !== "maximum" ||
  metadata.policy?.default_driver !== "gpt-5.6-sol" ||
  metadata.policy?.default_reasoning !== "high";

process.exit(needsRefresh ? 0 : 1);
NODE
}

model_profile_metadata_is_legacy() {
    local profile_path="$1"

    [ -f "$profile_path" ] || return 1

    CODEX_MODEL_PROFILE_PATH="$profile_path" node <<'NODE'
const fs = require("fs");

let metadata;
try {
  metadata = JSON.parse(fs.readFileSync(process.env.CODEX_MODEL_PROFILE_PATH, "utf8"));
} catch {
  process.exit(1);
}

const models = [
  metadata.profiles?.mixed?.main_model,
  metadata.profiles?.mixed?.review_model,
  metadata.profiles?.maximum?.main_model,
  metadata.profiles?.maximum?.review_model
].filter(Boolean);
const hasLegacyModel = models.some((model) => /gpt-5\.(?:3|4|5)(?:\b|-)|legacy/i.test(model));
const schemaVersion = Number(metadata.schema_version || 0);

process.exit(schemaVersion < 2 || hasLegacyModel ? 0 : 1);
NODE
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
    model: "gpt-5.6-terra",
    model_reasoning_effort: "medium",
    review_model: "gpt-5.6-sol"
  },
  maximum: {
    model: "gpt-5.6-sol",
    model_reasoning_effort: "high",
    review_model: "gpt-5.6-sol"
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
        output.push("hooks = true");
        insertedHooks = true;
      }

      inFeatures = tableMatch[1].trim() === "features";
      if (inFeatures) {
        sawFeatures = true;
        insertedHooks = false;
      }

      output.push(line);

      if (inFeatures) {
        output.push("hooks = true");
        insertedHooks = true;
      }
      continue;
    }

    if (inFeatures && (isActiveKey(line, "codex_hooks") || isActiveKey(line, "hooks"))) {
      continue;
    }

    output.push(line);
  }

  if (inFeatures && !insertedHooks) {
    output.push("hooks = true");
  }

  if (!sawFeatures) {
    if (output.length > 0 && output[output.length - 1] !== "") {
      output.push("");
    }
    output.push("[features]");
    output.push("hooks = true");
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
    model: "gpt-5.6-terra",
    model_reasoning_effort: "medium",
    review_model: "gpt-5.6-sol"
  },
  maximum: {
    model: "gpt-5.6-sol",
    model_reasoning_effort: "high",
    review_model: "gpt-5.6-sol"
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
if (features.hooks !== "true") needsRepair = true;
if (Object.prototype.hasOwnProperty.call(features, "codex_hooks")) needsRepair = true;

process.exit(needsRepair ? 0 : 1);
NODE
}
