#!/usr/bin/env node
"use strict";

const fs = require("node:fs");
const path = require("node:path");

function usage() {
  process.stderr.write("Usage: node lib/merge-hooks.cjs [--status] <target-hooks.json> <wizard-hooks.json>\n");
}

function readJson(filePath, label) {
  let content;
  try {
    content = fs.readFileSync(filePath, "utf8").replace(/^\uFEFF/, "");
  } catch (error) {
    throw new Error(`Failed to read ${label}: ${error.message}`);
  }

  let value;
  try {
    value = JSON.parse(content);
  } catch (error) {
    const invalid = new Error(`${label} is not valid JSON: ${error.message}`);
    invalid.code = "INVALID_HOOKS_DOCUMENT";
    throw invalid;
  }

  if (!value || typeof value !== "object" || Array.isArray(value)) {
    const invalid = new Error(`${label} must contain a JSON object`);
    invalid.code = "INVALID_HOOKS_DOCUMENT";
    throw invalid;
  }
  return value;
}

function validateHooksDocument(value, label) {
  if (value.hooks === undefined) return;
  if (!value.hooks || typeof value.hooks !== "object" || Array.isArray(value.hooks)) {
    const invalid = new Error(`${label}.hooks must be a JSON object`);
    invalid.code = "INVALID_HOOKS_DOCUMENT";
    throw invalid;
  }

  for (const [eventName, entries] of Object.entries(value.hooks)) {
    if (!Array.isArray(entries)) {
      const invalid = new Error(`${label}.hooks.${eventName} must be an array`);
      invalid.code = "INVALID_HOOKS_DOCUMENT";
      throw invalid;
    }
    for (const [entryIndex, entry] of entries.entries()) {
      if (!entry || typeof entry !== "object" || Array.isArray(entry) || !Array.isArray(entry.hooks)) {
        const invalid = new Error(`${label}.hooks.${eventName}[${entryIndex}] must contain a hooks array`);
        invalid.code = "INVALID_HOOKS_DOCUMENT";
        throw invalid;
      }
      for (const [hookIndex, hook] of entry.hooks.entries()) {
        if (!hook || typeof hook !== "object" || Array.isArray(hook)) {
          const invalid = new Error(`${label}.hooks.${eventName}[${entryIndex}].hooks[${hookIndex}] must be an object`);
          invalid.code = "INVALID_HOOKS_DOCUMENT";
          throw invalid;
        }
        if (hook.command !== undefined && typeof hook.command !== "string") {
          const invalid = new Error(`${label}.hooks.${eventName}[${entryIndex}].hooks[${hookIndex}].command must be a string`);
          invalid.code = "INVALID_HOOKS_DOCUMENT";
          throw invalid;
        }
      }
    }
  }
}

function directoryFoldsCase(directory) {
  if (process.platform === "win32") return true;
  if (process.platform !== "darwin") return false;

  const basename = path.basename(directory);
  const toggledBasename = basename.replace(/[A-Za-z]/, (character) =>
    character === character.toLowerCase() ? character.toUpperCase() : character.toLowerCase());
  if (toggledBasename === basename) return false;

  try {
    const alternate = path.join(path.dirname(directory), toggledBasename);
    return fs.realpathSync.native(directory) === fs.realpathSync.native(alternate);
  } catch (_error) {
    return false;
  }
}

function wizardCommandPath(command, foldPathCase) {
  if (typeof command !== "string") return "";
  const tokens = command.match(/"[^"\r\n]*"|'[^'\r\n]*'|`[^`\r\n]*`|[^\s]+/g) || [];
  const unquote = (token) => {
    const first = token[0];
    return token.length >= 2 && (first === '"' || first === "'" || first === "`") && token.at(-1) === first
      ? token.slice(1, -1)
      : token;
  };
  const normalized = tokens.map((token) => {
    const pathNormalized = unquote(token).replaceAll("\\", "/");
    return foldPathCase ? pathNormalized.toLowerCase() : pathNormalized;
  });
  const isWizardScript = (token) => /^(?:\.\/)?\.codex\/hooks\/(?:git-guard\.(?:cjs|js|ps1)|bash-guard\.sh|session-start\.(?:cjs|js|ps1|sh)|compact-guard\.cjs|sdlc-prompt-check\.sh)$/.test(token || "");

  if (isWizardScript(normalized[0])) return normalized[0];

  const executable = (normalized[0] || "").split("/").at(-1).toLowerCase();
  if (/^(?:node(?:\.exe)?|bash|sh)$/.test(executable)) {
    return isWizardScript(normalized[1]) ? normalized[1] : "";
  }
  if (/^(?:powershell|pwsh)(?:\.exe)?$/.test(executable)) {
    const fileFlag = normalized.findIndex((token, index) => index > 0 && token.toLowerCase() === "-file");
    const script = fileFlag === -1 ? normalized[1] : normalized[fileFlag + 1];
    return isWizardScript(script) ? script : "";
  }
  return "";
}

