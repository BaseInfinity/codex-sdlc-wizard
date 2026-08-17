#!/usr/bin/env node
"use strict";

const assert = require("node:assert/strict");
const childProcess = require("node:child_process");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const {
  REVIEW_STATES,
  classifyReviewFailure,
  runSupervisedProcess,
  runWithInfrastructureRetry,
} = require("../.codex/hooks/dual-review.cjs");

async function testHealthySilenceProducesHeartbeat() {
  const heartbeats = [];
  const result = await runSupervisedProcess(process.execPath, [
    "-e",
    "setTimeout(() => process.stdout.write('done\\n'), 120)",
  ], {
    heartbeatInterval: 25,
    stallTimeout: 400,
    timeout: 800,
    onHeartbeat: (heartbeat) => heartbeats.push(heartbeat),
  });

  assert.equal(result.status, 0);
  assert.equal(result.timedOut, false);
  assert.ok(heartbeats.length >= 2, "silent healthy child should produce bounded heartbeats");
  assert.ok(heartbeats.every((entry) => entry.elapsed_ms >= 0 && !Object.hasOwn(entry, "output")));
}

async function testHardTimeoutReapsDescendantTree() {
  if (process.platform === "win32") return;
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "codex-sdlc-supervisor-test-"));
  const pidPath = path.join(directory, "descendant.pid");
  const source = [
    "const cp=require('node:child_process'),fs=require('node:fs');",
    "const child=cp.spawn(process.execPath,['-e','setInterval(()=>{},1000)'],{stdio:'ignore'});",
    `fs.writeFileSync(${JSON.stringify(pidPath)},String(child.pid));`,
    "setInterval(()=>{},1000);",
  ].join("");
  const result = await runSupervisedProcess(process.execPath, ["-e", source], {
    heartbeatInterval: 25,
    stallTimeout: 500,
    timeout: 120,
    killGrace: 50,
  });
  assert.equal(result.timedOut, true);
  assert.equal(result.terminal_state, REVIEW_STATES.TIMED_OUT);
  const descendantPid = Number(fs.readFileSync(pidPath, "utf8"));
  await new Promise((resolve) => setTimeout(resolve, 50));
  assert.throws(() => process.kill(descendantPid, 0), /ESRCH/);
  fs.rmSync(directory, { recursive: true, force: true });
}

async function testCancellationStopsReviewerAndRetainsPrivateLog() {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "codex-sdlc-supervisor-cancel-"));
  const logPath = path.join(directory, "review.log");
  const controller = new AbortController();
  const result = await runSupervisedProcess(process.execPath, [
    "-e",
    "process.stdout.write(JSON.stringify({type:'review.started'})+'\\n');setInterval(()=>{},1000)",
  ], {
    heartbeatInterval: 20,
    stallTimeout: 500,
    timeout: 800,
    killGrace: 30,
    logPath,
    signal: controller.signal,
    onEvent: () => controller.abort(),
  });

  assert.equal(result.cancelled, true);
  assert.equal(result.terminal_state, REVIEW_STATES.CANCELLED);
  assert.equal(result.last_event_type, "review.started");
  assert.match(fs.readFileSync(logPath, "utf8"), /review\.started/);
  assert.equal(fs.statSync(logPath).mode & 0o777, 0o600);
  fs.rmSync(directory, { recursive: true, force: true });
}

async function testUnstructuredChatterDoesNotFakeProgress() {
  const result = await runSupervisedProcess(process.execPath, [
    "-e",
    "setInterval(() => process.stdout.write('noise\\n'), 10)",
  ], {
    heartbeatInterval: 20,
    stallTimeout: 80,
    timeout: 500,
    killGrace: 30,
    structuredEventsRequired: true,
  });

  assert.equal(result.timedOut, true);
  assert.equal(result.timeout_reason, "stall");
  assert.equal(result.terminal_state, REVIEW_STATES.TIMED_OUT);
}

function testAuthAndInvalidVerdictClassification() {
  assert.equal(classifyReviewFailure({
    status: 1,
    stdout: "Authentication required. Run /login.",
    stderr: "",
  }), REVIEW_STATES.AUTH_OR_INPUT_BLOCKED);
  assert.equal(classifyReviewFailure({
    status: 0,
    stdout: "{not-json",
    stderr: "",
  }), REVIEW_STATES.INVALID_VERDICT);
}

async function testOneInfrastructureRetryOnly() {
  let calls = 0;
  const recovered = await runWithInfrastructureRetry(async () => {
    calls += 1;
    return calls === 1
      ? { terminal_state: REVIEW_STATES.PROVIDER_OR_TRANSPORT_FAILURE }
      : { terminal_state: REVIEW_STATES.CLEAN };
  });
  assert.equal(calls, 2);
  assert.equal(recovered.attempts.length, 2);
  assert.equal(recovered.terminal_state, REVIEW_STATES.CLEAN);
  assert.equal(recovered.attempts[0].retry_reason, REVIEW_STATES.PROVIDER_OR_TRANSPORT_FAILURE);
  assert.equal(recovered.attempts[1].retry_reason, undefined);

  calls = 0;
  const findings = await runWithInfrastructureRetry(async () => {
    calls += 1;
    return { terminal_state: REVIEW_STATES.FINDINGS };
  });
  assert.equal(calls, 1);
  assert.equal(findings.attempts.length, 1);
}

(async () => {
  await testHealthySilenceProducesHeartbeat();
  await testHardTimeoutReapsDescendantTree();
  await testCancellationStopsReviewerAndRetainsPrivateLog();
  await testUnstructuredChatterDoesNotFakeProgress();
  testAuthAndInvalidVerdictClassification();
  await testOneInfrastructureRetryOnly();
  process.stdout.write("review supervision tests passed\n");
})().catch((error) => {
  process.stderr.write(`${error.stack || error.message}\n`);
  process.exitCode = 1;
});
