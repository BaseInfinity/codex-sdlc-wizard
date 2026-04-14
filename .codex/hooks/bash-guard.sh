#!/bin/bash
# PreToolUse hook for Bash commands — blocks git commit/push without tests
# Input: JSON on stdin with tool_input.command (Codex Bash payload)
# Output: JSON on stdout with decision:block to deny, or empty to allow

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

if echo "$COMMAND" | grep -qE 'git\s+commit'; then
  echo '{"decision":"block","reason":"TDD CHECK: Did you run tests before committing? Run your full test suite first. ALL tests must pass."}'
  exit 0
fi

if echo "$COMMAND" | grep -qE 'git\s+push'; then
  echo '{"decision":"block","reason":"REVIEW CHECK: Did you self-review your changes and run all tests before pushing?"}'
  exit 0
fi
