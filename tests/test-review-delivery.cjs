#!/usr/bin/env node
const childProcess = require("node:child_process");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const repo = path.resolve(__dirname, "..");
const deliveryScript = path.join(repo, ".codex", "hooks", "dual-review.cjs");

function run(command, args, options = {}) {
  return childProcess.spawnSync(command, args, {
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
    ...options,
  });
}

function must(command, args, options = {}) {
  const result = run(command, args, options);
  if (result.status !== 0) {
    throw new Error(`${command} ${args.join(" ")} failed:\n${result.stdout}${result.stderr}`);
  }
  return result.stdout.trim();
}

function git(root, ...args) {
  return must("git", ["-C", root, ...args]);
}

function receiptPath(root) {
  const target = git(root, "rev-parse", "--git-path", "codex-sdlc/dual-review.json");
  return path.isAbsolute(target) ? target : path.join(root, target);
}

function proofPath(root) {
  const target = git(root, "rev-parse", "--git-path", "codex-sdlc/proof.json");
  return path.isAbsolute(target) ? target : path.join(root, target);
}

function makeFixture(prefix) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), prefix));
  const remote = `${root}.git`;
  must("git", ["init", "--bare", "-q", remote]);
  must("git", ["init", "-q", "-b", "main", root]);
  git(root, "config", "user.email", "test@example.com");
  git(root, "config", "user.name", "SDLC Test");
  git(root, "remote", "add", "origin", remote);
  const hooks = path.join(root, ".codex", "hooks");
  fs.mkdirSync(hooks, { recursive: true });
  fs.copyFileSync(path.join(repo, ".codex", "hooks", "git-guard.cjs"), path.join(hooks, "git-guard.cjs"));
  fs.writeFileSync(path.join(root, "file.txt"), "baseline\n");
  git(root, "add", "file.txt", ".codex/hooks/git-guard.cjs");
  git(root, "commit", "-qm", "baseline");
  git(root, "push", "-q", "origin", "HEAD:refs/heads/main");
  git(root, "switch", "-qc", "feature");
  fs.writeFileSync(path.join(root, "file.txt"), "candidate\n");
  git(root, "add", "file.txt");
  const base = git(root, "rev-parse", "HEAD");
  const tree = git(root, "write-tree");
  const target = receiptPath(root);
  fs.mkdirSync(path.dirname(target), { recursive: true });
  must(process.execPath, [path.join(hooks, "git-guard.cjs"), "prove", "--reviewed", "--check", "true"], { cwd: root });
  const proof = JSON.parse(fs.readFileSync(proofPath(root), "utf8"));
  fs.writeFileSync(target, `${JSON.stringify({
    schema_version: 1,
    status: "certified",
    base_commit: base,
    head_before_commit: base,
    candidate_tree: tree,
    patch_sha256: "sha256:test",
    proof_workspace_fingerprint: proof.workspace_fingerprint,
    proof_created_at: proof.created_at,
    reviewer_policy: "sol-high+fable-high/independent-cross-feed-on-split/v1",
    joint_verdict: "CERTIFIED",
  })}\n`);
  return { root, remote, base, tree, receipt: target };
}

function certifyCommittedCandidate(fixture) {
  git(fixture.root, "commit", "-qm", "candidate checkpoint");
  const commit = git(fixture.root, "rev-parse", "HEAD");
  must(process.execPath, [path.join(fixture.root, ".codex", "hooks", "git-guard.cjs"),
    "prove", "--reviewed", "--check", "true"], { cwd: fixture.root });
  const proof = JSON.parse(fs.readFileSync(proofPath(fixture.root), "utf8"));
  const receipt = JSON.parse(fs.readFileSync(fixture.receipt, "utf8"));
  receipt.head_before_commit = commit;
  receipt.proof_workspace_fingerprint = proof.workspace_fingerprint;
  receipt.proof_created_at = proof.created_at;
  fs.writeFileSync(fixture.receipt, `${JSON.stringify(receipt)}\n`);
  return commit;
}

