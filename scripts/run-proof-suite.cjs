#!/usr/bin/env node

const { spawn } = require("node:child_process");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const repoRoot = path.resolve(__dirname, "..");
const checks = [
  { name: "diff", command: "git diff --check" },
  { name: "adapter", command: "bash tests/test-adapter.sh" },
  { name: "packaging", command: "bash tests/test-packaging.sh" },
  { name: "npm", command: "bash tests/test-npm.sh" },
  { name: "skill", command: "bash tests/test-skill.sh" },
  { name: "release", command: "bash tests/test-release.sh" },
  { name: "roadmap", command: "bash tests/test-roadmap.sh" },
  { name: "benchmark", command: "bash tests/test-benchmark.sh" },
  { name: "e2e", command: "bash tests/test-e2e.sh" },
  { name: "setup", command: "bash tests/test-setup.sh" },
  { name: "update", command: "bash tests/test-update.sh" }
];

function availableParallelism() {
  if (typeof os.availableParallelism === "function") {
    return os.availableParallelism();
  }

  return os.cpus().length || 2;
}

function defaultJobs() {
  const raw = process.env.CODEX_SDLC_PROOF_JOBS;
  if (raw) {
    const parsed = Number.parseInt(raw, 10);
    if (Number.isFinite(parsed) && parsed > 0) {
      return Math.min(parsed, checks.length);
    }
  }

  return Math.min(4, Math.max(2, availableParallelism()), checks.length);
}

function printHelp() {
  process.stdout.write(`Usage: node scripts/run-proof-suite.cjs [--serial] [--jobs N] [--list]

Runs the maintainer proof suite with bounded parallel jobs by default.

Options:
  --serial       Run one check at a time for debugging
  --jobs N       Run up to N checks at once
  --list         Print the check list without running it
  --help, -h     Show this help
`);
}

function parseArgs(args) {
  let jobs = defaultJobs();
  let list = false;

  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];

    if (arg === "--help" || arg === "-h") {
      return { help: true, jobs, list };
    }

    if (arg === "--list") {
      list = true;
      continue;
    }

    if (arg === "--serial") {
      jobs = 1;
      continue;
    }

    if (arg === "--jobs") {
      const raw = args[index + 1];
      const parsed = Number.parseInt(raw, 10);
      if (!Number.isFinite(parsed) || parsed < 1) {
        throw new Error("--jobs requires a positive integer");
      }
      jobs = parsed;
      index += 1;
      continue;
    }

    if (arg.startsWith("--jobs=")) {
      const parsed = Number.parseInt(arg.slice("--jobs=".length), 10);
      if (!Number.isFinite(parsed) || parsed < 1) {
        throw new Error("--jobs requires a positive integer");
      }
      jobs = parsed;
      continue;
    }

    throw new Error(`Unknown argument: ${arg}`);
  }

  return { help: false, jobs: Math.min(jobs, checks.length), list };
}

function printList(jobs) {
  process.stdout.write(`Parallel proof suite; default bounded jobs: ${defaultJobs()}; selected jobs: ${jobs}
Use --serial to run one check at a time.
Use --jobs N to tune concurrency.

Checks:
`);
  for (const check of checks) {
    process.stdout.write(`- ${check.command}\n`);
  }
}

function formatDuration(ms) {
  if (ms < 1000) {
    return `${ms}ms`;
  }

  return `${(ms / 1000).toFixed(1)}s`;
}

function logPathFor(logDir, index, check) {
  const safeName = check.name.replace(/[^a-z0-9_-]/gi, "-").toLowerCase();
  return path.join(logDir, `${String(index + 1).padStart(2, "0")}-${safeName}.log`);
}

function tailFile(file, maxLines) {
  try {
    const lines = fs.readFileSync(file, "utf8").trimEnd().split(/\r?\n/);
    return lines.slice(-maxLines).join("\n");
  } catch (_error) {
    return "";
  }
}

function terminateChild(child, signal) {
  if (!child || !child.pid) {
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
    // The process may already have exited.
  }
}

