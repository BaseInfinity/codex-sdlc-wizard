import asyncio
import importlib.util
import contextlib
import io
import json
from pathlib import Path
import subprocess
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import AsyncMock, patch

try:
    import websockets
except ModuleNotFoundError:
    websockets = None

SCRIPT = Path(__file__).resolve().parents[1] / "skill-sources/conduct/scripts/codex-native.py"
spec = importlib.util.spec_from_file_location("conduct_native", SCRIPT)
native = importlib.util.module_from_spec(spec)
spec.loader.exec_module(native)
THREAD = "01234567-89ab-4def-8123-456789abcdef"


@unittest.skipIf(websockets is None, "socket fixtures require optional websockets")
class NativeRpcTests(unittest.IsolatedAsyncioTestCase):
    async def test_initialization_and_notifications_preserve_response_matching(self):
        with tempfile.TemporaryDirectory() as directory:
            socket = str(Path(directory) / "server.sock")

            async def server(ws):
                init = json.loads(await ws.recv())
                self.assertEqual(init["method"], "initialize")
                self.assertEqual(init["params"]["clientInfo"]["name"], "conduct")
                await ws.send(json.dumps({"id": init["id"], "result": {}}))
                self.assertEqual(json.loads(await ws.recv())["method"], "initialized")
                request = json.loads(await ws.recv())
                self.assertEqual(request["method"], "thread/list")
                self.assertTrue(request["params"]["useStateDbOnly"])
                await ws.send(json.dumps({"method": "thread/status/changed", "params": {}}))
                await ws.send(json.dumps({"id": request["id"], "method": "unrelated/server/request", "params": {}}))
                refused = json.loads(await ws.recv())
                self.assertEqual(refused["error"]["code"], -32601)
                await ws.send(json.dumps({"id": request["id"], "result": {"data": [{"id": THREAD}], "nextCursor": "page-2"}}))

            async with websockets.unix_serve(server, socket):
                result = await native.rpc(socket, "thread/list", {"useStateDbOnly": True}, 2)
            self.assertEqual(result["data"][0]["id"], THREAD)
            self.assertEqual(result["nextCursor"], "page-2")

    async def test_server_error_is_not_an_empty_success(self):
        with tempfile.TemporaryDirectory() as directory:
            socket = str(Path(directory) / "server.sock")

            async def server(ws):
                init = json.loads(await ws.recv())
                await ws.send(json.dumps({"id": init["id"], "error": {"code": -1, "message": "denied"}}))

            async with websockets.unix_serve(server, socket):
                with self.assertRaisesRegex(RuntimeError, "denied"):
                    await native.rpc(socket, "thread/list", {}, 2)

    async def test_large_history_item_is_not_a_connection_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            socket = str(Path(directory) / "server.sock")
            text = "x" * (1024 * 1024 + 1024)

            async def server(ws):
                init = json.loads(await ws.recv())
                await ws.send(json.dumps({"id": init["id"], "result": {}}))
                await ws.recv()
                request = json.loads(await ws.recv())
                await ws.send(json.dumps({"id": request["id"], "result": {"data": [{"text": text}]}}))

            async with websockets.unix_serve(server, socket):
                result = await native.rpc(socket, "thread/items/list", {"threadId": THREAD}, 2)
            self.assertEqual(result["data"][0]["text"], text)

    async def test_read_timeout_is_bounded(self):
        with tempfile.TemporaryDirectory() as directory:
            socket = str(Path(directory) / "server.sock")

            async def server(ws):
                await ws.recv()
                await ws.wait_closed()

            async with websockets.unix_serve(server, socket):
                with self.assertRaisesRegex(RuntimeError, "timed out"):
                    await native.rpc(socket, "thread/list", {}, 0.05)

    async def test_write_rpc_methods_are_not_exposed(self):
        with self.assertRaises(ValueError):
            await native.rpc("/tmp/unused.sock", "turn/start", {}, 1)


