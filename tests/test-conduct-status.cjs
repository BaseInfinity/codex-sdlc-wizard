#!/usr/bin/env node

const crypto = require("node:crypto");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");

const EXPECTED_STATUS_SHA256 = "a00fc075651ef66b63e9f2b2c3c6246cfff5a002bdca376832eb7d4cac44e11f";
const repoRoot = path.resolve(__dirname, "..");
const conductScript = path.join(repoRoot, "skill-sources", "conduct", "scripts", "conduct.cjs");
const statusScript = path.join(repoRoot, "skill-sources", "conduct", "scripts", "status.cjs");
const scratchRoot = fs.mkdtempSync(path.join(os.tmpdir(), "conduct-status-tests-"));
let passed = 0;
let failed = 0;

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function runNode(script, args, cwd = repoRoot) {
  const result = spawnSync(process.execPath, [script, ...args], {
    cwd,
    encoding: "utf8",
    env: { ...process.env, NO_COLOR: "1" }
  });
  if (result.error) throw result.error;
  return result;
}

function runStatus(args, cwd = repoRoot, script = conductScript) {
  return runNode(script, ["status", ...args], cwd);
}

function success(result, label) {
  assert(result.status === 0, `${label} exited ${result.status}\nstdout:\n${result.stdout}\nstderr:\n${result.stderr}`);
}

function failure(result, label) {
  assert(result.status !== 0 && result.status !== null, `${label} unexpectedly exited ${result.status}`);
}

function runGit(args, cwd, encoding = "utf8") {
  const result = spawnSync("git", args, { cwd, encoding });
  if (result.error) throw result.error;
  assert(result.status === 0, `git ${args.join(" ")} exited ${result.status}: ${String(result.stderr)}`);
  return result.stdout;
}

function test(name, callback) {
  try {
    callback();
    process.stdout.write(`PASS: ${name}\n`);
    passed += 1;
  } catch (error) {
    process.stderr.write(`FAIL: ${name}: ${error instanceof Error ? error.message : String(error)}\n`);
    failed += 1;
  }
}

function testVendorHash() {
  assert(fs.existsSync(statusScript), "vendored status.cjs is missing");
  const actual = crypto.createHash("sha256").update(fs.readFileSync(statusScript)).digest("hex");
  assert(actual === EXPECTED_STATUS_SHA256, `status.cjs sha256 ${actual} does not match ${EXPECTED_STATUS_SHA256}`);
}

function testHelp() {
  const parentHelp = runNode(conductScript, ["--help"]);
  success(parentHelp, "conduct --help");
  assert(parentHelp.stdout.includes("conduct.cjs status"), "parent help does not advertise status");
  assert(parentHelp.stdout.includes("conduct.cjs emit") && parentHelp.stdout.includes("conduct.cjs mark"), "parent help lost emit/mark");

  for (const helpArg of ["--help", "-h"]) {
    const standaloneHelp = runNode(statusScript, [helpArg]);
    const parentStatusHelp = runStatus([helpArg]);
    success(standaloneHelp, `standalone status ${helpArg}`);
    success(parentStatusHelp, `conduct status ${helpArg}`);
    assert(parentStatusHelp.status === standaloneHelp.status, `parent status ${helpArg} changed the child exit status`);
    assert(parentStatusHelp.stdout === standaloneHelp.stdout, `parent status ${helpArg} changed child stdout`);
    assert(parentStatusHelp.stderr === standaloneHelp.stderr, `parent status ${helpArg} changed child stderr`);
  }
}

function testEmptyView() {
  const root = path.join(scratchRoot, "empty root with spaces");
  fs.mkdirSync(root, { recursive: true });
  const result = runStatus(["--root", root], scratchRoot);
  success(result, "empty status view");
  assert(result.stdout === "[USAGE]\n  claude-main unknown\n\nno fleet rows\n", `unexpected empty view:\n${result.stdout}`);
  assert(result.stderr === "", `empty view wrote stderr: ${result.stderr}`);
  assert(!fs.existsSync(path.join(root, ".brain", "fleet.json")), "read-only view created fleet state");
}

