#!/usr/bin/env node

const { spawnSync } = require("node:child_process");
const path = require("node:path");

const scriptDir = path.resolve(__dirname, "..");
const rawArgs = process.argv.slice(2);
const codexCommand = process.env.CODEX_SDLC_CODEX_BIN || "codex";
const interactiveSessionPrompt = [
  "$setup-wizard",
  "This repo was just bootstrapped by codex-sdlc-wizard.",
  "Continue setup inside Codex: scan the repo, ask only unresolved questions, preserve intentional existing docs, generate or refresh repo-specific SDLC docs, verify the result, and finish setup.",
  "Use xhigh reasoning for setup."
].join("\n\n");

function printHelp() {
  process.stdout.write(`Usage: codex-sdlc-wizard [setup|check|update|install] [options]

Commands:
  setup          Adaptive setup. Interactive default bootstraps then launches Codex for live setup
  check          Report managed-file drift for the current repo
  update         Apply selective updates for missing or drifted managed files
  install        Advanced escape hatch: run install.sh without adaptive setup

Default behavior: bootstrap the current repo, then hand off into a live Codex setup session.
Automation/non-interactive behavior: use setup --yes to stay on the shell path.
Bootstrap/setup recommendation: maximum.
Routine work after bootstrap: mixed.

Options:
  --model-profile <mixed|maximum>
                Wizard-owned profile toggle. Use 'maximum' for setup/bootstrap
                work, then switch routine work back to 'mixed' for better
                speed/token efficiency with xhigh review.
  --help, -h     Show this help

Examples:
  npx codex-sdlc-wizard
  npx codex-sdlc-wizard --model-profile maximum
  npx codex-sdlc-wizard setup --yes
  npx codex-sdlc-wizard check
  npx codex-sdlc-wizard update
  npx codex-sdlc-wizard install
`);
}

let command = "setup";
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

function getSetupModelProfile(args) {
  for (let i = 0; i < args.length; i += 1) {
    if (args[i] === "--model-profile" && typeof args[i + 1] === "string") {
      return args[i + 1];
    }
    if (args[i].startsWith("--model-profile=")) {
      return args[i].slice("--model-profile=".length);
    }
  }

  return "maximum";
}

function spawnCodex(args, stdio) {
  return spawnSync(codexCommand, args, {
    cwd: process.cwd(),
    stdio,
    shell: Boolean(process.platform === "win32" && process.env.CODEX_SDLC_CODEX_BIN)
  });
}

function codexAvailable() {
  const result = spawnCodex(["--version"], "ignore");

  return !result.error && result.status === 0;
}

function isCiEnvironment() {
  const ciValue = process.env.CI;

  if (typeof ciValue !== "string") {
    return false;
  }

  return ciValue !== "" && ciValue !== "0" && ciValue.toLowerCase() !== "false";
}

function isHandoffCompatibleArg(arg) {
  return arg === "--model-profile" ||
    arg.startsWith("--model-profile=") ||
    arg === "mixed" ||
    arg === "maximum";
}

function shouldHandoffToCodex() {
  if (command !== "setup") {
    return false;
  }

  if (scriptArgs.includes("--yes") || scriptArgs.includes("-y")) {
    return false;
  }

  if (!scriptArgs.every(isHandoffCompatibleArg)) {
    return false;
  }

  if (process.env.CODEX_SDLC_FORCE_CODEX_HANDOFF === "1") {
    return true;
  }

  if (process.env.CODEX_SDLC_DISABLE_CODEX_HANDOFF === "1" || isCiEnvironment()) {
    return false;
  }

  return codexAvailable();
}

function runScript(scriptName, args) {
  return spawnSync("bash", [path.join(scriptDir, scriptName), ...args], {
    cwd: process.cwd(),
    stdio: "inherit"
  });
}

function handoffToCodex(modelProfile) {
  const installArgs = ["--model-profile", modelProfile];
  const installResult = runScript("install.sh", installArgs);

  if (installResult.error) {
    process.stderr.write(`${installResult.error.message}\n`);
    process.exit(1);
  }

  if (installResult.status !== 0) {
    process.exit(installResult.status === null ? 1 : installResult.status);
  }

  process.stdout.write("\nHanding off into Codex for live setup...\n");

  const codexArgs = [
    "--full-auto",
    "-C",
    process.cwd(),
    "-m",
    "gpt-5.4",
    "-c",
    'model_reasoning_effort="xhigh"',
    interactiveSessionPrompt
  ];

  const codexResult = spawnCodex(codexArgs, "inherit");

  if (codexResult.error) {
    process.stderr.write(`${codexResult.error.message}\n`);
    process.exit(1);
  }

  process.exit(codexResult.status === null ? 1 : codexResult.status);
}

if (shouldHandoffToCodex()) {
  handoffToCodex(getSetupModelProfile(scriptArgs));
}

const scriptName = command === "setup"
  ? "setup.sh"
  : command === "check"
    ? "check.sh"
    : command === "update"
      ? "update.sh"
      : "install.sh";
const scriptPath = path.join(scriptDir, scriptName);
const result = runScript(scriptName, scriptArgs);

if (result.error) {
  process.stderr.write(`${result.error.message}\n`);
  process.exit(1);
}

process.exit(result.status === null ? 1 : result.status);
