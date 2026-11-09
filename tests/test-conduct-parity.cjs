#!/usr/bin/env node

const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");

const BEGIN = Buffer.from("<!-- conduct-operating-model:begin -->", "utf8");
const END = Buffer.from("<!-- conduct-operating-model:end -->", "utf8");
const EXPECTED_LOCAL_BLOCK_SHA256 = "73e4fda9653cb3333b06518fe7b5124696a52b65bf9216578add64ec8ac7b431";
const repoRoot = path.resolve(__dirname, "..");
const localSkill = process.env.CONDUCT_SKILL_SOURCE ||
  path.join(repoRoot, "skill-sources", "conduct", "SKILL.template.md");

function occurrences(content, marker) {
  const offsets = [];
  let offset = 0;
  while (offset <= content.length - marker.length) {
    const found = content.indexOf(marker, offset);
    if (found === -1) break;
    offsets.push(found);
    offset = found + marker.length;
  }
  return offsets;
}

function extractMarkedBlock(file, label) {
  const content = fs.readFileSync(file);
  const begins = occurrences(content, BEGIN);
  const ends = occurrences(content, END);
  if (begins.length !== 1 || ends.length !== 1) {
    throw new Error(`${label} must contain exactly one begin marker and one end marker`);
  }
  if (ends[0] <= begins[0]) {
    throw new Error(`${label} has reversed operating-model markers`);
  }
  const blockEnd = ends[0] + END.length;
  if (content[blockEnd] !== 0x0a) {
    throw new Error(`${label} marked block must end with one LF byte`);
  }
  return content.subarray(begins[0], blockEnd + 1);
}

function digest(content) {
  return crypto.createHash("sha256").update(content).digest("hex");
}

try {
  const localBlock = extractMarkedBlock(localSkill, "Codex Conduct skill");
  if (digest(localBlock) !== EXPECTED_LOCAL_BLOCK_SHA256) {
    throw new Error("Codex Conduct skill does not contain the pinned 15-line, 11-row operating-model block");
  }

  const peerRoot = process.env.CLAUDE_SDLC_WIZARD_DIR;
  if (!peerRoot) {
    process.stdout.write("SKIP: CLAUDE_SDLC_WIZARD_DIR is unset; pinned local operating-model block verified\n");
    process.exit(0);
  }

  const peerSkill = path.join(peerRoot, "skills", "conduct", "SKILL.md");
  const peerBlock = extractMarkedBlock(peerSkill, "Claude Conduct skill");
  if (!localBlock.equals(peerBlock)) {
    throw new Error("Claude and Codex operating-model blocks differ at the raw-byte level");
  }
  process.stdout.write("PASS: Claude and Codex operating-model blocks match byte-for-byte, including final LF\n");
} catch (error) {
  process.stderr.write(`FAIL: ${error instanceof Error ? error.message : String(error)}\n`);
  process.exit(1);
}
