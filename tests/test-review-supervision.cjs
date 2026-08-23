#!/usr/bin/env node
"use strict";

const assert = require("node:assert/strict");
const childProcess = require("node:child_process");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const {
  REVIEW_STATES,
  aggregatePartialOutcome,
  claudeToolFreeArgs,
  classifyAvailabilityProbe,
  classifyReviewFailure,
  independentPrompt,
  reconciliationPrompt,
  rejectClaudeReviewerToolUse,
  runSupervisedProcess,
  runWithInfrastructureRetry,
  validateClaudeReviewEvents,
  validateClaudeToolFreePreflight,
} = require("../.codex/hooks/dual-review.cjs");

const REVIEW_EVENT_FIXTURES = path.join(__dirname, "fixtures", "review-events");

function reviewEventFixture(name) {
  return JSON.parse(fs.readFileSync(path.join(REVIEW_EVENT_FIXTURES, name), "utf8"));
}

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

function realClaudeAdvisorEvent() {
  return reviewEventFixture("claude-advisor-tool-use.json");
}

function realClaudeBashEvent() {
  return reviewEventFixture("claude-bash-tool-use.json");
}

function realClaudeStructuredOutputEvent() {
  return {
    type: "assistant",
    message: {
      content: [{
        type: "tool_use",
        name: "StructuredOutput",
        input: { findings: [], verdict: "CERTIFIED", confidence: 92 },
        caller: { type: "direct" },
      }],
    },
  };
}

function testClaudeToolUseDetectorScansRealAssistantEnvelope() {
  assert.equal(
    rejectClaudeReviewerToolUse(realClaudeAdvisorEvent()),
    "forbidden reviewer tool use: advisor",
  );
  assert.equal(
    rejectClaudeReviewerToolUse(realClaudeBashEvent()),
    "forbidden reviewer tool use: Bash",
  );
}

function testClaudeToolUseDetectorScansArrayEnvelope() {
  assert.equal(
    rejectClaudeReviewerToolUse([
      realClaudeAdvisorEvent(),
      { type: "result", structured_output: { findings: [], verdict: "CERTIFIED", confidence: 99 } },
    ]),
    "forbidden reviewer tool use: advisor",
  );
}

function testClaudeToolUseDetectorRejectsEveryToolIncludingStructuredOutput() {
  assert.equal(
    rejectClaudeReviewerToolUse(realClaudeStructuredOutputEvent(), { allowStructuredOutput: true }),
    "forbidden reviewer tool use: StructuredOutput",
  );
  assert.equal(
    rejectClaudeReviewerToolUse(realClaudeStructuredOutputEvent()),
    "forbidden reviewer tool use: StructuredOutput",
  );
}

function testClaudeToolUseDetectorNormalizesNestedEventShapes() {
  assert.equal(
    rejectClaudeReviewerToolUse({
      wrapper: {
        event: {
          type: "Anthropic.ServerToolUse",
          name: "BASH",
        },
      },
    }),
    "forbidden reviewer tool use: BASH",
  );
}

function testClaudeLaunchIsToolFreeByConstruction() {
  const args = claudeToolFreeArgs({ model: "fable", effort: "high" });
  const valueAfter = (flag) => args[args.indexOf(flag) + 1];

  assert.equal(valueAfter("--setting-sources"), "");
  assert.equal(valueAfter("--tools"), "");
  assert.equal(valueAfter("--disallowedTools"), "*");
  assert.equal(valueAfter("--max-turns"), "1");
  assert.equal(valueAfter("--output-format"), "stream-json");
  assert.equal(valueAfter("--mcp-config"), '{"mcpServers":{}}');
  assert.ok(args.includes("--safe-mode"));
  assert.ok(args.includes("--strict-mcp-config"));
  assert.ok(args.includes("--disable-slash-commands"));
  assert.ok(args.includes("--no-session-persistence"));
  assert.ok(args.includes("--verbose"));
  assert.equal(args.includes("--json-schema"), false);
}

