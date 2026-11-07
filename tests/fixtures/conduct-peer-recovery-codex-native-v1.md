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
