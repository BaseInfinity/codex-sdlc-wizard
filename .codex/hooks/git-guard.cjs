#!/usr/bin/env node
const fs = require("node:fs");

const input = fs.readFileSync(0, "utf8");
let payload = {};

if (input.trim() !== "") {
  try {
    payload = JSON.parse(input);
  } catch {
    process.exit(0);
  }
}

const command = String(payload?.tool_input?.command ?? payload?.command ?? "");

function block(reason) {
  process.stdout.write(JSON.stringify({ decision: "block", reason }));
}

if (/^\s*(?:(?:\/usr\/bin|\/bin)\/)?(?:bash|zsh|sh|dash|ksh|fish)(?:\s+-[\w-]+)*\s*$/.test(command)) {
  block("SDLC GUARD: Do not bypass checks through an interactive shell. Run the exact command directly so commit/push hooks can inspect it.");
  process.exit(0);
}

if (/(^|\s)git(?:\s+-[^\s]+)*(?:\s+[^\s]+)*\s+commit(?:\s|$)/.test(command)) {
  block("TDD CHECK: Did you run tests before committing? Run your full test suite first. ALL tests must pass.");
  process.exit(0);
}

if (/(^|\s)git(?:\s+-[^\s]+)*(?:\s+[^\s]+)*\s+push(?:\s|$)/.test(command)) {
  block("REVIEW CHECK: Did you self-review your changes and run all tests before pushing?");
}
