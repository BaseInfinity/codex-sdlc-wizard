#!/usr/bin/env node
const childProcess = require("node:child_process");
const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");

const PROOF_TTL_MS = 4 * 60 * 60 * 1000;
const PROOF_RELATIVE_PATH = "codex-sdlc/proof.json";
const WORKTREE_PROOF_PATH = ".codex-sdlc/proof.json";
const GIT_REPOSITORY_ENV_NAMES = new Set(["GIT_COMMON_DIR", "GIT_DIR", "GIT_WORK_TREE"]);

if (process.argv[2] === "prove") {
  process.exit(runProofCli(process.argv.slice(3)));
}

const input = fs.readFileSync(0, "utf8");
let payload = {};

if (input.trim() !== "") {
  try {
    payload = JSON.parse(input);
  } catch {
    process.exit(0);
  }
}

const command = String(payload?.tool_input?.command ?? payload?.command ?? "");
const commandCwd = commandWorkingDirectory(payload);
const MAX_RECURSION_DEPTH = 20;
const SHELL_NAMES = new Set(["bash", "dash", "fish", "ksh", "sh", "zsh"]);
const WINDOWS_SHELL_NAMES = new Set(["cmd", "powershell", "pwsh"]);

function block(reason) {
  process.stdout.write(JSON.stringify({ decision: "block", reason }));
}

function commandWorkingDirectory(inputPayload) {
  const value = inputPayload?.tool_input?.workdir
    ?? inputPayload?.tool_input?.cwd
    ?? inputPayload?.tool_input?.working_dir
    ?? inputPayload?.workdir
    ?? inputPayload?.cwd
    ?? inputPayload?.working_dir;

  if (typeof value !== "string" || value.trim() === "") {
    return process.cwd();
  }

  return path.resolve(process.cwd(), value);
}

function runGit(cwd, args) {
  const result = childProcess.spawnSync("git", ["-C", cwd, ...args], {
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
  });

  return {
    ok: result.status === 0,
    status: result.status,
    stdout: result.stdout || "",
    stderr: result.stderr || "",
  };
}

function repositoryRoot(cwd = process.cwd()) {
  const result = runGit(cwd, ["rev-parse", "--show-toplevel"]);
  if (!result.ok) {
    return "";
  }

  return result.stdout.trim();
}

function proofPath(root) {
  const result = runGit(root, ["rev-parse", "--git-path", PROOF_RELATIVE_PATH]);
  if (result.ok && result.stdout.trim() !== "") {
    return path.resolve(root, result.stdout.trim());
  }

  return path.join(root, ".git", PROOF_RELATIVE_PATH);
}

function safeProofCommand(value) {
  const command = String(value ?? "").trim();
  const missingCommand = command === ""
    || /^none$/i.test(command)
    || /^n\/a$/i.test(command)
    || /^unknown$/i.test(command)
    || /^<none>$/i.test(command);

  if (missingCommand) {
    return "";
  }

  return command;
}

function configuredProofCommands(root) {
  const manifestPath = path.join(root, ".codex-sdlc", "manifest.json");
  if (!fs.existsSync(manifestPath)) {
    return [];
  }

  try {
    const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
    const values = { ...(manifest.scan || {}), ...(manifest.resolved_values || {}) };
    return [
      safeProofCommand(values.test_command),
      safeProofCommand(values.lint_command),
      safeProofCommand(values.typecheck_command),
      safeProofCommand(values.build_command),
    ].filter(Boolean);
  } catch {
    return [];
  }
}

function proofHelp() {
  return [
    "Usage: node .codex/hooks/git-guard.cjs prove [--reviewed] [--check <command>...]",
    "",
    "Runs proof checks and writes a local SDLC proof stamp for git commit/push gates.",
    "When --check is omitted, commands are read from .codex-sdlc/manifest.json.",
    "Use --reviewed only after self-review is complete.",
  ].join("\n");
}

function parseProofArgs(args) {
  const checks = [];
  let reviewed = false;

  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];

    if (arg === "--help" || arg === "-h") {
      return { help: true, checks, reviewed };
    }

    if (arg === "--reviewed") {
      reviewed = true;
      continue;
    }

    if (arg === "--check") {
      const command = safeProofCommand(args[index + 1]);
      if (command === "") {
        return { error: "Missing value for --check" };
      }
      checks.push(command);
      index += 1;
      continue;
    }

    if (arg.startsWith("--check=")) {
      const command = safeProofCommand(arg.slice("--check=".length));
      if (command === "") {
        return { error: "Missing value for --check" };
      }
      checks.push(command);
      continue;
    }

    return { error: `Unknown prove argument: ${arg}` };
  }

  return { checks, reviewed };
}

function relativeFingerprintPath(root, relativePath) {
  const absolutePath = path.resolve(root, relativePath);
  const rootWithSeparator = root.endsWith(path.sep) ? root : `${root}${path.sep}`;

  if (absolutePath !== root && !absolutePath.startsWith(rootWithSeparator)) {
    return "";
  }

  return absolutePath;
}

function fileFingerprintEntry(root, relativePath) {
  if (relativePath === WORKTREE_PROOF_PATH) {
    return "";
  }

  const absolutePath = relativeFingerprintPath(root, relativePath);
  if (absolutePath === "") {
    return "";
  }

  let stat;
  try {
    stat = fs.lstatSync(absolutePath);
  } catch {
    return `missing ${relativePath}\n`;
  }

  if (stat.isSymbolicLink()) {
    return `symlink ${relativePath}\0${fs.readlinkSync(absolutePath)}\n`;
  }

  if (!stat.isFile()) {
    return "";
  }

  const mode = stat.mode & 0o777;
  const digest = crypto.createHash("sha256").update(fs.readFileSync(absolutePath)).digest("hex");
  return `file ${mode.toString(8)} ${relativePath}\0${digest}\n`;
}

function workspaceFingerprint(root) {
  const filesResult = runGit(root, ["ls-files", "-co", "--exclude-standard", "-z"]);
  if (!filesResult.ok) {
    return { ok: false, reason: "git file listing failed" };
  }

  const files = filesResult.stdout.split("\0").filter(Boolean).sort();
  const hash = crypto.createHash("sha256");
  let fileCount = 0;

  for (const relativePath of files) {
    const entry = fileFingerprintEntry(root, relativePath);
    if (entry === "") {
      continue;
    }
    fileCount += 1;
    hash.update(entry);
  }

  return {
    ok: true,
    fileCount,
    hash: `sha256:${hash.digest("hex")}`,
  };
}

function writeProof(root, checks, reviewed) {
  const fingerprint = workspaceFingerprint(root);
  if (!fingerprint.ok) {
    throw new Error(fingerprint.reason);
  }

  const now = new Date();
  const head = runGit(root, ["rev-parse", "HEAD"]);
  const proof = {
    schema_version: 1,
    status: "pass",
    created_at: now.toISOString(),
    expires_at: new Date(now.getTime() + PROOF_TTL_MS).toISOString(),
    reviewed,
    workspace_fingerprint: fingerprint.hash,
    file_count: fingerprint.fileCount,
    commands: checks,
    git: {
      head: head.ok ? head.stdout.trim() : "",
    },
  };
  const target = proofPath(root);
  fs.mkdirSync(path.dirname(target), { recursive: true });
  fs.writeFileSync(target, `${JSON.stringify(proof, null, 2)}\n`);
  return target;
}

function runProofCli(args) {
  const parsed = parseProofArgs(args);
  if (parsed.help) {
    process.stdout.write(`${proofHelp()}\n`);
    return 0;
  }
  if (parsed.error) {
    process.stderr.write(`${parsed.error}\n${proofHelp()}\n`);
    return 2;
  }

  const root = repositoryRoot();
  if (root === "") {
    process.stderr.write("Cannot write SDLC proof outside a git worktree.\n");
    return 2;
  }

  const checks = parsed.checks.length > 0 ? parsed.checks : configuredProofCommands(root);
  if (checks.length === 0) {
    process.stderr.write("No proof checks configured. Pass --check <command> or run setup first.\n");
    return 2;
  }

  for (const check of checks) {
    process.stdout.write(`Running SDLC proof check: ${check}\n`);
    const result = childProcess.spawnSync(check, {
      cwd: root,
      shell: true,
      stdio: "inherit",
    });

    if (result.status !== 0) {
      process.stderr.write(`SDLC proof check failed: ${check}\n`);
      return typeof result.status === "number" ? result.status : 1;
    }
  }

  try {
    const target = writeProof(root, checks, parsed.reviewed);
    process.stdout.write(`Wrote SDLC proof: ${target}\n`);
    return 0;
  } catch (error) {
    process.stderr.write(`Failed to write SDLC proof: ${error.message}\n`);
    return 2;
  }
}

function proofCommandHint(root) {
  const checks = configuredProofCommands(root);
  if (checks.length === 0) {
    return "Run node .codex/hooks/git-guard.cjs prove --reviewed --check \"<full-suite command>\".";
  }

  return "Run node .codex/hooks/git-guard.cjs prove --reviewed.";
}

function sdlcProofStatus(cwd = process.cwd()) {
  const root = repositoryRoot(cwd);
  if (root === "") {
    return {
      ok: false,
      reason: "no git worktree was detected",
      hint: "Run this from the repo root.",
    };
  }

  const target = proofPath(root);
  if (!fs.existsSync(target)) {
    return { ok: false, reason: "proof is missing", hint: proofCommandHint(root) };
  }

  let proof;
  try {
    proof = JSON.parse(fs.readFileSync(target, "utf8"));
  } catch {
    return { ok: false, reason: "proof is invalid", hint: proofCommandHint(root) };
  }

  if (proof.status !== "pass") {
    return { ok: false, reason: "proof did not pass", hint: proofCommandHint(root) };
  }

  if (proof.reviewed !== true) {
    return {
      ok: false,
      reason: "proof is missing self-review",
      hint: "Re-run proof with --reviewed after self-review.",
    };
  }

  const expiresAt = Date.parse(String(proof.expires_at || ""));
  if (!Number.isFinite(expiresAt) || expiresAt <= Date.now()) {
    return { ok: false, reason: "proof is expired", hint: proofCommandHint(root) };
  }

  const fingerprint = workspaceFingerprint(root);
  if (!fingerprint.ok) {
    return { ok: false, reason: fingerprint.reason, hint: proofCommandHint(root) };
  }

  if (proof.workspace_fingerprint !== fingerprint.hash) {
    return { ok: false, reason: "proof is stale", hint: proofCommandHint(root) };
  }

  return { ok: true, reason: "fresh proof is present", hint: "" };
}

function isRedirectionOperatorPrefix(value) {
  return /^(?:(?:&>>?)|(?:\d+)?(?:<<<|<<-?|<>|>>|>\||[<>]&|>|<))$/.test(value);
}

function executableName(word) {
  return String(word ?? "").replace(/\\/g, "/").split("/").pop().replace(/\.exe$/i, "").toLowerCase();
}

function safeFromCodePoint(value) {
  if (!Number.isInteger(value) || value < 0 || value > 0x10ffff) {
    return "";
  }

  return String.fromCodePoint(value);
}

function decodeAnsiCString(content) {
  let decoded = "";

  for (let index = 0; index < content.length; index += 1) {
    const char = content[index];

    if (char !== "\\") {
      decoded += char;
      continue;
    }

    const nextChar = content[index + 1];

    if (nextChar === undefined) {
      decoded += "\\";
      continue;
    }

    if (/[0-7]/.test(nextChar)) {
      const match = content.slice(index + 1).match(/^[0-7]{1,3}/)[0];
      decoded += safeFromCodePoint(Number.parseInt(match, 8));
      index += match.length;
      continue;
    }

    if (nextChar === "x") {
      const match = content.slice(index + 2).match(/^[0-9A-Fa-f]{1,2}/)?.[0] ?? "";
      if (match !== "") {
        decoded += safeFromCodePoint(Number.parseInt(match, 16));
        index += match.length + 1;
        continue;
      }
    }

    if (nextChar === "u" || nextChar === "U") {
      const maxLength = nextChar === "u" ? 4 : 8;
      const match = content.slice(index + 2).match(new RegExp(`^[0-9A-Fa-f]{1,${maxLength}}`))?.[0] ?? "";
      if (match !== "") {
        decoded += safeFromCodePoint(Number.parseInt(match, 16));
        index += match.length + 1;
        continue;
      }
    }

    if (nextChar === "c" && content[index + 2] !== undefined) {
      decoded += safeFromCodePoint(content[index + 2].toUpperCase().charCodeAt(0) & 0x1f);
      index += 2;
      continue;
    }

    const simpleEscapes = {
      a: "\x07",
      b: "\b",
      e: "\x1b",
      E: "\x1b",
      f: "\f",
      n: "\n",
      r: "\r",
      t: "\t",
      v: "\v",
      "\\": "\\",
      "'": "'",
      "\"": "\"",
      "?": "?",
    };

    decoded += simpleEscapes[nextChar] ?? nextChar;
    index += 1;
  }

  return decoded;
}

function collectAnsiCString(text, startIndex) {
  let content = "";
  let escaping = false;

  for (let index = startIndex; index < text.length; index += 1) {
    const char = text[index];

    if (escaping) {
      content += `\\${char}`;
      escaping = false;
      continue;
    }

    if (char === "\\") {
      escaping = true;
      continue;
    }

    if (char === "'") {
      return { content: decodeAnsiCString(content), endIndex: index };
    }

    content += char;
  }

  if (escaping) {
    content += "\\";
  }

  return { content: decodeAnsiCString(content), endIndex: text.length - 1 };
}

function renderedCommandSubstitutionText(content) {
  const rendered = commandSubstitutionLiteralPayload(content);

  return rendered ?? `$(${content})`;
}

function renderedBacktickSubstitutionText(content) {
  const rendered = commandSubstitutionLiteralPayload(content);

  return rendered ?? `\`${content}\``;
}

function shellTokens(text) {
  const tokens = [];
  let current = "";
  let quote = "";
  let escaping = false;

  function pushWord() {
    if (current !== "") {
      tokens.push({ type: "word", value: current });
      current = "";
    }
  }

  function appendRendered(value, splitFields) {
    if (!splitFields) {
      current += value;
      return;
    }

    for (const part of String(value).split(/(\s+)/)) {
      if (part === "") {
        continue;
      }

      if (/^\s+$/.test(part)) {
        pushWord();
      } else {
        current += part;
      }
    }
  }

  for (let index = 0; index < text.length; index += 1) {
    const char = text[index];
    const nextChar = text[index + 1];

    if (escaping) {
      if (char === "\n" || char === "\r") {
        if (char === "\r" && text[index + 1] === "\n") {
          index += 1;
        }

        escaping = false;
        continue;
      }

      current += char;
      escaping = false;
      continue;
    }

    if (char === "\\" && quote === '"' && nextChar !== "$" && nextChar !== "`" && nextChar !== '"' && nextChar !== "\\" && nextChar !== "\n" && nextChar !== "\r") {
      current += char;
      continue;
    }

    if (char === "\\" && quote !== "'") {
      escaping = true;
      continue;
    }

    if (quote !== "") {
      if (char === quote) {
        quote = "";
      } else if (quote === "\"" && char === "$" && nextChar === "(") {
        const substitution = collectCommandSubstitution(text, index + 2);
        appendRendered(renderedCommandSubstitutionText(substitution.content), false);
        index = substitution.endIndex;
      } else if (quote === "\"" && char === "`") {
        const substitution = collectBacktickSubstitution(text, index + 1);
        appendRendered(renderedBacktickSubstitutionText(substitution.content), false);
        index = substitution.endIndex;
      } else {
        current += char;
      }
      continue;
    }

    if (char === "$" && nextChar === "'") {
      const ansiString = collectAnsiCString(text, index + 2);
      current += ansiString.content;
      index = ansiString.endIndex;
      continue;
    }

    if (char === "$" && nextChar === "(") {
      const substitution = collectCommandSubstitution(text, index + 2);
      appendRendered(renderedCommandSubstitutionText(substitution.content), !isRedirectionOperatorPrefix(current));
      index = substitution.endIndex;
      continue;
    }

    if (char === "`") {
      const substitution = collectBacktickSubstitution(text, index + 1);
      appendRendered(renderedBacktickSubstitutionText(substitution.content), !isRedirectionOperatorPrefix(current));
      index = substitution.endIndex;
      continue;
    }

    if (char === "'" || char === '"') {
      quote = char;
      continue;
    }

    if (char === "\n" || char === "\r") {
      pushWord();
      tokens.push({ type: "operator", value: char });
      continue;
    }

    if (/\s/.test(char)) {
      pushWord();
      continue;
    }

    if (char === "#" && current === "") {
      while (index + 1 < text.length && text[index + 1] !== "\n" && text[index + 1] !== "\r") {
        index += 1;
      }
      continue;
    }

    if (char === "(" && current !== "" && current !== "$") {
      current += char;
      continue;
    }

    if (char === ";" || char === "(" || char === ")") {
      pushWord();
      tokens.push({ type: "operator", value: char });
      continue;
    }

    if (char === "&" && nextChar === ">" && current !== "" && !/^(?:\d+)?[<>]$/.test(current)) {
      pushWord();
      current += char;
      continue;
    }

    if ((char === "<" || char === ">") && current !== "" && !/^(?:&>?|\d+|\d*[<>]+)$/.test(current)) {
      pushWord();
      current += char;
      continue;
    }

    if ((char === "&" && (nextChar === ">" || /^(?:\d+)?[<>]$/.test(current))) || (char === "|" && /^(?:\d+)?>$/.test(current))) {
      current += char;
      continue;
    }

    if (char === "|" && nextChar === "&") {
      pushWord();
      tokens.push({ type: "operator", value: "|" });
      index += 1;
      continue;
    }

    if ((char === "&" && nextChar === "&") || (char === "|" && nextChar === "|")) {
      pushWord();
      tokens.push({ type: "operator", value: `${char}${nextChar}` });
      index += 1;
      continue;
    }

    if (char === "|" || char === "&") {
      pushWord();
      tokens.push({ type: "operator", value: char });
      continue;
    }

    current += char;
  }

  pushWord();

  return tokens;
}

