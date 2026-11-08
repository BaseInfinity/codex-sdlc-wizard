#!/usr/bin/env python3
"""Deterministic stdio fixture for codex-thread.py contract tests."""

import json
import os
from pathlib import Path
import queue
import sys
import threading
import time


THREAD_ID = "thread-fixture-1"
LEDGER_THREAD_ID = "01a1b80d-a3c3-7863-afd3-59045023870a"
TURN_ID = "turn-fixture-1"
EXACT_ANSWER = "Exact answer from the fake server.\nSecond line preserved."
UNICODE_ANSWER = "café — déjà vu"
CHINESE_ANSWER = "你好，世界"
ONE_TRAILING_NEWLINE_ANSWER = "Answer with one trailing newline.\n"
MULTIPLE_TRAILING_NEWLINES_ANSWER = "Answer with two trailing newlines.\n\n"


def emit(*messages):
    payload = "".join(
        json.dumps(message, ensure_ascii=False, separators=(",", ":")) + "\n"
        for message in messages
    )
    os.write(sys.stdout.fileno(), payload.encode("utf-8"))


def rpc_result(message, result):
    return {"id": message["id"], "result": result}


def read_message(timeout):
    """Read one client message without letting a broken client stall the fixture."""
    result = queue.Queue()

    def read():
        result.put(sys.stdin.readline())

    threading.Thread(target=read, daemon=True).start()
    try:
        line = result.get(timeout=timeout)
    except queue.Empty:
        return None
    return json.loads(line) if line else None


def is_negative_response(message, request_id):
    if not isinstance(message, dict) or message.get("id") != request_id:
        return False
    if isinstance(message.get("error"), dict):
        return True
    result = message.get("result")
    if not isinstance(result, dict):
        return False
    if result.get("accepted") is True or result.get("approved") is True:
        return False
    decision = str(result.get("decision", "")).lower()
    if decision in {"approve", "approved", "accept", "accepted"}:
        return False
    return (
        result.get("accepted") is False
        or result.get("approved") is False
        or decision in {"decline", "declined", "deny", "denied"}
    )


def ledger_turn_error(message):
    root = Path(os.environ["CONDUCT_TEST_LEDGER_ROOT"])
    run_id = os.environ["CONDUCT_TEST_RUN"]
    request_id = os.environ["CONDUCT_TEST_REQUEST_ID"]
    request_path = root / ".brain/runs" / run_id / "outbox" / f"{request_id}.json"
    ledger_path = root / ".brain/runs" / run_id / "turns.jsonl"
    if not root.is_absolute() or not request_path.is_file() or not ledger_path.is_file():
        return "canonical ledger files did not exist before turn/start"
    raw_envelope = request_path.read_text(encoding="utf-8")
    envelope = json.loads(raw_envelope)
    expected_prompt_file = os.environ.get("CONDUCT_TEST_PROMPT_FILE")
    expected_prompt = (
        Path(expected_prompt_file).read_text(encoding="utf-8").rstrip("\n")
        if expected_prompt_file
        else os.environ["CONDUCT_TEST_PROMPT"]
    )
    expected = {
        "v": 1,
        "id": request_id,
        "from": os.environ["CONDUCT_TEST_FROM"],
        "to": f"codex:{LEDGER_THREAD_ID}",
        "type": os.environ["CONDUCT_TEST_TYPE"],
        "prompt": expected_prompt,
        "cwd": os.environ.get("CONDUCT_TEST_CWD", str(Path.cwd())),
        "ref": None,
    }
    if envelope != expected:
        return "canonical envelope did not address the actual thread UUID"
    entries = [json.loads(line) for line in ledger_path.read_text(encoding="utf-8").splitlines()]
    if not entries or entries[-1].get("envelope") != envelope:
        return "canonical ledger entry was missing before turn/start"
    expected_transport = (
        "$conduct receive\n"
        f"Ledger root: {root}\n"
        f"Run: {run_id}\n"
        f"Request: {request_path}\n"
        f"Envelope:\n{raw_envelope.rstrip(chr(10))}"
    )
    params = message.get("params", {})
    inputs = params.get("input", [])
    if params.get("threadId") != LEDGER_THREAD_ID or inputs != [
        {"type": "text", "text": expected_transport}
    ]:
        return "turn/start did not carry the saved envelope and absolute ledger metadata"
    return None