function testSetViewFilterAndLiteralArgv() {
  const root = path.join(scratchRoot, "fleet root with spaces");
  const caller = path.join(scratchRoot, "independent caller cwd");
  const canary = path.join(scratchRoot, "SHELL_CANARY_MUST_NOT_EXIST");
  fs.mkdirSync(root, { recursive: true });
  fs.mkdirSync(caller, { recursive: true });
  const workstream = `literal ; $(touch ${canary})`;
  const next = `next && touch ${canary}`;
  const evidence = `evidence \`touch ${canary}\``;
  const setResult = runStatus([
    "set", "--root", root, "--controller", "HARNESS", "--workstream", workstream,
    "--percent", "50", "--state", "in_flight", "--next", next, "--evidence", evidence
  ], caller);
  success(setResult, "status set from independent cwd");
  const saved = JSON.parse(fs.readFileSync(path.join(root, ".brain", "fleet.json"), "utf8"));
  const row = Object.values(saved.rows)[0];
  assert(row.workstream === workstream && row.next_step === next && row.evidence === evidence, "literal argv values were changed");
  assert(!fs.existsSync(canary), "a shell metacharacter argument executed the canary");
  assert(JSON.parse(setResult.stdout).row.workstream === workstream, "set stdout did not preserve the row");

  const second = runStatus([
    "set", "--root", root, "--controller", "CODEX", "--workstream", "separate row",
    "--percent", "5", "--state", "planned"
  ], caller);
  success(second, "second controller set");

  const filtered = runStatus(["--root", root, "--controller", "HARNESS"], caller);
  success(filtered, "controller filter");
  assert(filtered.stdout.includes("[HARNESS]") && filtered.stdout.includes(workstream), "filter omitted the selected controller row");
  assert(!filtered.stdout.includes("[CODEX]") && !filtered.stdout.includes("[USAGE]"), "filter leaked another controller or usage section");
  assert(filtered.stdout.includes(next) && filtered.stdout.includes(evidence), "view omitted next/evidence literals");
  assert(!fs.existsSync(canary), "rendering literal values executed the canary");
  assert(JSON.stringify(fs.readdirSync(root).sort()) === JSON.stringify([".brain"]), "set wrote outside the owned .brain fixture");
  assert(JSON.stringify(fs.readdirSync(path.join(root, ".brain")).sort()) === JSON.stringify(["fleet.json"]), "set left unexpected state files");
}

function testValidationAndChildFailurePropagation() {
  const root = path.join(scratchRoot, "validation root");
  fs.mkdirSync(root, { recursive: true });
  const common = ["set", "--root", root, "--controller", "HARNESS", "--workstream", "blocked", "--percent", "10"];

  const missingOwner = runStatus([...common, "--state", "blocked"]);
  failure(missingOwner, "blocked row without owner");
  assert(missingOwner.stderr.includes("status: --state blocked requires --blocker-owner"), "missing-owner child error was not propagated");

  const forbiddenOwner = runStatus([...common, "--state", "planned", "--blocker-owner", "ROOT"]);
  failure(forbiddenOwner, "owner on unblocked row");
  assert(forbiddenOwner.stderr.includes("status: --blocker-owner is allowed only with --state blocked"), "forbidden-owner child error was not propagated");

  const badController = runStatus(["--root", root, "--controller", "NOT_A_CONTROLLER"]);
  failure(badController, "unknown controller");
  assert(badController.stderr.startsWith("status: controller must be one of"), "controller error was reinterpreted by the parent");

  const unknown = runStatus(["--root", root, "--unknown", "value"]);
  failure(unknown, "unknown status option");
  assert(unknown.stderr === "status: unknown option: --unknown\n", `unknown-option stderr changed: ${unknown.stderr}`);
  assert(!unknown.stderr.includes("conduct:"), "parent rewrote the child error");
}

function testProgressBars() {
  const root = path.join(scratchRoot, "bar root");
  fs.mkdirSync(root, { recursive: true });
  const cases = [
    [0, "░░░░░░░░░░"],
    [5, "█░░░░░░░░░"],
    [50, "█████░░░░░"],
    [95, "█████████░"],
    [99, "█████████░"],
    [100, "██████████"]
  ];
  for (const [percent] of cases) {
    const result = runStatus([
      "set", "--root", root, "--controller", "CODEX", "--workstream", `bar ${percent}`,
      "--percent", String(percent), "--state", "planned"
    ]);
    success(result, `set ${percent}% row`);
  }
  const view = runStatus(["--root", root, "--controller", "CODEX"]);
  success(view, "bar view");
  for (const [percent, bar] of cases) {
    const expected = `${bar} ${String(percent).padStart(3)}% bar ${percent}`;
    assert(view.stdout.includes(expected), `missing bar rendering: ${expected}`);
  }
  assert(!view.stdout.includes("██████████  99%"), "99% rendered as a full bar");
}