function commandSegments(tokens) {
  return commandSegmentsWithOperators(tokens).map((segment) => segment.words);
}

function commandSegmentsWithOperators(tokens) {
  const segments = [];
  let words = [];
  let beforeOperator = "";

  for (const token of tokens) {
    if (token.type === "operator") {
      if (words.length > 0) {
        segments.push({ words, beforeOperator, afterOperator: token.value });
        words = [];
      } else if (segments.length > 0) {
        segments[segments.length - 1].afterOperator = token.value;
      }

      beforeOperator = token.value;
    } else {
      words.push(token.value);
    }
  }

  if (words.length > 0) {
    segments.push({ words, beforeOperator, afterOperator: "" });
  }

  return segments;
}

function commandReadsShellFromStdin(commandText, depth = 0) {
  if (depth > 5) {
    return false;
  }

  for (const segment of commandSegments(shellTokens(commandText))) {
    const envPayload = envSplitStringPayload(segment);

    if (envPayload !== null && commandReadsShellFromStdin(envPayload, depth + 1)) {
      return true;
    }

    const executableIndex = firstExecutableIndex(segment);

    if (executableIndex >= 0 && SHELL_NAMES.has(executableName(segment[executableIndex]))) {
      return true;
    }
  }

  return false;
}

function heredocFeedsShell(commandSuffix) {
  if (commandReadsShellFromStdin(commandSuffix)) {
    return true;
  }

  return processSubstitutionTexts(commandSuffix).some((substitutionText) => commandReadsShellFromStdin(substitutionText));
}

function heredocPattern() {
  return /<<-?\s*(?:"([^"]+)"|'([^']+)'|([^\s;|&()<>]+))/g;
}

function shellQuoteRemove(text) {
  let output = "";
  let quote = "";
  let escaping = false;

  for (let index = 0; index < String(text).length; index += 1) {
    const char = String(text)[index];

    if (escaping) {
      output += char;
      escaping = false;
      continue;
    }

    if (char === "\\" && quote !== "'") {
      escaping = true;
      continue;
    }

    if (quote !== "") {
      if (char === quote) {
        quote = "";
      } else {
        output += char;
      }
      continue;
    }

    if (char === "'" || char === '"') {
      quote = char;
      continue;
    }

    output += char;
  }

  if (escaping) {
    output += "\\";
  }

  return output;
}

function heredocDelimiter(match) {
  if (match[1] !== undefined) {
    return match[1];
  }

  if (match[2] !== undefined) {
    return match[2];
  }

  return shellQuoteRemove(match[3]);
}

function shellCommentStartIndex(text) {
  let quote = "";
  let escaping = false;

  for (let index = 0; index < text.length; index += 1) {
    const char = text[index];

    if (escaping) {
      escaping = false;
      continue;
    }

    if (char === "\\" && quote !== "'") {
      escaping = true;
      continue;
    }

    if (quote !== "") {
      if (char === quote) {
        quote = "";
      }
      continue;
    }

    if (char === "'" || char === '"') {
      quote = char;
      continue;
    }

    if (char === "#" && (index === 0 || /\s|[;&|()]/.test(text[index - 1]))) {
      return index;
    }
  }

  return text.length;
}

function stripHeredocBodies(text, options = {}) {
  const quotedOnly = options.quotedOnly === true;
  const lines = text.split(/\r?\n/);
  const pendingDelimiters = [];

  return lines.map((line) => {
    if (pendingDelimiters.length > 0) {
      const trimmedLine = line.trim();
      const delimiterIndex = pendingDelimiters.indexOf(trimmedLine);

      if (delimiterIndex >= 0) {
        pendingDelimiters.splice(delimiterIndex, 1);
      }

      return "";
    }

    const activeLine = line.slice(0, shellCommentStartIndex(line));
    const pattern = heredocPattern();
    let match = pattern.exec(activeLine);

    while (match) {
      const commandPrefix = activeLine.slice(0, match.index);
      const commandSuffix = activeLine.slice(match.index + match[0].length);
      const quotedDelimiter = match[1] !== undefined || match[2] !== undefined;
      const feedsShell = heredocFeedsShell(`${commandPrefix} ${commandSuffix}`);
      const catProducer = /(^|[\s;&|()])cat([\s;&|()]|$)/.test(commandPrefix);

      if (!feedsShell && (quotedDelimiter || (!quotedOnly && catProducer))) {
        pendingDelimiters.push(heredocDelimiter(match));
      }

      match = pattern.exec(activeLine);
    }

    return line;
  }).join("\n");
}

function activeCasePattern(content) {
  let caseDepth = 0;
  let waitingForIn = false;

  for (const match of content.matchAll(/\b(case|esac|in)\b/g)) {
    if (match[1] === "case") {
      caseDepth += 1;
      waitingForIn = true;
      continue;
    }

    if (match[1] === "in" && caseDepth > 0 && waitingForIn) {
      waitingForIn = false;
      continue;
    }

    if (match[1] === "esac" && caseDepth > 0) {
      caseDepth -= 1;
      waitingForIn = false;
    }
  }

  return caseDepth > 0 && !waitingForIn;
}

function collectCommandSubstitution(text, startIndex) {
  let content = "";
  let quote = "";
  let escaping = false;
  let depth = 1;

  for (let index = startIndex; index < text.length; index += 1) {
    const char = text[index];
    const nextChar = text[index + 1];

    if (escaping) {
      content += char;
      escaping = false;
      continue;
    }

    if (char === "\\" && quote !== "'") {
      content += char;
      escaping = true;
      continue;
    }

    if (quote === "'") {
      if (char === "'") {
        quote = "";
      }
      content += char;
      continue;
    }

    if (char === "'" && quote === "") {
      quote = char;
      content += char;
      continue;
    }

    if (char === '"') {
      quote = quote === '"' ? "" : '"';
      content += char;
      continue;
    }

    if (char === "$" && nextChar === "(") {
      depth += 1;
      content += "$(";
      index += 1;
      continue;
    }

    if (char === "(" && quote === "") {
      depth += 1;
      content += char;
      continue;
    }

    if (char === ")" && quote === "") {
      if (activeCasePattern(content)) {
        content += char;
        continue;
      }

      depth -= 1;

      if (depth === 0) {
        return { content, endIndex: index };
      }

      content += char;
      continue;
    }

    content += char;
  }

  return { content, endIndex: text.length - 1 };
}

function commandSubstitutionTexts(text) {
  const substitutions = [];
  let quote = "";
  let escaping = false;

  for (let index = 0; index < text.length; index += 1) {
    const char = text[index];
    const nextChar = text[index + 1];

    if (escaping) {
      escaping = false;
      continue;
    }

    if (char === "\\" && quote !== "'") {
      escaping = true;
      continue;
    }

    if (quote === "'") {
      if (char === "'") {
        quote = "";
      }
      continue;
    }

    if (char === "'" && quote === "") {
      quote = char;
      continue;
    }

    if (char === '"') {
      quote = quote === '"' ? "" : '"';
      continue;
    }

    if (char === "$" && nextChar === "(") {
      const substitution = collectCommandSubstitution(text, index + 2);
      substitutions.push(substitution.content);
      index = substitution.endIndex;
    }
  }

  return substitutions;
}

function processSubstitutionTexts(text) {
  return processSubstitutionDetails(text).map((substitution) => substitution.content);
}

function processSubstitutionDetails(text) {
  const substitutions = [];
  let quote = "";
  let escaping = false;

  for (let index = 0; index < text.length; index += 1) {
    const char = text[index];
    const nextChar = text[index + 1];

    if (escaping) {
      escaping = false;
      continue;
    }

    if (char === "\\" && quote !== "'") {
      escaping = true;
      continue;
    }

    if (quote !== "") {
      if (char === quote) {
        quote = "";
      }
      continue;
    }

    if (char === "'" || char === '"') {
      quote = char;
      continue;
    }

    if ((char === "<" || char === ">") && nextChar === "(") {
      const substitution = collectCommandSubstitution(text, index + 2);
      substitutions.push({
        content: substitution.content,
        endIndex: substitution.endIndex,
        operator: char,
        startIndex: index,
      });
      index = substitution.endIndex;
    }
  }

  return substitutions;
}

function backtickSubstitutionTexts(text) {
  const substitutions = [];
  let quote = "";
  let escaping = false;

  for (let index = 0; index < text.length; index += 1) {
    const char = text[index];

    if (escaping) {
      escaping = false;
      continue;
    }

    if (char === "\\" && quote !== "'") {
      escaping = true;
      continue;
    }

    if (quote === "'") {
      if (char === "'") {
        quote = "";
      }
      continue;
    }

    if (char === "'" && quote === "") {
      quote = char;
      continue;
    }

    if (char === '"') {
      quote = quote === '"' ? "" : '"';
      continue;
    }

    if (char !== "`") {
      continue;
    }

    let content = "";
    let backtickEscaping = false;
    for (let endIndex = index + 1; endIndex < text.length; endIndex += 1) {
      const nextChar = text[endIndex];

      if (backtickEscaping) {
        content += nextChar;
        backtickEscaping = false;
        continue;
      }

      if (nextChar === "\\") {
        content += nextChar;
        backtickEscaping = true;
        continue;
      }

      if (nextChar === "`") {
        substitutions.push(content);
        index = endIndex;
        break;
      }

      content += nextChar;
    }
  }

  return substitutions;
}

function collectBacktickSubstitution(text, startIndex) {
  let content = "";
  let escaping = false;

  for (let index = startIndex; index < text.length; index += 1) {
    const char = text[index];

    if (escaping) {
      content += char;
      escaping = false;
      continue;
    }

    if (char === "\\") {
      content += char;
      escaping = true;
      continue;
    }

    if (char === "`") {
      return { content, endIndex: index };
    }

    content += char;
  }

  return { content, endIndex: text.length - 1 };
}

function executableSubstitutionTexts(text) {
  return [
    ...commandSubstitutionTexts(text),
    ...processSubstitutionTexts(text),
    ...backtickSubstitutionTexts(text),
  ];
}

function mentionedGuardedGitSubcommand(text) {
  for (const words of commandSegments(shellTokens(text))) {
    for (let index = 0; index < words.length; index += 1) {
      if (executableName(words[index]) !== "git") {
        continue;
      }

      const subcommandDetails = gitSubcommandDetails(words, index + 1);
      const subcommand = subcommandDetails.subcommand;

      if ((subcommand === "commit" || subcommand === "push") && !gitSubcommandRequestsHelp(words, subcommandDetails.index + 1, subcommand)) {
        return subcommand;
      }
    }
  }

  return "";
}

function mentionedGuardedGitInSubstitutions(text) {
  for (const substitutionText of [
    ...commandSubstitutionTexts(text),
    ...backtickSubstitutionTexts(text),
  ]) {
    const subcommand = mentionedGuardedGitSubcommand(substitutionText);

    if (subcommand) {
      return subcommand;
    }
  }

  return "";
}

function commandSuffixAfterSubstitution(text, startIndex) {
  let suffix = "";
  let quote = "";
  let escaping = false;

  for (let index = startIndex; index < text.length; index += 1) {
    const char = text[index];

    if (escaping) {
      suffix += char;
      escaping = false;
      continue;
    }

    if (char === "\\" && quote !== "'") {
      suffix += char;
      escaping = true;
      continue;
    }

    if (quote !== "") {
      if (char === quote) {
        quote = "";
      } else {
        suffix += char;
      }
      continue;
    }

    if (char === "'" || char === '"') {
      quote = char;
      continue;
    }

    if (char === ";" || char === "|" || char === "&" || char === ")" || char === "\n" || char === "\r") {
      break;
    }

    suffix += char;
  }

  return suffix.trim();
}

function rawCommandSuffixAfterSubstitution(text, startIndex) {
  let suffix = "";
  let quote = "";
  let escaping = false;

  for (let index = startIndex; index < text.length; index += 1) {
    const char = text[index];

    if (escaping) {
      suffix += char;
      escaping = false;
      continue;
    }

    if (char === "\\" && quote !== "'") {
      suffix += char;
      escaping = true;
      continue;
    }

    if (quote !== "") {
      suffix += char;
      if (char === quote) {
        quote = "";
      }
      continue;
    }

    if (char === "'" || char === '"') {
      quote = char;
      suffix += char;
      continue;
    }

    if (char === ";" || char === "|" || char === "&" || char === ")" || char === "\n" || char === "\r") {
      break;
    }

    suffix += char;
  }

  return suffix.trim();
}

function commandPositionSubstitutionPayloads(commandText) {
  const payloads = [];
  let quote = "";
  let escaping = false;
  let atCommandStart = true;

  for (let index = 0; index < commandText.length; index += 1) {
    const char = commandText[index];
    const nextChar = commandText[index + 1];

    if (escaping) {
      escaping = false;
      atCommandStart = false;
      continue;
    }

    if (char === "\\" && quote !== "'") {
      escaping = true;
      continue;
    }

    if (quote !== "") {
      if (char === quote) {
        quote = "";
      }
      continue;
    }

    if (char === "'" || char === '"') {
      quote = char;
      atCommandStart = false;
      continue;
    }

    if (/\s/.test(char)) {
      continue;
    }

    if (char === ";" || char === "|" || char === "&" || char === "(" || char === ")" || char === "\n" || char === "\r") {
      atCommandStart = true;
      continue;
    }

    if (atCommandStart && char === "$" && nextChar === "(") {
      const substitution = collectCommandSubstitution(commandText, index + 2);
      const rendered = commandSubstitutionLiteralPayload(substitution.content) ?? substitution.content;
      const suffix = commandSuffixAfterSubstitution(commandText, substitution.endIndex + 1);
      payloads.push([rendered, suffix].filter(Boolean).join(" "));
      index = substitution.endIndex;
      atCommandStart = false;
      continue;
    }

    if (atCommandStart && char === "`") {
      const substitution = collectBacktickSubstitution(commandText, index + 1);
      const rendered = commandSubstitutionLiteralPayload(substitution.content) ?? substitution.content;
      const suffix = commandSuffixAfterSubstitution(commandText, substitution.endIndex + 1);
      payloads.push([rendered, suffix].filter(Boolean).join(" "));
      index = substitution.endIndex;
      atCommandStart = false;
      continue;
    }

    atCommandStart = false;
  }

  return payloads;
}

function isAssignment(word) {
  return /^[A-Za-z_][A-Za-z0-9_]*(?:\[[^\]]+\])?(?:\+)?=.*/.test(word);
}

function skipAssignments(words, index) {
  let nextIndex = index;

  while (nextIndex < words.length && isAssignment(words[nextIndex])) {
    nextIndex += 1;
  }

  return nextIndex;
}

function redirectionDetails(words, index) {
  const match = words[index]?.match(/^((?:&>>?)|(?:\d+)?(?:<<<|<<-?|<>|>>|>\||[<>]&|>|<))(.*)$/);

  if (!match) {
    return null;
  }

  const attachedOperand = match[2] ?? "";

  return {
    operator: match[1] ?? "",
    operand: attachedOperand === "" ? words[index + 1] ?? "" : attachedOperand,
    nextIndex: attachedOperand === "" ? index + 2 : index + 1,
  };
}