function runCheck(check, index, logDir, activeChildren) {
  return new Promise((resolve) => {
    const startedAt = Date.now();
    const logFile = logPathFor(logDir, index, check);
    const logStream = fs.createWriteStream(logFile);

    logStream.write(`$ ${check.command}\n\n`);

    const child = spawn(check.command, {
      cwd: repoRoot,
      env: process.env,
      shell: true,
      detached: process.platform !== "win32"
    });

    activeChildren.add(child);
    child.stdout.pipe(logStream, { end: false });
    child.stderr.pipe(logStream, { end: false });

    child.on("error", (error) => {
      logStream.write(`\nspawn error: ${error.message}\n`);
    });

    child.on("close", (code, signal) => {
      activeChildren.delete(child);
      const durationMs = Date.now() - startedAt;
      const ok = code === 0;
      logStream.write(`\nexit: ${code === null ? "null" : code}${signal ? ` signal:${signal}` : ""}\n`);
      logStream.end(() => {
        resolve({
          check,
          code,
          durationMs,
          index,
          logFile,
          ok,
          signal
        });
      });
    });
  });
}

async function runSuite(jobs) {
  const logDir = fs.mkdtempSync(path.join(os.tmpdir(), "codex-sdlc-proof-"));
  const activeChildren = new Set();
  const results = [];
  let nextIndex = 0;
  let interrupted = false;

  const stopChildren = (signal) => {
    interrupted = true;
    for (const child of activeChildren) {
      terminateChild(child, signal);
    }
  };

  for (const signal of ["SIGINT", "SIGTERM"]) {
    process.once(signal, () => stopChildren(signal));
  }

  process.stdout.write(`Running ${checks.length} proof checks with ${jobs} parallel job${jobs === 1 ? "" : "s"}.\n`);
  process.stdout.write(`Logs: ${logDir}\n\n`);

  async function worker() {
    while (!interrupted) {
      const current = nextIndex;
      nextIndex += 1;

      if (current >= checks.length) {
        return;
      }

      const check = checks[current];
      process.stdout.write(`start ${current + 1}/${checks.length}: ${check.command}\n`);
      const result = await runCheck(check, current, logDir, activeChildren);
      results.push(result);

      const status = result.ok ? "pass" : "fail";
      process.stdout.write(`${status}  ${current + 1}/${checks.length}: ${check.command} (${formatDuration(result.durationMs)})\n`);
    }
  }

  await Promise.all(Array.from({ length: jobs }, () => worker()));

  results.sort((a, b) => a.index - b.index);
  const failed = results.filter((result) => !result.ok);

  process.stdout.write("\nProof summary:\n");
  for (const result of results) {
    process.stdout.write(`- ${result.ok ? "PASS" : "FAIL"} ${result.check.command} (${formatDuration(result.durationMs)})\n`);
  }

  if (interrupted) {
    process.stderr.write("\nProof interrupted; child processes were signaled.\n");
    process.exit(130);
  }

  if (failed.length > 0) {
    process.stderr.write(`\n${failed.length} proof check${failed.length === 1 ? "" : "s"} failed. Logs: ${logDir}\n`);
    for (const result of failed) {
      process.stderr.write(`\n--- ${result.check.command} (${result.logFile}) ---\n`);
      const tail = tailFile(result.logFile, 80);
      process.stderr.write(tail ? `${tail}\n` : "(no log output)\n");
    }
    process.exit(1);
  }

  process.stdout.write(`\nAll proof checks passed. Logs: ${logDir}\n`);
}

async function main() {
  let options;
  try {
    options = parseArgs(process.argv.slice(2));
  } catch (error) {
    process.stderr.write(`${error.message}\n`);
    printHelp();
    process.exit(2);
  }

  if (options.help) {
    printHelp();
    return;
  }

  if (options.list) {
    printList(options.jobs);
    return;
  }

  await runSuite(options.jobs);
}

main().catch((error) => {
  process.stderr.write(`${error.stack || error.message}\n`);
  process.exit(1);
});
