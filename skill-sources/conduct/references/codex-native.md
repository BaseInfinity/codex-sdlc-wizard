# Native Codex session adapter

The optional `scripts/codex-native.py` adapter uses the running Codex daemon's
documented JSON-RPC protocol over WebSocket on a Unix socket. The controller can
run in a terminal. A desktop-origin session is addressable only if that daemon
exposes it; app installation or a thread's source label does not prove a live
desktop route.

Prerequisites for macOS/Linux native reads: Codex CLI 0.167.0+, Python 3.11+ and the Python
`websockets` package (tested with 16.0). Queue delivery invokes the installed
Codex CLI with an argument array and never executes prompt text as shell source.
These are optional adapter prerequisites; ordinary conduct ledger operations
still use Node and do not need Python.

## Start a new Conduct thread

For the Conduct new-target workflow, the private app-server connection must stay
open from UUID allocation through the first turn. The helper receives the actual
UUID from `thread/start`, invokes its sibling `conduct.cjs emit` as a Node
subprocess with a structured argument array, rereads the saved canonical outbox
file, and only then sends `turn/start` on that same connection.
Keep the script, option values, working directory, and prompt file as separate
arguments; shell users quote each path.

On Unix, use `python3`:

```bash
python3 "<skill-root>/scripts/codex-thread.py" \
  --ledger-root "/absolute/ledger/repo" \
  --run "run-001" \
  --request-id "req-001" \
  --from "codex:<controller-uuid>" \
  --type task \
  "/absolute/receiver/cwd" "/absolute/prompt.txt"
```

On Windows, use `py -3`:

```powershell
py -3 "<skill-root>\scripts\codex-thread.py" `
  --ledger-root "C:\absolute\ledger\repo" `
  --run "run-001" `
  --request-id "req-001" `
  --from "codex:<controller-uuid>" `
  --type task `
  "C:\absolute\receiver\cwd" "C:\absolute\prompt.txt"
```

All five request options are required together. `--ledger-root` is the absolute
directory that owns `.brain`, `--run` and `--request-id` select the canonical
outbox path, `--from` is the controller address, and `--type` is one of `task`,
`review`, `design`, or `question`. CWD becomes the envelope `cwd`; the prompt
file becomes its `prompt`; the helper derives `to` as `codex:<actual-uuid>`.
It sends the saved envelope contents plus the absolute ledger root, run ID, and
request-file path. Canonical writer failure, incomplete options, or invalid
options cause no `turn/start`.

The plain startup-probe convenience mode remains available when an immediate,
unrecorded first turn is explicitly intended. Save its prompt in a file and
keep the working directory and prompt file as separate arguments:

```bash
python3 "<skill-root>/scripts/codex-thread.py" "/absolute/cwd" "/absolute/prompt.txt"
```

```powershell
py -3 "<skill-root>\scripts\codex-thread.py" "C:\absolute\cwd" "C:\absolute\prompt.txt"
```

The startup-probe mode immediately sends the prompt and starts one turn without
a Conduct ledger record, so it is not the Conduct new-target dispatch path.

If the Python launcher is unavailable, use a verified Python 3 `python.exe` or
`python` executable with the same separate, quoted arguments; do not assume an
unverified `python` command is Python 3. These instructions provide portable
invocation guidance, not live Windows proof or coverage.

The helper starts a private `codex app-server --listen stdio://`. Ledger-aware
or startup-probe success means the first turn completed; invalid arguments,
canonical writer failure, or any failed, interrupted, incomplete, or RPC-failed
operation is nonzero. The helper does not claim that a UUID returned before a
turn is independently queueable. The completed thread is stored where Codex
Desktop can list it, but this terminal route does not grant direct GUI access or
permission to change another receiver's runtime mode. It uses only Python's
standard library and was observed with Codex CLI 0.167.0.

This helper owns only the private app-server process it starts and reaps that
process when the bounded turn ends. It does not start, stop, or reconfigure the
shared daemon used by `codex-native.py` below.

```bash
# Discover local sessions; use returned UUIDs, preserve pagination cursors.
python3 <skill-root>/scripts/codex-native.py list --limit 20
python3 <skill-root>/scripts/codex-native.py list --source appServer
python3 <skill-root>/scripts/codex-native.py loaded

# Inspect one authorized target and page its turns/items.
python3 <skill-root>/scripts/codex-native.py read --thread <uuid>
python3 <skill-root>/scripts/codex-native.py turns --thread <uuid>
python3 <skill-root>/scripts/codex-native.py items --thread <uuid> --turn <turn-id>

# Deliver the validated, already-recorded request. Receiver owns policy/model.
python3 <skill-root>/scripts/codex-native.py queue \
  --thread <uuid> --envelope <absolute-outbox-file> \
  --ledger-root <repo> --run <run-id> --resume
```

Global options precede the subcommand: `--socket <absolute-path>` selects an
explicit endpoint and `--timeout <seconds>` bounds one observation. The default
socket comes from `codex app-server daemon version`; the adapter never starts,
restarts, or reconfigures the daemon itself.

Discovery and metadata reads do not start turns. `queue` checks the exact
eight-field envelope and requires `to` to match the selected Codex UUID. The
file must be in that run's canonical inbox/outbox and match its immutable ledger
record. Results need the recorded reversed-address parent; answered requests
cannot be dispatched again. The
message carries the run root/ID as transport metadata. `accepted: true` means
queued only, even when `--resume` is requested. Record `sent` with `conduct.cjs
mark`, then await the correlated result before marking `answered`. A queue
timeout means delivery is unknown: inspect the run and target before retrying.

`thread/read` requests metadata only. Use the paginated turn/item methods for
authorized response inspection; do not depend on deprecated full-history
hydration. `list` uses the state database without a rollout-repair scan.
Turn/item pages default to newest first; use `--direction asc` when reading in
chronological order.

The local endpoint schema can be generated with `codex app-server
generate-json-schema --out <directory>`. The transport is described in the
[official app-server protocol](https://learn.chatgpt.com/docs/app-server#protocol).
No desktop UI access is required for this adapter, and it does not grant access
to GUI-only or unregistered conversations.