function isWizardCommand(command, foldPathCase) {
  return Boolean(wizardCommandPath(command, foldPathCase));
}

function clone(value) {
  return JSON.parse(JSON.stringify(value));
}

function mergeHooks(existing, wizard, foldPathCase) {
  const merged = clone(existing);
  merged.hooks = merged.hooks || {};

  for (const [eventName, entries] of Object.entries(merged.hooks)) {
    const keptEntries = [];
    for (const entry of entries) {
      const keptHooks = entry.hooks.filter((hook) => !isWizardCommand(hook.command, foldPathCase));
      if (keptHooks.length > 0) {
        keptEntries.push({ ...entry, hooks: keptHooks });
      }
    }
    if (keptEntries.length > 0) {
      merged.hooks[eventName] = keptEntries;
    } else {
      delete merged.hooks[eventName];
    }
  }

  for (const [eventName, entries] of Object.entries(wizard.hooks || {})) {
    merged.hooks[eventName] = [
      ...(merged.hooks[eventName] || []),
      ...clone(entries),
    ];
  }

  return merged;
}

function wizardSurface(value, foldPathCase) {
  const surface = {};
  for (const [eventName, entries] of Object.entries(value.hooks || {})) {
    const wizardEntries = [];
    for (const entry of entries) {
      const wizardHooks = entry.hooks.filter((hook) => isWizardCommand(hook.command, foldPathCase));
      if (wizardHooks.length > 0) {
        wizardEntries.push({ ...entry, hooks: wizardHooks });
      }
    }
    if (wizardEntries.length > 0) surface[eventName] = wizardEntries;
  }
  return surface;
}

function wizardSurfaceMatches(existing, wizard, foldPathCase) {
  const sortEvents = (hooks) => Object.fromEntries(
    Object.entries(hooks).sort(([left], [right]) => left.localeCompare(right)),
  );
  return JSON.stringify(sortEvents(wizardSurface(existing, foldPathCase))) ===
    JSON.stringify(sortEvents(wizard.hooks || {}));
}

function writeAtomically(filePath, value) {
  const directory = path.dirname(filePath);
  const mode = fs.existsSync(filePath)
    ? fs.statSync(filePath).mode & 0o777
    : 0o666 & ~process.umask();
  fs.mkdirSync(directory, { recursive: true });
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
  const args = process.argv.slice(2);
  const statusOnly = args[0] === "--status";
  if (statusOnly) args.shift();
  if (args.length !== 2) {
    usage();
    process.exitCode = 2;
    return;
  }

  const [targetPath, wizardPath] = args;
  const wizard = readJson(wizardPath, wizardPath);
  validateHooksDocument(wizard, wizardPath);

  const exists = fs.existsSync(targetPath);
  let existing = {};
  if (exists) {
    try {
      existing = readJson(targetPath, targetPath);
      validateHooksDocument(existing, targetPath);
    } catch (error) {
      if (statusOnly && error.code === "INVALID_HOOKS_DOCUMENT") {
        process.stdout.write("target-broken\n");
        return;
      }
      throw error;
    }
  }
  const foldPathCase = directoryFoldsCase(path.dirname(targetPath));
  const changed = !exists || !wizardSurfaceMatches(existing, wizard, foldPathCase);

  if (statusOnly) {
    process.stdout.write(changed ? "merge\n" : "match\n");
    return;
  }
  if (changed) writeAtomically(targetPath, mergeHooks(existing, wizard, foldPathCase));
}

if (require.main === module) {
  try {
    main();
  } catch (error) {
    process.stderr.write(`Error: ${error.message}\n`);
    process.exitCode = 1;
  }
}

module.exports = { directoryFoldsCase, isWizardCommand, validateHooksDocument, wizardCommandPath };
