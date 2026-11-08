---
name: conduct
description: Coordinate registered Claude and Codex sessions for bounded reviews, design questions, and task handoffs. Use when the user asks one agent to consult, dispatch to, review with, or coordinate another Claude/Codex session, including CLI and desktop surfaces with an installed adapter.
---

# Conduct

Coordinate multiple agent sessions through one logical controller. One Conductor can conduct both ecosystems, but only sessions that are registered and reachable through a verified adapter. Never imply access to arbitrary dormant or unregistered sessions.

Read [references/protocol.md](references/protocol.md) before dispatching. It defines the exact `{v, id, from, to, type, prompt, cwd, ref}` envelope, durable `.brain` ledger, and one-request/one-response boundary.

## Workflow

1. Resolve the repository root and create or reuse one run ID.
2. Discover reachable targets. Prefer stable UUIDs; do not guess when names collide.
3. Emit the request with `scripts/conduct.cjs` before transport:

   ```bash
   node <skill-root>/scripts/conduct.cjs emit \
     --root <repo> --run <run-id> --box outbox \
     --from <source-address> --to <target-address> \
     --type <task|review|design|question> \
     --prompt <message> --cwd <repo>
   ```

4. Deliver the envelope through the first reachable native-first route below.
   Send the saved envelope file's contents, not the helper's stdout wrapper. Include the absolute ledger root, run ID, and request-file path as transport metadata alongside the envelope so the receiver can record its result in the same run even when its working repository differs. Keep the envelope itself at eight fields. Pass message contents with structured tool arguments or a safely quoted file read; never interpolate raw prompt text into shell command source.
5. Obtain exactly one bounded response. Emit it as `type: result`, `box: inbox`, and `--ref <request-id>`.
6. Present the result to the user. Do not automatically dispatch another turn.

Record observed delivery changes with `node <skill-root>/scripts/conduct.cjs mark --root <repo> --run <run-id> --id <request-id> --transport <adapter> --status <sent|delivered|answered|failed>`. Mark `sent` only after transport acceptance, `delivered` only after receiver evidence, and `answered` after the correlated result is in the ledger. Status events retain the same immutable envelope; they are not new messages or permission to dispatch again.

If a writer crashes, the error names its `.write-lock` directory and `owner.json` records the PID and timestamp. Confirm the owning process/tool handle has terminated before removing that exact lock and retrying; do not remove a live writer's lock based on elapsed time alone.

## Native-first routes

| Target | Preferred route | Fallback |
|---|---|---|
| Existing Codex session | Native Codex session tool when available; otherwise `codex queue --thread <uuid-or-exact-name> --message <text>` | Exact iTerm2 session ID |
| One-shot Codex | `codex exec` | Exact iTerm2 session ID |
| Existing Claude session from Codex | Claude CLI courier with native `ListAgents` / `SendMessage`, when exposed | Exact iTerm2 session ID |
| Claude teammate from Claude | Native Claude agent messaging | Exact iTerm2 session ID |
| One-shot Claude from Codex | `claude -p` | Exact iTerm2 session ID |
| Codex Desktop | Native thread/session adapter | Registered iTerm2 session when applicable |
| Claude Desktop | Installed Claude plugin/MCP adapter | None until registered; do not claim reachability |

`it2api` is the universal local fallback for visible iTerm2 panes, not the primary transport. Send to an exact session ID and submit the text as a separate carriage-return action. Use `it2api get-buffer` only for the session involved in the current authorized handoff.

Before every terminal send, inspect that exact session's buffer and confirm it is at an idle Claude/Codex agent input. Do not inject into a shell prompt, running command, or permission dialog. If the target is busy, wait for its agent input or use a verified native queue; never treat transport success as task completion.

The receiver owns model, reasoning effort, permissions, and escalation policy. Do not put those fields into the envelope.

For an inactive Codex session, use `codex queue --resume` when a local daemon or selected remote server can resume it. Queue success confirms acceptance only: a failed resume is a warning, so verify the target actually runs and produces its correlated result before reporting completion. Otherwise report it as queued and awaiting a reachable receiver.

## Discovery

- Use the native session-listing capability exposed on the current surface.
- `claude agents --json` lists interactive and background Claude sessions with session UUID, unique name, cwd, PID, and status. A Claude CLI courier can use native `ListAgents` / `SendMessage` to deliver the saved envelope to an existing session inbox while it is busy. Give the courier the verified target mapping and restrict it to reading that envelope and sending that one message; it must not perform the task itself. Cross-check native refs/names against the registry and reject ambiguous targets. Inbox acceptance is `sent`; only a receiver response proves completion.
- Codex CLI may address sessions with `codex queue`; prefer UUIDs over duplicate names.
- Claude native agent tools are available only from surfaces that expose them.
- Use `it2api list-sessions` to discover visible terminal fallback targets.
- Merge results by stable ID, not display name.

Report targets as `address`, `kind`, `transport`, and `status`. A session without a verified send/read route is visible but not reachable.

## Peer supervision during active work

When the user asks the agents to keep each other moving, supervise the assigned peer until that task completes or the user pauses/stops it. Keep one controller for each run and track the peer session ID, current task, process/tool handle when available, and last observed progress.

- Check at task boundaries and about every 30–60 seconds while waiting. Prefer native status/results, then the exact peer process and its output; use the terminal buffer as fallback.
- A live process with recent output is working. A timeout or unchanged buffer alone is not proof of a stall; inspect its live handle before restarting anything.
- If a peer is idle with an assigned unfinished task and the user has not paused it, send one bounded recovery request with the concrete next step and evidence. Use a new request ID and correlate its single response. Do not repeatedly nudge the same unanswered request.
- If a peer process has exited, inspect its result and resume the remaining authorized work or repair the verified failure. Preserve its worktree and evidence.
- Permission/auth dialogs, explicit user pauses, and unresolved user choices require their owning authority. Never type approval into either agent's permission prompt or override a pause. Report the exact blocker and continue independent authorized work.
- Stop supervision when the assigned task is complete. Do not create an unattended permanent watcher or agent-to-agent chatter without a separate user request.

## Dispatch safety

- Dispatch only because this skill was invoked for an authorized handoff. There are no raw prefix triggers; never execute model-printed dispatch text.
- One request gets at most one response. Every response must reference its request. Never dispatch a response to a response.
- Keep one logical controller per run. The helper serializes ledger writes and rejects duplicates, unsafe paths, reversed-address mismatches, and cyclic response chains.
- Validate `cwd` and the exact target before sending.
- Never include secrets, credentials, or access tokens in prompts or `.brain` files.
- Preserve the user's task boundary. Cross-model help does not authorize unrelated changes, pushes, purchases, or account actions.