function fakeGh(directory) {
  const target = path.join(directory, "fake-gh.cjs");
  fs.writeFileSync(target, `#!/usr/bin/env node
const fs = require("node:fs");
const cp = require("node:child_process");
const args = process.argv.slice(2);
const head = cp.spawnSync("git", ["-C", process.cwd(), "rev-parse", "HEAD"], { encoding: "utf8" }).stdout.trim();
fs.appendFileSync(process.env.GH_LOG, JSON.stringify({
  args,
  ghRepo: process.env.GH_REPO || "",
  ghHost: process.env.GH_HOST || "",
  lowerGitDir: process.env.git_dir || "",
  lowerGhRepo: process.env.gh_repo || "",
}) + "\\n");
const headMismatch = process.env.GH_MODE === "head-mismatch";
const baseMismatch = process.env.GH_MODE === "base-mismatch";
const remoteBase = cp.spawnSync("git", ["--git-dir", process.env.REMOTE_PATH, "rev-parse", "refs/heads/main"], { encoding: "utf8" }).stdout.trim();
const merged = remoteBase === head;
if (args[0] === "pr" && args[1] === "list") {
  process.stdout.write(process.env.GH_MODE === "ambiguous-pr"
    ? JSON.stringify([{ number: 7, headRefOid: head, baseRefOid: process.env.BASE_SHA }])
    : "[]");
}
else if (args[0] === "pr" && args[1] === "create") process.stdout.write("https://github.com/acme/project/pull/7\\n");
else if (args[0] === "pr" && args[1] === "view") {
  const wrongSelection = process.env.GH_MODE === "ambiguous-pr" && args[2] !== "7";
  const viewCount = fs.readFileSync(process.env.GH_LOG, "utf8").trim().split("\\n")
    .map((line) => JSON.parse(line)).filter((call) => call.args[0] === "pr" && call.args[1] === "view").length;
  process.stdout.write(JSON.stringify({
    number: wrongSelection ? 8 : 7,
    state: merged ? "MERGED" : (process.env.GH_MODE === "closed" ? "CLOSED" : "OPEN"),
    isDraft: process.env.GH_MODE === "draft",
    headRefOid: headMismatch ? "0000000000000000000000000000000000000000" : head,
    baseRefOid: baseMismatch ? "1111111111111111111111111111111111111111" : process.env.BASE_SHA,
    headRefName: "feature",
    baseRefName: wrongSelection ? "other-base" : "main",
    mergeable: process.env.GH_MODE === "conflicting" ? "CONFLICTING" : "MERGEABLE",
    mergeStateStatus: process.env.GH_MODE === "blocked"
      ? "BLOCKED"
      : (process.env.GH_MODE === "blocked-pending" && viewCount === 1
        ? "BLOCKED"
        : (["unknown", "unstable"].includes(process.env.GH_MODE)
          ? process.env.GH_MODE.toUpperCase()
          : (process.env.GH_MODE === "conflicting" ? "DIRTY" : "CLEAN"))),
    statusCheckRollup: process.env.GH_MODE === "checks-empty"
      ? []
      : (process.env.GH_MODE === "blocked-pending" && viewCount === 1
        ? [{ status: "IN_PROGRESS", conclusion: "" }]
        : [{ status: "COMPLETED", conclusion: "SUCCESS" }]),
    mergeCommit: merged ? { oid: head } : null,
  }));
  if (process.env.GH_MODE === "base-race" && !merged) {
    const tree = cp.spawnSync("git", ["--git-dir", process.env.REMOTE_PATH, "rev-parse", "refs/heads/main^{tree}"], { encoding: "utf8" }).stdout.trim();
    const raced = cp.spawnSync("git", ["--git-dir", process.env.REMOTE_PATH, "commit-tree", tree, "-p", process.env.BASE_SHA, "-m", "base race"], {
      encoding: "utf8",
      env: { ...process.env, GIT_AUTHOR_NAME: "Race", GIT_AUTHOR_EMAIL: "race@example.com", GIT_COMMITTER_NAME: "Race", GIT_COMMITTER_EMAIL: "race@example.com" },
    }).stdout.trim();
    cp.spawnSync("git", ["--git-dir", process.env.REMOTE_PATH, "update-ref", "refs/heads/main", raced]);
  }
}
else if (args[0] === "api") process.stdout.write(JSON.stringify({ tree: { sha: process.env.CANDIDATE_TREE } }));
else { process.stderr.write("unexpected gh argv: " + JSON.stringify(args) + "\\n"); process.exit(2); }
`);
  fs.chmodSync(target, 0o755);
  return target;
}

