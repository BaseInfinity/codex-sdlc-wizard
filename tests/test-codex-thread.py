import contextlib
import importlib.util
import io
import json
import ntpath
import os
from pathlib import Path
import posixpath
import runpy
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch


REPO = Path(__file__).resolve().parents[1]
SCRIPT = REPO / "skill-sources/conduct/scripts/codex-thread.py"
CONDUCT = REPO / "skill-sources/conduct/scripts/conduct.cjs"
C30_CONDUCT = REPO / "tests/fixtures/conduct-c30-conduct.cjs"
FAKE_SERVER = Path(__file__).resolve().parent / "fixtures/fake-codex-app-server.py"
REAL_POPEN = subprocess.Popen
REAL_RUN = subprocess.run
LEDGER_THREAD_ID = "01a1b80d-a3c3-7863-afd3-59045023870a"
EXACT_ANSWER = "Exact answer from the fake server.\nSecond line preserved."
UNICODE_ANSWER = "café — déjà vu"
CHINESE_ANSWER = "你好，世界"
ONE_TRAILING_NEWLINE_ANSWER = "Answer with one trailing newline.\n"
MULTIPLE_TRAILING_NEWLINES_ANSWER = "Answer with two trailing newlines.\n\n"
LAST_USABLE_ANSWER = "  Résumé 🧪\n第二行\t  "
NO_USABLE_ANSWER_DIAGNOSTIC = "TURN_NO_USABLE_AGENT_MESSAGE"

codex_thread = None
if SCRIPT.is_file():
    spec = importlib.util.spec_from_file_location("conduct_codex_thread", SCRIPT)
    codex_thread = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(codex_thread)


class CodexThreadPresenceTests(unittest.TestCase):
    def test_helper_exists(self):
        self.assertTrue(SCRIPT.is_file(), f"required Conduct helper is missing: {SCRIPT}")


