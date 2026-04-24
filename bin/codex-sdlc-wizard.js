#!/usr/bin/env node

const { spawnSync } = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");
const readline = require("node:readline/promises");

const scriptDir = path.resolve(__dirname, "..");
const rawArgs = process.argv.slice(2);
const codexCommand = process.env.CODEX_SDLC_CODEX_BIN || "codex";
const interactiveSessionPrompt = [
  "$setup-wizard",
  "This repo was just bootstrapped by codex-sdlc-wizard.",
  "Continue setup inside Codex: scan the repo, ask only unresolved questions, preserve intentional existing docs, generate or refresh repo-specific SDLC docs, verify the result, and finish setup.",
  "Use xhigh reasoning for setup."
].join(" ");

function printHelp() {
  process.stdout.write(`Usage: codex-sdlc-wizard [setup|check|update|install] [options]

Commands:
  setup          Adaptive setup. Interactive default bootstraps then launches Codex for live setup
  check          Report managed-file drift for the current repo
  update         Apply selective updates for missing or drifted managed files using this package version
  install        Advanced escape hatch: run install.sh without adaptive setup

Default behavior: bootstrap the current repo, then hand off into a live plain Codex setup session.
Type 'full-auto' at the handoff prompt if you want codex --full-auto for first-run setup.
Automation/non-interactive behavior: use setup --yes to stay on the shell path.
Bootstrap/setup recommendation: maximum.
Routine work after bootstrap: mixed.
Update boundary: update repairs repo artifacts with the invoked package; it does not self-update the npm package.
To consume the newest release, run: npx codex-sdlc-wizard@latest update

Options:
  --model-profile <mixed|maximum>
                Wizard-owned profile toggle. Use 'maximum' for setup/bootstrap
                work, then switch routine work back to 'mixed' for better
                speed/token efficiency with xhigh main reasoning and review.
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
  if (process.platform === "win32") {
    return spawnSync(process.env.ComSpec || "cmd.exe", ["/d", "/s", "/c", codexCommand, ...args], {
      cwd: process.cwd(),
      stdio,
      shell: false
    });
  }

  return spawnSync(codexCommand, args, {
    cwd: process.cwd(),
    stdio,
    shell: false
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

async function askHandoffMode() {
  if (process.env.CODEX_SDLC_HANDOFF_MODE === "full-auto") {
    return "full-auto";
  }

  if (process.env.CODEX_SDLC_HANDOFF_MODE === "plain") {
    return "plain";
  }

  const prompt = [
    "",
    "Choose first-run Codex handoff mode:",
    "  Press Enter: plain codex (recommended)",
    "  Type full-auto: codex --full-auto",
    "  If interrupted later, resume with: codex resume --full-auto <session-id>",
    "> "
  ].join("\n");

  if (!process.stdin.isTTY) {
    process.stdout.write(prompt);
    const answer = fs.readFileSync(0, "utf8").split(/\r?\n/, 1)[0].trim().toLowerCase();
    process.stdout.write("\n");
    return answer === "full-auto" ? "full-auto" : "plain";
  }

  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout
  });

  try {
    const answer = (await rl.question(prompt)).trim().toLowerCase();
    return answer === "full-auto" ? "full-auto" : "plain";
  } finally {
    rl.close();
  }
}

async function handoffToCodex(modelProfile) {
  const installArgs = ["--model-profile", modelProfile];
  const installResult = runScript("install.sh", installArgs);

  if (installResult.error) {
    process.stderr.write(`${installResult.error.message}\n`);
    process.exit(1);
  }

  if (installResult.status !== 0) {
    process.exit(installResult.status === null ? 1 : installResult.status);
  }

  const handoffMode = await askHandoffMode();
  const modeLabel = handoffMode === "full-auto" ? "codex --full-auto" : "plain codex";
  process.stdout.write(`\nHanding off into Codex for live setup using ${modeLabel}...\n`);

  const codexArgs = [
    "-C",
    process.cwd(),
    "-m",
    "gpt-5.5",
    "-c",
    "model_reasoning_effort='xhigh'",
    interactiveSessionPrompt
  ];

  if (handoffMode === "full-auto") {
    codexArgs.unshift("--full-auto");
  }

  const codexResult = spawnCodex(codexArgs, "inherit");

  if (codexResult.error) {
    process.stderr.write(`${codexResult.error.message}\n`);
    process.exit(1);
  }

  return codexResult.status === null ? 1 : codexResult.status;
}

async function main() {
  if (shouldHandoffToCodex()) {
    process.exit(await handoffToCodex(getSetupModelProfile(scriptArgs)));
  }

  const scriptName = command === "setup"
    ? "setup.sh"
    : command === "check"
      ? "check.sh"
      : command === "update"
        ? "update.sh"
        : "install.sh";
  const result = runScript(scriptName, scriptArgs);

  if (result.error) {
    process.stderr.write(`${result.error.message}\n`);
    process.exit(1);
  }

  process.exit(result.status === null ? 1 : result.status);
}

main().catch((error) => {
  process.stderr.write(`${error.message}\n`);
  process.exit(1);
});