function fakeGit(directory) {
const target = path.join(directory, "git");
  fs.writeFileSync(target, `#!/usr/bin/env node
const cp = require("node:child_process");
const fs = require("node:fs");
const args = process.argv.slice(2);
fs.appendFileSync(process.env.GIT_LOG, JSON.stringify({
  args,
  noReplace: process.env.GIT_NO_REPLACE_OBJECTS || "",
}) + "\\n");
if (args.includes("push") || args.includes("ls-remote")) {
  for (let index = 0; index < args.length; index += 1) {
    if (args[index] === "origin") args[index] = process.env.REMOTE_PATH;
  }
}
if (process.env.GIT_MODE === "post-push-observation-failure"
    && args.includes("ls-remote")
    && args.includes("refs/heads/main")
    && !fs.existsSync(process.env.GIT_FAILURE_MARKER)) {
  const rootIndex = args.indexOf("-C");
  const root = rootIndex >= 0 ? args[rootIndex + 1] : process.cwd();
  const head = cp.spawnSync(process.env.REAL_GIT, ["-C", root, "rev-parse", "HEAD"], { encoding: "utf8" }).stdout.trim();
  const remoteHead = cp.spawnSync(process.env.REAL_GIT,
    ["--git-dir", process.env.REMOTE_PATH, "rev-parse", "refs/heads/main"], { encoding: "utf8" }).stdout.trim();
  if (head === remoteHead) {
    fs.writeFileSync(process.env.GIT_FAILURE_MARKER, "failed after base push\\n");
    process.stderr.write("simulated post-push observation failure\\n");
    process.exit(92);
  }
}
const result = cp.spawnSync(process.env.REAL_GIT, args, { stdio: "inherit", env: process.env });
process.exit(result.status === null ? 2 : result.status);
`);
  fs.chmodSync(target, 0o755);
  return target;
}

function invoke(fixture, mode, operation = "github", replacements = [], extraEnvironment = {}) {
  const support = fs.mkdtempSync(path.join(os.tmpdir(), "review-delivery-gh-"));
  const log = path.join(support, "gh.jsonl");
  const gitLog = path.join(support, "git.jsonl");
  const marker = path.join(support, "merged");
  const gh = fakeGh(support);
  fakeGit(support);
  if (operation === "github") {
    git(fixture.root, "remote", "set-url", "origin", "git@github.com:acme/project.git");
  }
  const args = [deliveryScript, "deliver", operation,
    "--message", "feat: exact candidate",
    "--branch", "feature"];
  if (operation === "github") args.push(
    "--base", "main", "--title", "Exact candidate", "--body", "Closes #111",
  );
  for (let index = 0; index < replacements.length; index += 2) {
    const flag = replacements[index];
    const value = replacements[index + 1];
    if (value === null) {
      args.push(flag);
      continue;
    }
    const position = args.indexOf(flag);
    if (position >= 0) args[position + 1] = value;
    else args.push(flag, value);
  }
  const result = run(process.execPath, args, {
    cwd: fixture.root,
    env: {
      ...process.env,
      CODEX_SDLC_TEST_MODE: "1",
      CODEX_SDLC_GH_PATH: gh,
      CODEX_SDLC_GIT_PATH: path.join(support, "git"),
      GH_LOG: log,
      GIT_LOG: gitLog,
      GH_MERGED_MARKER: marker,
      GH_MODE: mode,
      GIT_MODE: mode,
      GIT_FAILURE_MARKER: `${fixture.remote}.post-push-failure`,
      GH_REPO: "attacker/wrong-repo",
      GH_HOST: "evil.invalid",
      git_dir: "/attacker/wrong-git-dir",
      gh_repo: "attacker/lowercase-repo",
      BASE_SHA: fixture.base,
      CANDIDATE_TREE: fixture.tree,
      REMOTE_PATH: fixture.remote,
      REAL_GIT: must("which", ["git"]),
      ...extraEnvironment,
    },
  });
  const calls = fs.existsSync(log)
    ? fs.readFileSync(log, "utf8").trim().split("\n").filter(Boolean).map(JSON.parse)
    : [];
  const gitCalls = fs.existsSync(gitLog)
    ? fs.readFileSync(gitLog, "utf8").trim().split("\n").filter(Boolean).map(JSON.parse)
    : [];
  return { result, calls, gitCalls, marker };
}

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

