#!/usr/bin/env node

const { spawnSync } = require("node:child_process");
const path = require("node:path");

const scriptDir = path.resolve(__dirname, "..");
const rawArgs = process.argv.slice(2);

function printHelp() {
  process.stdout.write(`Usage: codex-sdlc-wizard [install|setup|check|update] [options]

Commands:
  install        Install AGENTS.md, hooks, and config into the current repo
  setup          Run adaptive setup.sh in the current repo
  check          Report managed-file drift for the current repo
  update         Apply selective updates for missing or drifted managed files

Options:
  --setup        Alias for the setup command
  --model-profile <mixed|maximum>
                Wizard-owned profile toggle. Use 'maximum' for setup/bootstrap
                work, then switch routine work back to 'mixed' for better
                speed/token efficiency with xhigh review.
  --help, -h     Show this help

Examples:
  npx codex-sdlc-wizard
  npx codex-sdlc-wizard setup --yes
  npx codex-sdlc-wizard setup --yes --model-profile maximum
  npx codex-sdlc-wizard check
  npx codex-sdlc-wizard update
  npx codex-sdlc-wizard --setup --yes --force
`);
}

let command = "install";
let scriptArgs = rawArgs;

if (rawArgs.includes("--help") || rawArgs.includes("-h")) {
  printHelp();
  process.exit(0);
}

if (rawArgs[0] === "setup" || rawArgs.includes("--setup")) {
  command = "setup";
  scriptArgs = rawArgs.filter((arg, index) => !(index === 0 && arg === "setup") && arg !== "--setup");
} else if (rawArgs[0] === "check") {
  command = "check";
  scriptArgs = rawArgs.slice(1);
} else if (rawArgs[0] === "update") {
  command = "update";
  scriptArgs = rawArgs.slice(1);
} else if (rawArgs[0] === "install") {
  scriptArgs = rawArgs.slice(1);
}

const scriptName = command === "setup"
  ? "setup.sh"
  : command === "check"
    ? "check.sh"
    : command === "update"
      ? "update.sh"
      : "install.sh";
const scriptPath = path.join(scriptDir, scriptName);
const result = spawnSync("bash", [scriptPath, ...scriptArgs], {
  cwd: process.cwd(),
  stdio: "inherit"
});

if (result.error) {
  process.stderr.write(`${result.error.message}\n`);
  process.exit(1);
}

process.exit(result.status === null ? 1 : result.status);