@unittest.skipUnless(SCRIPT.is_file(), "codex-thread helper not integrated yet")
class CodexThreadPipeTests(unittest.TestCase):
    def stop_process(self, process):
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=2)

    def run_main(self, scenario, cwd, prompt_file):
        owned = []
        commands = []

        def launch(command, *args, **kwargs):
            commands.append(command)
            process = REAL_POPEN(
                [sys.executable, str(FAKE_SERVER), scenario], *args, **kwargs
            )
            owned.append(process)
            self.addCleanup(self.stop_process, process)
            return process

        stdout = io.StringIO()
        stderr = io.StringIO()
        with patch.object(codex_thread.subprocess, "Popen", side_effect=launch):
            with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
                code = codex_thread.main(str(cwd), str(prompt_file))

        self.assertEqual(
            commands,
            [["codex", "app-server", "--listen", "stdio://"]],
        )
        return code, stdout.getvalue(), stderr.getvalue(), owned

    def install_fake_codex(self, directory, scenario, osname=os.name):
        bin_dir = Path(directory) / "fake-bin"
        bin_dir.mkdir()
        if osname == "nt":
            launcher = bin_dir / "codex.cmd"
            launcher.write_text(
                "@echo off\n"
                '"%CONDUCT_TEST_PYTHON%" "%CONDUCT_TEST_FAKE_SERVER%" '
                '"%CONDUCT_TEST_SCENARIO%"\n'
                "exit /b %errorlevel%\n",
                encoding="ascii",
            )
        else:
            launcher = bin_dir / "codex"
            launcher.write_text(
                "#!/bin/sh\n"
                'exec "$CONDUCT_TEST_PYTHON" "$CONDUCT_TEST_FAKE_SERVER" '
                '"$CONDUCT_TEST_SCENARIO"\n',
                encoding="ascii",
            )
            launcher.chmod(0o755)
        return bin_dir

    def run_cli(
        self,
        scenario,
        directory,
        prompt_file,
        extra_env=None,
        ledger_args=None,
        include_real_node=False,
        cwd_arg=None,
        script_path=SCRIPT,
    ):
        bin_dir = self.install_fake_codex(directory, scenario)
        env = os.environ.copy()
        path_parts = [str(bin_dir)]
        if include_real_node:
            node = shutil.which("node")
            self.assertIsNotNone(node, "Node is required for the canonical Conduct writer")
            path_parts.append(str(Path(node).resolve().parent))
        env["PATH"] = os.pathsep.join(path_parts)
        env["PATHEXT"] = ".COM;.EXE;.BAT;.CMD"
        env["CONDUCT_TEST_PYTHON"] = str(Path(sys.executable).resolve())
        env["CONDUCT_TEST_FAKE_SERVER"] = str(FAKE_SERVER.resolve())
        env["CONDUCT_TEST_SCENARIO"] = scenario
        if extra_env:
            env.update(extra_env)
        script_args = list(ledger_args or []) + [
            cwd_arg or str(Path(directory).resolve()),
            str(prompt_file),
        ]
        process = REAL_POPEN(
            [str(Path(sys.executable).resolve()), str(script_path), *script_args],
            cwd=str(Path(directory).resolve()),
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=env,
        )
        self.addCleanup(self.stop_process, process)
        return process

    def test_absolute_cwd_validation_uses_injected_platform_semantics(self):
        cases = [
            (posixpath.isabs, "/tmp/project", True),
            (posixpath.isabs, "tmp/project", False),
            (ntpath.isabs, "C:\\work\\project", True),
            (ntpath.isabs, "\\\\server\\share\\project", True),
            (ntpath.isabs, "work\\project", False),
        ]
        for isabs, path, expected in cases:
            with self.subTest(isabs=isabs.__module__, path=path):
                self.assertIs(codex_thread.valid_cwd(path, isabs), expected)
        self.assertEqual(
            codex_thread.normalize_ledger_cwd(
                r"\\server\share\folder\.\child",
                path_module=ntpath,
                osname="nt",
            ),
            r"\\server\share\folder\child",
        )

    def test_burst_messages_in_one_os_write_remain_readable_while_server_idles(self):
        # This is intentionally a real pipe. A reader thread/queue works on Windows too;
        # select() on a Windows pipe handle does not. This Mac run is not Windows proof.
        server = codex_thread.Server(
            [sys.executable, str(FAKE_SERVER), "burst"]
        )
        self.addCleanup(server.close)

        first = server.wait(lambda message: message.get("id") == 101, 2)
        started = time.monotonic()
        second = server.wait(lambda message: message.get("id") == 102, 0.5)
        elapsed = time.monotonic() - started

        self.assertEqual(first["result"]["sequence"], "first")
        self.assertEqual(second["result"]["sequence"], "second")
        self.assertLess(elapsed, 0.5)

    def test_completed_turn_prints_exact_answer_and_returns_zero(self):
        with tempfile.TemporaryDirectory() as directory:
            prompt = Path(directory) / "prompt.txt"
            prompt.write_text("Perform one bounded task.")
            code, stdout, _, _ = self.run_main(
                "completed", Path(directory), prompt
            )

        self.assertEqual(code, 0)
        self.assertEqual(
            stdout,
            f"THREAD thread-fixture-1\n{EXACT_ANSWER}\n",
        )

    def test_cli_ledger_start_records_actual_target_before_same_connection_turn(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "ledger-root"
            root.mkdir()
            prompt = Path(directory) / "prompt.txt"
            prompt_text = "Perform the canonical ledger-aware task."
            prompt.write_text(prompt_text, encoding="utf-8")
            run_id = "ledger-start-001"
            request_id = "req-ledger-start-001"
            sender = "codex:controller"
            request_path = root / ".brain/runs" / run_id / "outbox" / f"{request_id}.json"
            process = self.run_cli(
                "ledger-aware",
                directory,
                prompt,
                {
                    "CONDUCT_TEST_LEDGER_ROOT": str(root.resolve()),
                    "CONDUCT_TEST_RUN": run_id,
                    "CONDUCT_TEST_REQUEST_ID": request_id,
                    "CONDUCT_TEST_FROM": sender,
                    "CONDUCT_TEST_TYPE": "task",
                    "CONDUCT_TEST_PROMPT": prompt_text,
                },
                [
                    "--ledger-root", str(root.resolve()),
                    "--run", run_id,
                    "--request-id", request_id,
                    "--from", sender,
                    "--type", "task",
                ],
                include_real_node=True,
            )
            stdout, stderr = process.communicate(timeout=10)

            self.assertEqual(
                process.returncode,
                0,
                (stdout + stderr).decode("utf-8", errors="replace"),
            )
            self.assertEqual(
                stdout,
                f"THREAD {LEDGER_THREAD_ID}\n{EXACT_ANSWER}\n".encode("utf-8"),
            )
            envelope = json.loads(request_path.read_text(encoding="utf-8"))
            self.assertEqual(
                envelope,
                {
                    "v": 1,
                    "id": request_id,
                    "from": sender,
                    "to": f"codex:{LEDGER_THREAD_ID}",
                    "type": "task",
                    "prompt": prompt_text,
                    "cwd": str(Path(directory).resolve()),
                    "ref": None,
                },
            )
            ledger = [
                json.loads(line)
                for line in (root / ".brain/runs" / run_id / "turns.jsonl")
                .read_text(encoding="utf-8")
                .splitlines()
            ]
            self.assertEqual([entry["envelope"] for entry in ledger], [envelope])

    def test_ledger_start_keeps_large_unicode_prompt_off_node_argv(self):
        with tempfile.TemporaryDirectory() as directory:
            node = shutil.which("node")
            self.assertIsNotNone(node, "Node is required for the canonical Conduct writer")
            root = Path(directory) / "ledger-root"
            root.mkdir()
            prompt = Path(directory) / "prompt.txt"
            prompt_text = "first line\n" + ("🧪漢字\n" * 9000) + "last line"
            self.assertGreater(
                len(prompt_text.encode("utf-16-le")) // 2,
                32767,
                "fixture must exceed the Windows CreateProcess command-line limit",
            )
            prompt.write_text(prompt_text, encoding="utf-8")
            run_id = "ledger-large-prompt-001"
            request_id = "req-ledger-large-prompt-001"
            sender = "codex:controller"
            writer_calls = []

            def run_writer(argv, *args, **kwargs):
                writer_calls.append((list(argv), dict(kwargs)))
                return REAL_RUN(argv, *args, **kwargs)

            environment = {
                "CONDUCT_TEST_LEDGER_ROOT": str(root.resolve()),
                "CONDUCT_TEST_RUN": run_id,
                "CONDUCT_TEST_REQUEST_ID": request_id,
                "CONDUCT_TEST_FROM": sender,
                "CONDUCT_TEST_TYPE": "task",
                "CONDUCT_TEST_PROMPT_FILE": str(prompt.resolve()),
                "CONDUCT_TEST_CWD": str(Path(directory).resolve()),
            }
            stdout = io.StringIO()
            stderr = io.StringIO()
            with (
                patch.dict(os.environ, environment, clear=False),
                patch.object(codex_thread.subprocess, "run", side_effect=run_writer),
                contextlib.redirect_stdout(stdout),
                contextlib.redirect_stderr(stderr),
            ):
                code = codex_thread.main(
                    str(Path(directory).resolve()),
                    str(prompt),
                    [sys.executable, str(FAKE_SERVER), "ledger-aware"],
                    ledger={
                        "root": str(root.resolve()),
                        "run": run_id,
                        "request_id": request_id,
                        "from": sender,
                        "type": "task",
                    },
                )

            self.assertEqual(code, 0, stdout.getvalue() + stderr.getvalue())
            emit_calls = [call for call in writer_calls if len(call[0]) > 2 and call[0][2] == "emit"]
            self.assertEqual(len(emit_calls), 1)
            argv, emit_kwargs = emit_calls[0]
            self.assertIsInstance(emit_kwargs.get("input"), bytes)
            self.assertEqual(emit_kwargs["input"], prompt_text.encode("utf-8"))
            self.assertNotIn("text", emit_kwargs)
            self.assertNotIn("encoding", emit_kwargs)
            self.assertNotIn(prompt_text, argv)
            self.assertLess(
                sum(len(str(value).encode("utf-16-le")) // 2 + 1 for value in argv),
                32767,
            )
            help_calls = [call for call in writer_calls if call[0][-1:] == ["--help"]]
            self.assertEqual(len(help_calls), 1)
            self.assertEqual(help_calls[0][1]["timeout"], 10)
            request_path = root / ".brain/runs" / run_id / "outbox" / f"{request_id}.json"
            envelope = json.loads(request_path.read_text(encoding="utf-8"))
            self.assertEqual(
                set(envelope),
                {"v", "id", "from", "to", "type", "prompt", "cwd", "ref"},
            )
            self.assertEqual(envelope["prompt"], prompt_text)

    def test_ledger_mode_rejects_old_writer_before_app_server_allocation(self):
        with tempfile.TemporaryDirectory() as directory:
            runtime = Path(directory) / "legacy-runtime"
            runtime.mkdir()
            legacy_thread = runtime / "codex-thread.py"
            shutil.copy2(SCRIPT, legacy_thread)
            shutil.copy2(C30_CONDUCT, runtime / "conduct.cjs")
            root = Path(directory) / "ledger-root"
            root.mkdir()
            prompt = Path(directory) / "prompt.txt"
            prompt.write_text("Do not allocate a thread for an unsupported writer.", encoding="utf-8")
            server_marker = Path(directory) / "app-server-started"
            process = self.run_cli(
                "writer-failure-no-turn",
                directory,
                prompt,
                {"FAKE_SERVER_PID_FILE": str(server_marker)},
                [
                    "--ledger-root", str(root.resolve()),
                    "--run", "unsupported-writer-001",
                    "--request-id", "req-unsupported-writer-001",
                    "--from", "codex:controller",
                    "--type", "task",
                ],
                include_real_node=True,
                script_path=legacy_thread,
            )
            stdout, stderr = process.communicate(timeout=10)

            diagnostic = (stdout + stderr).decode("utf-8", errors="replace")
            self.assertEqual(process.returncode, 2, diagnostic)
            self.assertIn("LEDGER_WRITER_UNSUPPORTED", diagnostic)
            self.assertNotIn("THREAD ", diagnostic)
            self.assertFalse(server_marker.exists())
            self.assertFalse((root / ".brain").exists())

    def test_plain_startup_does_not_probe_old_writer_capability(self):
        with tempfile.TemporaryDirectory() as directory:
            runtime = Path(directory) / "legacy-runtime"
            runtime.mkdir()
            legacy_thread = runtime / "codex-thread.py"
            shutil.copy2(SCRIPT, legacy_thread)
            shutil.copy2(C30_CONDUCT, runtime / "conduct.cjs")
            prompt = Path(directory) / "prompt.txt"
            prompt.write_text("Plain startup remains writer-independent.", encoding="utf-8")
            process = self.run_cli(
                "completed",
                directory,
                prompt,
                script_path=legacy_thread,
            )
            stdout, stderr = process.communicate(timeout=10)

            self.assertEqual(
                process.returncode,
                0,
                (stdout + stderr).decode("utf-8", errors="replace"),
            )
            self.assertEqual(stdout, f"THREAD thread-fixture-1\n{EXACT_ANSWER}\n".encode("utf-8"))

    def test_canonical_writer_stdin_prompt_still_enforces_maximum(self):
        with tempfile.TemporaryDirectory() as directory:
            node = shutil.which("node")
            self.assertIsNotNone(node, "Node is required for the canonical Conduct writer")
            result = REAL_RUN(
                [
                    node,
                    str(CONDUCT),
                    "emit",
                    "--root", directory,
                    "--run", "over-limit",
                    "--id", "over-limit-request",
                    "--from", "codex:controller",
                    "--to", f"codex:{LEDGER_THREAD_ID}",
                    "--type", "task",
                    "--prompt-file", "-",
                    "--cwd", directory,
                ],
                input="x" * 100001,
                capture_output=True,
                text=True,
                encoding="utf-8",
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("prompt exceeds 100000 characters", result.stderr)
            self.assertFalse((Path(directory) / ".brain").exists())

    def test_cli_ledger_start_normalizes_native_cwd_lexically(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "ledger-root"
            root.mkdir()
            prompt = Path(directory) / "prompt.txt"
            prompt_text = "Perform the lexical CWD normalization task."
            prompt.write_text(prompt_text, encoding="utf-8")
            run_id = "ledger-cwd-001"
            request_id = "req-ledger-cwd-001"
            sender = "codex:controller"
            raw_cwd = os.path.join(str(Path(directory).resolve()), ".", "")
            normalized_cwd = os.path.abspath(os.path.normpath(raw_cwd))
            request_path = root / ".brain/runs" / run_id / "outbox" / f"{request_id}.json"
            process = self.run_cli(
                "ledger-aware",
                directory,
                prompt,
                {
                    "CONDUCT_TEST_LEDGER_ROOT": str(root.resolve()),
                    "CONDUCT_TEST_RUN": run_id,
                    "CONDUCT_TEST_REQUEST_ID": request_id,
                    "CONDUCT_TEST_FROM": sender,
                    "CONDUCT_TEST_TYPE": "task",
                    "CONDUCT_TEST_PROMPT": prompt_text,
                },
                [
                    "--ledger-root", str(root.resolve()),
                    "--run", run_id,
                    "--request-id", request_id,
                    "--from", sender,
                    "--type", "task",
                ],
                include_real_node=True,
                cwd_arg=raw_cwd,
            )
            stdout, stderr = process.communicate(timeout=10)

            self.assertEqual(
                process.returncode,
                0,
                (stdout + stderr).decode("utf-8", errors="replace"),
            )
            self.assertEqual(
                stdout,
                f"THREAD {LEDGER_THREAD_ID}\n{EXACT_ANSWER}\n".encode("utf-8"),
            )
            envelope = json.loads(request_path.read_text(encoding="utf-8"))
            self.assertEqual(envelope["cwd"], normalized_cwd)

    @unittest.skipUnless(os.name == "posix", "exactly-double-slash is POSIX-specific")
    def test_cli_ledger_start_collapses_exactly_double_slash_like_node(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "ledger-root"
            root.mkdir()
            prompt = Path(directory) / "prompt.txt"
            prompt_text = "Perform the double-slash CWD task."
            prompt.write_text(prompt_text, encoding="utf-8")
            run_id = "ledger-double-slash-001"
            request_id = "req-ledger-double-slash-001"
            sender = "codex:controller"
            normalized_cwd = str(Path(directory).resolve())
            raw_cwd = "/" + normalized_cwd
            self.assertTrue(raw_cwd.startswith("//") and not raw_cwd.startswith("///"))
            request_path = root / ".brain/runs" / run_id / "outbox" / f"{request_id}.json"
            process = self.run_cli(
                "ledger-aware",
                directory,
                prompt,
                {
                    "CONDUCT_TEST_LEDGER_ROOT": str(root.resolve()),
                    "CONDUCT_TEST_RUN": run_id,
                    "CONDUCT_TEST_REQUEST_ID": request_id,
                    "CONDUCT_TEST_FROM": sender,
                    "CONDUCT_TEST_TYPE": "task",
                    "CONDUCT_TEST_PROMPT": prompt_text,
                },
                [
                    "--ledger-root", str(root.resolve()),
                    "--run", run_id,
                    "--request-id", request_id,
                    "--from", sender,
                    "--type", "task",
                ],
                include_real_node=True,
                cwd_arg=raw_cwd,
            )
            stdout, stderr = process.communicate(timeout=10)

            self.assertEqual(
                process.returncode,
                0,
                (stdout + stderr).decode("utf-8", errors="replace"),
            )
            self.assertEqual(
                stdout,
                f"THREAD {LEDGER_THREAD_ID}\n{EXACT_ANSWER}\n".encode("utf-8"),
            )
            envelope = json.loads(request_path.read_text(encoding="utf-8"))
            self.assertEqual(envelope["cwd"], normalized_cwd)

    def test_canonical_writer_failure_does_not_start_turn(self):
        with tempfile.TemporaryDirectory() as directory:
            node = shutil.which("node")
            self.assertIsNotNone(node, "Node is required for the canonical Conduct writer")
            root = Path(directory) / "ledger-root"
            root.mkdir()
            prompt = Path(directory) / "prompt.txt"
            prompt.write_text("This duplicate request must not execute.", encoding="utf-8")
            run_id = "ledger-writer-failure-001"
            request_id = "req-ledger-writer-failure-001"
            sender = "codex:controller"
            existing = subprocess.run(
                [
                    node,
                    str(CONDUCT),
                    "emit",
                    "--root", str(root.resolve()),
                    "--run", run_id,
                    "--box", "outbox",
                    "--id", request_id,
                    "--from", sender,
                    "--to", f"codex:{LEDGER_THREAD_ID}",
                    "--type", "task",
                    "--prompt", "Existing canonical request.",
                    "--cwd", str(Path(directory).resolve()),
                ],
                capture_output=True,
                text=True,
            )
            self.assertEqual(existing.returncode, 0, existing.stderr)
            turn_marker = Path(directory) / "turn-started"
            process = self.run_cli(
                "writer-failure-no-turn",
                directory,
                prompt,
                {"FAKE_SERVER_TURN_FILE": str(turn_marker)},
                [
                    "--ledger-root", str(root.resolve()),
                    "--run", run_id,
                    "--request-id", request_id,
                    "--from", sender,
                    "--type", "task",
                ],
                include_real_node=True,
            )
            stdout, stderr = process.communicate(timeout=10)

            diagnostic = (stdout + stderr).decode("utf-8", errors="replace")
            self.assertEqual(process.returncode, 2, diagnostic)
            self.assertIn("LEDGER_EMIT_FAILED", diagnostic)
            self.assertFalse(turn_marker.exists(), "turn/start ran after writer failure")
            ledger_lines = (
                root / ".brain/runs" / run_id / "turns.jsonl"
            ).read_text(encoding="utf-8").splitlines()
            self.assertEqual(len(ledger_lines), 1)

    def test_item_completed_before_turn_reply_supplies_empty_summary_answer(self):
        with tempfile.TemporaryDirectory() as directory:
            prompt = Path(directory) / "prompt.txt"
            prompt.write_text("Perform one bounded task.")
            code, stdout, _, _ = self.run_main(
                "item-completed-empty-summary", Path(directory), prompt
            )

        self.assertEqual(code, 0)
        self.assertEqual(
            stdout,
            f"THREAD thread-fixture-1\n{EXACT_ANSWER}\n",
        )

    def test_completed_turn_without_usable_agent_message_returns_diagnostic(self):
        for scenario in (
            "completed-empty-items",
            "completed-blank-messages",
            "completed-no-agent-message",
        ):
            with self.subTest(scenario=scenario), tempfile.TemporaryDirectory() as directory:
                prompt = Path(directory) / "prompt.txt"
                prompt.write_text("Complete without a usable final response.")
                code, stdout, stderr, _ = self.run_main(
                    scenario, Path(directory), prompt
                )

                self.assertEqual(code, 2, stdout + stderr)
                self.assertEqual(
                    stdout,
                    f"THREAD thread-fixture-1\n{NO_USABLE_ANSWER_DIAGNOSTIC}\n",
                )

    def test_last_usable_agent_message_ignores_blank_trailing_messages_exactly(self):
        with tempfile.TemporaryDirectory() as directory:
            prompt = Path(directory) / "prompt.txt"
            prompt.write_text("Return the last usable Unicode response exactly.")
            code, stdout, stderr, _ = self.run_main(
                "completed-usable-then-blanks", Path(directory), prompt
            )

        self.assertEqual(code, 0, stdout + stderr)
        self.assertEqual(
            stdout,
            f"THREAD thread-fixture-1\n{LAST_USABLE_ANSWER}\n",
        )

    def test_turn_summary_precedes_correlated_item_notification(self):
        with tempfile.TemporaryDirectory() as directory:
            prompt = Path(directory) / "prompt.txt"
            prompt.write_text("Prefer the completed-turn summary response.")
            code, stdout, stderr, _ = self.run_main(
                "completed-summary-precedence", Path(directory), prompt
            )

        self.assertEqual(code, 0, stdout + stderr)
        self.assertEqual(
            stdout,
            f"THREAD thread-fixture-1\n{EXACT_ANSWER}\n",
        )

    def test_default_windows_launcher_resolves_npm_cmd_shim_safely(self):
        codex_cmd = r"C:\Users\Fixture User\AppData\Roaming\npm\codex.cmd"
        cmd_exe = r"C:\Windows\System32\cmd.exe"
        calls = []

        class CapturedProcess:
            def __init__(self):
                self.stdin = io.StringIO()
                self.stdout = io.StringIO()
                self.returncode = None

            def terminate(self):
                self.returncode = -15

            def wait(self, timeout=None):
                self.returncode = self.returncode if self.returncode is not None else 0
                return self.returncode

            def kill(self):
                self.returncode = -9

        def windows_which(name, path=None):
            candidate = str(name).lower()
            if candidate in {"codex", "codex.cmd"}:
                return codex_cmd
            if candidate in {"cmd", "cmd.exe"}:
                return cmd_exe
            return None

        def capture(argv, *args, **kwargs):
            calls.append((argv, kwargs))
            return CapturedProcess()

        windows_env = {
            "COMSPEC": cmd_exe,
            "PATH": r"C:\Users\Fixture User\AppData\Roaming\npm;C:\Windows\System32",
            "PATHEXT": ".COM;.EXE;.BAT;.CMD",
        }
        windows_spec = importlib.util.spec_from_file_location(
            "conduct_codex_thread_windows_fixture", str(SCRIPT)
        )
        windows_codex_thread = importlib.util.module_from_spec(windows_spec)
        with (
            patch.object(os, "name", "nt"),
            patch.object(sys, "platform", "win32"),
            patch.object(shutil, "which", side_effect=windows_which) as resolve,
            patch.dict(os.environ, windows_env, clear=False),
        ):
            windows_spec.loader.exec_module(windows_codex_thread)
            with patch.object(
                windows_codex_thread.subprocess, "Popen", side_effect=capture
            ):
                server = windows_codex_thread.Server()
                server.close()

        resolve.assert_called_with("codex")
        self.assertEqual(len(calls), 1)
        command, kwargs = calls[0]
        self.assertFalse(kwargs.get("shell", False))
        if isinstance(command, str):
            self.assertEqual(
                command,
                f'cmd.exe /d /s /c ""{codex_cmd}" app-server --listen stdio://"',
            )
        else:
            self.assertIsInstance(command, (list, tuple))
            argv = [str(part) for part in command]
            self.assertEqual(argv[-3:], ["app-server", "--listen", "stdio://"])
            flattened = " ".join(argv).lower()
            self.assertIn(codex_cmd.lower(), flattened)
            launcher = argv[0].lower()
            self.assertNotEqual(launcher, "codex")
            self.assertFalse(
                launcher.endswith((".cmd", ".bat")),
                "CreateProcess cannot directly execute an npm command shim",
            )
            self.assertNotIn(ntpath.basename(launcher), {"cmd", "cmd.exe"})

    def test_fake_codex_launcher_is_platform_executable_and_hermetic(self):
        with tempfile.TemporaryDirectory() as directory:
            fixture_root = Path(directory) / "fixture 空间"
            fixture_root.mkdir()
            bin_dir = self.install_fake_codex(
                fixture_root, "completed-cjk", osname="nt"
            )
            cmd_launcher = bin_dir / "codex.cmd"
            self.assertTrue(cmd_launcher.is_file())
            self.assertFalse((bin_dir / "codex").exists())
            source = cmd_launcher.read_text(encoding="ascii")

        self.assertIn('"%CONDUCT_TEST_PYTHON%"', source)
        self.assertIn('"%CONDUCT_TEST_FAKE_SERVER%"', source)
        self.assertIn('"%CONDUCT_TEST_SCENARIO%"', source)
        self.assertNotIn("prompt", source.lower())
        self.assertNotIn(str(FAKE_SERVER), source)

    def test_missing_fake_codex_cannot_fall_back_to_real_path(self):
        with tempfile.TemporaryDirectory() as directory:
            empty_bin = Path(directory) / "empty-bin"
            empty_bin.mkdir()
            prompt = Path(directory) / "prompt.txt"
            prompt.write_text("Never reach a real Codex executable.")
            env = os.environ.copy()
            env["PATH"] = str(empty_bin)
            env["PATHEXT"] = ".COM;.EXE;.BAT;.CMD"
            process = REAL_POPEN(
                [
                    str(Path(sys.executable).resolve()),
                    str(SCRIPT),
                    str(Path(directory).resolve()),
                    str(prompt),
                ],
                cwd=str(Path(directory).resolve()),
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                env=env,
            )
            self.addCleanup(self.stop_process, process)
            stdout, stderr = process.communicate(timeout=5)

        diagnostic = (stdout + stderr).decode("utf-8", errors="replace")
        self.assertEqual(process.returncode, 2, diagnostic)
        self.assertIn("SERVER_START_FAILED", diagnostic)
        self.assertNotIn("THREAD ", diagnostic)

    def test_real_pipe_decodes_utf8_answer_under_non_utf8_parent_locale(self):
        with tempfile.TemporaryDirectory() as directory:
            prompt = Path(directory) / "prompt.txt"
            prompt.write_text("Return the exact non-ASCII fixture answer.")
            # This test runner enables Python UTF-8 mode, so inject the legacy
            # parent locale where Popen resolves an omitted text encoding.
            with patch.object(
                codex_thread.subprocess, "_text_encoding", return_value="cp1252"
            ):
                code, stdout, _, _ = self.run_main(
                    "completed-unicode", Path(directory), prompt
                )

        self.assertEqual(code, 0)
        self.assertEqual(
            stdout,
            f"THREAD thread-fixture-1\n{UNICODE_ANSWER}\n",
        )

    def test_cli_writes_exact_utf8_cjk_under_legacy_stdout_encoding(self):
        with tempfile.TemporaryDirectory() as directory:
            prompt = Path(directory) / "prompt.txt"
            prompt.write_text("Return the exact CJK fixture answer.")
            process = self.run_cli(
                "completed-cjk",
                directory,
                prompt,
                {"PYTHONIOENCODING": "cp1252", "PYTHONUTF8": "0"},
            )
            stdout, stderr = process.communicate(timeout=5)

        self.assertEqual(process.returncode, 0, stderr.decode("utf-8", errors="replace"))
        self.assertEqual(
            stdout,
            f"THREAD thread-fixture-1\n{CHINESE_ANSWER}\n".encode("utf-8"),
        )
        self.assertNotIn(b"UnicodeEncodeError", stderr)

    def test_cli_preserves_one_existing_trailing_answer_newline(self):
        with tempfile.TemporaryDirectory() as directory:
            prompt = Path(directory) / "prompt.txt"
            prompt.write_text("Return the one-newline fixture answer.")
            process = self.run_cli("completed-trailing-one", directory, prompt)
            stdout, stderr = process.communicate(timeout=5)

        self.assertEqual(process.returncode, 0, stderr.decode("utf-8", errors="replace"))
        self.assertEqual(
            stdout,
            b"THREAD thread-fixture-1\n"
            + ONE_TRAILING_NEWLINE_ANSWER.encode("utf-8"),
        )

    def test_cli_preserves_multiple_existing_trailing_answer_newlines(self):
        with tempfile.TemporaryDirectory() as directory:
            prompt = Path(directory) / "prompt.txt"
            prompt.write_text("Return the multiple-newline fixture answer.")
            process = self.run_cli("completed-trailing-many", directory, prompt)
            stdout, stderr = process.communicate(timeout=5)

        self.assertEqual(process.returncode, 0, stderr.decode("utf-8", errors="replace"))
        self.assertEqual(
            stdout,
            b"THREAD thread-fixture-1\n"
            + MULTIPLE_TRAILING_NEWLINES_ANSWER.encode("utf-8"),
        )

    def test_cli_broken_server_pipe_returns_runtime_error_and_reaps_only_owned_child(self):
        peer = REAL_POPEN(
            [sys.executable, str(FAKE_SERVER), "idle"],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        self.addCleanup(self.stop_process, peer)

        with tempfile.TemporaryDirectory() as directory:
            prompt = Path(directory) / "prompt.txt"
            prompt.write_text("Perform one bounded task.")
            pid_file = Path(directory) / "owned-server.pid"
            process = self.run_cli(
                "close-stdin-after-initialize",
                directory,
                prompt,
                {"FAKE_SERVER_PID_FILE": str(pid_file)},
            )
            stdout, stderr = process.communicate(timeout=5)
            owned_pid = int(pid_file.read_text())

        diagnostic = (stdout + stderr).decode("utf-8", errors="replace")
        self.assertEqual(process.returncode, 2, diagnostic)
        self.assertRegex(diagnostic, r"(?i)(server.*(failed|error)|broken pipe)")
        self.assertNotIn("Traceback", diagnostic)
        with self.assertRaises(ProcessLookupError):
            os.kill(owned_pid, 0)
        self.assertIsNone(peer.poll(), "helper cleanup touched an unrelated process")

    def test_server_request_id_collision_is_declined_before_turn_completes(self):
        with tempfile.TemporaryDirectory() as directory:
            prompt = Path(directory) / "prompt.txt"
            prompt.write_text("Do not request interactive approval.")
            started = time.monotonic()
            code, stdout, stderr, _ = self.run_main(
                "server-request-collision", Path(directory), prompt
            )
            elapsed = time.monotonic() - started

        self.assertEqual(code, 0, stdout + stderr)
        self.assertEqual(
            stdout,
            f"THREAD thread-fixture-1\n{EXACT_ANSWER}\n",
        )
        self.assertLess(elapsed, 3, "fixture must fail quickly, not reach 300 seconds")

    def test_failed_and_interrupted_terminal_turns_return_nonzero(self):
        for status in ("failed", "interrupted"):
            with self.subTest(status=status), tempfile.TemporaryDirectory() as directory:
                prompt = Path(directory) / "prompt.txt"
                prompt.write_text("Perform one bounded task.")
                code, _, _, _ = self.run_main(status, Path(directory), prompt)
                self.assertNotEqual(code, 0)

    def test_rpc_error_returns_nonzero(self):
        with tempfile.TemporaryDirectory() as directory:
            prompt = Path(directory) / "prompt.txt"
            prompt.write_text("Perform one bounded task.")
            code, _, _, _ = self.run_main(
                "rpc-error", Path(directory), prompt
            )

        self.assertNotEqual(code, 0)

    def test_spawn_failure_returns_runtime_code_and_diagnostic(self):
        with tempfile.TemporaryDirectory() as directory:
            prompt = Path(directory) / "prompt.txt"
            prompt.write_text("Perform one bounded task.")
            missing = Path(directory) / "missing-codex-app-server"
            stdout = io.StringIO()
            stderr = io.StringIO()
            with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
                code = codex_thread.main(
                    str(Path(directory).resolve()), str(prompt), [str(missing)]
                )

        self.assertEqual(code, 2)
        self.assertRegex(stdout.getvalue() + stderr.getvalue(), r"(?i)(failed|error)")

    def test_cleanup_reaps_owned_server_without_touching_peer_process(self):
        peer = REAL_POPEN(
            [sys.executable, str(FAKE_SERVER), "idle"],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        self.addCleanup(self.stop_process, peer)

        with tempfile.TemporaryDirectory() as directory:
            prompt = Path(directory) / "prompt.txt"
            prompt.write_text("Perform one bounded task.")
            code, _, _, owned = self.run_main("completed", Path(directory), prompt)

        self.assertEqual(code, 0)
        self.assertEqual(len(owned), 1)
        self.assertIsNotNone(owned[0].returncode, "owned server was not reaped")
        self.assertIsNone(peer.poll(), "cleanup terminated an unrelated peer process")

    def test_invalid_arguments_do_not_start_app_server(self):
        with tempfile.TemporaryDirectory() as directory:
            prompt = Path(directory) / "prompt.txt"
            prompt.write_text("Perform one bounded task.")
            missing = Path(directory) / "missing.txt"
            absolute_cwd = str(Path(directory).resolve())
            cases = [
                [str(SCRIPT), "relative/cwd", str(prompt)],
                [str(SCRIPT), absolute_cwd, str(missing)],
                [
                    str(SCRIPT),
                    "--ledger-root", absolute_cwd,
                    absolute_cwd, str(prompt),
                ],
                [
                    str(SCRIPT),
                    "--ledger-root", "relative/root",
                    "--run", "run-001",
                    "--request-id", "req-001",
                    "--from", "codex:controller",
                    "--type", "task",
                    absolute_cwd, str(prompt),
                ],
                [
                    str(SCRIPT),
                    "--ledger-root", absolute_cwd,
                    "--run", "run-001",
                    "--request-id", "req-001",
                    "--from", "codex:controller",
                    "--type", "result",
                    absolute_cwd, str(prompt),
                ],
            ]

            with patch.object(subprocess, "Popen") as spawn:
                for argv in cases:
                    with self.subTest(argv=argv):
                        with patch.object(sys, "argv", argv):
                            with contextlib.redirect_stderr(io.StringIO()):
                                with self.assertRaises(SystemExit) as stopped:
                                    runpy.run_path(str(SCRIPT), run_name="__main__")
                        self.assertNotEqual(stopped.exception.code, 0)
                spawn.assert_not_called()


if __name__ == "__main__":
    unittest.main()
