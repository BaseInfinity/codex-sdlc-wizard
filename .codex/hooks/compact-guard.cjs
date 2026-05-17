#!/usr/bin/env node
const childProcess = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");

const input = fs.readFileSync(0, "utf8");
let payload = {};

if (input.trim() !== "") {
  try {
    payload = JSON.parse(input);
  } catch {
    process.exit(0);
  }
}

const eventName = String(payload.hook_event_name ?? payload.hookEventName ?? "");
if (eventName !== "PreCompact" && eventName !== "PostCompact") {
  process.exit(0);
}

const cwd = safeCwd(payload.cwd);
const trigger = String(payload.trigger ?? "unknown");
const status = gitStatus(cwd);
const dirtyText = status.available
  ? (status.count > 0
    ? ` dirty worktree: ${status.count} changed path(s).`
    : " worktree appears clean.")
  : " git status unavailable; inspect repository state if context is missing.";

const message = eventName === "PreCompact"
  ? `SDLC compact guard (${eventName}/${trigger}): preserve the active SDLC state before compaction: goal, plan status, files changed, proof/review status, blockers, and next command.${dirtyText}`
  : `SDLC compact guard (${eventName}/${trigger}): after compaction, reread AGENTS.md and GOALS.md/ROADMAP.md when present, inspect git status/log if context is missing, and continue from the preserved SDLC state.${dirtyText}`;

process.stdout.write(JSON.stringify({
  continue: true,
  suppressOutput: false,
  systemMessage: message,
}));

function safeCwd(value) {
  if (typeof value !== "string" || value.trim() === "") {
    return process.cwd();
  }

  return path.resolve(value);
}

function gitStatus(repoCwd) {
  const result = childProcess.spawnSync("git", ["-C", repoCwd, "status", "--porcelain"], {
    encoding: "utf8",
    stdio: ["ignore", "pipe", "ignore"],
  });

  if (result.status !== 0) {
    return { available: false, count: 0 };
  }

  const count = (result.stdout || "").split(/\r?\n/).filter(Boolean).length;
  return { available: true, count };
}
