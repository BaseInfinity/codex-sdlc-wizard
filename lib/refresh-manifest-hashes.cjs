#!/usr/bin/env node
"use strict";

const fs = require("node:fs");
const path = require("node:path");
const { inspectManagedFile } = require("./managed-file-hash.cjs");

function hash(filePath) {
  return inspectManagedFile(filePath).canonical_hash;
}

function writeTextAtomically(filePath, value) {
  const directory = path.dirname(filePath);
  const mode = fs.existsSync(filePath)
    ? fs.statSync(filePath).mode & 0o777
    : 0o666 & ~process.umask();
  const temporary = path.join(
    directory,
    `.${path.basename(filePath)}.${process.pid}.${Math.random().toString(16).slice(2)}.tmp`,
  );
  try {
    fs.writeFileSync(temporary, value, { flag: "wx", mode });
    fs.chmodSync(temporary, mode);
    fs.renameSync(temporary, filePath);
  } finally {
    try {
      fs.unlinkSync(temporary);
    } catch (error) {
      if (error.code !== "ENOENT") throw error;
    }
  }
}

function refreshProfileGuidance(manifest, touchedFiles, selectedProfile, baselineReasoning) {
  const agentsPath = "AGENTS.md";
  const previousProfile = manifest.model_profile?.selected_profile;
  const trackedHash = manifest.managed_files?.[agentsPath];
  if (
    typeof previousProfile !== "string" ||
    previousProfile === "" ||
    previousProfile === selectedProfile ||
    typeof trackedHash !== "string" ||
    !fs.existsSync(agentsPath) ||
    !inspectManagedFile(agentsPath, trackedHash).matches_expected
  ) {
    return false;
  }

  const original = fs.readFileSync(agentsPath, "utf8");
  const selectedProfilePattern = /^(- Selected profile: )(`?)[^`\r\n]+(`?)$/m;
  const baselineReasoningPattern = /^- Baseline reasoning: `[^`\r\n]+`$/m;
  if (!selectedProfilePattern.test(original) || !baselineReasoningPattern.test(original)) {
    return false;
  }
  let updated = original.replace(
    selectedProfilePattern,
    (_match, prefix, opening, closing) => `${prefix}${opening}${selectedProfile}${closing}`,
  );
  updated = updated.replace(
    baselineReasoningPattern,
    `- Baseline reasoning: \`${baselineReasoning}\``,
  );
  updated = updated.replace(
    /^(- Start work at the selected )`[^`\r\n]+`( baseline\..*)$/m,
    `$1\`${baselineReasoning}\`$2`,
  );

  if (updated === original) {
    return false;
  }
  writeTextAtomically(agentsPath, updated);
  touchedFiles.add(agentsPath);
  return true;
}

function synchronizeModelProfile(manifest, touchedFiles) {
  const profilePath = ".codex-sdlc/model-profile.json";
  if (!touchedFiles.has(profilePath) || !fs.existsSync(profilePath)) return false;

  const profile = JSON.parse(fs.readFileSync(profilePath, "utf8"));
  const selectedProfile = profile?.selected_profile;
  if (typeof selectedProfile !== "string" || selectedProfile === "") {
    throw new Error(`${profilePath}.selected_profile must contain a nonempty string`);
  }

  const next = {
    ...(manifest.model_profile || {}),
    selected_profile: selectedProfile,
  };
  const baselineReasoning = profile.profiles?.[selectedProfile]?.main_reasoning;
  if (typeof baselineReasoning !== "string" || baselineReasoning === "") {
    throw new Error(`${profilePath} does not define main_reasoning for ${selectedProfile}`);
  }
  next.baseline_reasoning = baselineReasoning;

  const guidanceChanged = refreshProfileGuidance(
    manifest,
    touchedFiles,
    selectedProfile,
    next.baseline_reasoning,
  );
  const changed = guidanceChanged || JSON.stringify(manifest.model_profile || {}) !== JSON.stringify(next);
  manifest.model_profile = next;
  return changed;
}

function writeAtomically(filePath, value) {
  const directory = path.dirname(filePath);
  const mode = fs.existsSync(filePath)
    ? fs.statSync(filePath).mode & 0o777
    : 0o666 & ~process.umask();
  const temporary = path.join(
    directory,
    `.${path.basename(filePath)}.${process.pid}.${Math.random().toString(16).slice(2)}.tmp`,
  );
  try {
    fs.writeFileSync(temporary, `${JSON.stringify(value, null, 2)}\n`, {
      flag: "wx",
      mode,
    });
    fs.chmodSync(temporary, mode);
    fs.renameSync(temporary, filePath);
  } finally {
    try {
      fs.unlinkSync(temporary);
    } catch (error) {
      if (error.code !== "ENOENT") throw error;
    }
  }
}

function main() {
  const [manifestPath, ...touchedFiles] = process.argv.slice(2);
  if (!manifestPath) {
    process.stderr.write("Usage: node lib/refresh-manifest-hashes.cjs <manifest.json> [touched-file ...]\n");
    process.exitCode = 2;
    return;
  }
  if (!fs.existsSync(manifestPath)) return;

  const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
  if (!manifest || typeof manifest !== "object" || Array.isArray(manifest)) {
    throw new Error(`${manifestPath} must contain a JSON object`);
  }
  const managed = manifest.managed_files;
  if (!managed || typeof managed !== "object" || Array.isArray(managed)) {
    throw new Error(`${manifestPath}.managed_files must contain a JSON object`);
  }

  const touchedFileSet = new Set(touchedFiles);
  let changed = synchronizeModelProfile(manifest, touchedFileSet);
  for (const filePath of touchedFileSet) {
    if (!fs.existsSync(filePath)) {
      if (Object.prototype.hasOwnProperty.call(managed, filePath)) {
        delete managed[filePath];
        changed = true;
      }
      continue;
    }
    const currentHash = hash(filePath);
    if (managed[filePath] !== currentHash) {
      managed[filePath] = currentHash;
      changed = true;
    }
  }
  if (changed) writeAtomically(manifestPath, manifest);
}

try {
  main();
} catch (error) {
  process.stderr.write(`Error: ${error.message}\n`);
  process.exitCode = 1;
}
