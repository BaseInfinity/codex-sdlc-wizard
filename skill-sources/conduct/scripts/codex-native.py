#!/usr/bin/env python3
"""Optional native Codex adapter: Python 3.11+, websockets for socket reads."""

import argparse
import asyncio
import json
from pathlib import Path
import re
import subprocess
import sys
import uuid

FIELDS = {"v", "id", "from", "to", "type", "prompt", "cwd", "ref"}
READ_METHODS = {"thread/list", "thread/read", "thread/loaded/list", "thread/turns/list", "thread/items/list"}


def identifier(value):
    if not isinstance(value, str) or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,127}", value) or ".." in value:
        raise ValueError("unsafe run/message ID")
    return value


def thread_id(value):
    return str(uuid.UUID(value))


def default_socket():
    result = subprocess.run(["codex", "app-server", "daemon", "version"], capture_output=True, text=True, timeout=10)
    if result.returncode:
        raise RuntimeError("cannot inspect Codex daemon; supply --socket explicitly")
    state = json.loads(result.stdout)
    if state.get("status") != "running" or not state.get("socketPath"):
        raise RuntimeError("Codex daemon is not running; start it explicitly before using this adapter")
    return state["socketPath"]


async def rpc(socket, method, params, timeout=15):
    if method not in READ_METHODS:
        raise ValueError("only read-only native methods are supported")
    try:
        import websockets
        from websockets.exceptions import WebSocketException
    except ImportError as error:
        raise RuntimeError("native reads require the optional Python package websockets (tested with 16.0)") from error

    async def exchange():
        async with websockets.unix_connect(str(socket), uri="ws://localhost/", open_timeout=min(timeout, 10), close_timeout=1, max_size=None) as ws:
            async def request(number, name, body):
                await ws.send(json.dumps({"id": number, "method": name, "params": body}))
                while True:
                    message = json.loads(await ws.recv())
                    if not isinstance(message, dict):
                        raise RuntimeError("invalid native response object")
                    if "method" in message:
                        if "id" in message:
                            await ws.send(json.dumps({"id": message["id"], "error": {"code": -32601, "message": "read-only conduct client does not handle server requests"}}))
                        continue
                    if message.get("id") != number:
                        continue
                    if "error" in message:
                        error = message["error"]
                        detail = error.get("message", "unknown error") if isinstance(error, dict) else "invalid error response"
                        raise RuntimeError(f"native request failed: {detail}")
                    if "result" not in message:
                        raise RuntimeError("native response has no result")
                    return message["result"]

            await request(1, "initialize", {"clientInfo": {"name": "conduct", "version": "0.1"}})
            await ws.send(json.dumps({"method": "initialized"}))
            return await request(2, method, params)

    try:
        return await asyncio.wait_for(exchange(), timeout)
    except asyncio.TimeoutError as error:
        raise RuntimeError("native read timed out; the peer may still be running") from error
    except (WebSocketException, json.JSONDecodeError) as error:
        raise RuntimeError("native read connection failed; inspect endpoint availability") from error


