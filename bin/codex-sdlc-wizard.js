#!/usr/bin/env node

const { spawnSync } = require("node:child_process");
const path = require("node:path");

const scriptDir = path.resolve(__dirname, "..");
const rawArgs = process.argv.slice(2);

function printHelp() {
  process.stdout.write(`Usage: codex-sdlc-wizard [install|setup] [options]

Commands:
  install        Install AGENTS.md, hooks, and config into the current repo
  setup          Run adaptive setup.sh in the current repo

Options:
  --setup        Alias for the setup command
  --model-profile <mixed|maximum>
                Wizard-owned profile toggle. 'mixed' favors speed/token
                efficiency with xhigh review; 'maximum' favors stability.
  --help, -h     Show this help

Examples:
  npx codex-sdlc-wizard
  npx codex-sdlc-wizard setup --yes
  npx codex-sdlc-wizard setup --yes --model-profile maximum
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
} else if (rawArgs[0] === "install") {
  scriptArgs = rawArgs.slice(1);
}

const scriptPath = path.join(scriptDir, command === "setup" ? "setup.sh" : "install.sh");
const result = spawnSync("bash", [scriptPath, ...scriptArgs], {
  cwd: process.cwd(),
  stdio: "inherit"
});

if (result.error) {
  process.stderr.write(`${result.error.message}\n`);
  process.exit(1);
}

process.exit(result.status === null ? 1 : result.status);
