#!/usr/bin/env node
"use strict";

const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawn } = require("node:child_process");

const repoRoot = path.resolve(__dirname, "..");
const runnerSource = path.join(repoRoot, "scripts", "run-proof-suite.cjs");

function writeExecutable(target, contents) {
  fs.writeFileSync(target, contents);
  fs.chmodSync(target, 0o755);
}

function terminate(child, signal) {
  if (!child || !child.pid || child.exitCode !== null || child.signalCode !== null) {
    return;
  }

  try {
    if (process.platform !== "win32") {
      process.kill(-child.pid, signal);
      return;
    }
  } catch (_error) {
    // Fall through to direct child termination.
  }

  try {
    child.kill(signal);
  } catch (_error) {
    // The owned child may already have exited.
  }
}

function readPid(pidPath) {
  try {
    const pid = Number.parseInt(fs.readFileSync(pidPath, "utf8"), 10);
    return Number.isInteger(pid) && pid > 0 ? pid : null;
  } catch (_error) {
    return null;
  }
}

function terminatePid(pid, signal) {
  if (!pid) return;
  try {
    process.kill(pid, signal);
  } catch (_error) {
    // The owned probe may already have exited.
  }
}

function pidIsAlive(pid) {
  if (!pid) return false;
  try {
    process.kill(pid, 0);
    return true;
  } catch (error) {
    return error.code !== "ESRCH";
  }
}

function createFixture() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "proof-runner-stdin-"));
  const scriptsDir = path.join(root, "scripts");
  const testsDir = path.join(root, "tests");
  const fakeBin = path.join(root, "fake-bin");
  fs.mkdirSync(scriptsDir);
  fs.mkdirSync(testsDir);
  fs.mkdirSync(fakeBin);
  fs.copyFileSync(runnerSource, path.join(scriptsDir, "run-proof-suite.cjs"));

  const pidPath = path.join(root, "probe.pid");
  const outcomePath = path.join(root, "probe.outcome");
  const probePath = path.join(root, "stdin-probe.cjs");
  fs.writeFileSync(probePath, `"use strict";
const fs = require("node:fs");
fs.writeFileSync(process.env.PROOF_STDIN_PID_PATH, String(process.pid));
process.stdout.write("probe stdout captured\\n");
process.stderr.write("probe stderr captured\\n");
let settled = false;
let timeout;
function finish(outcome, code) {
  if (settled) return;
  settled = true;
  clearTimeout(timeout);
  fs.writeFileSync(process.env.PROOF_STDIN_OUTCOME_PATH, outcome + "\\n");
  const stream = code === 0 ? process.stdout : process.stderr;
  stream.write(outcome + "\\n", () => {
    process.stdin.destroy();
    process.exit(code);
  });
}
process.stdin.on("end", () => finish("EOF_OBSERVED", 0));
process.stdin.on("error", (error) => finish("STDIN_ERROR:" + error.code, 24));
process.stdin.resume();
timeout = setTimeout(() => finish("EOF_NOT_OBSERVED", 23), 350);
`);

  writeExecutable(path.join(fakeBin, "git"), `#!/bin/sh
exec "$PROOF_NODE" "$PROOF_STDIN_PROBE" "$@"
`);
  fs.writeFileSync(path.join(fakeBin, "git.cmd"), "@echo off\r\n\"%PROOF_NODE%\" \"%PROOF_STDIN_PROBE%\" %*\r\n");

  writeExecutable(path.join(fakeBin, "bash"), `#!/bin/sh
printf '%s\\n' 'fixture stdout captured'
printf '%s\\n' 'fixture stderr captured' >&2
exit 0
`);
  fs.writeFileSync(path.join(fakeBin, "bash.cmd"), "@echo off\r\necho fixture stdout captured\r\necho fixture stderr captured 1>&2\r\nexit /b 0\r\n");

  // The copied runner includes this suite; keep the nested black-box run bounded.
  fs.writeFileSync(path.join(testsDir, "test-proof-runner.cjs"), "process.exit(0);\n");

  return { fakeBin, outcomePath, pidPath, probePath, root };
}