function toolFreePreflightOutput(overrides = {}) {
  const init = {
    type: "system",
    subtype: "init",
    model: "claude-fable-5",
    tools: [],
    ...overrides.init,
  };
  const result = {
    type: "result",
    model: "claude-fable-5",
    is_error: false,
    result: '{"tool_free":true}',
    ...overrides.result,
  };
  return `${JSON.stringify(init)}\n${JSON.stringify(result)}\n`;
}

function testClaudeToolFreePreflightRequiresEmptyInitAndExactResult() {
  const reviewer = { label: "Fable High", actualModel: /^(?:fable|claude-fable(?:-|$))/i };
  assert.deepEqual(validateClaudeToolFreePreflight(toolFreePreflightOutput(), reviewer), {
    actualModel: "claude-fable-5",
  });
  assert.throws(
    () => validateClaudeToolFreePreflight(toolFreePreflightOutput({ init: { tools: ["Bash"] } }), reviewer),
    /advertised built-in tools/i,
  );
  assert.throws(
    () => validateClaudeToolFreePreflight(toolFreePreflightOutput({ result: { result: '{"tool_free":true,"extra":1}' } }), reviewer),
    /tool-free acknowledgement/i,
  );
  assert.throws(
    () => validateClaudeToolFreePreflight(JSON.stringify({ type: "result", model: "claude-fable-5", result: '{"tool_free":true}' }), reviewer),
    /initialization envelope/i,
  );
}

function testReviewPromptsNameTheExactVerdictContract() {
  const binding = {
    baseCommit: "base-commit",
    headCommit: "head-commit",
    candidateTree: "candidate-tree",
    patchSha256: "sha256:patch",
  };
  const proof = { commands: ["proof command"], status: "passed" };
  const review = { findings: [], verdict: "CERTIFIED", confidence: 98 };
  const prompts = [
    independentPrompt("Fable High", binding, proof, Buffer.from("candidate patch")),
    reconciliationPrompt("Fable High", { name: "sol", review }, review, binding, proof, Buffer.from("candidate patch")),
  ].map(String);

  for (const prompt of prompts) {
    assert.match(prompt, /Set verdict to exactly "CERTIFIED" or "NOT CERTIFIED"/);
    assert.match(prompt, /Do not use aliases/);
    assert.match(prompt, /"CERTIFIED" only when there are no P0\/P1 findings/);
    assert.match(prompt, /"NOT CERTIFIED" whenever any P0\/P1 finding exists/);
  }
}

function testClaudeReviewRequiresExactPlainJsonContract() {
  const reviewer = { label: "Fable High", actualModel: /^(?:fable|claude-fable(?:-|$))/i };
  const review = { findings: [], verdict: "CERTIFIED", confidence: 98 };
  const output = (envelope) => JSON.stringify([
    { type: "system", subtype: "init", model: "claude-fable-5", tools: [] },
    { type: "result", model: "claude-fable-5", ...envelope },
  ]);

  assert.deepEqual(validateClaudeReviewEvents(output({ result: JSON.stringify(review) }), reviewer), {
    actualModel: "claude-fable-5",
    review,
  });
  assert.throws(
    () => validateClaudeReviewEvents(output({ structured_output: review }), reviewer),
    /plain-JSON review result/i,
  );
  assert.throws(
    () => validateClaudeReviewEvents(JSON.stringify([
      { type: "system", subtype: "init", model: "claude-fable-5", tools: ["Bash"] },
      { type: "result", model: "claude-fable-5", result: JSON.stringify(review) },
    ]), reviewer),
    /advertised built-in tools/i,
  );
  assert.throws(
    () => validateClaudeReviewEvents(JSON.stringify([
      { type: "system", subtype: "init", model: "claude-fable-5", tools: [] },
      { type: "system", subtype: "init", model: "claude-fable-5", tools: ["advisor"] },
      { type: "result", model: "claude-fable-5", result: JSON.stringify(review) },
    ]), reviewer),
    /advertised built-in tools/i,
  );
  assert.throws(
    () => validateClaudeReviewEvents(output({ result: JSON.stringify({ ...review, extra: true }) }), reviewer),
    /unexpected field/i,
  );
  // Alias rejection is the pre-existing fail-closed validator boundary; prompt guidance must not replace it.
  assert.throws(
    () => validateClaudeReviewEvents(output({ result: JSON.stringify({ ...review, verdict: "pass" }) }), reviewer),
    /invalid structured review/i,
  );
  assert.throws(
    () => validateClaudeReviewEvents(output({
      result: JSON.stringify({
        findings: [{ priority: "P2", title: "note", details: "detail", extra: true }],
        verdict: "CERTIFIED",
        confidence: 98,
      }),
    }), reviewer),
    /unexpected finding field/i,
  );
}

