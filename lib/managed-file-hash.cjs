#!/usr/bin/env node
"use strict";

const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");

const CANONICAL_TEXT_EXTENSIONS = new Set([
  ".cjs",
  ".js",
  ".json",
  ".md",
  ".ps1",
  ".toml",
  ".txt",
  ".yaml",
  ".yml",
]);

function sha256(buffer) {
  return `sha256:${crypto.createHash("sha256").update(buffer).digest("hex")}`;
}

function isCanonicalTextManagedPath(filePath) {
  const extension = path.extname(filePath).toLowerCase();
  return extension !== ".sh" && CANONICAL_TEXT_EXTENSIONS.has(extension);
}

function normalizeTextEol(buffer) {
  return Buffer.from(buffer.toString("utf8").replace(/\r\n|\r/g, "\n"), "utf8");
}

function eolRepresentationHashes(canonicalBuffer) {
  const canonicalText = canonicalBuffer.toString("utf8");
  return new Set([
    sha256(canonicalBuffer),
    sha256(Buffer.from(canonicalText.replace(/\n/g, "\r\n"), "utf8")),
    sha256(Buffer.from(canonicalText.replace(/\n/g, "\r"), "utf8")),
  ]);
}

function inspectManagedFile(filePath, expectedHash = "") {
  const rawBuffer = fs.readFileSync(filePath);
  const rawHash = sha256(rawBuffer);
  const canonicalText = isCanonicalTextManagedPath(filePath);
  const canonicalBuffer = canonicalText ? normalizeTextEol(rawBuffer) : rawBuffer;
  const canonicalHash = sha256(canonicalBuffer);
  const acceptedHashes = canonicalText
    ? eolRepresentationHashes(canonicalBuffer)
    : new Set([rawHash]);
  acceptedHashes.add(rawHash);

  return {
    raw_hash: rawHash,
    canonical_hash: canonicalHash,
    hash_mode: canonicalText ? "canonical-text" : "raw",
    carriage_returns: rawBuffer.reduce((count, byte) => count + (byte === 0x0d ? 1 : 0), 0),
    matches_expected: Boolean(expectedHash) && acceptedHashes.has(expectedHash),
    manifest_hash_migration: Boolean(expectedHash) && acceptedHashes.has(expectedHash) && expectedHash !== canonicalHash,
  };
}

function writeJsonAtomically(filePath, value) {
  const directory = path.dirname(filePath);
  const mode = fs.statSync(filePath).mode & 0o777;
  const temporary = path.join(
    directory,
    `.${path.basename(filePath)}.${process.pid}.${Math.random().toString(16).slice(2)}.tmp`,
  );
  try {
    fs.writeFileSync(temporary, `${JSON.stringify(value, null, 2)}\n`, { flag: "wx", mode });
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

function migrateManifestHashes(manifestPath) {
  const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
  const root = path.dirname(path.dirname(path.resolve(manifestPath)));
  const migrated = [];

  for (const [relativePath, expectedHash] of Object.entries(manifest.managed_files || {})) {
    const absolutePath = path.join(root, relativePath);
    if (!expectedHash || !fs.existsSync(absolutePath)) continue;
    const info = inspectManagedFile(absolutePath, expectedHash);
    if (!info.manifest_hash_migration) continue;
    manifest.managed_files[relativePath] = info.canonical_hash;
    migrated.push(relativePath);
  }

  if (migrated.length > 0) writeJsonAtomically(manifestPath, manifest);
  return migrated;
}

function main() {
  const [command, filePath, expectedHash = ""] = process.argv.slice(2);
  if (!command || !filePath) {
    process.stderr.write("Usage: managed-file-hash.cjs <hash|raw|inspect|migrate-manifest> <path> [expected-hash]\n");
    process.exitCode = 2;
    return;
  }

  if (command === "migrate-manifest") {
    process.stdout.write(`${migrateManifestHashes(filePath).join("\n")}${"\n"}`);
    return;
  }

  const info = inspectManagedFile(filePath, expectedHash);
  if (command === "hash") process.stdout.write(info.canonical_hash);
  else if (command === "raw") process.stdout.write(info.raw_hash);
  else if (command === "inspect") process.stdout.write(`${JSON.stringify(info)}\n`);
  else {
    process.stderr.write(`Unknown command: ${command}\n`);
    process.exitCode = 2;
  }
}

module.exports = {
  inspectManagedFile,
  isCanonicalTextManagedPath,
  migrateManifestHashes,
  normalizeTextEol,
};

if (require.main === module) {
  try {
    main();
  } catch (error) {
    process.stderr.write(`Error: ${error.message}\n`);
    process.exitCode = 1;
  }
}
