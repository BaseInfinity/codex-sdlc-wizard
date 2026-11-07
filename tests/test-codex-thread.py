import contextlib
import importlib.util
import io
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
FAKE_SERVER = Path(__file__).resolve().parent / "fixtures/fake-codex-app-server.py"
REAL_POPEN = subprocess.Popen
EXACT_ANSWER = "Exact answer from the fake server.\nSecond line preserved."
UNICODE_ANSWER = "café — déjà vu"
CHINESE_ANSWER = "你好，世界"
ONE_TRAILING_NEWLINE_ANSWER = "Answer with one trailing newline.\n"
MULTIPLE_TRAILING_NEWLINES_ANSWER = "Answer with two trailing newlines.\n\n"

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

    def run_cli(self, scenario, directory, prompt_file, extra_env=None):
        bin_dir = self.install_fake_codex(directory, scenario)
        env = os.environ.copy()
        env["PATH"] = str(bin_dir)
        env["PATHEXT"] = ".COM;.EXE;.BAT;.CMD"
        env["CONDUCT_TEST_PYTHON"] = str(Path(sys.executable).resolve())
        env["CONDUCT_TEST_FAKE_SERVER"] = str(FAKE_SERVER.resolve())
        env["CONDUCT_TEST_SCENARIO"] = scenario
        if extra_env:
            env.update(extra_env)
        process = REAL_POPEN(
            [
                str(Path(sys.executable).resolve()),
                str(SCRIPT),
                str(Path(directory).resolve()),
                str(prompt_file),
            ],
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
            cases = [
                ("relative/cwd", prompt),
                (str(Path(directory).resolve()), missing),
            ]

            with patch.object(subprocess, "Popen") as spawn:
                for cwd, prompt_file in cases:
                    with self.subTest(cwd=cwd, prompt_file=prompt_file):
                        argv = [str(SCRIPT), cwd, str(prompt_file)]
                        with patch.object(sys, "argv", argv):
                            with contextlib.redirect_stderr(io.StringIO()):
                                with self.assertRaises(SystemExit) as stopped:
                                    runpy.run_path(str(SCRIPT), run_name="__main__")
                        self.assertNotEqual(stopped.exception.code, 0)
                spawn.assert_not_called()


if __name__ == "__main__":
    unittest.main()