function redirectionFd(operator, fallbackFd) {
  const match = String(operator ?? "").match(/^(\d+)/);
  return match ? match[1] : fallbackFd;
}

function redirectionReceivesStdout(operator) {
  return /^(?:(?:1)?(?:>\|?|>>)|&>>?)$/.test(String(operator ?? ""));
}

function skipRedirection(words, index) {
  const details = redirectionDetails(words, index);

  if (!details) {
    return index;
  }

  return details.nextIndex;
}

function nextArgumentIndex(words, index) {
  let nextIndex = index;

  while (nextIndex < words.length) {
    const redirectionIndex = skipRedirection(words, nextIndex);

    if (redirectionIndex === nextIndex) {
      return nextIndex;
    }

    nextIndex = redirectionIndex;
  }

  return nextIndex;
}

function optionOperand(words, index) {
  const operandIndex = nextArgumentIndex(words, index);

  return {
    index: operandIndex,
    value: operandIndex < words.length ? words[operandIndex] : "",
  };
}

function indexAfterOptionOperand(words, index) {
  const operand = optionOperand(words, index);

  return operand.index < words.length ? operand.index + 1 : operand.index;
}

function shortClusterValueOperand(word, optionsWithValues) {
  if (!/^-[^-].+/.test(word)) {
    return "";
  }

  const valueOptionNames = new Set(
    [...optionsWithValues]
      .filter((option) => /^-[A-Za-z0-9]$/.test(option))
      .map((option) => option[1])
  );

  for (let index = 1; index < word.length; index += 1) {
    if (valueOptionNames.has(word[index])) {
      return index === word.length - 1 ? "next" : "attached";
    }
  }

  return "";
}

function skipWrapperOptions(words, index, optionsWithValues, longOptionsWithValues) {
  let nextIndex = index;

  while (nextIndex < words.length && words[nextIndex].startsWith("-")) {
    const word = words[nextIndex];
    const clusterValueOperand = shortClusterValueOperand(word, optionsWithValues);
    const shortOption = [...optionsWithValues].find((option) => option.length === 2 && word.startsWith(option) && word !== option);

    if (clusterValueOperand === "attached") {
      nextIndex += 1;
      continue;
    }

    if (clusterValueOperand === "next") {
      nextIndex = indexAfterOptionOperand(words, nextIndex + 1);
      continue;
    }

    if (shortOption) {
      nextIndex += 1;
      continue;
    }

    if (optionsWithValues.has(word)) {
      nextIndex = indexAfterOptionOperand(words, nextIndex + 1);
      continue;
    }

    if ([...longOptionsWithValues].some((option) => word.startsWith(`${option}=`))) {
      nextIndex += 1;
      continue;
    }

    if (longOptionsWithValues.has(word)) {
      nextIndex = indexAfterOptionOperand(words, nextIndex + 1);
      continue;
    }

    nextIndex += 1;
  }

  return nextIndex;
}

function envShortSplitStringPayload(word, restWords) {
  if (!/^-[^-].+/.test(word)) {
    return null;
  }

  const splitIndex = word.indexOf("S", 1);

  if (splitIndex < 0) {
    return null;
  }

  if (splitIndex === word.length - 1) {
    return restWords.join(" ");
  }

  return [word.slice(splitIndex + 1), ...restWords].join(" ");
}

function envSplitStringCommandText(payload) {
  return `env ${payload}`.trim();
}

function prefixedExecutableIndex(words, stopBeforeNames = new Set()) {
  const transparentShellWords = new Set(["!", "{", "builtin", "command", "coproc", "do", "elif", "else", "eval", "exec", "if", "nocorrect", "noglob", "nohup", "sudo", "then", "time", "until", "while"]);
  const wrapperOptionOperands = new Map([
    ["arch", {
      short: new Set([]),
      long: new Set([]),
    }],
    ["chrt", {
      short: new Set([]),
      long: new Set([]),
    }],
    ["doas", {
      short: new Set(["-C", "-u"]),
      long: new Set([]),
    }],
    ["env", {
      short: new Set(["-a", "-C", "-P", "-u"]),
      long: new Set(["--argv0", "--chdir", "--unset"]),
    }],
    ["exec", {
      short: new Set(["-a"]),
      long: new Set([]),
    }],
    ["ionice", {
      short: new Set(["-c", "-n", "-p"]),
      long: new Set(["--class", "--classdata", "--pid"]),
    }],
    ["nice", {
      short: new Set(["-n"]),
      long: new Set(["--adjustment"]),
    }],
    ["runuser", {
      short: new Set(["-g", "-G", "-u"]),
      long: new Set(["--group", "--supp-group", "--user"]),
    }],
    ["setsid", {
      short: new Set([]),
      long: new Set([]),
    }],
    ["ssh-agent", {
      short: new Set(["-a", "-E", "-O", "-P", "-t"]),
      long: new Set([]),
    }],
    ["sudo", {
      short: new Set(["-C", "-D", "-g", "-h", "-p", "-r", "-t", "-T", "-u"]),
      long: new Set(["--chdir", "--close-from", "--command-timeout", "--group", "--host", "--prompt", "--role", "--type", "--user"]),
    }],
    ["stdbuf", {
      short: new Set(["-e", "-i", "-o"]),
      long: new Set(["--error", "--input", "--output"]),
    }],
    ["taskset", {
      short: new Set(["-p"]),
      long: new Set(["--pid"]),
    }],
    ["time", {
      short: new Set(["-f", "-o"]),
      long: new Set(["--format", "--output"]),
    }],
    ["timeout", {
      short: new Set(["-k", "-s"]),
      long: new Set(["--kill-after", "--signal"]),
    }],
    ["unbuffer", {
      short: new Set([]),
      long: new Set([]),
    }],
  ]);
  let index = skipAssignments(words, 0);

  while (index < words.length) {
    const word = words[index];
    const commandName = executableName(word);
    const nextIndex = skipRedirection(words, index);

    if (nextIndex !== index) {
      index = nextIndex;
      continue;
    }

    if (stopBeforeNames.has(commandName)) {
      return index;
    }

    const wrapperOptions = wrapperOptionOperands.get(commandName);
    if (wrapperOptions) {
      index += 1;
      index = skipWrapperOptions(words, index, wrapperOptions.short, wrapperOptions.long);
      if (new Set(["chrt", "script", "taskset", "timeout"]).has(commandName) && index < words.length) {
        index = indexAfterOptionOperand(words, index);
      }
      index = skipAssignments(words, index);
      continue;
    }

    if (commandName === "function") {
      index += 1;
      if (index < words.length && words[index] !== "{") {
        index += 1;
      }
      if (words[index] === "{") {
        index += 1;
      }
      continue;
    }

    if (transparentShellWords.has(commandName)) {
      index += 1;
      while (index < words.length && words[index].startsWith("-")) {
        index += 1;
      }
      continue;
    }

    return index;
  }

  return -1;
}

function firstExecutableIndex(words) {
  return prefixedExecutableIndex(words);
}

function initialWordIndex(words) {
  let index = skipAssignments(words, 0);

  while (index < words.length) {
    const nextIndex = skipRedirection(words, index);

    if (nextIndex === index) {
      return index;
    }

    index = nextIndex;
  }

  return -1;
}

function envSplitStringPayload(words) {
  let index = prefixedExecutableIndex(words, new Set(["env"]));
  const envOptionsWithValues = new Set(["-a", "-C", "-P", "-u"]);

  if (index < 0 || executableName(words[index]) !== "env") {
    return null;
  }

  index += 1;

  while (index < words.length) {
    const word = words[index];
    const shortSplitPayload = envShortSplitStringPayload(word, words.slice(index + 1));

    if (word === "-S" || word === "--split-string") {
      return envSplitStringCommandText(words.slice(index + 1).join(" "));
    }

    if (shortSplitPayload !== null) {
      return envSplitStringCommandText(shortSplitPayload);
    }

    if (word.startsWith("-S") && word !== "-S") {
      return envSplitStringCommandText([word.slice(2), ...words.slice(index + 1)].join(" "));
    }

    if (word.startsWith("--split-string=")) {
      return envSplitStringCommandText([word.slice("--split-string=".length), ...words.slice(index + 1)].join(" "));
    }

    const nextIndex = skipRedirection(words, index);

    if (nextIndex !== index) {
      index = nextIndex;
      continue;
    }

    if (isAssignment(word)) {
      index += 1;
      continue;
    }

    const clusterValueOperand = shortClusterValueOperand(word, envOptionsWithValues);

    if (clusterValueOperand === "attached") {
      index += 1;
      continue;
    }

    if (clusterValueOperand === "next") {
      index = indexAfterOptionOperand(words, index + 1);
      continue;
    }

    if (word === "-a" || word === "-C" || word === "-P" || word === "-u" || word === "--argv0" || word === "--chdir" || word === "--unset") {
      index = indexAfterOptionOperand(words, index + 1);
      continue;
    }

    if (/^(?:-[aCPu].+|--(?:argv0|chdir|unset)=)/.test(word)) {
      index += 1;
      continue;
    }

    if (word.startsWith("-")) {
      index += 1;
      continue;
    }

    return null;
  }

  return null;
}

function evalPayload(words) {
  const index = prefixedExecutableIndex(words, new Set(["eval"]));

  if (index >= 0 && words[index] === "eval") {
    let payloadIndex = nextArgumentIndex(words, index + 1);

    if (words[payloadIndex] === "--") {
      payloadIndex = nextArgumentIndex(words, payloadIndex + 1);
    }

    return words.slice(payloadIndex).join(" ");
  }

  return null;
}