function runFixture(fixture) {
  return new Promise((resolve) => {
    let stdout = "";
    let stderr = "";
    let timedOut = false;
    const child = spawn(process.execPath, [path.join(fixture.root, "scripts", "run-proof-suite.cjs"), "--serial"], {
      cwd: fixture.root,
      detached: process.platform !== "win32",
      env: {
        ...process.env,
        PATH: `${fixture.fakeBin}${path.delimiter}${process.env.PATH || ""}`,
        PROOF_NODE: process.execPath,
        PROOF_STDIN_OUTCOME_PATH: fixture.outcomePath,
        PROOF_STDIN_PID_PATH: fixture.pidPath,
        PROOF_STDIN_PROBE: fixture.probePath,
      },
      stdio: ["ignore", "pipe", "pipe"],
    });

    child.stdout.on("data", (chunk) => {
      stdout += chunk;
    });
    child.stderr.on("data", (chunk) => {
      stderr += chunk;
    });

    const watchdog = setTimeout(() => {
      timedOut = true;
      terminate(child, "SIGKILL");
      terminatePid(readPid(fixture.pidPath), "SIGKILL");
    }, 5000);

    child.on("close", (code, signal) => {
      clearTimeout(watchdog);
      resolve({ child, code, signal, stderr, stdout, timedOut });
    });
  });
}

function runnerLogDirectory(output) {
  const match = output.match(/^Logs: (.+)$/m);
  return match ? match[1].trim() : null;
}

async function main() {
  const fixture = createFixture();
  let logDir = null;
  let result;

  try {
    result = await runFixture(fixture);
    logDir = runnerLogDirectory(`${result.stdout}\n${result.stderr}`);
    const logPath = logDir ? path.join(logDir, "01-diff.log") : null;
    const log = logPath && fs.existsSync(logPath) ? fs.readFileSync(logPath, "utf8") : "";
    const outcome = fs.existsSync(fixture.outcomePath)
      ? fs.readFileSync(fixture.outcomePath, "utf8").trim()
      : "MISSING";
    const probePid = readPid(fixture.pidPath);
    const failures = [];

    if (result.timedOut) failures.push("runner exceeded the 5-second watchdog");
    if (result.code !== 0) failures.push(`runner exited ${result.code}${result.signal ? ` (${result.signal})` : ""}`);
    if (outcome !== "EOF_OBSERVED") failures.push(`probe outcome was ${outcome}`);
    if (!log.includes("probe stdout captured")) failures.push("probe stdout was not captured in the check log");
    if (!log.includes("probe stderr captured")) failures.push("probe stderr was not captured in the check log");
    if (!log.includes("exit: 0")) failures.push("check log did not record the successful child return outcome");
    if (!probePid) failures.push("probe did not record its PID");
    else if (pidIsAlive(probePid)) {
      failures.push(`probe process ${probePid} was not reaped`);
      terminatePid(probePid, "SIGKILL");
    }

    if (failures.length > 0) {
      throw new Error([
        ...failures,
        `runner stdout:\n${result.stdout.trimEnd() || "(empty)"}`,
        `runner stderr:\n${result.stderr.trimEnd() || "(empty)"}`,
        `diff check log:\n${log.trimEnd() || "(empty)"}`,
      ].join("\n\n"));
    }

    process.stdout.write("PASS: proof runner sends EOF, captures output and return status, and reaps its child\n");
  } finally {
    if (result && result.child) terminate(result.child, "SIGKILL");
    if (logDir) fs.rmSync(logDir, { force: true, recursive: true });
    fs.rmSync(fixture.root, { force: true, recursive: true });
  }
}

main().catch((error) => {
  process.stderr.write(`${error.stack || error.message}\n`);
  process.exit(1);
});
