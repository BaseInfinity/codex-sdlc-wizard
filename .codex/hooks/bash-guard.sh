#!/bin/bash
# PreToolUse hook for Bash commands — blocks git commit/push without tests
# Input: JSON on stdin with tool_input.command (Codex Bash payload)
# Output: JSON on stdout with decision:block to deny, or empty to allow

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // .command // empty')

if echo "$COMMAND" | grep -qE '^[[:space:]]*((/usr/bin/|/bin/)?(bash|zsh|sh|dash|ksh|fish))( [[:space:]]*(-[[:alnum:]-]+))*[[:space:]]*$'; then
  echo '{"decision":"block","reason":"SDLC GUARD: Do not bypass checks through an interactive shell. Run the exact command directly so commit/push hooks can inspect it."}'
  exit 0
fi

if echo "$COMMAND" | grep -qE '(^|[[:space:]])git([[:space:]-][^[:space:]]+([[:space:]][^[:space:]]+)*)?[[:space:]]commit([[:space:]]|$)'; then
  echo '{"decision":"block","reason":"TDD CHECK: Did you run tests before committing? Run your full test suite first. ALL tests must pass."}'
  exit 0
fi

if echo "$COMMAND" | grep -qE '(^|[[:space:]])git([[:space:]-][^[:space:]]+([[:space:]][^[:space:]]+)*)?[[:space:]]push([[:space:]]|$)'; then
  echo '{"decision":"block","reason":"REVIEW CHECK: Did you self-review your changes and run all tests before pushing?"}'
  exit 0
fi
