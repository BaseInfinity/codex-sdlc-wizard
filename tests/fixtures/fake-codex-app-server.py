#!/usr/bin/env python3
"""Deterministic stdio fixture for codex-thread.py contract tests."""

import json
import os
import queue
import sys
import threading
import time


THREAD_ID = "thread-fixture-1"
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
            emit(rpc_result(message, {"thread": {"id": THREAD_ID}}))
            continue
        if method == "turn/start":
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
            # The response and terminal notification deliberately share one OS write.
            emit(
                rpc_result(message, {"turn": {"id": TURN_ID}}),
                {
                    "method": "turn/completed",
                    "params": {
                        "threadId": THREAD_ID,
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