def queue(socket, thread, envelope_path, ledger_root, run, resume=False, timeout=15):
    thread = thread_id(thread)
    run = identifier(run)
    root = str(Path(ledger_root).resolve())
    if "\n" in root or "\r" in root:
        raise ValueError("ledger root must not contain line breaks")
    envelope = json.loads(Path(envelope_path).read_text(encoding="utf-8"))
    if not isinstance(envelope, dict) or set(envelope) != FIELDS or type(envelope["v"]) is not int or envelope["v"] != 1:
        raise ValueError("expected the exact v1 eight-field envelope")
    identifier(envelope["id"])
    if envelope["to"] != f"codex:{thread}":
        raise ValueError("envelope target does not match the requested session UUID")
    if not isinstance(envelope["from"], str) or not envelope["from"].strip() or envelope["from"] == envelope["to"]:
        raise ValueError("invalid sender address")
    if envelope["type"] not in {"task", "review", "design", "question", "result"}:
        raise ValueError("unknown envelope type")
    if not isinstance(envelope["prompt"], str) or not envelope["prompt"].strip():
        raise ValueError("envelope prompt must be nonempty text")
    if not isinstance(envelope["cwd"], str) or not Path(envelope["cwd"]).is_absolute():
        raise ValueError("envelope cwd must be absolute")
    if envelope["type"] == "result":
        identifier(envelope["ref"])
    elif envelope["ref"] is not None:
        raise ValueError("request ref must be null")

    run_path = Path(root) / ".brain" / "runs" / run
    box = "inbox" if envelope["type"] == "result" else "outbox"
    expected = run_path / box / f"{envelope['id']}.json"
    ledger = run_path / "turns.jsonl"
    for destination in [expected, ledger]:
        current = destination
        while current != Path(root):
            if current.is_symlink():
                raise ValueError("conduct run state must not use symlinks")
            current = current.parent
    if Path(envelope_path).resolve() != expected.resolve() or not ledger.is_file():
        raise ValueError("envelope must belong to the selected recorded run")
    turns = [json.loads(line) for line in ledger.read_text(encoding="utf-8").split("\n") if line.strip()]
    snapshots = [turn.get("envelope") for turn in turns if isinstance(turn, dict) and isinstance(turn.get("envelope"), dict)]
    recorded = [value for value in snapshots if value.get("id") == envelope["id"]]
    if not recorded or any(value != envelope for value in recorded):
        raise ValueError("envelope does not match its immutable ledger record")
    if envelope["type"] == "result":
        parent = next((value for value in snapshots if value.get("id") == envelope["ref"]), None)
        if not parent or parent.get("type") == "result" or parent.get("ref") is not None or parent.get("from") != envelope["to"] or parent.get("to") != envelope["from"]:
            raise ValueError("result requires its matching reversed-address request in the ledger")
    elif any(value.get("type") == "result" and value.get("ref") == envelope["id"] for value in snapshots):
        raise ValueError("request already has a recorded result; do not dispatch it again")

    message = f"$conduct receive\nLedger root: {root}\nRun: {run}\nEnvelope:\n{json.dumps(envelope, ensure_ascii=False)}"
    argv = ["codex", "queue", "--remote", f"unix://{socket}", "--thread", thread, "--message", message]
    if resume:
        argv.append("--resume")
    try:
        result = subprocess.run(argv, capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired as error:
        raise RuntimeError("queue timed out; delivery is unknown, inspect the run before retrying") from error
    if result.returncode:
        raise RuntimeError(f"queue failed: {result.stderr.strip()}")
    return {"accepted": True, "executionConfirmed": False, "resumeRequested": resume, "diagnostic": result.stderr.strip()}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--socket", help="Explicit Unix socket; defaults to the running Codex daemon")
    parser.add_argument("--timeout", type=float, default=15)
    commands = parser.add_subparsers(dest="command", required=True)
    listing = commands.add_parser("list")
    listing.add_argument("--source", action="append", choices=["cli", "vscode", "exec", "appServer", "unknown"])
    listing.add_argument("--cwd")
    loaded = commands.add_parser("loaded")
    read = commands.add_parser("read")
    read.add_argument("--thread", required=True, type=thread_id)
    turns = commands.add_parser("turns")
    turns.add_argument("--thread", required=True, type=thread_id)
    items = commands.add_parser("items")
    items.add_argument("--thread", required=True, type=thread_id)
    items.add_argument("--turn")
    for paged in [listing, loaded, turns, items]:
        paged.add_argument("--limit", type=int, default=20)
        paged.add_argument("--cursor")
    for history in [turns, items]:
        history.add_argument("--direction", choices=["asc", "desc"], default="desc")
    sending = commands.add_parser("queue")
    sending.add_argument("--thread", required=True, type=thread_id)
    sending.add_argument("--envelope", required=True)
    sending.add_argument("--ledger-root", required=True)
    sending.add_argument("--run", required=True)
    sending.add_argument("--resume", action="store_true")
    args = parser.parse_args(argv)
    if args.timeout <= 0:
        parser.error("timeout must be positive")
    if hasattr(args, "limit") and not 1 <= args.limit <= 100:
        parser.error("limit must be between 1 and 100")
    socket = args.socket or default_socket()
    if not Path(socket).is_absolute():
        parser.error("socket must be an absolute path")
    if args.command == "queue":
        result = queue(socket, args.thread, args.envelope, args.ledger_root, args.run, args.resume, args.timeout)
    else:
        params = {"limit": args.limit} if hasattr(args, "limit") else {}
        if getattr(args, "cursor", None):
            params["cursor"] = args.cursor
        if args.command == "list":
            params["useStateDbOnly"] = True
            if args.source:
                params["sourceKinds"] = args.source
            if args.cwd:
                params["cwd"] = args.cwd
        if hasattr(args, "thread"):
            params["threadId"] = args.thread
        if args.command == "read":
            params["includeTurns"] = False
        if args.command == "items" and args.turn:
            params["turnId"] = args.turn
        if hasattr(args, "direction"):
            params["sortDirection"] = args.direction
        method = {"list": "thread/list", "loaded": "thread/loaded/list", "read": "thread/read", "turns": "thread/turns/list", "items": "thread/items/list"}[args.command]
        result = asyncio.run(rpc(socket, method, params, args.timeout))
    print(json.dumps(result, ensure_ascii=True))


if __name__ == "__main__":
    try:
        main()
    except (ValueError, RuntimeError, OSError, subprocess.SubprocessError) as error:
        print(f"conduct-native: {error}", file=sys.stderr)
        sys.exit(1)
