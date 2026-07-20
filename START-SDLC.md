# Start SDLC

Codex does not have a native `/sdlc` command. Start the loop explicitly.

## Paste This At Session Start

```text
Work in SDLC mode for this repo.

Before editing:
1. Restate the task in one sentence.
2. Set a scope guard.
3. State confidence as HIGH, MEDIUM, or LOW.
4. Use high reasoning by default. Escalate security review, migrations, destructive operations, long-running research, or unusually difficult coding to xhigh when high leaves unresolved risk. Follow any measured repo-local exception.
5. Treat Max as a single-task escalation and Ultra as subagent-backed parallel-work escalation; most tasks do not need Max or Ultra.
6. Define the red check first.
7. Define the prove-it gate before coding.

During implementation:
- Make the smallest useful change.
- Keep the work to one slice at a time.
- If setup/auth work is involved, prefer full access and capture the evidence.

After implementation:
1. Run the targeted checks.
2. Summarize the prove-it evidence.
3. Review the diff for risk and junk.
4. Do not commit until the checks are green.
```

## Open These While Working

- `SDLC-LOOP.md`
- `PROVE-IT.md`
- `AGENTS.md`