const cleanup = [];
try {
  const success = makeFixture("review-delivery-success-");
  cleanup.push(success.root, success.remote);
  const hostHooks = fs.mkdtempSync(path.join(os.tmpdir(), "review-delivery-host-hooks-"));
  const hookMarker = path.join(hostHooks, "executed");
  cleanup.push(hostHooks);
  for (const hook of ["post-commit", "pre-push"]) {
    const hookPath = path.join(hostHooks, hook);
    fs.writeFileSync(hookPath, `#!/bin/sh\nprintf '%s\\n' '${hook}' >> '${hookMarker}'\n`);
    fs.chmodSync(hookPath, 0o755);
  }
  git(success.root, "config", "core.hooksPath", hostHooks);
  const delivered = invoke(success, "clean");
  assert(delivered.result.status === 0, `GitHub delivery failed:\n${delivered.result.stdout}${delivered.result.stderr}`);
  const hookCalls = fs.readFileSync(hookMarker, "utf8").trim().split("\n");
  assert(hookCalls.includes("post-commit") && hookCalls.filter((entry) => entry === "pre-push").length === 2,
    "Configured commit/push hooks did not execute throughout delivery");
  const commit = git(success.root, "rev-parse", "HEAD");
  assert(git(success.root, "rev-parse", "HEAD^{tree}") === success.tree, "Committed tree differs from certified tree");
  assert(must("git", ["--git-dir", success.remote, "rev-parse", "refs/heads/feature"]) === commit, "Explicit feature ref was not pushed");
  assert(must("git", ["--git-dir", success.remote, "rev-parse", "refs/heads/main"]) === commit, "Base did not advance to the exact certified commit");
  assert(delivered.calls.every((call) => call.ghRepo === "" && call.ghHost === ""), "Ambient GH_REPO/GH_HOST leaked into gh");
  assert(delivered.calls.every((call) => call.lowerGitDir === "" && call.lowerGhRepo === ""),
    "Case-variant retargeting variables leaked into delivery subprocesses");
  const mergeCalls = delivered.calls.filter((call) => call.args[0] === "pr" && call.args[1] === "merge");
  assert(mergeCalls.length === 0, "GitHub merge cannot guarantee the exact integrated tree");
  const finalReceipt = JSON.parse(fs.readFileSync(success.receipt, "utf8"));
  assert(finalReceipt.delivery?.status === "integrated" && finalReceipt.delivery?.commit === commit, "Receipt lacks exact delivery result");

  const alreadyCommitted = makeFixture("review-delivery-already-committed-");
  cleanup.push(alreadyCommitted.root, alreadyCommitted.remote);
  const certifiedCommit = certifyCommittedCandidate(alreadyCommitted);
  const alreadyCommittedResult = invoke(alreadyCommitted, "clean", "direct");
  assert(alreadyCommittedResult.result.status === 0,
    `Already-committed certified candidate failed delivery:\n${alreadyCommittedResult.result.stdout}${alreadyCommittedResult.result.stderr}`);
  assert(git(alreadyCommitted.root, "rev-parse", "HEAD") === certifiedCommit,
    "Delivery created an extra commit for an already-committed certified candidate");
  assert(git(alreadyCommitted.root, "ls-remote", "origin", "refs/heads/feature").startsWith(certifiedCommit),
    "Already-committed certified candidate was not published");

  const replacementObjects = makeFixture("review-delivery-replacement-objects-");
  cleanup.push(replacementObjects.root, replacementObjects.remote);
  const replacementObjectsResult = invoke(replacementObjects, "clean", "direct");
  assert(replacementObjectsResult.result.status === 0,
    `Replacement-object-safe delivery failed:\n${replacementObjectsResult.result.stdout}${replacementObjectsResult.result.stderr}`);
  assert(replacementObjectsResult.gitCalls.length > 0
    && replacementObjectsResult.gitCalls.every((call) => call.noReplace === "1"),
  "Delivery Git commands did not disable replacement-object resolution");

  const blockedByHook = makeFixture("review-delivery-hook-blocked-");
  cleanup.push(blockedByHook.root, blockedByHook.remote);
  const blockingHooks = fs.mkdtempSync(path.join(os.tmpdir(), "review-delivery-blocking-hooks-"));
  cleanup.push(blockingHooks);
  const prePush = path.join(blockingHooks, "pre-push");
  fs.writeFileSync(prePush, "#!/bin/sh\nexit 97\n");
  fs.chmodSync(prePush, 0o755);
  git(blockedByHook.root, "config", "core.hooksPath", blockingHooks);
  const hookBlocked = invoke(blockedByHook, "clean");
  assert(hookBlocked.result.status !== 0, "Delivery ignored a failing configured pre-push hook");
  assert(must("git", ["--git-dir", blockedByHook.remote, "rev-parse", "refs/heads/main"]) === blockedByHook.base,
    "Delivery advanced the base after a configured hook rejected the push");

  const emptyChecks = makeFixture("review-delivery-empty-checks-");
  cleanup.push(emptyChecks.root, emptyChecks.remote);
  const noChecks = invoke(emptyChecks, "checks-empty");
  assert(noChecks.result.status !== 0, "Delivery treated an empty GitHub check rollup as green");
  assert(must("git", ["--git-dir", emptyChecks.remote, "rev-parse", "refs/heads/main"]) === emptyChecks.base,
    "Delivery advanced the base before GitHub checks became observable");

  const explicitlyCheckless = makeFixture("review-delivery-checkless-opt-out-");
  cleanup.push(explicitlyCheckless.root, explicitlyCheckless.remote);
  const checkless = invoke(explicitlyCheckless, "checks-empty", "github", ["--allow-no-checks", null]);
  assert(checkless.result.status === 0, `Explicit check-less delivery failed:\n${checkless.result.stdout}${checkless.result.stderr}`);
  assert(must("git", ["--git-dir", explicitlyCheckless.remote, "rev-parse", "refs/heads/main"])
    === git(explicitlyCheckless.root, "rev-parse", "HEAD"), "Explicit check-less delivery did not integrate the certified commit");

  const stale = makeFixture("review-delivery-stale-");
  cleanup.push(stale.root, stale.remote);
  fs.writeFileSync(path.join(stale.root, "file.txt"), "changed after review\n");
  git(stale.root, "add", "file.txt");
  const rejected = invoke(stale, "clean");
  assert(rejected.result.status !== 0, "Stale candidate was delivered");
  assert(rejected.calls.length === 0, "Stale candidate reached GitHub");
  assert(git(stale.root, "rev-list", "--count", "HEAD") === "1", "Stale candidate was committed");

  const staleProof = makeFixture("review-delivery-stale-proof-");
  const otherProof = makeFixture("review-delivery-other-proof-");
  cleanup.push(staleProof.root, staleProof.remote, otherProof.root, otherProof.remote);
  const proofTarget = git(staleProof.root, "rev-parse", "--git-path", "codex-sdlc/proof.json");
  const staleProofPath = path.isAbsolute(proofTarget) ? proofTarget : path.join(staleProof.root, proofTarget);
  const expiredProof = JSON.parse(fs.readFileSync(staleProofPath, "utf8"));
  expiredProof.expires_at = "2000-01-01T00:00:00.000Z";
  fs.writeFileSync(staleProofPath, `${JSON.stringify(expiredProof)}\n`);
  const otherGitDirectory = git(otherProof.root, "rev-parse", "--absolute-git-dir");
  const staleProofResult = invoke(staleProof, "clean", "github", [], { GIT_DIR: otherGitDirectory });
  assert(staleProofResult.result.status !== 0, "Delivery accepted an expired proof receipt");
  assert(staleProofResult.calls.length === 0, "Expired proof reached GitHub");
  assert(git(staleProof.root, "rev-list", "--count", "HEAD") === "1", "Expired proof created a commit");

  const replacedProof = makeFixture("review-delivery-replaced-proof-");
  cleanup.push(replacedProof.root, replacedProof.remote);
  const reviewedProof = JSON.parse(fs.readFileSync(proofPath(replacedProof.root), "utf8"));
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 5);
  must(process.execPath, [path.join(replacedProof.root, ".codex", "hooks", "git-guard.cjs"),
    "prove", "--reviewed", "--check", "true"], { cwd: replacedProof.root });
  const replacementProof = JSON.parse(fs.readFileSync(proofPath(replacedProof.root), "utf8"));
  assert(replacementProof.created_at !== reviewedProof.created_at, "Replacement proof did not receive a distinct identity");
  const replacedProofResult = invoke(replacedProof, "clean");
  assert(replacedProofResult.result.status !== 0, "Delivery accepted a proof different from the one reviewers certified");
  assert(replacedProofResult.calls.length === 0, "Replacement proof reached GitHub");
  assert(git(replacedProof.root, "rev-list", "--count", "HEAD") === "1", "Replacement proof created a commit");

  const mismatch = makeFixture("review-delivery-mismatch-");
  cleanup.push(mismatch.root, mismatch.remote);
  const mismatched = invoke(mismatch, "head-mismatch");
  assert(mismatched.result.status !== 0, "Authoritative PR head mismatch was accepted");
  assert(!mismatched.calls.some((call) => call.args[0] === "pr" && call.args[1] === "merge"), "Mismatched PR reached merge");

  const ambiguous = makeFixture("review-delivery-ambiguous-pr-");
  cleanup.push(ambiguous.root, ambiguous.remote);
  const exactPull = invoke(ambiguous, "ambiguous-pr");
  assert(exactPull.result.status === 0, `Exact PR-number delivery failed:\n${exactPull.result.stdout}${exactPull.result.stderr}`);
  const viewedPulls = exactPull.calls.filter((call) => call.args[0] === "pr" && call.args[1] === "view");
  assert(viewedPulls.length > 0 && viewedPulls.every((call) => call.args[2] === "7"),
    "Delivery did not bind PR verification to the exact filtered pull-request number");

  const baseMismatch = makeFixture("review-delivery-base-mismatch-");
  cleanup.push(baseMismatch.root, baseMismatch.remote);
  const baseMismatched = invoke(baseMismatch, "base-mismatch");
  assert(baseMismatched.result.status !== 0, "Authoritative PR base mismatch was accepted");
  assert(!baseMismatched.calls.some((call) => call.args[0] === "pr" && call.args[1] === "merge"), "PR with a changed base reached merge");

  for (const mode of ["closed", "draft", "conflicting", "blocked", "unknown", "unstable"]) {
    const unready = makeFixture(`review-delivery-${mode}-`);
    cleanup.push(unready.root, unready.remote);
    const result = invoke(unready, mode);
    assert(result.result.status !== 0, `Delivery accepted a ${mode} PR`);
    assert(must("git", ["--git-dir", unready.remote, "rev-parse", "refs/heads/main"]) === unready.base,
      `Delivery advanced the base for a ${mode} PR`);
  }

  const blockedPending = makeFixture("review-delivery-blocked-pending-");
  cleanup.push(blockedPending.root, blockedPending.remote);
  const blockedPendingResult = invoke(blockedPending, "blocked-pending");
  assert(blockedPendingResult.result.status === 0,
    `Delivery did not wait through GitHub's BLOCKED-while-checks-pending state:\n${blockedPendingResult.result.stdout}${blockedPendingResult.result.stderr}`);
  const blockedPendingViews = blockedPendingResult.calls.filter((call) => call.args[0] === "pr" && call.args[1] === "view");
  assert(blockedPendingViews.length >= 2, "Delivery did not poll the blocked PR until required checks completed");

  const interrupted = makeFixture("review-delivery-post-push-failure-");
  const interruptionMarker = `${interrupted.remote}.post-push-failure`;
  cleanup.push(interrupted.root, interrupted.remote, interruptionMarker);
  const interruptedResult = invoke(interrupted, "post-push-observation-failure");
  assert(interruptedResult.result.status !== 0, "Simulated post-push observation failure did not interrupt delivery");
  const interruptedCommit = git(interrupted.root, "rev-parse", "HEAD");
  assert(must("git", ["--git-dir", interrupted.remote, "rev-parse", "refs/heads/main"]) === interruptedCommit,
    "Simulated failure occurred before the exact certified commit reached the base");
  const recoveredResult = invoke(interrupted, "post-push-observation-failure");
  assert(recoveredResult.result.status === 0,
    `Delivery did not recover an already-integrated certified commit:\n${recoveredResult.result.stdout}${recoveredResult.result.stderr}`);
  assert(git(interrupted.root, "rev-list", "--count", "HEAD") === "2", "Recovery created an extra commit");
  const recoveredReceipt = JSON.parse(fs.readFileSync(interrupted.receipt, "utf8"));
  assert(recoveredReceipt.delivery?.status === "integrated" && recoveredReceipt.delivery?.commit === interruptedCommit,
    "Recovery did not finalize the integrated delivery receipt");

  const unvalidated = makeFixture("review-delivery-unvalidated-base-");
  cleanup.push(unvalidated.root, unvalidated.remote);
  const directToBase = invoke(unvalidated, "clean", "direct", ["--branch", "main"]);
  assert(directToBase.result.status === 0, `Direct delivery to base failed:\n${directToBase.result.stdout}${directToBase.result.stderr}`);
  const launderingAttempt = invoke(unvalidated, "clean");
  assert(launderingAttempt.result.status !== 0, "GitHub delivery accepted an unvalidated commit already on the base");
  const unvalidatedReceipt = JSON.parse(fs.readFileSync(unvalidated.receipt, "utf8"));
  assert(unvalidatedReceipt.delivery?.status !== "integrated" || unvalidatedReceipt.delivery?.mode !== "github",
    "Unvalidated base update was laundered into an integrated GitHub receipt");

  const rewritten = makeFixture("review-delivery-rewritten-url-");
  cleanup.push(rewritten.root, rewritten.remote);
  git(rewritten.root, "config", `url.${rewritten.remote}.insteadOf`, "git@github.com:acme/project.git");
  const rewrittenResult = invoke(rewritten, "clean");
  assert(rewrittenResult.result.status !== 0, "Delivery accepted a Git URL rewrite to another repository");
  assert(git(rewritten.root, "rev-list", "--count", "HEAD") === "1", "URL rewrite created a commit before rejection");

  const race = makeFixture("review-delivery-race-");
  cleanup.push(race.root, race.remote);
  const raced = invoke(race, "base-race");
  assert(raced.result.status !== 0, "Advanced base was overwritten");
  assert(must("git", ["--git-dir", race.remote, "rev-parse", "refs/heads/main"]) !== git(race.root, "rev-parse", "HEAD"), "Base race landed an uncertified integration");

  const sameBranch = makeFixture("review-delivery-same-branch-");
  cleanup.push(sameBranch.root, sameBranch.remote);
  const same = invoke(sameBranch, "clean", "github", ["--branch", "main"]);
  assert(same.result.status !== 0, "GitHub delivery accepted identical head and base branches");
  assert(git(sameBranch.root, "rev-list", "--count", "HEAD") === "1", "Invalid branch equality created a commit");

  const remoteOption = makeFixture("review-delivery-remote-option-");
  cleanup.push(remoteOption.root, remoteOption.remote);
  const option = invoke(remoteOption, "clean", "direct", ["--remote", "--repo=attacker.invalid/repo.git"]);
  assert(option.result.status !== 0, "Direct delivery accepted a Git option as the remote");
  assert(git(remoteOption.root, "rev-list", "--count", "HEAD") === "1", "Invalid remote created a commit");

  const divergent = makeFixture("review-delivery-divergent-remote-");
  const divergentPush = `${divergent.root}.push.git`;
  cleanup.push(divergent.root, divergent.remote, divergentPush);
  must("git", ["init", "--bare", "-q", divergentPush]);
  git(divergent.root, "remote", "set-url", "--push", "origin", divergentPush);
  const diverged = invoke(divergent, "clean");
  assert(diverged.result.status !== 0, "GitHub delivery accepted divergent fetch and push targets");
  assert(git(divergent.root, "rev-list", "--count", "HEAD") === "1", "Divergent remote created a commit");

  const direct = makeFixture("review-delivery-direct-");
  cleanup.push(direct.root, direct.remote);
  const directResult = invoke(direct, "clean", "direct");
  assert(directResult.result.status === 0, `Direct delivery failed:\n${directResult.result.stdout}${directResult.result.stderr}`);
  const directCommit = git(direct.root, "rev-parse", "HEAD");
  assert(git(direct.root, "ls-remote", "origin", "refs/heads/feature").startsWith(directCommit), "Direct mode did not publish the exact certified commit");

  const extraRefs = makeFixture("review-delivery-extra-refs-");
  cleanup.push(extraRefs.root, extraRefs.remote);
  git(extraRefs.root, "tag", "-am", "unreviewed release tag", "unreviewed-release", "HEAD");
  git(extraRefs.root, "config", "push.followTags", "true");
  git(extraRefs.root, "config", "push.recurseSubmodules", "on-demand");
  const exactRefResult = invoke(extraRefs, "clean", "direct");
  assert(exactRefResult.result.status === 0,
    `Exact-ref delivery failed:\n${exactRefResult.result.stdout}${exactRefResult.result.stderr}`);
  assert(git(extraRefs.root, "ls-remote", "--tags", "origin") === "",
    "Delivery published an ambient annotated tag outside the certified ref");

  const linkedHost = makeFixture("review-delivery-linked-host-");
  const linked = `${linkedHost.root}-worktree`;
  cleanup.push(linkedHost.root, linkedHost.remote, linked);
  git(linkedHost.root, "reset", "--hard", "-q", "HEAD");
  git(linkedHost.root, "worktree", "add", "-qb", "linked", linked, "main");
  fs.writeFileSync(path.join(linked, "file.txt"), "linked candidate\n");
  git(linked, "add", "file.txt");
  const linkedBase = git(linked, "rev-parse", "HEAD");
  const linkedTree = git(linked, "write-tree");
  const linkedReceipt = receiptPath(linked);
  fs.mkdirSync(path.dirname(linkedReceipt), { recursive: true });
  must(process.execPath, [path.join(linked, ".codex", "hooks", "git-guard.cjs"), "prove", "--reviewed", "--check", "true"], { cwd: linked });
  const linkedProof = JSON.parse(fs.readFileSync(proofPath(linked), "utf8"));
  fs.writeFileSync(linkedReceipt, `${JSON.stringify({
    schema_version: 1,
    status: "certified",
    base_commit: linkedBase,
    head_before_commit: linkedBase,
    candidate_tree: linkedTree,
    patch_sha256: "sha256:test",
    proof_workspace_fingerprint: linkedProof.workspace_fingerprint,
    proof_created_at: linkedProof.created_at,
    reviewer_policy: "sol-high+fable-high/independent-cross-feed-on-split/v1",
    joint_verdict: "CERTIFIED",
  })}\n`);
  const linkedResult = invoke({ root: linked, remote: linkedHost.remote, base: linkedBase, tree: linkedTree }, "clean", "direct");
  assert(linkedResult.result.status === 0, `Linked-worktree delivery failed:\n${linkedResult.result.stdout}${linkedResult.result.stderr}`);
  const linkedCommit = git(linked, "rev-parse", "HEAD");
  assert(git(linked, "ls-remote", "origin", "refs/heads/feature").startsWith(linkedCommit), "Linked worktree did not publish the exact certified commit");

  process.stdout.write("review delivery tests passed\n");
} finally {
  for (const target of cleanup) fs.rmSync(target, { recursive: true, force: true });
}
