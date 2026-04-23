#!/bin/bash
cat <<'EOF'
Codex does not have a native /sdlc command.

Use this kickoff prompt:

Work in SDLC mode for this repo.

Before editing:
1. Restate the task in one sentence.
2. Set a scope guard.
3. State confidence as HIGH, MEDIUM, or LOW.
4. Use high reasoning by default. Only use xhigh if the task is blocked, architecturally ambiguous, or high-stakes.
5. Define the red check first.
6. Define the prove-it gate before coding.

During implementation:
- Make the smallest useful change.
- Keep the work to one slice at a time.
- If setup/auth work is involved, prefer full access and capture the evidence.

After implementation:
1. Run the targeted checks.
2. Summarize the prove-it evidence.
3. Review the diff for risk and junk.
4. Do not commit until the checks are green.

Open these files while working:
- SDLC-LOOP.md
- PROVE-IT.md
- AGENTS.md
EOF