async function testRejectedToolUseCannotBecomeCleanResult() {
  const source = [
    "const forbidden={type:'assistant',message:{content:[{type:'server_tool_use',name:'advisor'}]}};",
    "const clean={type:'result',model:'fable',structured_output:{findings:[],verdict:'CERTIFIED',confidence:99}};",
    "process.on('SIGTERM',()=>process.exit(0));",
    "process.stdout.write(JSON.stringify(forbidden)+'\\n'+JSON.stringify(clean)+'\\n');",
    "setInterval(()=>{},1000);",
  ].join("");
  const result = await runSupervisedProcess(process.execPath, ["-e", source], {
    heartbeatInterval: 20,
    stallTimeout: 500,
    timeout: 800,
    killGrace: 30,
    structuredEventsRequired: true,
    rejectEvent: rejectClaudeReviewerToolUse,
  });

  assert.equal(result.timedOut, false);
  assert.equal(result.terminal_state, REVIEW_STATES.INVALID_VERDICT);
  assert.equal(result.rejected_event.reason, "forbidden reviewer tool use: advisor");
  assert.match(result.stdout, /\"verdict\":\"CERTIFIED\"/);
}

async function testRejectedFinalBufferCannotBecomeCleanResult() {
  const source = [
    "const forbidden={type:'assistant',message:{content:[{type:'server_tool_use',name:'advisor'}]}};",
    "const clean={type:'result',model:'fable',structured_output:{findings:[],verdict:'CERTIFIED',confidence:99}};",
    "process.stdout.write(JSON.stringify([forbidden,clean]));",
  ].join("");
  const result = await runSupervisedProcess(process.execPath, ["-e", source], {
    heartbeatInterval: 20,
    stallTimeout: 500,
    timeout: 800,
    killGrace: 30,
    structuredEventsRequired: true,
    rejectEvent: rejectClaudeReviewerToolUse,
  });

  assert.equal(result.timedOut, false);
  assert.equal(result.terminal_state, REVIEW_STATES.INVALID_VERDICT);
  assert.equal(result.rejected_event.reason, "forbidden reviewer tool use: advisor");
}

async function testRejectedToolUseOutranksTimeout() {
  const source = [
    "process.on('SIGTERM',()=>{});",
    "process.stdout.write(JSON.stringify({type:'assistant',message:{content:[{type:'server_tool_use',name:'advisor'}]}})+'\\n');",
    "setInterval(()=>{},1000);",
  ].join("");
  const result = await runSupervisedProcess(process.execPath, ["-e", source], {
    heartbeatInterval: 25,
    stallTimeout: 2000,
    timeout: 500,
    killGrace: 650,
    structuredEventsRequired: true,
    rejectEvent: rejectClaudeReviewerToolUse,
  });

  assert.equal(result.timedOut, true);
  assert.equal(result.timeout_reason, "wall");
  assert.equal(result.terminal_state, REVIEW_STATES.INVALID_VERDICT);
  assert.equal(result.rejected_event.reason, "forbidden reviewer tool use: advisor");
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

function testAvailabilityProbeUsesActualTerminalState() {
  assert.deepEqual(classifyAvailabilityProbe({
    status: 1,
    stdout: "Authentication required. Run /login.",
    stderr: "",
    terminal_state: REVIEW_STATES.AUTH_OR_INPUT_BLOCKED,
  }, "quota_exhausted"), {
    confirmed: false,
    classification: "auth",
  });
  assert.deepEqual(classifyAvailabilityProbe({
    status: 1,
    stdout: "",
    stderr: "Network connection failed.",
    terminal_state: REVIEW_STATES.PROVIDER_OR_TRANSPORT_FAILURE,
  }, "quota_exhausted"), {
    confirmed: false,
    classification: "invocation",
  });
  assert.deepEqual(classifyAvailabilityProbe({
    status: null,
    stdout: "quota exhausted",
    stderr: "",
    cancelled: true,
    terminal_state: REVIEW_STATES.CANCELLED,
  }, "quota_exhausted"), {
    confirmed: false,
    classification: "invocation",
  });
  assert.deepEqual(classifyAvailabilityProbe({
    status: 0,
    stdout: "available",
    stderr: "",
    terminal_state: REVIEW_STATES.CLEAN,
  }, "quota_exhausted"), {
    confirmed: false,
    classification: "invocation",
  });
}

function testAggregateRetryRequiresEveryCausalFailureToBeTransient() {
  const transientQuota = {
    completed: false,
    classification: "quota",
    infrastructure_failure: true,
    transient: true,
    retry: { recommended: true, guidance: "Retry after reviewer quota becomes available." },
    verdict: null,
    runtime: { terminal_state: REVIEW_STATES.PROVIDER_OR_TRANSPORT_FAILURE },
  };
  const invalidExecution = {
    completed: false,
    classification: "invalid_execution",
    infrastructure_failure: false,
    transient: false,
    retry: { recommended: false, guidance: null },
    verdict: null,
    runtime: { terminal_state: REVIEW_STATES.INVALID_VERDICT },
  };
  const cancelledPeer = {
    completed: false,
    classification: "invocation",
    infrastructure_failure: false,
    transient: false,
    retry: { recommended: false, guidance: null },
    verdict: null,
    runtime: { terminal_state: REVIEW_STATES.CANCELLED },
  };

  assert.deepEqual(
    aggregatePartialOutcome(transientQuota, { sol: transientQuota, cross_model: invalidExecution }, {}),
    { ...transientQuota, retry: { recommended: false, guidance: null } },
  );
  assert.deepEqual(
    aggregatePartialOutcome(transientQuota, { sol: transientQuota, cross_model: cancelledPeer }, {}),
    transientQuota,
  );
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
  testClaudeToolUseDetectorScansRealAssistantEnvelope();
  testClaudeToolUseDetectorScansArrayEnvelope();
  testClaudeToolUseDetectorRejectsEveryToolIncludingStructuredOutput();
  testClaudeToolUseDetectorNormalizesNestedEventShapes();
  testClaudeLaunchIsToolFreeByConstruction();
  testClaudeToolFreePreflightRequiresEmptyInitAndExactResult();
  testReviewPromptsNameTheExactVerdictContract();
  testClaudeReviewRequiresExactPlainJsonContract();
  await testRejectedToolUseCannotBecomeCleanResult();
  await testRejectedFinalBufferCannotBecomeCleanResult();
  await testRejectedToolUseOutranksTimeout();
  testAuthAndInvalidVerdictClassification();
  testAggregateRetryRequiresEveryCausalFailureToBeTransient();
  testAvailabilityProbeUsesActualTerminalState();
  await testOneInfrastructureRetryOnly();
  process.stdout.write("review supervision tests passed\n");
})().catch((error) => {
  process.stderr.write(`${error.stack || error.message}\n`);
  process.exitCode = 1;
});
