#!/usr/bin/env node
"use strict";

const fs = require("node:fs");
const path = require("node:path");

const RULE = ".codex/hooks/*.sh text eol=lf";

function hasRule(content) {
  return content
    .replace(/^\uFEFF/, "")
    .split(/\r\n|\r|\n/)
    .some((line) => /^\s*\.codex\/hooks\/\*\.sh\s+text\s+eol=lf\s*(?:#.*)?$/.test(line));
}

function preferredEol(content) {
  const crlfCount = (content.match(/\r\n/g) || []).length;
  const lfCount = (content.replace(/\r\n/g, "").match(/\n/g) || []).length;
  return crlfCount > lfCount ? "\r\n" : "\n";
}

function mergedContent(content) {
  if (hasRule(content)) return content;
  const eol = preferredEol(content);
  if (!content) return `${RULE}${eol}`;
  return `${content}${/[\r\n]$/.test(content) ? "" : eol}${RULE}${eol}`;
}

function writeAtomically(filePath, content) {
  const directory = path.dirname(filePath);
  fs.mkdirSync(directory, { recursive: true });
  const mode = fs.existsSync(filePath)
    ? fs.statSync(filePath).mode & 0o777
    : 0o666 & ~process.umask();
  const temporary = path.join(
    directory,
    `.${path.basename(filePath)}.${process.pid}.${Math.random().toString(16).slice(2)}.tmp`,
  );
  try {
    fs.writeFileSync(temporary, content, { flag: "wx", mode });
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
  const filePath = path.resolve(statusOnly ? args[1] || ".gitattributes" : args[0] || ".gitattributes");
  const content = fs.existsSync(filePath) ? fs.readFileSync(filePath, "utf8") : "";
  if (statusOnly) {
    process.stdout.write(hasRule(content) ? "match\n" : "merge\n");
    return;
  }
  const next = mergedContent(content);
  if (next !== content) writeAtomically(filePath, next);
}

module.exports = { RULE, hasRule, mergedContent };

if (require.main === module) {
  try {
    main();
  } catch (error) {
    process.stderr.write(`Error: ${error.message}\n`);
    process.exitCode = 1;
  }
}