def serve(scenario):
    pid_file = os.environ.get("FAKE_SERVER_PID_FILE")
    if pid_file:
        with open(pid_file, "w", encoding="ascii") as file:
            file.write(str(os.getpid()))

    if scenario == "idle":
        time.sleep(30)
        return

    if scenario == "burst":
        # One kernel write plus an idle writer reproduces the buffered-read edge case.
        emit(
            {"id": 101, "result": {"sequence": "first"}},
            {"id": 102, "result": {"sequence": "second"}},
        )
        time.sleep(30)
        return

    for line in sys.stdin:
        message = json.loads(line)
        method = message.get("method")

        if method == "initialized":
            continue
        if method == "initialize":
            if scenario == "close-stdin-after-initialize":
                os.close(sys.stdin.fileno())
                emit(rpc_result(message, {}))
                time.sleep(1)
                return
            emit(rpc_result(message, {}))
            continue
        if method == "thread/start":
            params = message.get("params", {})
            if (
                params.get("sandbox") != "read-only"
                or params.get("approvalPolicy") != "never"
            ):
                emit(
                    {
                        "id": message["id"],
                        "error": {
                            "code": -32001,
                            "message": "unsafe thread/start policy in test client",
                        },
                    }
                )
                continue
            thread_id = (
                LEDGER_THREAD_ID
                if scenario in {"ledger-aware", "writer-failure-no-turn"}
                else THREAD_ID
            )
            emit(rpc_result(message, {"thread": {"id": thread_id}}))
            continue
        if method == "turn/start":
            if scenario == "writer-failure-no-turn":
                marker = os.environ.get("FAKE_SERVER_TURN_FILE")
                if marker:
                    Path(marker).write_text("turn/start observed", encoding="utf-8")
                emit(
                    {
                        "id": message["id"],
                        "error": {
                            "code": -32002,
                            "message": "writer failure must prevent turn/start",
                        },
                    }
                )
                continue
            if scenario == "ledger-aware":
                error = ledger_turn_error(message)
                if error:
                    emit(
                        {
                            "id": message["id"],
                            "error": {"code": -32003, "message": error},
                        }
                    )
                    continue
            if scenario == "rpc-error":
                emit(
                    {
                        "id": message["id"],
                        "error": {"code": -32000, "message": "synthetic RPC failure"},
                    }
                )
                continue

            if scenario == "item-completed-empty-summary":
                # Codex 0.145 emits the final agent item separately and may send
                # an empty summary. Decoys enforce thread/turn correlation, and
                # all item notifications precede the turn/start RPC response.
                emit(
                    {
                        "method": "item/completed",
                        "params": {
                            "threadId": "thread-foreign",
                            "turnId": TURN_ID,
                            "item": {"type": "agentMessage", "text": "FOREIGN THREAD"},
                        },
                    },
                    {
                        "method": "item/completed",
                        "params": {
                            "threadId": THREAD_ID,
                            "turnId": "turn-foreign",
                            "item": {"type": "agentMessage", "text": "FOREIGN TURN"},
                        },
                    },
                    {
                        "method": "item/completed",
                        "params": {
                            "threadId": THREAD_ID,
                            "turnId": TURN_ID,
                            "item": {"type": "agentMessage", "text": EXACT_ANSWER},
                        },
                    },
                    rpc_result(message, {"turn": {"id": TURN_ID}}),
                    {
                        "method": "turn/completed",
                        "params": {
                            "threadId": THREAD_ID,
                            "turn": {
                                "id": TURN_ID,
                                "status": "completed",
                                "items": [],
                            },
                        },
                    },
                )
                continue

            if scenario == "server-request-collision":
                request_id = message["id"]
                emit(
                    {
                        "id": request_id,
                        "method": "item/tool/requestUserInput",
                        "params": {
                            "threadId": THREAD_ID,
                            "turnId": TURN_ID,
                            "questions": [{"id": "approval", "prompt": "Approve?"}],
                        },
                    }
                )
                declined = read_message(0.75)
                if not is_negative_response(declined, request_id):
                    return
                emit(
                    rpc_result(message, {"turn": {"id": TURN_ID}}),
                    {
                        "method": "turn/completed",
                        "params": {
                            "threadId": THREAD_ID,
                            "turn": {
                                "id": TURN_ID,
                                "status": "completed",
                                "items": [
                                    {"type": "agentMessage", "text": EXACT_ANSWER}
                                ],
                            },
                        },
                    },
                )
                continue

            status = {
                "completed": "completed",
                "completed-unicode": "completed",
                "completed-cjk": "completed",
                "completed-trailing-one": "completed",
                "completed-trailing-many": "completed",
                "ledger-aware": "completed",
                "failed": "failed",
                "interrupted": "interrupted",
            }[scenario]
            answers = {
                "completed-unicode": UNICODE_ANSWER,
                "completed-cjk": CHINESE_ANSWER,
                "completed-trailing-one": ONE_TRAILING_NEWLINE_ANSWER,
                "completed-trailing-many": MULTIPLE_TRAILING_NEWLINES_ANSWER,
            }
            answer = answers.get(scenario, EXACT_ANSWER)
            active_thread_id = (
                LEDGER_THREAD_ID if scenario == "ledger-aware" else THREAD_ID
            )
            # The response and terminal notification deliberately share one OS write.
            emit(
                rpc_result(message, {"turn": {"id": TURN_ID}}),
                {
                    "method": "turn/completed",
                    "params": {
                        "threadId": active_thread_id,
                        "turn": {
                            "id": TURN_ID,
                            "status": status,
                            "items": [
                                {"type": "agentMessage", "text": answer}
                            ],
                        },
                    },
                },
            )
            continue
        if "id" in message:
            emit(rpc_result(message, {}))


if __name__ == "__main__":
    serve(sys.argv[1])
