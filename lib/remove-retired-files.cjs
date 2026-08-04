#!/usr/bin/env node
"use strict";

const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
const { directoryFoldsCase } = require("./merge-hooks.cjs");

const checkOnly = process.argv.includes("--status");
const manifestPath = ".codex-sdlc/manifest.json";
const retiredFiles = [
  {
    path: ".codex/hooks/sdlc-prompt-check.sh",
    hashes: new Set([
      "84ba0abfdf7b55849dd925a726c5de77d713d83efd9c50b19dfa06ff38f28112",
      "0e395ce56dae7c017cd761eb669cb9302f251abe8493b35f34c5e00effc50258",
    ]),
  },
];

function inspectRetiredFile(entry) {
  let stat;
  try {
    stat = fs.lstatSync(entry.path);
  } catch (error) {
    if (error.code === "ENOENT") return "missing";
    throw error;
  }

  if (stat.isSymbolicLink()) {
    try {
      fs.statSync(entry.path);
    } catch (error) {
      if (error.code === "ENOENT") return "missing";
      throw error;
    }
    return "customized";
  }
  if (!stat.isFile()) return "customized";
  const hash = crypto.createHash("sha256").update(fs.readFileSync(entry.path)).digest("hex");
  return entry.hashes.has(hash) ? "wizard-managed" : "customized";
}

function commandTokens(command, foldPathCase) {
  const tokens = command.match(/"[^"\r\n]*"|'[^'\r\n]*'|`[^`\r\n]*`|[^\s]+/g) || [];
  return tokens.map((token) => {
    const first = token[0];
    const unquoted = token.length >= 2
      && (first === '"' || first === "'" || first === "`")
      && token.at(-1) === first
      ? token.slice(1, -1)
      : token;
    const normalized = unquoted.replaceAll("\\", "/");
    return foldPathCase ? normalized.toLowerCase() : normalized;
  });
}

function isStandardWizardInvocation(tokens, normalizedPath) {
  const isRetiredPath = (token) => token === normalizedPath || token === `./${normalizedPath}`;
  if (isRetiredPath(tokens[0])) return true;

  const executable = (tokens[0] || "").split("/").at(-1).toLowerCase();
  return /^(?:bash|sh)$/.test(executable) && isRetiredPath(tokens[1]);
}

function hasRetainedHookReference(retiredPath) {
  const hooksPath = ".codex/hooks.json";
  if (!fs.existsSync(hooksPath)) return false;

  let hooks;
  try {
    hooks = JSON.parse(fs.readFileSync(hooksPath, "utf8").replace(/^\uFEFF/, ""));
  } catch (_error) {
    return false;
  }

  const commands = [];
  const visit = (value) => {
    if (!value || typeof value !== "object") return;
    if (typeof value.command === "string") commands.push(value.command);
    for (const child of Object.values(value)) visit(child);
  };
  visit(hooks);

  const foldPathCase = directoryFoldsCase(path.dirname(hooksPath));
  const pathNormalized = retiredPath.replaceAll("\\", "/");
  const normalizedPath = foldPathCase ? pathNormalized.toLowerCase() : pathNormalized;
  const retiredScriptName = path.posix.basename(pathNormalized).toLowerCase();
  return commands.some((command) => {
    const tokens = commandTokens(command, foldPathCase);
    const referencesPath = tokens.some((token) => token.toLowerCase().includes(retiredScriptName));
    return referencesPath && !isStandardWizardInvocation(tokens, normalizedPath);
  });
}

function readManifest() {
  if (!fs.existsSync(manifestPath)) return null;
  const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
  if (!manifest || typeof manifest !== "object" || Array.isArray(manifest)) {
    throw new Error(`${manifestPath} must contain a JSON object`);
  }
  if (!manifest.managed_files || typeof manifest.managed_files !== "object" || Array.isArray(manifest.managed_files)) {
    throw new Error(`${manifestPath}.managed_files must contain a JSON object`);
  }
  return manifest;
}

function writeManifest(manifest) {
  const temporary = path.join(
    path.dirname(manifestPath),
    `.${path.basename(manifestPath)}.${process.pid}.${Math.random().toString(16).slice(2)}.tmp`,
  );
  const mode = fs.statSync(manifestPath).mode & 0o777;
  try {
    fs.writeFileSync(temporary, `${JSON.stringify(manifest, null, 2)}\n`, { flag: "wx", mode });
    fs.chmodSync(temporary, mode);
    fs.renameSync(temporary, manifestPath);
  } finally {
    try {
      fs.unlinkSync(temporary);
    } catch (error) {
      if (error.code !== "ENOENT") throw error;
    }
  }
}

const manifest = readManifest();

for (const entry of retiredFiles) {
  const fileStatus = inspectRetiredFile(entry);
  const retainedHookReference = hasRetainedHookReference(entry.path);
  const manifestTracked = Boolean(
    manifest && Object.prototype.hasOwnProperty.call(manifest.managed_files, entry.path),
  );
  const status = retainedHookReference
    ? fileStatus === "missing"
      ? "retained-missing"
      : manifestTracked
        ? "tracked-retired"
        : "retained-customized"
    : fileStatus === "wizard-managed"
      ? "wizard-managed"
      : manifestTracked
        ? "tracked-retired"
        : fileStatus;
  if (checkOnly) {
    process.stdout.write(`${entry.path}\t${status}\n`);
    continue;
  }

  if (retainedHookReference && fileStatus === "missing") {
    throw new Error(`Retained hook references missing retired file: ${entry.path}`);
  } else if (fileStatus === "wizard-managed" && !retainedHookReference) {
    fs.unlinkSync(entry.path);
    process.stdout.write(`Removed retired wizard file: ${entry.path}\n`);
  } else if (retainedHookReference) {
    process.stdout.write(`Preserved retired file still referenced by a retained hook: ${entry.path}\n`);
  } else if (fileStatus === "customized") {
    process.stdout.write(`Preserved customized retired file: ${entry.path}\n`);
  }
  if (manifestTracked) {
    delete manifest.managed_files[entry.path];
    writeManifest(manifest);
    process.stdout.write(`Removed retired manifest ownership: ${entry.path}\n`);
  }
}