function testMissingHelperFailure() {
  const scripts = path.join(scratchRoot, "missing helper", "scripts");
  fs.mkdirSync(scripts, { recursive: true });
  const isolatedParent = path.join(scripts, "conduct.cjs");
  fs.copyFileSync(conductScript, isolatedParent);
  const helpResult = runStatus(["--help"], scratchRoot, isolatedParent);
  const viewResult = runStatus(["--root", scratchRoot], scratchRoot, isolatedParent);
  failure(helpResult, "status help with missing sibling helper");
  failure(viewResult, "status view with missing sibling helper");
  assert(helpResult.stderr.length > 0 && viewResult.stderr.length > 0, "missing helper failed without a diagnostic");
}

function testAutocrlfCheckoutBytes() {
  assert(fs.existsSync(statusScript), "vendored status.cjs is missing from the EOL fixture inputs");
  const fixture = path.join(scratchRoot, "autocrlf fixture");
  const checkout = path.join(scratchRoot, "autocrlf checkout");
  const paths = [
    ".gitattributes",
    "skill-sources/conduct/SKILL.template.md",
    "skill-sources/conduct/scripts/status.cjs",
    "skill-sources/conduct/scripts/conduct.cjs"
  ];
  fs.mkdirSync(fixture, { recursive: true });
  fs.mkdirSync(checkout, { recursive: true });
  for (const relative of paths) {
    const target = path.join(fixture, relative);
    fs.mkdirSync(path.dirname(target), { recursive: true });
    fs.copyFileSync(path.join(repoRoot, relative), target);
  }
  runGit(["init", "-q"], fixture);
  runGit(["-c", "core.autocrlf=false", "add", "--", "."], fixture);
  for (const relative of paths.slice(1)) {
    const source = fs.readFileSync(path.join(repoRoot, relative));
    const indexed = runGit(["show", `:${relative}`], fixture, null);
    assert(source.equals(indexed), `${relative} index bytes differ before checkout`);
  }
  runGit(["-c", "core.autocrlf=true", "checkout-index", "--all", "--force", `--prefix=${checkout}${path.sep}`], fixture);
  for (const relative of paths.slice(1)) {
    const source = fs.readFileSync(path.join(repoRoot, relative));
    const checkedOut = fs.readFileSync(path.join(checkout, relative));
    assert(source.equals(checkedOut), `${relative} changed bytes under core.autocrlf=true`);
  }
}

const eolOnly = process.argv.slice(2).includes("--eol-only");
const unknown = process.argv.slice(2).filter((arg) => arg !== "--eol-only");
if (unknown.length) {
  process.stderr.write(`Unknown test option: ${unknown[0]}\n`);
  process.exit(2);
}

if (eolOnly) {
  test("targeted Conduct assets survive an autocrlf checkout byte-for-byte", testAutocrlfCheckoutBytes);
} else {
  test("vendored status helper matches the owner-certified byte hash", testVendorHash);
  test("parent and status help expose the supported commands", testHelp);
  test("empty owned roots render without creating fleet state", testEmptyView);
  test("set/view/filter preserve literal argv without shell execution", testSetViewFilterAndLiteralArgv);
  test("blocked-owner and child argument failures propagate", testValidationAndChildFailurePropagation);
  test("progress bars reserve a full bar for 100 percent", testProgressBars);
  test("a missing sibling status helper fails honestly", testMissingHelperFailure);
  test("targeted Conduct assets survive an autocrlf checkout byte-for-byte", testAutocrlfCheckoutBytes);
}

process.stdout.write(`Scratch retained: ${scratchRoot}\n`);
process.stdout.write(`=== Results: ${passed} passed, ${failed} failed ===\n`);
if (failed) process.exit(1);