class NativeQueueTests(unittest.TestCase):
    def envelope(self, directory):
        file = Path(directory) / ".brain/runs/run-1/outbox/req.json"
        file.parent.mkdir(parents=True)
        file.write_text(json.dumps({"v": 1, "id": "req", "from": "claude:peer", "to": f"codex:{THREAD}", "type": "question", "prompt": "literal $(touch should-not-exist) `command`", "cwd": directory, "ref": None}))
        (file.parent.parent / "turns.jsonl").write_text(json.dumps({"envelope": json.loads(file.read_text())}) + "\n")
        return file

    def test_queue_uses_argv_and_does_not_claim_execution(self):
        with tempfile.TemporaryDirectory() as directory:
            envelope = self.envelope(directory)
            with patch.object(native.subprocess, "run", return_value=SimpleNamespace(returncode=0, stdout="Queued", stderr="resume warning")) as run:
                result = native.queue("/tmp/test.sock", THREAD, envelope, directory, "run-1", True, 2)
            call = run.call_args
            argv = call.args[0]
            self.assertIn("--resume", argv)
            self.assertIn(f"unix:///tmp/test.sock", argv)
            self.assertNotIn("shell", call.kwargs)
            message = argv[argv.index("--message") + 1]
            self.assertIn("literal $(touch should-not-exist) `command`", message)
            self.assertTrue(result["accepted"])
            self.assertFalse(result["executionConfirmed"])
            self.assertEqual(result["diagnostic"], "resume warning")

    def test_wrong_target_is_rejected_before_delivery(self):
        with tempfile.TemporaryDirectory() as directory:
            envelope = self.envelope(directory)
            with patch.object(native.subprocess, "run") as run:
                with self.assertRaises(ValueError):
                    native.queue("/tmp/test.sock", "11111111-1111-4111-8111-111111111111", envelope, directory, "run-1", False, 2)
                run.assert_not_called()

    def test_queue_timeout_reports_unknown_delivery(self):
        with tempfile.TemporaryDirectory() as directory:
            envelope = self.envelope(directory)
            with patch.object(native.subprocess, "run", side_effect=subprocess.TimeoutExpired("codex", 2)):
                with self.assertRaisesRegex(RuntimeError, "unknown"):
                    native.queue("/tmp/test.sock", THREAD, envelope, directory, "run-1", False, 2)

    def test_invalid_version_and_extra_fields_are_rejected(self):
        for change in [{"v": True}, {"model": "sender-must-not-control-this"}]:
            with self.subTest(change=change), tempfile.TemporaryDirectory() as directory:
                file = self.envelope(directory)
                value = json.loads(file.read_text())
                value.update(change)
                file.write_text(json.dumps(value))
                with patch.object(native.subprocess, "run") as run:
                    with self.assertRaises(ValueError):
                        native.queue("/tmp/test.sock", THREAD, file, directory, "run-1", False, 2)
                    run.assert_not_called()

    def test_unrecorded_or_wrong_run_envelope_is_not_delivered(self):
        for wrong_run in [False, True]:
            with self.subTest(wrong_run=wrong_run), tempfile.TemporaryDirectory() as directory:
                file = self.envelope(directory)
                if not wrong_run:
                    (file.parent.parent / "turns.jsonl").unlink()
                with patch.object(native.subprocess, "run") as run:
                    with self.assertRaises(ValueError):
                        native.queue("/tmp/test.sock", THREAD, file, directory, "different-run" if wrong_run else "run-1", False, 2)
                    run.assert_not_called()

    def test_changed_envelope_does_not_match_ledger(self):
        with tempfile.TemporaryDirectory() as directory:
            file = self.envelope(directory)
            value = json.loads(file.read_text())
            value["prompt"] = "changed after recording"
            file.write_text(json.dumps(value))
            with patch.object(native.subprocess, "run") as run:
                with self.assertRaisesRegex(ValueError, "immutable ledger"):
                    native.queue("/tmp/test.sock", THREAD, file, directory, "run-1", False, 2)
                run.assert_not_called()

    def test_result_requires_recorded_parent(self):
        with tempfile.TemporaryDirectory() as directory:
            file = Path(directory) / ".brain/runs/run-1/inbox/result.json"
            file.parent.mkdir(parents=True)
            value = {"v": 1, "id": "result", "from": "claude:peer", "to": f"codex:{THREAD}", "type": "result", "prompt": "done", "cwd": directory, "ref": "missing-parent"}
            file.write_text(json.dumps(value))
            (file.parent.parent / "turns.jsonl").write_text(json.dumps({"envelope": value}) + "\n")
            with patch.object(native.subprocess, "run") as run:
                with self.assertRaisesRegex(ValueError, "matching reversed-address request"):
                    native.queue("/tmp/test.sock", THREAD, file, directory, "run-1", False, 2)
                run.assert_not_called()

    def test_read_cli_requests_metadata_only(self):
        with patch.object(native, "rpc", new_callable=AsyncMock, return_value={}) as rpc:
            with contextlib.redirect_stdout(io.StringIO()):
                native.main(["--socket", "/tmp/test.sock", "read", "--thread", THREAD])
        self.assertEqual(rpc.call_args.args[1], "thread/read")
        self.assertEqual(rpc.call_args.args[2], {"threadId": THREAD, "includeTurns": False})

    def test_history_cli_requests_newest_first(self):
        with patch.object(native, "rpc", new_callable=AsyncMock, return_value={}) as rpc:
            with contextlib.redirect_stdout(io.StringIO()):
                native.main(["--socket", "/tmp/test.sock", "turns", "--thread", THREAD])
        self.assertEqual(rpc.call_args.args[1], "thread/turns/list")
        self.assertEqual(rpc.call_args.args[2]["sortDirection"], "desc")


if __name__ == "__main__":
    unittest.main()
