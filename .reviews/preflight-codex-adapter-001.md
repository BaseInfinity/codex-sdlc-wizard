## Preflight Self-Review: Codex SDLC Adapter v1
- [x] Self-review via read-back of all files passed
- [x] All 15 tests passing
- [x] Checked for: macOS grep regex compat (fixed \s → [[:space:]] in install.sh)
- [x] Verified: hook payloads match Codex source (tool_input.command, ^Bash$ matcher)
- [x] Verified: blocking protocol uses legacy path (decision:block) per plan
- [x] Verified: install.sh non-destructive (backs up hooks.json, skips existing AGENTS.md)
- [x] Known limitations: Windows not supported (Codex disables hooks on Windows), TDD file-edit gate is soft only