function renderShellPayloadWithPositionals(payload, commandWords) {
  if (commandWords.length === 0) {
    return payload;
  }

  const positionalText = commandTextFromArgvWords(commandWords.slice(1));
  const joinedPositionalsText = shellQuoteWord(commandWords.slice(1).join(" "));
  let rendered = String(payload);

  rendered = rendered.replace(/(["']?)\$\{([@*]):(-?\d+)(?::(-?\d+))?\}\1/g, (_match, _quote, kind, startText, lengthText) => {
    const start = Number.parseInt(startText, 10);
    const length = lengthText === undefined ? undefined : Number.parseInt(lengthText, 10);

    if (!Number.isInteger(start) || (lengthText !== undefined && (!Number.isInteger(length) || length < 0))) {
      return "";
    }

    const sliceStart = Math.max(start, 0);
    const sliceEnd = length === undefined ? undefined : sliceStart + length;
    const words = commandWords.slice(sliceStart, sliceEnd);

    return kind === "*" ? shellQuoteWord(words.join(" ")) : commandTextFromArgvWords(words);
  });

  rendered = rendered
    .replace(/"\$\{\*(?::1)?\}"/g, joinedPositionalsText)
    .replace(/'\$\{\*(?::1)?\}'/g, joinedPositionalsText)
    .replace(/"\$\{@(?::1)?\}"/g, positionalText)
    .replace(/'\$\{@(?::1)?\}'/g, positionalText)
    .replace(/"\$\*"/g, joinedPositionalsText)
    .replace(/'\$\*'/g, joinedPositionalsText)
    .replace(/"\$@"/g, positionalText)
    .replace(/'\$@'/g, positionalText)
    .replace(/\$\{[@*]\}/g, positionalText)
    .replace(/\$[@*]/g, positionalText);

  rendered = rendered.replace(/(["']?)\$\{?([0-9]+)\}?\1/g, (_match, _quote, numberText) => {
    const value = commandWords[Number.parseInt(numberText, 10)] ?? "";
    return shellQuoteWord(value);
  });

  return rendered;
}

function isInsideShellQuote(text, targetIndex) {
  let quote = "";
  let escaping = false;

  for (let index = 0; index < targetIndex; index += 1) {
    const char = text[index];

    if (escaping) {
      escaping = false;
      continue;
    }

    if (char === "\\" && quote !== "'") {
      escaping = true;
      continue;
    }

    if (quote !== "") {
      if (char === quote) {
        quote = "";
      }
      continue;
    }

    if (char === "'" || char === '"') {
      quote = char;
    }
  }

  return quote !== "";
}

function collectShellBraceBody(text, startIndex) {
  let content = "";
  let quote = "";
  let escaping = false;
  let depth = 1;

  for (let index = startIndex; index < text.length; index += 1) {
    const char = text[index];

    if (escaping) {
      content += char;
      escaping = false;
      continue;
    }

    if (char === "\\" && quote !== "'") {
      content += char;
      escaping = true;
      continue;
    }

    if (quote !== "") {
      if (char === quote) {
        quote = "";
      }
      content += char;
      continue;
    }

    if (char === "'" || char === '"') {
      quote = char;
      content += char;
      continue;
    }

    if (char === "{") {
      depth += 1;
      content += char;
      continue;
    }

    if (char === "}") {
      depth -= 1;

      if (depth === 0) {
        return { content, endIndex: index };
      }

      content += char;
      continue;
    }

    content += char;
  }

  return null;
}

function shellFunctionDefinitions(commandText) {
  const definitions = [];
  const pattern = /(?:^|[;&|\n]\s*)(?:function\s+([A-Za-z_][A-Za-z0-9_]*)(?:\s*\(\s*\))?\s*|([A-Za-z_][A-Za-z0-9_]*)\s*\(\s*\)\s*)\{/g;
  let match = pattern.exec(commandText);

  while (match) {
    if (isInsideShellQuote(commandText, match.index)) {
      match = pattern.exec(commandText);
      continue;
    }

    const body = collectShellBraceBody(commandText, pattern.lastIndex);

    if (body === null) {
      match = pattern.exec(commandText);
      continue;
    }

    definitions.push({
      body: body.content,
      endIndex: body.endIndex,
      name: String(match[1] ?? match[2]).toLowerCase(),
    });
    pattern.lastIndex = body.endIndex + 1;
    match = pattern.exec(commandText);
  }

  return definitions;
}

function shellFunctionCallPayloads(commandText) {
  const payloads = [];

  for (const definition of shellFunctionDefinitions(commandText)) {
    const suffix = commandText.slice(definition.endIndex + 1);

    for (const segment of commandSegments(shellTokens(suffix))) {
      const executableIndex = firstExecutableIndex(segment);

      if (executableIndex < 0 || executableName(segment[executableIndex]) !== definition.name) {
        continue;
      }

      payloads.push(renderShellPayloadWithPositionals(definition.body, segment.slice(executableIndex)));
    }
  }

  return payloads;
}

function shellOptionsWithOperands(commandName) {
  const options = new Set(["+O", "+o", "-O", "-o", "--init-file", "--rcfile"]);

  if (commandName === "fish") {
    options.add("--features");
  }

  if (commandName === "zsh") {
    options.add("--emulate");
  }

  return options;
}

function shellOptionHasAttachedOperand(commandName, word) {
  if (/^(?:[-+]O.+|[-+]o.+|--(?:init-file|rcfile)=)/.test(word)) {
    return true;
  }

  if (commandName === "fish" && word.startsWith("--features=")) {
    return true;
  }

  return commandName === "zsh" && word.startsWith("--emulate=");
}

function shellCommandPayload(words) {
  const index = prefixedExecutableIndex(words, SHELL_NAMES);
  let optionsEnded = false;

  if (index < 0 || !SHELL_NAMES.has(executableName(words[index]))) {
    return null;
  }

  const commandName = executableName(words[index]);

  for (let optionIndex = index + 1; optionIndex < words.length; optionIndex += 1) {
    const word = words[optionIndex];
    const nextIndex = skipRedirection(words, optionIndex);

    if (nextIndex !== optionIndex) {
      optionIndex = nextIndex - 1;
      continue;
    }

    if (word === "--") {
      optionsEnded = true;
      continue;
    }

    if (optionsEnded) {
      return null;
    }

    if (commandName === "fish" && (word === "-C" || word === "--command" || word === "--init-command")) {
      return optionOperand(words, optionIndex + 1).value || null;
    }

    if (commandName === "fish" && word.startsWith("-C") && word !== "-C") {
      return word.slice(2) || null;
    }

    if (commandName === "fish" && (word.startsWith("--command=") || word.startsWith("--init-command="))) {
      return word.slice(word.indexOf("=") + 1) || null;
    }

    if (word === "-c" || /^-[^-]*c/.test(word)) {
      let payload = optionOperand(words, optionIndex + 1);

      if (payload.value === "--") {
        payload = optionOperand(words, payload.index + 1);
      }

      return renderShellPayloadWithPositionals(payload.value, words.slice(payload.index + 1));
    }

    if (shellOptionsWithOperands(commandName).has(word)) {
      optionIndex = indexAfterOptionOperand(words, optionIndex + 1) - 1;
      continue;
    }

    if (shellOptionHasAttachedOperand(commandName, word)) {
      continue;
    }

    if (!word.startsWith("-")) {
      return null;
    }
  }

  return null;
}

function cmdShellPayload(words, startIndex) {
  for (let index = startIndex; index < words.length; index += 1) {
    const nextIndex = skipRedirection(words, index);

    if (nextIndex !== index) {
      index = nextIndex - 1;
      continue;
    }

    const word = words[index];
    const lowerWord = String(word).toLowerCase();

    if (lowerWord === "/c" || lowerWord === "/k") {
      const payload = words.slice(index + 1).join(" ");
      return payload === "" ? null : payload;
    }

    if ((lowerWord.startsWith("/c") || lowerWord.startsWith("/k")) && lowerWord.length > 2) {
      const payload = [word.slice(2), ...words.slice(index + 1)].join(" ");
      return payload === "" ? null : payload;
    }

    if (lowerWord === "/d" || lowerWord === "/q" || lowerWord === "/s" || lowerWord.startsWith("/e") || lowerWord.startsWith("/v")) {
      continue;
    }

    if (word.startsWith("/")) {
      continue;
    }

    return null;
  }

  return null;
}

function decodePowerShellEncodedCommand(value) {
  const encoded = String(value ?? "").replace(/\s+/g, "");

  if (encoded === "" || !/^[A-Za-z0-9+/]*={0,2}$/.test(encoded)) {
    return "";
  }

  try {
    return Buffer.from(encoded, "base64").toString("utf16le").replace(/\u0000+$/g, "");
  } catch {
    return "";
  }
}

function isPowerShellEncodedCommandOption(lowerWord) {
  return new Set(["-encodedcommand", "-enc", "-ec", "-e", "/encodedcommand", "/enc", "/ec", "/e"]).has(lowerWord);
}

function powerShellEncodedCommandAttachedPayload(word) {
  const lowerWord = String(word).toLowerCase();
  const prefixes = [
    "-encodedcommand:",
    "-encodedcommand=",
    "/encodedcommand:",
    "/encodedcommand=",
    "-enc:",
    "-enc=",
    "/enc:",
    "/enc=",
    "-ec:",
    "-ec=",
    "/ec:",
    "/ec=",
    "-e:",
    "-e=",
    "/e:",
    "/e=",
  ];
  const prefix = prefixes.find((candidate) => lowerWord.startsWith(candidate));

  if (prefix === undefined) {
    return null;
  }

  const payload = decodePowerShellEncodedCommand(String(word).slice(prefix.length));
  return payload === "" ? null : payload;
}

function powershellPayload(words, startIndex) {
  const optionsWithValues = new Set([
    "-configurationname",
    "-custompipename",
    "-executionpolicy",
    "-file",
    "-inputformat",
    "-outputformat",
    "-psconsolefile",
    "-settingsfile",
    "-version",
    "-windowstyle",
    "/configurationname",
    "/custompipename",
    "/executionpolicy",
    "/file",
    "/inputformat",
    "/outputformat",
    "/psconsolefile",
    "/settingsfile",
    "/version",
    "/windowstyle",
  ]);

  for (let index = startIndex; index < words.length; index += 1) {
    const nextIndex = skipRedirection(words, index);

    if (nextIndex !== index) {
      index = nextIndex - 1;
      continue;
    }

    const word = words[index];
    const lowerWord = String(word).toLowerCase();
    const encodedCommandAttachedPayload = powerShellEncodedCommandAttachedPayload(word);

    if (encodedCommandAttachedPayload !== null) {
      return encodedCommandAttachedPayload;
    }

    if (isPowerShellEncodedCommandOption(lowerWord)) {
      const payload = decodePowerShellEncodedCommand(optionOperand(words, index + 1).value);
      return payload === "" ? null : payload;
    }

    if (lowerWord === "-command" || lowerWord === "-c" || lowerWord === "/command" || lowerWord === "/c") {
      const payload = words.slice(index + 1).join(" ");
      return payload === "" ? null : payload;
    }

    if (lowerWord.startsWith("-command:") || lowerWord.startsWith("-command=") || lowerWord.startsWith("/command:") || lowerWord.startsWith("/command=")) {
      const separatorIndex = Math.max(word.indexOf(":"), word.indexOf("="));
      const payload = [word.slice(separatorIndex + 1), ...words.slice(index + 1)].join(" ");
      return payload === "" ? null : payload;
    }

    if (optionsWithValues.has(lowerWord)) {
      index = indexAfterOptionOperand(words, index + 1) - 1;
      continue;
    }

    if (word.startsWith("-") || word.startsWith("/")) {
      continue;
    }

    return null;
  }

  return null;
}

function windowsShellCommandPayload(words) {
  const index = prefixedExecutableIndex(words, WINDOWS_SHELL_NAMES);

  if (index < 0) {
    return null;
  }

  const commandName = executableName(words[index]);

  if (commandName === "cmd") {
    return cmdShellPayload(words, index + 1);
  }

  if (commandName === "powershell" || commandName === "pwsh") {
    return powershellPayload(words, index + 1);
  }

  return null;
}

function shellExecutableIndex(words) {
  const index = prefixedExecutableIndex(words, SHELL_NAMES);

  return index >= 0 && SHELL_NAMES.has(executableName(words[index])) ? index : -1;
}

function shellReadsFromStdinInvocation(words) {
  const index = shellExecutableIndex(words);
  let optionsEnded = false;

  if (index < 0) {
    return false;
  }

  const commandName = executableName(words[index]);

  for (let optionIndex = index + 1; optionIndex < words.length; optionIndex += 1) {
    const redirection = redirectionDetails(words, optionIndex);

    if (redirection) {
      optionIndex = redirection.nextIndex - 1;
      continue;
    }

    const word = words[optionIndex];

    if (word === "--") {
      optionsEnded = true;
      continue;
    }

    if (optionsEnded) {
      return false;
    }

    if (word === "-c" || /^-[^-]*c/.test(word)) {
      return false;
    }

    if (word === "-n" || word === "--noexec") {
      return false;
    }

    if (word === "-s" || /^-[^-]*s/.test(word)) {
      return true;
    }

    if (shellOptionsWithOperands(commandName).has(word)) {
      optionIndex = indexAfterOptionOperand(words, optionIndex + 1) - 1;
      continue;
    }

    if (shellOptionHasAttachedOperand(commandName, word)) {
      continue;
    }

    if (word.startsWith("-")) {
      continue;
    }

    return false;
  }

  return true;
}

function sourceReadsAttachedStdinInvocation(words) {
  const executableIndex = firstExecutableIndex(words);

  if (executableIndex < 0 || !new Set([".", "source"]).has(executableName(words[executableIndex]))) {
    return false;
  }

  for (let index = executableIndex + 1; index < words.length;) {
    const nextIndex = skipRedirection(words, index);

    if (nextIndex !== index) {
      index = nextIndex;
      continue;
    }

    const word = words[index];

    if (word === "--" || word.startsWith("-")) {
      index += 1;
      continue;
    }

    return new Set(["/dev/fd/0", "/dev/stdin", "/proc/self/fd/0"]).has(word);
  }

  return false;
}

function scriptFdNumber(scriptPath) {
  return String(scriptPath ?? "").match(/^\/(?:dev\/fd|proc\/self\/fd)\/([0-9]+)$/)?.[1] ?? "";
}

function shellScriptFdInvocation(words) {
  const shellIndex = shellExecutableIndex(words);
  let optionsEnded = false;

  if (shellIndex < 0) {
    return null;
  }

  const commandName = executableName(words[shellIndex]);

  for (let index = shellIndex + 1; index < words.length;) {
    const redirectionIndex = skipRedirection(words, index);

    if (redirectionIndex !== index) {
      index = redirectionIndex;
      continue;
    }

    const word = words[index];

    if (word === "--" && !optionsEnded) {
      optionsEnded = true;
      index += 1;
      continue;
    }

    if (!optionsEnded && (word === "-c" || /^-[^-]*c/.test(word))) {
      return null;
    }

    if (!optionsEnded && shellOptionsWithOperands(commandName).has(word)) {
      index = indexAfterOptionOperand(words, index + 1);
      continue;
    }

    if (!optionsEnded && shellOptionHasAttachedOperand(commandName, word)) {
      index += 1;
      continue;
    }

    if (!optionsEnded && word.startsWith("-")) {
      index += 1;
      continue;
    }

    const fd = scriptFdNumber(word);
    return fd === "" ? null : { fd, invocationWords: words.slice(index) };
  }

  return null;
}

function sourceScriptFdInvocation(words) {
  const executableIndex = firstExecutableIndex(words);

  if (executableIndex < 0 || !new Set([".", "source"]).has(executableName(words[executableIndex]))) {
    return null;
  }

  for (let index = executableIndex + 1; index < words.length;) {
    const redirectionIndex = skipRedirection(words, index);

    if (redirectionIndex !== index) {
      index = redirectionIndex;
      continue;
    }

    const word = words[index];

    if (word === "--" || word.startsWith("-")) {
      index += 1;
      continue;
    }

    const fd = scriptFdNumber(word);
    return fd === "" ? null : { fd, invocationWords: words.slice(index) };
  }

  return null;
}

function scriptFdInvocation(words) {
  return shellScriptFdInvocation(words) ?? sourceScriptFdInvocation(words);
}

function commandConsumesAttachedStdin(commandText, depth = 0) {
  if (depth > 5) {
    return false;
  }

  for (const segment of commandSegments(shellTokens(commandText))) {
    if (shellReadsFromStdinInvocation(segment) || sourceReadsAttachedStdinInvocation(segment)) {
      return true;
    }

    const envPayload = envSplitStringPayload(segment);
    if (envPayload !== null && commandConsumesAttachedStdin(envPayload, depth + 1)) {
      return true;
    }

    const payload = shellCommandPayload(segment);
    if (payload !== null && commandConsumesAttachedStdin(payload, depth + 1)) {
      return true;
    }
  }

  return false;
}

function invocationConsumesAttachedStdin(words) {
  if (shellReadsFromStdinInvocation(words) || sourceReadsAttachedStdinInvocation(words)) {
    return true;
  }

  const envPayload = envSplitStringPayload(words);
  if (envPayload !== null) {
    return commandConsumesAttachedStdin(envPayload);
  }

  const payload = shellCommandPayload(words);
  return payload !== null && commandConsumesAttachedStdin(payload);
}

function hereStringDetails(words) {
  const details = [];

  for (let index = 0; index < words.length; index += 1) {
    const redirection = redirectionDetails(words, index);

    if (!redirection) {
      continue;
    }

    if (String(redirection.operator).endsWith("<<<") && redirection.operand !== "") {
      details.push({
        fd: redirectionFd(redirection.operator, "0"),
        payload: redirection.operand,
      });
    }

    index = redirection.nextIndex - 1;
  }

  return details;
}

function hereStringPayloads(words) {
  return hereStringDetails(words)
    .filter((detail) => detail.fd === "0")
    .map((detail) => detail.payload);
}

function scriptFdHereStringPayloads(words) {
  const invocation = scriptFdInvocation(words);

  if (invocation === null) {
    return [];
  }

  return hereStringDetails(words)
    .filter((detail) => detail.fd === invocation.fd)
    .map((detail) => renderShellPayloadWithPositionals(detail.payload, invocation.invocationWords));
}

function shellStdinInlinePayloads(words) {
  const payloads = invocationConsumesAttachedStdin(words) ? hereStringPayloads(words) : [];
  payloads.push(...scriptFdHereStringPayloads(words));
  return payloads;
}

function catPassesStdin(words) {
  const executableIndex = firstExecutableIndex(words);

  if (executableIndex < 0 || executableName(words[executableIndex]) !== "cat") {
    return false;
  }

  for (let index = executableIndex + 1; index < words.length;) {
    const nextIndex = skipRedirection(words, index);

    if (nextIndex !== index) {
      index = nextIndex;
      continue;
    }

    if (words[index] === "-" || words[index].startsWith("-")) {
      index += 1;
      continue;
    }

    return false;
  }

  return true;
}

function teePassesStdin(words) {
  const executableIndex = firstExecutableIndex(words);

  if (executableIndex < 0 || executableName(words[executableIndex]) !== "tee") {
    return false;
  }

  for (let index = executableIndex + 1; index < words.length;) {
    const nextIndex = skipRedirection(words, index);

    if (nextIndex !== index) {
      index = nextIndex;
      continue;
    }

    if (words[index] === "--help" || words[index] === "--version") {
      return false;
    }

    index += 1;
  }

  return true;
}

function commandPassesStdin(words) {
  return catPassesStdin(words) || teePassesStdin(words);
}

function commandHasHeredoc(words) {
  for (let index = 0; index < words.length; index += 1) {
    const redirection = redirectionDetails(words, index);

    if (!redirection) {
      continue;
    }

    if (redirection.operator === "<<" || redirection.operator === "<<-") {
      return true;
    }

    index = redirection.nextIndex - 1;
  }

  return false;
}

function outputProcessSubstitutionCommand(word) {
  const match = String(word).match(/^(?:\d*)?>\((.*)$/);

  return match ? match[1] : "";
}

function outputProcessSubstitutionReceivesStdin(words) {
  if (!commandPassesStdin(words)) {
    return false;
  }

  for (const word of words) {
    const commandText = outputProcessSubstitutionCommand(word);

    if (commandText !== "" && commandReadsShellFromStdin(commandText)) {
      return true;
    }
  }

  return false;
}

function decodePrintfEscape(text, index) {
  const match = text.slice(index).match(/^\\(?:x[0-9A-Fa-f]{1,2}|[0-7]{1,3}|.)/)?.[0] ?? "\\";

  return {
    value: decodeAnsiCString(match),
    index: index + match.length - 1,
  };
}

function renderPrintfFormatOnce(format, args, startArgIndex) {
  let output = "";
  let argIndex = startArgIndex;

  for (let index = 0; index < format.length; index += 1) {
    const char = format[index];

    if (char === "\\") {
      const escape = decodePrintfEscape(format, index);
      output += escape.value;
      index = escape.index;
      continue;
    }

    if (char !== "%") {
      output += char;
      continue;
    }

    if (format[index + 1] === "%") {
      output += "%";
      index += 1;
      continue;
    }

    let specIndex = index + 1;
    while (specIndex < format.length && !/[A-Za-z]/.test(format[specIndex])) {
      specIndex += 1;
    }

    if (specIndex >= format.length) {
      output += "%";
      continue;
    }

    const specifier = format[specIndex];
    if ("bcsdiouxXfFeEgGaAq".includes(specifier)) {
      const value = args[argIndex] ?? "";
      output += specifier === "b" ? decodeAnsiCString(value) : specifier === "q" ? shellQuoteWord(value) : value;
      argIndex += 1;
      index = specIndex;
      continue;
    }

    output += format.slice(index, specIndex + 1);
    index = specIndex;
  }

  return { argIndex, output };
}

function renderPrintfPayload(words) {
  let formatIndex = 0;

  if (words[formatIndex] === "--") {
    formatIndex += 1;
  }

  if (formatIndex >= words.length) {
    return null;
  }

  const format = words[formatIndex];
  const args = words.slice(formatIndex + 1);

  if (!format.includes("%")) {
    return decodeAnsiCString(format);
  }

  let output = "";
  let argIndex = 0;

  do {
    const result = renderPrintfFormatOnce(format, args, argIndex);
    const consumedArgs = result.argIndex - argIndex;
    output += result.output;
    argIndex = result.argIndex;

    if (consumedArgs <= 0) {
      break;
    }
  } while (argIndex < args.length);

  return output;
}

function renderEchoPayload(words) {
  let index = 0;
  let decodeEscapes = false;
  let trailingNewline = true;

  while (index < words.length && /^-[neE]+$/.test(words[index])) {
    for (const option of words[index].slice(1)) {
      if (option === "n") {
        trailingNewline = false;
      }

      if (option === "e") {
        decodeEscapes = true;
      }

      if (option === "E") {
        decodeEscapes = false;
      }
    }

    index += 1;
  }

  const payload = words.slice(index).join(" ");
  return `${decodeEscapes ? decodeAnsiCString(payload) : payload}${trailingNewline ? "\n" : ""}`;
}

function stdoutLiteralPayload(words) {
  const executableIndex = firstExecutableIndex(words);

  if (executableIndex < 0) {
    return null;
  }

  const commandName = executableName(words[executableIndex]);
  const restWords = words.slice(executableIndex + 1);

  if (commandName === "echo") {
    return renderEchoPayload(restWords);
  }

  if (commandName === "printf") {
    return renderPrintfPayload(restWords);
  }

  if ((commandName === "cat" && catPassesStdin(words)) || (commandName === "tee" && teePassesStdin(words))) {
    const payloads = hereStringPayloads(words);
    return payloads.length > 0 ? payloads.join("\n") : null;
  }

  return null;
}

function wordsEqual(left, right) {
  return left.length === right.length && left.every((word, index) => word === right[index]);
}

function heredocPayloadDetailsFromCommandText(commandText) {
  const lines = String(commandText).split(/\r?\n/);
  const payloads = [];

  if (lines.length < 2) {
    return payloads;
  }

  for (let lineIndex = 0; lineIndex < lines.length; lineIndex += 1) {
    const firstLine = lines[lineIndex];
    const activeLine = firstLine.slice(0, shellCommentStartIndex(firstLine));
    const pattern = heredocPattern();
    let match = pattern.exec(activeLine);

    while (match) {
      const delimiter = heredocDelimiter(match);
      const body = [];

      for (let bodyIndex = lineIndex + 1; bodyIndex < lines.length; bodyIndex += 1) {
        if (lines[bodyIndex].trim() === delimiter) {
          payloads.push({
            activeLine,
            body: body.join("\n"),
            firstLine,
            lineIndex,
            matchIndex: match.index,
          });
          lineIndex = bodyIndex;
          break;
        }

        body.push(lines[bodyIndex]);
      }

      match = pattern.exec(activeLine);
    }
  }

  return payloads;
}

function heredocPayloadFromSegment(commandText, segmentWords) {
  for (const detail of heredocPayloadDetailsFromCommandText(commandText)) {
    for (const words of commandSegments(shellTokens(detail.activeLine))) {
      if (wordsEqual(words, segmentWords)) {
        return detail.body;
      }
    }
  }

  return null;
}

function catHeredocPayloadFromCommandText(commandText) {
  const detail = heredocPayloadDetailsFromCommandText(commandText).find((payload) => {
    const prefixSegments = commandSegments(shellTokens(payload.activeLine.slice(0, payload.matchIndex)));

    if (prefixSegments.length !== 1) {
      return false;
    }

    const executableIndex = firstExecutableIndex(prefixSegments[0]);

    return executableIndex >= 0 && new Set(["cat", "tee"]).has(executableName(prefixSegments[0][executableIndex]));
  });

  return detail?.body ?? null;
}

function firstHeredocPayloadFromCommandText(commandText) {
  return heredocPayloadDetailsFromCommandText(commandText)[0]?.body ?? null;
}

function catHeredocScriptTargetFromWords(words) {
  const executableIndex = firstExecutableIndex(words);

  if (executableIndex < 0) {
    return "";
  }

  const commandName = executableName(words[executableIndex]);
  let hasHeredoc = false;
  let fallbackTarget = "";
  let target = "";

  if (commandName === "tee") {
    for (let index = executableIndex + 1; index < words.length;) {
      const redirection = redirectionDetails(words, index);

      if (redirection) {
        if (redirection.operator === "<<" || redirection.operator === "<<-") {
          hasHeredoc = true;
        }

        if (fallbackTarget === "" && /^(?:(?:\d*)?>\|?|(?:\d*)?>>|&>>?)$/.test(redirection.operator)) {
          fallbackTarget = redirection.operand;
        }

        index = redirection.nextIndex;
        continue;
      }

      if (words[index] === "--") {
        index += 1;
        continue;
      }

      if (words[index].startsWith("-")) {
        index += 1;
        continue;
      }

      if (target === "") {
        target = words[index];
      }

      index += 1;
    }

    return hasHeredoc ? (target || fallbackTarget) : "";
  }

  if (commandName !== "cat") {
    return "";
  }

  for (let index = executableIndex + 1; index < words.length;) {
    const redirection = redirectionDetails(words, index);

    if (!redirection) {
      index += 1;
      continue;
    }

    if (redirection.operator === "<<" || redirection.operator === "<<-") {
      hasHeredoc = true;
    }

    if (/^(?:(?:\d*)?>\|?|(?:\d*)?>>|&>>?)$/.test(redirection.operator)) {
      target = redirection.operand;
    }

    index = redirection.nextIndex;
  }

  return hasHeredoc ? target : "";
}

function teeScriptOutputTarget(words) {
  const executableIndex = firstExecutableIndex(words);
  let fallbackTarget = "";
  let target = "";

  if (executableIndex < 0 || executableName(words[executableIndex]) !== "tee") {
    return "";
  }

  for (let index = executableIndex + 1; index < words.length;) {
    const redirection = redirectionDetails(words, index);

    if (redirection) {
      if (fallbackTarget === "" && /^(?:(?:\d*)?>\|?|(?:\d*)?>>|&>>?)$/.test(redirection.operator)) {
        fallbackTarget = redirection.operand;
      }

      index = redirection.nextIndex;
      continue;
    }

    if (words[index] === "--") {
      index += 1;
      continue;
    }

    if (words[index].startsWith("-")) {
      index += 1;
      continue;
    }

    if (target === "") {
      target = words[index];
    }

    index += 1;
  }

  return target || fallbackTarget;
}

function catHeredocScriptTarget(firstLine) {
  const segments = commandSegmentsWithOperators(shellTokens(firstLine));

  for (const { words } of segments) {
    const target = catHeredocScriptTargetFromWords(words);

    if (target !== "") {
      return target;
    }
  }

  for (let index = 0; index < segments.length - 1; index += 1) {
    if (!commandHasHeredoc(segments[index].words) || segments[index].afterOperator !== "|" || segments[index + 1].beforeOperator !== "|") {
      continue;
    }

    const target = teeScriptOutputTarget(segments[index + 1].words);

    if (target !== "") {
      return target;
    }
  }

  return "";
}

function normalizedScriptPath(scriptPath) {
  return String(scriptPath).replace(/\\/g, "/").replace(/^(?:\.\/)+/, "");
}

function sameScriptPath(left, right) {
  return left === right || normalizedScriptPath(left) === normalizedScriptPath(right);
}

function shellExecutesScriptPath(words, scriptPath) {
  return shellScriptInvocationWords(words, scriptPath).length > 0;
}

function shellScriptInvocationWords(words, scriptPath) {
  const shellIndex = shellExecutableIndex(words);
  let optionsEnded = false;

  if (shellIndex < 0 || scriptPath === "") {
    return [];
  }

  const commandName = executableName(words[shellIndex]);

  for (let index = shellIndex + 1; index < words.length;) {
    const redirectionIndex = skipRedirection(words, index);

    if (redirectionIndex !== index) {
      index = redirectionIndex;
      continue;
    }

    const word = words[index];

    if (word === "--" && !optionsEnded) {
      optionsEnded = true;
      index += 1;
      continue;
    }

    if (!optionsEnded && (word === "-c" || /^-[^-]*c/.test(word))) {
      return [];
    }

    if (!optionsEnded && shellOptionsWithOperands(commandName).has(word)) {
      index = indexAfterOptionOperand(words, index + 1);
      continue;
    }

    if (!optionsEnded && shellOptionHasAttachedOperand(commandName, word)) {
      index += 1;
      continue;
    }

    if (!optionsEnded && word.startsWith("-")) {
      index += 1;
      continue;
    }

    return sameScriptPath(word, scriptPath) ? words.slice(index) : [];
  }

  return [];
}

function shellStdinRedirectionMatchesScript(redirection, scriptPath) {
  if (!redirection || scriptPath === "") {
    return false;
  }

  const operator = redirection.operator;
  const fd = redirectionFd(operator, "0");

  return fd === "0" && new Set(["<", "0<", "<>", "0<>"]).has(operator) && sameScriptPath(redirection.operand, scriptPath);
}

function shellStdinScriptInvocationWords(words, scriptPath) {
  const shellIndex = shellExecutableIndex(words);
  let optionsEnded = false;
  let readsStdinExplicitly = false;
  let stdinMatches = false;
  let stdinPositionals = [];

  if (shellIndex < 0 || scriptPath === "") {
    return [];
  }

  const commandName = executableName(words[shellIndex]);

  for (let index = shellIndex + 1; index < words.length;) {
    const redirection = redirectionDetails(words, index);

    if (redirection) {
      stdinMatches = stdinMatches || shellStdinRedirectionMatchesScript(redirection, scriptPath);
      index = redirection.nextIndex;
      continue;
    }

    const word = words[index];

    if (word === "--" && !optionsEnded) {
      optionsEnded = true;
      index += 1;
      continue;
    }

    if (!optionsEnded && (word === "-c" || /^-[^-]*c/.test(word))) {
      return [];
    }

    if (!optionsEnded && (word === "-s" || /^-[^-]*s/.test(word))) {
      readsStdinExplicitly = true;
      index += 1;
      continue;
    }

    if (!optionsEnded && shellOptionsWithOperands(commandName).has(word)) {
      index = indexAfterOptionOperand(words, index + 1);
      continue;
    }

    if (!optionsEnded && shellOptionHasAttachedOperand(commandName, word)) {
      index += 1;
      continue;
    }

    if (!optionsEnded && word.startsWith("-")) {
      index += 1;
      continue;
    }

    if (!readsStdinExplicitly) {
      return [];
    }

    stdinPositionals = words.slice(index);
    break;
  }

  return stdinMatches ? [scriptPath, ...stdinPositionals] : [];
}

function sourceExecutesScriptPath(words, scriptPath) {
  return sourceScriptInvocationWords(words, scriptPath).length > 0;
}

function sourceScriptInvocationWords(words, scriptPath) {
  const executableIndex = firstExecutableIndex(words);

  if (executableIndex < 0 || scriptPath === "" || !new Set([".", "source"]).has(executableName(words[executableIndex]))) {
    return [];
  }

  for (let index = executableIndex + 1; index < words.length;) {
    const redirectionIndex = skipRedirection(words, index);

    if (redirectionIndex !== index) {
      index = redirectionIndex;
      continue;
    }

    const word = words[index];

    if (word === "--") {
      index += 1;
      continue;
    }

    return sameScriptPath(word, scriptPath) ? words.slice(index) : [];
  }

  return [];
}

function directScriptInvocationWords(words, scriptPath) {
  const executableIndex = firstExecutableIndex(words);

  if (executableIndex < 0 || scriptPath === "") {
    return [];
  }

  return sameScriptPath(words[executableIndex], scriptPath) ? words.slice(executableIndex) : [];
}

function directExecutesScriptPath(words, scriptPath) {
  return directScriptInvocationWords(words, scriptPath).length > 0;
}

function scriptInvocationWordsForSegment(words, scriptPath) {
  for (const invocationWords of [
    shellScriptInvocationWords(words, scriptPath),
    shellStdinScriptInvocationWords(words, scriptPath),
    sourceScriptInvocationWords(words, scriptPath),
    directScriptInvocationWords(words, scriptPath),
  ]) {
    if (invocationWords.length > 0) {
      return invocationWords;
    }
  }

  return [];
}

function commandScriptInvocationWords(commandText, scriptPath) {
  const invocations = [];

  for (const words of commandSegments(shellTokens(commandText))) {
    const invocationWords = scriptInvocationWordsForSegment(words, scriptPath);

    if (invocationWords.length > 0) {
      invocations.push(invocationWords);
    }
  }

  return invocations;
}

function heredocScriptPayloads(commandText) {
  const lines = String(commandText).split(/\r?\n/);
  const payloads = [];

  for (let lineIndex = 0; lineIndex < lines.length; lineIndex += 1) {
    const firstLine = lines[lineIndex];
    const activeLine = firstLine.slice(0, shellCommentStartIndex(firstLine));
    const pattern = heredocPattern();
    let match = pattern.exec(activeLine);

    while (match) {
      const scriptPath = catHeredocScriptTarget(activeLine);
      const sameLineRestText = activeLine.slice(match.index + match[0].length);
      const delimiter = heredocDelimiter(match);
      const body = [];

      for (let bodyIndex = lineIndex + 1; bodyIndex < lines.length; bodyIndex += 1) {
        if (lines[bodyIndex].trim() === delimiter) {
          const restText = [sameLineRestText, lines.slice(bodyIndex + 1).join("\n")].filter(Boolean).join("\n");
          const bodyText = body.join("\n");
          const invocations = commandScriptInvocationWords(restText, scriptPath);

          for (const invocationWords of invocations) {
            payloads.push(renderShellPayloadWithPositionals(bodyText, invocationWords));
          }

          lineIndex = bodyIndex;
          break;
        }

        body.push(lines[bodyIndex]);
      }

      match = pattern.exec(activeLine);
    }
  }

  return payloads;
}

function stdoutLiteralPayloadFromCommandText(commandText) {
  const catHeredocPayload = catHeredocPayloadFromCommandText(commandText);

  if (catHeredocPayload !== null && catHeredocPayload !== "") {
    return catHeredocPayload;
  }

  const segments = commandSegmentsWithOperators(shellTokens(commandText));
  const outputs = [];
  let pipelinePayload = null;

  for (const segment of segments) {
    if (segment.beforeOperator !== "|") {
      pipelinePayload = null;
    }

    let segmentPayload = stdoutLiteralPayload(segment.words);

    if (segment.beforeOperator === "|" && pipelinePayload !== null && commandPassesStdin(segment.words)) {
      segmentPayload = pipelinePayload;
    }

    if (segment.afterOperator === "|") {
      if (segmentPayload !== null && segmentPayload !== "") {
        pipelinePayload = segmentPayload;
        continue;
      }

      if (pipelinePayload !== null && commandPassesStdin(segment.words)) {
        continue;
      }

      return null;
    }

    if (segment.beforeOperator === "|" && segmentPayload === null) {
      return null;
    }

    if (segmentPayload !== null && segmentPayload !== "") {
      outputs.push(segmentPayload);
      continue;
    }

    if (segments.length === 1) {
      return null;
    }
  }

  const payload = outputs.join("");
  return payload === "" ? null : payload;
}

function ignoredScriptTarget(target) {
  return target === "" || /^\/dev\/null$/i.test(target) || /^nul$/i.test(target);
}

function stdoutRedirectionTargets(words) {
  const targets = [];

  for (let index = 0; index < words.length; index += 1) {
    const redirection = redirectionDetails(words, index);

    if (!redirection) {
      continue;
    }

    if (redirectionReceivesStdout(redirection.operator) && !ignoredScriptTarget(redirection.operand)) {
      targets.push(redirection.operand);
    }

    index = redirection.nextIndex - 1;
  }

  return targets;
}

function wordsWithoutStdoutRedirections(words) {
  const output = [];

  for (let index = 0; index < words.length; index += 1) {
    const redirection = redirectionDetails(words, index);

    if (redirection && redirectionReceivesStdout(redirection.operator)) {
      index = redirection.nextIndex - 1;
      continue;
    }

    output.push(words[index]);
  }

  return output;
}

function rememberGeneratedScript(generatedScripts, scriptPath, payload) {
  if (ignoredScriptTarget(scriptPath) || payload === null || payload === "") {
    return;
  }

  generatedScripts.push({ payload, scriptPath });
}

function stdoutPayloadForPipelineSegment(commandText, segment) {
  return stdoutLiteralPayload(wordsWithoutStdoutRedirections(segment.words))
    ?? (commandHasHeredoc(segment.words) ? heredocPayloadFromSegment(commandText, segment.words) ?? catHeredocPayloadFromCommandText(commandText) : null);
}

function stdoutRedirectScriptPayloads(commandText) {
  const segments = commandSegmentsWithOperators(shellTokens(commandText));
  const generatedScripts = [];
  const payloads = [];
  let pipelinePayload = null;

  for (const segment of segments) {
    if (segment.beforeOperator !== "|") {
      pipelinePayload = null;
    }

    for (const generatedScript of generatedScripts) {
      const invocationWords = scriptInvocationWordsForSegment(segment.words, generatedScript.scriptPath);

      if (invocationWords.length > 0) {
        payloads.push(renderShellPayloadWithPositionals(generatedScript.payload, invocationWords));
      }
    }

    const segmentPayload = stdoutPayloadForPipelineSegment(commandText, segment);

    for (const target of stdoutRedirectionTargets(segment.words)) {
      rememberGeneratedScript(generatedScripts, target, segmentPayload);
    }

    const teeTarget = teeScriptOutputTarget(segment.words);
    const teePayload = segment.beforeOperator === "|" && pipelinePayload !== null
      ? pipelinePayload
      : stdoutLiteralPayload(segment.words);
    rememberGeneratedScript(generatedScripts, teeTarget, teePayload);

    if (segment.afterOperator !== "|") {
      pipelinePayload = null;
      continue;
    }

    if (segmentPayload !== null && segmentPayload !== "") {
      pipelinePayload = segmentPayload;
      continue;
    }

    if (pipelinePayload !== null && commandPassesStdin(segment.words)) {
      continue;
    }

    pipelinePayload = null;
  }

  return payloads;
}

function commandSubstitutionLiteralPayload(commandText) {
  return stdoutLiteralPayloadFromCommandText(commandText)?.replace(/\n+$/, "") ?? null;
}

function segmentStartBeforeIndex(text, targetIndex) {
  let segmentStart = 0;
  let quote = "";
  let escaping = false;

  for (let index = 0; index < targetIndex; index += 1) {
    const char = text[index];
    const nextChar = text[index + 1];

    if (escaping) {
      escaping = false;
      continue;
    }

    if (char === "\\" && quote !== "'") {
      escaping = true;
      continue;
    }

    if (quote !== "") {
      if (char === quote) {
        quote = "";
      }
      continue;
    }

    if (char === "'" || char === '"') {
      quote = char;
      continue;
    }

    if (char === "$" && nextChar === "(") {
      const substitution = collectCommandSubstitution(text, index + 2);
      index = Math.min(substitution.endIndex, targetIndex - 1);
      continue;
    }

    if ((char === "<" || char === ">") && nextChar === "(") {
      const substitution = collectCommandSubstitution(text, index + 2);
      index = Math.min(substitution.endIndex, targetIndex - 1);
      continue;
    }

    if (char === "`") {
      const substitution = collectBacktickSubstitution(text, index + 1);
      index = Math.min(substitution.endIndex, targetIndex - 1);
      continue;
    }

    if (char === ";" || char === "\n" || char === "\r") {
      segmentStart = index + 1;
      continue;
    }

    if ((char === "&" && nextChar === "&") || (char === "|" && nextChar === "|")) {
      segmentStart = index + 2;
      index += 1;
      continue;
    }

    if (char === "&" && (nextChar === ">" || previousNonWhitespaceChar(text, index) === ">")) {
      continue;
    }

    if (char === "|" && previousNonWhitespaceChar(text, index) === ">") {
      continue;
    }

    if (char === "|" || char === "&") {
      segmentStart = index + 1;
    }
  }

  return segmentStart;
}

function previousNonWhitespaceChar(text, index) {
  for (let cursor = index - 1; cursor >= 0; cursor -= 1) {
    if (!/\s/.test(text[cursor])) {
      return text[cursor];
    }
  }

  return "";
}

function shellConsumesProcessSubstitution(commandText, substitution) {
  if (substitution.operator !== "<") {
    return false;
  }

  const segmentStart = segmentStartBeforeIndex(commandText, substitution.startIndex);
  const segmentPrefix = commandText.slice(segmentStart, substitution.startIndex);
  const words = commandSegments(shellTokens(segmentPrefix)).at(-1) ?? [];
  const executableIndex = firstExecutableIndex(words);

  if (executableIndex < 0) {
    return false;
  }

  const commandName = executableName(words[executableIndex]);

  if (!SHELL_NAMES.has(commandName) && commandName !== "source" && commandName !== ".") {
    return false;
  }

  const prefix = commandText.slice(0, substitution.startIndex).trimEnd();
  const previous = previousNonWhitespaceChar(commandText, substitution.startIndex);
  return previous !== ">" || /(?:^|\s)(?:\d*)<>$/.test(prefix);
}

function shellProcessSubstitutionPayloads(commandText) {
  return processSubstitutionDetails(commandText)
    .filter((substitution) => shellConsumesProcessSubstitution(commandText, substitution))
    .map((substitution) => stdoutLiteralPayloadFromCommandText(substitution.content) ?? substitution.content);
}

function stripTrailingProcessSubstitutionRedirection(text) {
  return String(text).replace(/(?:^|\s)(?:\d*)?(?:&>>?|>>|>\||>)\s*$/, " ");
}

function outputProcessSubstitutionPayloads(commandText) {
  const payloads = [];

  for (const substitution of processSubstitutionDetails(commandText)) {
    if (substitution.operator !== ">" || !commandReadsShellFromStdin(substitution.content)) {
      continue;
    }

    const segmentStart = segmentStartBeforeIndex(commandText, substitution.startIndex);
    const segmentPrefix = commandText.slice(segmentStart, substitution.startIndex);
    const segmentSuffix = rawCommandSuffixAfterSubstitution(commandText, substitution.endIndex + 1);
    const segmentWords = commandSegments(shellTokens([
      stripTrailingProcessSubstitutionRedirection(segmentPrefix),
      segmentSuffix,
    ].filter(Boolean).join(" "))).at(-1) ?? [];
    const producerWords = commandSegments(shellTokens(segmentPrefix)).at(-1) ?? [];
    const payload = stdoutLiteralPayload(producerWords) ?? stdoutLiteralPayload(segmentWords);

    if (payload !== null && payload !== "") {
      payloads.push(payload);
    }
  }

  return payloads;
}

function shellStdinPayloads(commandText) {
  const segments = commandSegmentsWithOperators(shellTokens(commandText));
  const payloads = [];
  let pipelinePayload = null;

  for (let index = 0; index < segments.length; index += 1) {
    const segment = segments[index];

    if (segment.beforeOperator !== "|") {
      pipelinePayload = null;
    }

    payloads.push(...shellStdinInlinePayloads(segment.words));

    if (segment.beforeOperator === "|" && invocationConsumesAttachedStdin(segment.words) && pipelinePayload !== null && pipelinePayload !== "") {
      payloads.push(pipelinePayload);
    }

    if (segment.beforeOperator === "|" && pipelinePayload !== null && pipelinePayload !== "" && outputProcessSubstitutionReceivesStdin(segment.words)) {
      payloads.push(pipelinePayload);
    }

    if (segment.beforeOperator === "|" && pipelinePayload !== null && pipelinePayload !== "") {
      payloads.push(...xargsPipelinePayloads(segment.words, pipelinePayload));
    }

    for (const inputPayload of hereStringPayloads(segment.words)) {
      payloads.push(...xargsPipelinePayloads(segment.words, inputPayload));
    }

    if (commandHasHeredoc(segment.words)) {
      const heredocPayload = heredocPayloadFromSegment(commandText, segment.words) ?? firstHeredocPayloadFromCommandText(commandText);

      if (heredocPayload !== null && heredocPayload !== "") {
        payloads.push(...xargsPipelinePayloads(segment.words, heredocPayload));
      }
    }

    if (segment.afterOperator !== "|") {
      pipelinePayload = null;
      continue;
    }

    const producerPayload = stdoutLiteralPayload(segment.words)
      ?? (commandHasHeredoc(segment.words) ? heredocPayloadFromSegment(commandText, segment.words) ?? catHeredocPayloadFromCommandText(commandText) : null);

    if (producerPayload !== null && producerPayload !== "") {
      pipelinePayload = producerPayload;
      continue;
    }

    if (pipelinePayload !== null && commandPassesStdin(segment.words)) {
      continue;
    }

    pipelinePayload = null;
  }

  return payloads;
}

function isGitHelpOption(word) {
  return word === "-h" || word === "--help" || word === "--man" || word === "--info";
}

function gitSubcommandDetails(words, startIndex) {
  const optionsWithValues = new Set(["-C", "-c", "--exec-path", "--git-dir", "--work-tree", "--namespace", "--config-env"]);

  for (let index = startIndex; index < words.length; index += 1) {
    const word = words[index];
    const nextIndex = skipRedirection(words, index);

    if (nextIndex !== index) {
      index = nextIndex - 1;
      continue;
    }

    if (word === "--") {
      return { subcommand: words[index + 1] ?? "", index: index + 1 };
    }

    if (isGitHelpOption(word)) {
      return { subcommand: "", index: -1 };
    }

    if (optionsWithValues.has(word)) {
      index = indexAfterOptionOperand(words, index + 1) - 1;
      continue;
    }

    if (/^--(?:exec-path|git-dir|work-tree|namespace|config-env)=/.test(word)) {
      continue;
    }

    if (word.startsWith("-")) {
      continue;
    }

    return { subcommand: word, index };
  }

  return { subcommand: "", index: -1 };
}

function gitRepositoryOverrideOption(words, startIndex) {
  const optionsWithValues = new Set(["-c", "--exec-path", "--namespace", "--config-env"]);

  for (let index = startIndex; index < words.length; index += 1) {
    const word = words[index];
    const nextIndex = skipRedirection(words, index);

    if (nextIndex !== index) {
      index = nextIndex - 1;
      continue;
    }

    if (word === "--") {
      return "";
    }

    if (isGitHelpOption(word)) {
      return "";
    }

    if (word === "-C" || (word.startsWith("-C") && word !== "-c")) {
      return "-C";
    }

    if (word === "--git-dir" || word === "--work-tree") {
      return word;
    }

    if (/^--(?:git-dir|work-tree)=/.test(word)) {
      return word.split("=", 1)[0];
    }

    if (optionsWithValues.has(word)) {
      index = indexAfterOptionOperand(words, index + 1) - 1;
      continue;
    }

    if (/^--(?:exec-path|namespace|config-env)=/.test(word)) {
      continue;
    }

    if (word.startsWith("-")) {
      continue;
    }

    return "";
  }

  return "";
}

function gitEnvironmentRepositoryOverrideOption(words, limitIndex) {
  for (let index = 0; index < Math.min(limitIndex, words.length); index += 1) {
    const nextIndex = skipRedirection(words, index);

    if (nextIndex !== index) {
      index = nextIndex - 1;
      continue;
    }

    const match = String(words[index]).match(/^([A-Za-z_][A-Za-z0-9_]*)=/);

    if (match && GIT_REPOSITORY_ENV_NAMES.has(match[1])) {
      return match[1];
    }
  }

  return "";
}

function gitRepositoryEnvName(word) {
  const match = String(word ?? "").match(/^([A-Za-z_][A-Za-z0-9_]*)(?:=.*)?$/);

  if (match && GIT_REPOSITORY_ENV_NAMES.has(match[1])) {
    return match[1];
  }

  return "";
}

function shellExportsGitRepositoryEnv(segment) {
  const executableIndex = firstExecutableIndex(segment);
  const commandName = executableIndex >= 0 ? executableName(segment[executableIndex]) : "";

  if (commandName !== "declare" && commandName !== "export" && commandName !== "typeset") {
    return false;
  }

  for (let index = executableIndex + 1; index < segment.length; index += 1) {
    const nextIndex = skipRedirection(segment, index);

    if (nextIndex !== index) {
      index = nextIndex - 1;
      continue;
    }

    const word = segment[index];

    if (word === "--") {
      continue;
    }

    if (word.startsWith("-") || word.startsWith("+")) {
      continue;
    }

    if (gitRepositoryEnvName(word) !== "") {
      return true;
    }
  }

  return false;
}

function segmentSetsGitRepositoryEnv(segment) {
  for (let index = 0; index < segment.length; index += 1) {
    const nextIndex = skipRedirection(segment, index);

    if (nextIndex !== index) {
      index = nextIndex - 1;
      continue;
    }

    const word = segment[index];

    if (!isAssignment(word)) {
      return false;
    }

    if (gitRepositoryEnvName(word) !== "") {
      return true;
    }
  }

  return false;
}

function commandHasGitRepositoryOverride(commandText, depth = 0) {
  if (depth > MAX_RECURSION_DEPTH) {
    return false;
  }

  for (const payload of shellFunctionCallPayloads(commandText)) {
    if (commandHasGitRepositoryOverride(payload, depth + 1)) {
      return true;
    }
  }

  for (const segment of commandSegments(shellTokens(commandText))) {
    for (const payload of [evalPayload(segment), shellCommandPayload(segment), windowsShellCommandPayload(segment)]) {
      if (payload !== null && commandHasGitRepositoryOverride(payload, depth + 1)) {
        return true;
      }
    }
  }

  for (const payload of [
    ...commandPositionSubstitutionPayloads(commandText),
    ...shellStdinPayloads(commandText),
    ...shellProcessSubstitutionPayloads(commandText),
    ...outputProcessSubstitutionPayloads(commandText),
    ...stdoutRedirectScriptPayloads(commandText),
    ...heredocScriptPayloads(commandText),
  ]) {
    if (commandHasGitRepositoryOverride(payload, depth + 1)) {
      return true;
    }
  }

  const normalizedCommandText = stripHeredocBodies(commandText);
  const segments = commandSegments(shellTokens(normalizedCommandText));

  for (const segment of segments) {
    if (segmentSetsGitRepositoryEnv(segment)) {
      return true;
    }

    const envPayload = envSplitStringPayload(segment);

    if (envPayload !== null) {
      if (commandHasGitRepositoryOverride(envPayload, depth + 1)) {
        return true;
      }

      continue;
    }

    for (const payload of [evalPayload(segment), shellCommandPayload(segment), windowsShellCommandPayload(segment)]) {
      if (payload !== null && commandHasGitRepositoryOverride(payload, depth + 1)) {
        return true;
      }
    }

    for (const payload of helperCommandPayloads(segment)) {
      if (commandHasGitRepositoryOverride(payload, depth + 1)) {
        return true;
      }
    }

    if (shellExportsGitRepositoryEnv(segment)) {
      return true;
    }

    const executableIndex = firstExecutableIndex(segment);

    if (executableIndex >= 0
      && executableName(segment[executableIndex]) === "git"
      && gitEnvironmentRepositoryOverrideOption(segment, executableIndex) !== "") {
      return true;
    }

    if (executableIndex >= 0
      && executableName(segment[executableIndex]) === "git"
      && gitRepositoryOverrideOption(segment, executableIndex + 1) !== "") {
      return true;
    }
  }

  if (depth < 5) {
    const substitutionScanText = stripHeredocBodies(commandText, { quotedOnly: true });

    for (const substitutionText of executableSubstitutionTexts(substitutionScanText)) {
      if (commandHasGitRepositoryOverride(substitutionText, depth + 1)) {
        return true;
      }
    }
  }

  return false;
}

function commandChangesDirectory(commandText, depth = 0) {
  if (depth > MAX_RECURSION_DEPTH) {
    return false;
  }

  for (const payload of shellFunctionCallPayloads(commandText)) {
    if (commandChangesDirectory(payload, depth + 1)) {
      return true;
    }
  }

  for (const segment of commandSegments(shellTokens(commandText))) {
    for (const payload of [evalPayload(segment), shellCommandPayload(segment), windowsShellCommandPayload(segment)]) {
      if (payload !== null && commandChangesDirectory(payload, depth + 1)) {
        return true;
      }
    }
  }

  for (const payload of [
    ...commandPositionSubstitutionPayloads(commandText),
    ...shellStdinPayloads(commandText),
    ...shellProcessSubstitutionPayloads(commandText),
    ...outputProcessSubstitutionPayloads(commandText),
    ...stdoutRedirectScriptPayloads(commandText),
    ...heredocScriptPayloads(commandText),
  ]) {
    if (commandChangesDirectory(payload, depth + 1)) {
      return true;
    }
  }

  const normalizedCommandText = stripHeredocBodies(commandText);
  const segments = commandSegments(shellTokens(normalizedCommandText));

  for (const segment of segments) {
    const envPayload = envSplitStringPayload(segment);

    if (envPayload !== null) {
      if (commandChangesDirectory(envPayload, depth + 1)) {
        return true;
      }

      continue;
    }

    for (const payload of [evalPayload(segment), shellCommandPayload(segment), windowsShellCommandPayload(segment)]) {
      if (payload !== null && commandChangesDirectory(payload, depth + 1)) {
        return true;
      }
    }

    for (const payload of helperCommandPayloads(segment)) {
      if (commandChangesDirectory(payload, depth + 1)) {
        return true;
      }
    }

    const executableIndex = firstExecutableIndex(segment);
    const commandName = executableIndex >= 0 ? executableName(segment[executableIndex]) : "";

    if (commandName === "cd" || commandName === "pushd" || commandName === "popd") {
      return true;
    }
  }

  if (depth < 5) {
    const substitutionScanText = stripHeredocBodies(commandText, { quotedOnly: true });

    for (const substitutionText of executableSubstitutionTexts(substitutionScanText)) {
      if (commandChangesDirectory(substitutionText, depth + 1)) {
        return true;
      }
    }
  }

  return false;
}

function commandTargetsAnotherRepoContext(commandText) {
  return commandHasGitRepositoryOverride(commandText) || commandChangesDirectory(commandText);
}

function assignmentValueBeforeIndex(words, name, limitIndex) {
  let value = process.env[String(name)] ?? "";

  for (let index = 0; index < Math.min(limitIndex, words.length); index += 1) {
    const nextIndex = skipRedirection(words, index);

    if (nextIndex !== index) {
      index = nextIndex - 1;
      continue;
    }

    const match = String(words[index]).match(/^([A-Za-z_][A-Za-z0-9_]*)=(.*)$/);

    if (match && match[1] === name) {
      value = match[2];
    }
  }

  return value;
}

function addGitConfigEnvAlias(aliases, configText, words, gitIndex) {
  const match = String(configText).match(/^alias\.([^=]+)=([A-Za-z_][A-Za-z0-9_]*)$/i);

  if (!match) {
    return;
  }

  const value = assignmentValueBeforeIndex(words, match[2], gitIndex);

  if (value !== "") {
    addGitAliasConfig(aliases, `alias.${match[1]}=${value}`);
  }
}

function gitConfigAliases(words, gitIndex, startIndex) {
  const aliases = new Map();
  const optionsWithValues = new Set(["-C", "-c", "--exec-path", "--git-dir", "--work-tree", "--namespace", "--config-env"]);

  for (let index = startIndex; index < words.length; index += 1) {
    const word = words[index];
    const nextIndex = skipRedirection(words, index);

    if (nextIndex !== index) {
      index = nextIndex - 1;
      continue;
    }

    if (word === "--") {
      break;
    }

    if (word === "-c") {
      const config = optionOperand(words, index + 1);
      addGitAliasConfig(aliases, config.value);
      index = config.index;
      continue;
    }

    if (word === "--config-env") {
      const config = optionOperand(words, index + 1);
      addGitConfigEnvAlias(aliases, config.value, words, gitIndex);
      index = config.index;
      continue;
    }

    if (word.startsWith("--config-env=")) {
      addGitConfigEnvAlias(aliases, word.slice("--config-env=".length), words, gitIndex);
      continue;
    }

    if (optionsWithValues.has(word)) {
      index = indexAfterOptionOperand(words, index + 1) - 1;
      continue;
    }

    if (/^--(?:exec-path|git-dir|work-tree|namespace|config-env)=/.test(word)) {
      continue;
    }

    if (word.startsWith("-")) {
      continue;
    }

    break;
  }

  return aliases;
}

function aliasForwardsRemainingArgs(commandText) {
  for (const segment of commandSegments(shellTokens(commandText))) {
    if (evalPayload(segment) === "$@" || shellCommandPayload(segment) === "$@") {
      return true;
    }

    const executableIndex = firstExecutableIndex(segment);

    if (executableIndex >= 0 && segment[executableIndex] === "$@") {
      return true;
    }
  }

  return false;
}

function aliasForwardsRemainingArgsToGit(commandText) {
  for (const segment of commandSegments(shellTokens(commandText))) {
    const executableIndex = firstExecutableIndex(segment);

    if (executableIndex < 0 || executableName(segment[executableIndex]) !== "git") {
      continue;
    }

    const subcommand = gitSubcommandDetails(segment, executableIndex + 1).subcommand;

    if (subcommand === "$@" || subcommand === "$*") {
      return true;
    }
  }

  return false;
}

function addGitAliasConfig(aliases, configText) {
  const match = String(configText).match(/^alias\.([^=]+)=(.*)$/i);

  if (!match) {
    return;
  }

  const aliasName = match[1].trim().toLowerCase();

  if (aliasName !== "") {
    aliases.set(aliasName, match[2]);
  }
}

function directGitAction(words, aliases, depth) {
  const subcommandDetails = gitSubcommandDetails(words, 1);
  const subcommand = subcommandDetails.subcommand;

  if (subcommandDetails.index < 0 || subcommand === "") {
    return "";
  }

  const aliasAction = gitAliasAction(subcommand, aliases, words.slice(subcommandDetails.index + 1), depth + 1);

  if (aliasAction) {
    return aliasAction;
  }

  if ((subcommand === "commit" || subcommand === "push") && !gitSubcommandRequestsHelp(words, subcommandDetails.index + 1, subcommand)) {
    return subcommand;
  }

  return nestedGitPushAction(subcommand, words.slice(subcommandDetails.index + 1));
}

function guardedGitSubcommandWithAliases(commandText, aliases, depth) {
  for (const segment of commandSegments(shellTokens(commandText))) {
    const executableIndex = firstExecutableIndex(segment);

    if (executableIndex >= 0 && executableName(segment[executableIndex]) === "git") {
      const action = directGitAction(segment.slice(executableIndex), aliases, depth);

      if (action) {
        return action;
      }
    }
  }

  return guardedGitSubcommand(commandText, depth);
}

function gitAliasAction(subcommand, aliases, remainingWords, depth) {
  if (depth > MAX_RECURSION_DEPTH) {
    return "push";
  }

  const aliasValue = aliases.get(String(subcommand).toLowerCase());

  if (aliasValue === undefined) {
    return "";
  }

  const trimmedValue = aliasValue.trim();

  if (trimmedValue === "") {
    return "";
  }

  const remainingText = commandTextFromArgvWords(remainingWords);
  const unquotedRemainingText = remainingWords.join(" ");

  if (trimmedValue.startsWith("!")) {
    const aliasCommand = trimmedValue.slice(1);
    const renderedAliasCommand = renderShellPayloadWithPositionals(aliasCommand, [aliasCommand, ...remainingWords]);
    const remainingAsGitText = ["git", remainingText].filter(Boolean).join(" ");
    const unquotedRemainingAsGitText = ["git", unquotedRemainingText].filter(Boolean).join(" ");

    if (aliasForwardsRemainingArgsToGit(aliasCommand)) {
      const forwardedGitAction = guardedGitSubcommandWithAliases(remainingAsGitText, aliases, depth + 1)
        || guardedGitSubcommandWithAliases(unquotedRemainingAsGitText, aliases, depth + 1);

      if (forwardedGitAction) {
        return forwardedGitAction;
      }
    }

    if (aliasForwardsRemainingArgs(aliasCommand)) {
      const remainingAction = guardedGitSubcommandWithAliases(remainingText, aliases, depth + 1)
        || guardedGitSubcommandWithAliases(unquotedRemainingText, aliases, depth + 1);

      if (remainingAction) {
        return remainingAction;
      }
    }

    return guardedGitSubcommandWithAliases(renderedAliasCommand, aliases, depth + 1);
  }

  const aliasSegments = commandSegments(shellTokens(trimmedValue));

  if (aliasSegments.length === 1) {
    const action = directGitAction(["git", ...aliasSegments[0], ...remainingWords], aliases, depth + 1);

    if (action) {
      return action;
    }
  }

  return guardedGitSubcommandWithAliases(["git", trimmedValue, remainingText].filter(Boolean).join(" "), aliases, depth + 1);
}

function gitSubcommandHelpOptionSets(subcommand) {
  if (subcommand === "commit") {
    return {
      optionsWithValues: new Set(["-C", "-c", "-F", "-m", "-t"]),
      longOptionsWithValues: new Set([
        "--author",
        "--cleanup",
        "--date",
        "--file",
        "--fixup",
        "--message",
        "--pathspec-from-file",
        "--reuse-message",
        "--reedit-message",
        "--squash",
        "--template",
        "--trailer",
      ]),
    };
  }

  if (subcommand === "push") {
    return {
      optionsWithValues: new Set(["-o", "--exec", "--push-option", "--receive-pack", "--repo", "--recurse-submodules"]),
      longOptionsWithValues: new Set(["--exec", "--push-option", "--receive-pack", "--repo", "--recurse-submodules"]),
    };
  }

  return { optionsWithValues: new Set(), longOptionsWithValues: new Set() };
}

function gitSubcommandRequestsHelp(words, startIndex, subcommand = "") {
  const { optionsWithValues, longOptionsWithValues } = gitSubcommandHelpOptionSets(subcommand);
  let index = startIndex;

  while (index < words.length) {
    const word = words[index];
    const nextIndex = skipRedirection(words, index);

    if (nextIndex !== index) {
      index = nextIndex;
      continue;
    }

    if (word === "--") {
      return false;
    }

    if (optionsWithValues.has(word)) {
      index = indexAfterOptionOperand(words, index + 1);
      continue;
    }

    if ([...longOptionsWithValues].some((option) => word.startsWith(`${option}=`))) {
      index += 1;
      continue;
    }

    if (longOptionsWithValues.has(word)) {
      index = indexAfterOptionOperand(words, index + 1);
      continue;
    }

    const clusterValueOperand = shortClusterValueOperand(word, optionsWithValues);

    if (clusterValueOperand === "attached") {
      index += 1;
      continue;
    }

    if (clusterValueOperand === "next") {
      index = indexAfterOptionOperand(words, index + 1);
      continue;
    }

    if (isGitHelpOption(word)) {
      return true;
    }

    index += 1;
  }

  return false;
}

function gitSubcommand(words, startIndex) {
  return gitSubcommandDetails(words, startIndex).subcommand;
}

function gitSubmoduleForeachPayloads(words) {
  for (let index = 0; index < words.length; index += 1) {
    const word = words[index];

    if (word === "--") {
      continue;
    }

    if (isGitHelpOption(word)) {
      return [];
    }

    if (word === "foreach") {
      let payloadIndex = index + 1;

      while (payloadIndex < words.length && /^-/.test(words[payloadIndex])) {
        payloadIndex += 1;
      }

      const payload = words.slice(payloadIndex).join(" ");
      return payload === "" ? [] : [payload];
    }
  }

  return [];
}

function nestedGitPushAction(subcommand, words) {
  if (!new Set(["lfs", "subtree"]).has(subcommand)) {
    return "";
  }

  const optionsWithValues = subcommand === "subtree" ? new Set(["-P", "--prefix", "-m", "--message", "--annotate", "-b", "--branch", "--onto"]) : new Set(["-c"]);
  const longOptionsWithValues = subcommand === "subtree" ? new Set(["--prefix", "--message", "--annotate", "--branch", "--onto"]) : new Set();

  for (let index = 0; index < words.length; index += 1) {
    const word = words[index];
    const nextIndex = skipRedirection(words, index);

    if (nextIndex !== index) {
      index = nextIndex - 1;
      continue;
    }

    if (word === "--") {
      continue;
    }

    if (isGitHelpOption(word)) {
      return "";
    }

    if (optionsWithValues.has(word)) {
      index = indexAfterOptionOperand(words, index + 1) - 1;
      continue;
    }

    if ([...longOptionsWithValues].some((option) => word.startsWith(`${option}=`))) {
      continue;
    }

    if (word.startsWith("-")) {
      continue;
    }

    if (word === "push") {
      return gitSubcommandRequestsHelp(words, index + 1, "push") ? "" : "push";
    }

    return "";
  }

  return "";
}

function findExecPayloads(words) {
  const payloads = [];
  const execPrimaries = new Set(["-exec", "-execdir", "-ok", "-okdir"]);

  for (let index = 0; index < words.length; index += 1) {
    if (!execPrimaries.has(words[index])) {
      continue;
    }

    const payload = [];
    for (let payloadIndex = index + 1; payloadIndex < words.length; payloadIndex += 1) {
      const word = words[payloadIndex];

      if (word === ";" || word === "+") {
        index = payloadIndex;
        break;
      }

      payload.push(word);
      index = payloadIndex;
    }

    if (payload.length > 0) {
      payloads.push(commandTextFromArgvWords(payload));
    }
  }

  return payloads;
}

function shellQuoteWord(word) {
  if (word === "") {
    return "''";
  }

  if (/^[A-Za-z0-9_@%+=:,./{}-]+$/.test(word)) {
    return word;
  }

  return `'${word.replace(/'/g, "'\\''")}'`;
}

function commandTextFromArgvWords(words) {
  return words.map(shellQuoteWord).join(" ");
}

function skipHelperOptions(words, optionsWithValues, longOptionsWithValues) {
  let index = 0;

  while (index < words.length) {
    const word = words[index];
    const nextIndex = skipRedirection(words, index);

    if (nextIndex !== index) {
      index = nextIndex;
      continue;
    }

    if (word === "--") {
      return index + 1;
    }

    if (optionsWithValues.has(word)) {
      index = indexAfterOptionOperand(words, index + 1);
      continue;
    }

    if ([...longOptionsWithValues].some((option) => word.startsWith(`${option}=`))) {
      index += 1;
      continue;
    }

    if (longOptionsWithValues.has(word)) {
      index = indexAfterOptionOperand(words, index + 1);
      continue;
    }

    const clusterValueOperand = shortClusterValueOperand(word, optionsWithValues);

    if (clusterValueOperand === "attached") {
      index += 1;
      continue;
    }

    if (clusterValueOperand === "next") {
      index = indexAfterOptionOperand(words, index + 1);
      continue;
    }

    if (word.startsWith("-")) {
      index += 1;
      continue;
    }

    return index;
  }

  return words.length;
}

const XARGS_OPTIONS_WITH_VALUES = new Set(["-a", "-d", "-E", "-J", "-L", "-l", "-n", "-P", "-R", "-S", "-s"]);
const XARGS_LONG_OPTIONS_WITH_VALUES = new Set([
  "--arg-file",
  "--delimiter",
  "--max-args",
  "--max-chars",
  "--max-lines",
  "--max-procs",
]);

function xargsCommandPlan(words) {
  let index = 0;
  let replacement = "";
  let delimiter = null;

  while (index < words.length) {
    const word = words[index];
    const nextIndex = skipRedirection(words, index);

    if (nextIndex !== index) {
      index = nextIndex;
      continue;
    }

    if (word === "--") {
      return { index: index + 1, replacement, delimiter };
    }

    if (word === "-0" || word === "--null") {
      delimiter = "\0";
      index += 1;
      continue;
    }

    if (word === "-I") {
      const operand = optionOperand(words, index + 1);
      replacement = operand.value || "{}";
      index = operand.index < words.length ? operand.index + 1 : operand.index;
      continue;
    }

    if (word.startsWith("-I") && word !== "-I") {
      replacement = word.slice(2) || "{}";
      index += 1;
      continue;
    }

    if (word === "-i" || word === "--replace") {
      replacement = "{}";
      index += 1;
      continue;
    }

    if (word.startsWith("-i") && word !== "-i") {
      replacement = word.slice(2) || "{}";
      index += 1;
      continue;
    }

    if (word === "-d" || word === "--delimiter") {
      const operand = optionOperand(words, index + 1);
      delimiter = xargsDelimiter(operand.value);
      index = operand.index < words.length ? operand.index + 1 : operand.index;
      continue;
    }

    if (word.startsWith("-d") && word !== "-d") {
      delimiter = xargsDelimiter(word.slice(2));
      index += 1;
      continue;
    }

    if (word.startsWith("--replace=")) {
      replacement = word.slice("--replace=".length) || "{}";
      index += 1;
      continue;
    }

    if (word.startsWith("--delimiter=")) {
      delimiter = xargsDelimiter(word.slice("--delimiter=".length));
      index += 1;
      continue;
    }

    if (XARGS_OPTIONS_WITH_VALUES.has(word)) {
      index = indexAfterOptionOperand(words, index + 1);
      continue;
    }

    if ([...XARGS_LONG_OPTIONS_WITH_VALUES].some((option) => word.startsWith(`${option}=`))) {
      index += 1;
      continue;
    }

    if (XARGS_LONG_OPTIONS_WITH_VALUES.has(word)) {
      index = indexAfterOptionOperand(words, index + 1);
      continue;
    }

    const clusterValueOperand = shortClusterValueOperand(word, XARGS_OPTIONS_WITH_VALUES);

    if (clusterValueOperand === "attached") {
      index += 1;
      continue;
    }

    if (clusterValueOperand === "next") {
      index = indexAfterOptionOperand(words, index + 1);
      continue;
    }

    if (word.startsWith("-")) {
      index += 1;
      continue;
    }

    return { index, replacement, delimiter };
  }

  return { index: words.length, replacement, delimiter };
}

function xargsDelimiter(value) {
  const decoded = decodeAnsiCString(String(value ?? ""));
  return decoded === "" ? "" : decoded[0];
}

function xargsDelimitedInputRecords(inputPayload, delimiter) {
  if (delimiter === "") {
    return [];
  }

  return String(inputPayload).split(delimiter).map((record) => record.trim()).filter(Boolean);
}

function xargsInputRecords(inputPayload, plan) {
  if (plan.delimiter !== null) {
    return xargsDelimitedInputRecords(inputPayload, plan.delimiter);
  }

  const text = String(inputPayload).trim();

  if (text === "") {
    return [];
  }

  if (plan.replacement !== "") {
    return text.split(/\r?\n/).map((line) => line.trim()).filter(Boolean);
  }

  return text.split(/\s+/).filter(Boolean);
}

function xargsPipelinePayloads(words, inputPayload) {
  const executableIndex = firstExecutableIndex(words);

  if (executableIndex < 0 || executableName(words[executableIndex]) !== "xargs") {
    return [];
  }

  const plan = xargsCommandPlan(words.slice(executableIndex + 1));
  const commandWords = words.slice(executableIndex + 1 + plan.index);
  const records = xargsInputRecords(inputPayload, plan);

  if (commandWords.length === 0 || records.length === 0) {
    return [];
  }

  if (plan.replacement === "") {
    return [commandTextFromArgvWords([...commandWords, ...records])];
  }

  return records.map((record) => commandTextFromArgvWords(
    commandWords.map((word) => word.split(plan.replacement).join(record))
  ));
}

function xargsPayload(words) {
  const { index } = xargsCommandPlan(words);
  const payload = commandTextFromArgvWords(words.slice(index));

  return payload === "" ? null : payload;
}

function watchPayload(words) {
  const index = skipHelperOptions(
    words,
    new Set(["-n"]),
    new Set(["--interval"])
  );
  const payload = words.slice(index).join(" ");

  return payload === "" ? null : payload;
}

function parallelPayloads(words) {
  const index = skipHelperOptions(
    words,
    new Set(["-a", "-C", "-j", "-L", "-n", "-N", "-S"]),
    new Set([
      "--arg-file",
      "--colsep",
      "--jobs",
      "--joblog",
      "--load",
      "--max-args",
      "--results",
      "--sshlogin",
      "--sshloginfile",
      "--tagstring",
      "--template",
      "--tmpdir",
      "--workdir",
    ])
  );
  const restWords = words.slice(index);
  const separatorIndex = restWords.findIndex((word) => word === ":::" || word === "::::");

  if (separatorIndex === 0 && restWords[0] === ":::") {
    return restWords.slice(1).filter((word) => word !== ":::" && word !== "::::");
  }

  if (separatorIndex > 0) {
    const templateWords = restWords.slice(0, separatorIndex);
    const records = restWords.slice(separatorIndex + 1).filter((word) => word !== ":::" && word !== "::::");

    if (records.length > 0 && templateWords.some((word) => word.includes("{}"))) {
      return records.map((record) => commandTextFromArgvWords(
        templateWords.map((word) => word.split("{}").join(record))
      ));
    }

    if (records.length > 0) {
      return records.map((record) => commandTextFromArgvWords([...templateWords, record]));
    }
  }

  const payloadWords = separatorIndex < 0 ? restWords : restWords.slice(0, separatorIndex);
  const payload = payloadWords.join(" ");

  return payload === "" ? [] : [payload];
}

function flockPayload(words) {
  for (let index = 0; index < words.length; index += 1) {
    const nextIndex = skipRedirection(words, index);

    if (nextIndex !== index) {
      index = nextIndex - 1;
      continue;
    }

    const word = words[index];

    if (word === "-c" || word === "--command") {
      return optionOperand(words, index + 1).value || null;
    }

    if (word.startsWith("-c") && word !== "-c") {
      return word.slice(2) || null;
    }

    if (word.startsWith("--command=")) {
      return word.slice("--command=".length) || null;
    }
  }

  const index = skipHelperOptions(
    words,
    new Set(["-E", "-w"]),
    new Set(["--conflict-exit-code", "--timeout"])
  );

  if (index >= words.length) {
    return null;
  }

  let payloadIndex = index + 1;

  if (words[payloadIndex] === "-c" || words[payloadIndex] === "--command") {
    return optionOperand(words, payloadIndex + 1).value || null;
  }

  if (String(words[payloadIndex] ?? "").startsWith("--command=")) {
    return words[payloadIndex].slice("--command=".length) || null;
  }

  const payload = commandTextFromArgvWords(words.slice(payloadIndex));
  return payload === "" ? null : payload;
}

function scriptPayloads(words) {
  const commandPayload = commandOptionPayload(words, "-c", "--command");

  if (commandPayload !== null) {
    return [commandPayload];
  }

  const index = skipHelperOptions(
    words,
    new Set(["-t", "-T"]),
    new Set(["--log-timing", "--logging-format", "--timing"])
  );
  const payloadWords = words.slice(index + 1);
  const payload = commandTextFromArgvWords(payloadWords);

  return payload === "" ? [] : [payload];
}

function commandOptionPayload(words, shortOption, longOption) {
  const longOptions = Array.isArray(longOption) ? longOption : [longOption];

  for (let index = 0; index < words.length; index += 1) {
    const nextIndex = skipRedirection(words, index);

    if (nextIndex !== index) {
      index = nextIndex - 1;
      continue;
    }

    const word = words[index];

    if (word === shortOption) {
      return optionOperand(words, index + 1).value || null;
    }

    if (/^-[A-Za-z0-9]$/.test(shortOption) && word.startsWith(shortOption) && word !== shortOption) {
      return word.slice(shortOption.length) || null;
    }

    for (const option of longOptions) {
      if (word === option) {
        return optionOperand(words, index + 1).value || null;
      }

      if (word.startsWith(`${option}=`)) {
        return word.slice(option.length + 1) || null;
      }
    }
  }

  return null;
}

function trapPayload(words) {
  for (let index = 0; index < words.length; index += 1) {
    const nextIndex = skipRedirection(words, index);

    if (nextIndex !== index) {
      index = nextIndex - 1;
      continue;
    }

    const word = words[index];

    if (word === "--") {
      continue;
    }

    if (word === "-" || word === "-l" || word === "-p" || word === "--help") {
      return null;
    }

    return word;
  }

  return null;
}

function cmdStartPayload(words) {
  const optionsWithValues = new Set(["/affinity", "/d", "/machine", "/node"]);
  let index = 0;

  while (index < words.length) {
    const nextIndex = skipRedirection(words, index);

    if (nextIndex !== index) {
      index = nextIndex;
      continue;
    }

    const word = words[index];
    const lowerWord = String(word).toLowerCase();

    if (optionsWithValues.has(lowerWord)) {
      index = indexAfterOptionOperand(words, index + 1);
      continue;
    }

    if (word.startsWith("/")) {
      index += 1;
      continue;
    }

    let payloadWords = words.slice(index);

    if (payloadWords.length > 1 && !cmdStartLooksExecutable(payloadWords[0]) && cmdStartLooksExecutable(payloadWords[1])) {
      payloadWords = payloadWords.slice(1);
    }

    const payload = commandTextFromArgvWords(payloadWords);
    return payload === "" ? null : payload;
  }

  return null;
}

function cmdStartLooksExecutable(word) {
  const commandName = executableName(word);
  const knownCommands = new Set([
    "call",
    "cmd",
    "find",
    "flock",
    "git",
    "parallel",
    "powershell",
    "pwsh",
    "script",
    "sh",
    "start",
    "start-process",
    "su",
    "watch",
    "xargs",
  ]);

  return knownCommands.has(commandName)
    || SHELL_NAMES.has(commandName)
    || WINDOWS_SHELL_NAMES.has(commandName)
    || String(word).startsWith(".")
    || String(word).includes("/")
    || String(word).includes("\\")
    || /\.exe$/i.test(String(word));
}

function powershellArgumentListWords(value) {
  return String(value).split(/[,\s]+/).filter(Boolean);
}

function powershellStartProcessPayload(words) {
  const optionsWithValues = new Set([
    "-argumentlist",
    "-credential",
    "-filepath",
    "-redirectstandarderror",
    "-redirectstandardinput",
    "-redirectstandardoutput",
    "-verb",
    "-windowstyle",
    "-workingdirectory",
  ]);
  let filePath = "";
  const argumentWords = [];

  for (let index = 0; index < words.length; index += 1) {
    const nextIndex = skipRedirection(words, index);

    if (nextIndex !== index) {
      index = nextIndex - 1;
      continue;
    }

    const word = words[index];
    const lowerWord = String(word).toLowerCase();
    const separatorIndex = Math.max(word.indexOf(":"), word.indexOf("="));

    if (lowerWord === "-filepath") {
      const operand = optionOperand(words, index + 1);
      filePath = operand.value;
      index = operand.index;
      continue;
    }

    if (lowerWord.startsWith("-filepath:") || lowerWord.startsWith("-filepath=")) {
      filePath = word.slice(separatorIndex + 1);
      continue;
    }

    if (lowerWord === "-argumentlist" || lowerWord === "-args") {
      const operand = optionOperand(words, index + 1);
      argumentWords.push(...powershellArgumentListWords(operand.value));
      index = operand.index;
      continue;
    }

    if (lowerWord.startsWith("-argumentlist:") || lowerWord.startsWith("-argumentlist=") || lowerWord.startsWith("-args:") || lowerWord.startsWith("-args=")) {
      argumentWords.push(...powershellArgumentListWords(word.slice(separatorIndex + 1)));
      continue;
    }

    if (optionsWithValues.has(lowerWord)) {
      index = indexAfterOptionOperand(words, index + 1) - 1;
      continue;
    }

    if (word.startsWith("-")) {
      continue;
    }

    if (filePath === "") {
      filePath = word;
    } else {
      argumentWords.push(word);
    }
  }

  const payload = commandTextFromArgvWords([filePath, ...argumentWords].filter(Boolean));
  return payload === "" ? null : payload;
}

function helperCommandPayloads(words) {
  const executableIndex = firstExecutableIndex(words);

  if (executableIndex < 0) {
    return [];
  }

  const commandName = executableName(words[executableIndex]);
  const restWords = words.slice(executableIndex + 1);
  const payloads = [];

  if (commandName === "start") {
    payloads.push(cmdStartPayload(restWords));
  }

  if (commandName === "start-process") {
    payloads.push(powershellStartProcessPayload(restWords));
  }

  if (commandName === "call") {
    payloads.push(commandTextFromArgvWords(restWords));
  }

  if (commandName === "find") {
    payloads.push(...findExecPayloads(restWords));
  }

  if (commandName === "xargs") {
    payloads.push(xargsPayload(restWords));
  }

  if (commandName === "watch") {
    payloads.push(watchPayload(restWords));
  }

  if (commandName === "parallel") {
    payloads.push(...parallelPayloads(restWords));
  }

  if (commandName === "script") {
    payloads.push(...scriptPayloads(restWords));
  }

  if (commandName === "flock") {
    payloads.push(flockPayload(restWords));
  }

  if (commandName === "su") {
    payloads.push(commandOptionPayload(restWords, "-c", ["--command", "--session-command"]));
  }

  if (commandName === "trap") {
    payloads.push(trapPayload(restWords));
  }

  return payloads.filter((payload) => payload !== null && payload !== "");
}

function guardedGitSubcommand(commandText, depth = 0) {
  if (depth > MAX_RECURSION_DEPTH) {
    return mentionedGuardedGitSubcommand(commandText) || "push";
  }

  for (const payload of shellFunctionCallPayloads(commandText)) {
    const subcommand = guardedGitSubcommand(payload, depth + 1);

    if (subcommand) {
      return subcommand;
    }
  }

  for (const segment of commandSegments(shellTokens(commandText))) {
    for (const payload of [evalPayload(segment), shellCommandPayload(segment), windowsShellCommandPayload(segment)]) {
      if (payload !== null) {
        const mentionedSubcommand = mentionedGuardedGitInSubstitutions(payload);

        if (mentionedSubcommand) {
          return mentionedSubcommand;
        }

        const subcommand = guardedGitSubcommand(payload, depth + 1);

        if (subcommand) {
          return subcommand;
        }
      }
    }
  }

  for (const payload of [
    ...commandPositionSubstitutionPayloads(commandText),
    ...shellStdinPayloads(commandText),
    ...shellProcessSubstitutionPayloads(commandText),
    ...outputProcessSubstitutionPayloads(commandText),
    ...stdoutRedirectScriptPayloads(commandText),
    ...heredocScriptPayloads(commandText),
  ]) {
    const subcommand = guardedGitSubcommand(payload, depth + 1);

    if (subcommand) {
      return subcommand;
    }
  }

  const normalizedCommandText = stripHeredocBodies(commandText);
  const segments = commandSegments(shellTokens(normalizedCommandText));

  for (const segment of segments) {
    const envPayload = envSplitStringPayload(segment);

    if (envPayload !== null) {
      const subcommand = guardedGitSubcommand(envPayload, depth + 1);

      if (subcommand) {
        return subcommand;
      }

      continue;
    }

    for (const payload of [evalPayload(segment), shellCommandPayload(segment), windowsShellCommandPayload(segment)]) {
      if (payload !== null) {
        const mentionedSubcommand = mentionedGuardedGitInSubstitutions(payload);

        if (mentionedSubcommand) {
          return mentionedSubcommand;
        }

        const subcommand = guardedGitSubcommand(payload, depth + 1);

        if (subcommand) {
          return subcommand;
        }
      }
    }

    // Some helpers execute argv as commands; inspect those payloads without
    // reverting to broad text matching that would block ordinary mentions.
    for (const payload of helperCommandPayloads(segment)) {
      const subcommand = guardedGitSubcommand(payload, depth + 1);

      if (subcommand) {
        return subcommand;
      }
    }

    const executableIndex = firstExecutableIndex(segment);

    if (executableIndex >= 0 && executableName(segment[executableIndex]) === "git") {
      const subcommandDetails = gitSubcommandDetails(segment, executableIndex + 1);
      const subcommand = subcommandDetails.subcommand;
      const aliases = gitConfigAliases(segment, executableIndex, executableIndex + 1);
      const aliasAction = gitAliasAction(subcommand, aliases, segment.slice(subcommandDetails.index + 1), depth);

      if (aliasAction) {
        return aliasAction;
      }

      if ((subcommand === "commit" || subcommand === "push") && !gitSubcommandRequestsHelp(segment, subcommandDetails.index + 1, subcommand)) {
        return subcommand;
      }

      const nestedAction = nestedGitPushAction(subcommand, segment.slice(subcommandDetails.index + 1));
      if (nestedAction) {
        return nestedAction;
      }

      if (subcommand === "submodule") {
        for (const payload of gitSubmoduleForeachPayloads(segment.slice(subcommandDetails.index + 1))) {
          const nestedSubcommand = guardedGitSubcommand(payload, depth + 1);

          if (nestedSubcommand) {
            return nestedSubcommand;
          }
        }
      }
    }
  }

  if (depth < 5) {
    const substitutionScanText = stripHeredocBodies(commandText, { quotedOnly: true });

    for (const substitutionText of executableSubstitutionTexts(substitutionScanText)) {
      const subcommand = guardedGitSubcommand(substitutionText, depth + 1);

      if (subcommand) {
        return subcommand;
      }
    }
  }

  return "";
}

if (/^\s*(?:(?:\/usr\/bin|\/bin)\/)?(?:bash|zsh|sh|dash|ksh|fish)(?:\s+-[\w-]+)*\s*$/.test(command)) {
  block("SDLC GUARD: Do not bypass checks through an interactive shell. Run the exact command directly so commit/push hooks can inspect it.");
  process.exit(0);
}

const subcommand = guardedGitSubcommand(command);

if (subcommand === "commit") {
  if (commandTargetsAnotherRepoContext(command)) {
    block("SDLC CHECKPOINT: git commit targets another repo context. Run from the target repo root and stamp fresh SDLC proof there.");
    process.exit(0);
  }
  const proof = sdlcProofStatus(commandCwd);
  if (proof.ok) {
    process.exit(0);
  }
  block(`SDLC CHECKPOINT: git commit is a hard manual checkpoint and requires fresh SDLC proof; ${proof.reason}. ${proof.hint}`);
  process.exit(0);
}

if (subcommand === "push") {
  if (commandTargetsAnotherRepoContext(command)) {
    block("SDLC CHECKPOINT: git push targets another repo context. Run from the target repo root and stamp fresh SDLC proof there.");
    process.exit(0);
  }
  const proof = sdlcProofStatus(commandCwd);
  if (proof.ok) {
    process.exit(0);
  }
  block(`SDLC CHECKPOINT: git push is a hard manual checkpoint and requires fresh SDLC proof; ${proof.reason}. ${proof.hint}`);
}
