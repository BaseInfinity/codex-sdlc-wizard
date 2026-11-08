"""Create a NEW Codex thread and run one bounded startup turn.

Talks JSON-RPC to a private `codex app-server --listen stdio://`. The completed
thread lands in the shared Codex thread store, so Codex Desktop lists it under CWD.
Read-only sandbox, never asks for approval.

Ledger-aware mode receives the actual thread UUID, invokes the sibling
conduct.cjs canonical writer, rereads its saved outbox envelope, and only then
starts the turn on the same app-server connection. Plain mode is a convenience
startup probe and sends PROMPT_FILE directly without creating a Conduct record.

Server requests (approvals, user input) are declined: no human answers them.
Answer text is the last nonblank string agent message from turn/completed items,
or from item/completed notifications when the server leaves those items empty.

Usage: python3 codex-thread.py CWD PROMPT_FILE
       python3 codex-thread.py --ledger-root ROOT --run RUN --request-id ID
           --from ADDRESS --type TYPE CWD PROMPT_FILE
Prints "THREAD <id>" then response or diagnostic data; exit status determines
success. Exit 0 only when a completed turn has a usable agent answer, 1 on bad
arguments, and 2 when the canonical writer or server fails, its pipes break,
the turn is not "completed" (failed, interrupted, or no turn/completed within
300 s), or a completed turn has no nonblank string agent message.
Observed on codex-cli 0.167.0.
"""
import argparse
import json
import os
from pathlib import Path
import queue
import re
import shutil
import subprocess
import sys
import threading
import time


def valid_cwd(path, isabs=os.path.isabs):
    """True for an absolute path on this platform (POSIX, C:\\ or UNC)."""
    return isabs(path)


def normalize_ledger_cwd(path, path_module=os.path, osname=os.name):
    """Lexically match Node path.resolve without rewriting symlink targets."""
    normalized = path_module.abspath(path_module.normpath(path))
    if osname != "nt" and normalized.startswith("//"):
        normalized = "/" + normalized.lstrip("/")
    return normalized


def handshake(cwd):
    return [
        ("initialize", {"clientInfo": {"name": "conduct", "version": "1"}}),
        ("initialized", None),
        ("thread/start", {"cwd": cwd, "sandbox": "read-only", "approvalPolicy": "never"}),
    ]


def turn(thread_id, prompt):
    return {"threadId": thread_id, "input": [{"type": "text", "text": prompt}]}


SERVER_ARGS = ["app-server", "--listen", "stdio://"]
REQUEST_TYPES = ("task", "review", "design", "question")
SAFE_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$")


def server_argv(osname=os.name, which=shutil.which):
    """Windows npm installs codex as a .cmd shim, which CreateProcess cannot
    run directly; launch it through cmd.exe with fixed arguments. `/s` strips
    the outer quote pair, so the path keeps its own quotes. The result is a
    command-line string, because list2cmdline would escape those quotes with
    backslashes that cmd.exe does not read. The prompt never reaches a shell:
    it travels as JSON on stdin."""
    if osname != "nt":
        return ["codex"] + SERVER_ARGS
    path = which("codex")
    if not path:
        return ["codex"] + SERVER_ARGS
    if path.lower().endswith((".cmd", ".bat")):
        return 'cmd.exe /d /s /c ""%s" %s"' % (path, " ".join(SERVER_ARGS))
    return [path] + SERVER_ARGS


class Server:
    """JSON-RPC over a child's stdio. A reader thread queues every line, so
    replies that arrive in one write are never stranded in a buffer. Messages
that no wait() has claimed yet stay in a backlog, so a notification that
lands before the reply it follows is not lost."""

    def __init__(self, cmd=None):
        self.p = subprocess.Popen(cmd or server_argv(),
                                  stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                  stderr=subprocess.DEVNULL, text=True, bufsize=1,
                                  encoding="utf-8")
        self.q = queue.Queue()
        threading.Thread(target=self._read, daemon=True).start()
        self.n = 0
        self.backlog = []
        self.seen = []

    def _read(self):
        for line in self.p.stdout:
            self.q.put(line)
        self.q.put(None)

    def send(self, method, params):
        m = {"method": method}
        if params is not None:
            m["params"] = params
        if method != "initialized":
            self.n += 1
            m["id"] = self.n
        self._write(m)
        return m.get("id")

    def _write(self, m):
        self.p.stdin.write(json.dumps(m) + "\n")
        self.p.stdin.flush()

    def wait(self, pred, timeout):
        for i, msg in enumerate(self.backlog):
            if pred(msg):
                return self.backlog.pop(i)
        end = time.time() + timeout
        while True:
            left = end - time.time()
            if left <= 0:
                return None
            try:
                line = self.q.get(timeout=left)
            except queue.Empty:
                return None
            if line is None:
                return None
            msg = json.loads(line)
            if "method" in msg and "id" in msg:
                self._write({"id": msg["id"],
                             "error": {"code": -32601, "message": "noninteractive client"}})
                continue
            self.seen.append(msg)
            if pred(msg):
                return msg
            self.backlog.append(msg)

    def close(self):
        try:
            self.p.stdin.close()
        except OSError:
            pass
        self.p.terminate()
        try:
            self.p.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.p.kill()
            self.p.wait(timeout=5)


def cli_stdout(stream):
    """Callers parse CLI output byte for byte: UTF-8 whatever the locale says,
    and no newline translation, so Windows never turns \n into \r\n."""
    stream.reconfigure(encoding="utf-8", newline="\n")


def request_path(ledger_root, run_id, request_id):
    return Path(ledger_root) / ".brain" / "runs" / run_id / "outbox" / (request_id + ".json")


def canonical_writer():
    return Path(__file__).resolve().with_name("conduct.cjs")


def decode_diagnostic(value):
    if isinstance(value, bytes):
        return value.decode("utf-8", errors="replace").strip()
    return str(value or "").strip()


def require_prompt_file_writer():
    try:
        checked = subprocess.run(
            ["node", str(canonical_writer()), "--help"],
            capture_output=True,
            timeout=10,
        )
    except subprocess.TimeoutExpired as error:
        raise RuntimeError("canonical writer capability probe timed out") from error
    except OSError as error:
        raise RuntimeError(error.strerror or str(error)) from error
    diagnostic = "\n".join(
        value for value in (
            decode_diagnostic(checked.stdout),
            decode_diagnostic(checked.stderr),
        ) if value
    )
    if checked.returncode:
        raise RuntimeError(diagnostic or "canonical writer help exited nonzero")
    if "--prompt-file" not in diagnostic:
        raise RuntimeError("canonical writer does not support --prompt-file")


def emit_request(cwd, prompt, thread_id, ledger):
    """Write one canonical request with the sibling Node helper, then return
    the exact saved envelope plus transport metadata for the first turn."""
    target = "codex:" + thread_id
    argv = [
        "node", str(canonical_writer()), "emit",
        "--root", ledger["root"],
        "--run", ledger["run"],
        "--box", "outbox",
        "--id", ledger["request_id"],
        "--from", ledger["from"],
        "--to", target,
        "--type", ledger["type"],
        "--prompt-file", "-",
        "--cwd", cwd,
    ]
    try:
        written = subprocess.run(
            argv,
            capture_output=True,
            input=prompt.encode("utf-8"),
            timeout=60,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        raise RuntimeError(str(error)) from error
    if written.returncode:
        raise RuntimeError(
            decode_diagnostic(written.stderr) or "canonical writer exited nonzero"
        )

    saved_path = request_path(ledger["root"], ledger["run"], ledger["request_id"]).resolve()
    try:
        saved = saved_path.read_text(encoding="utf-8")
        envelope = json.loads(saved)
    except (OSError, json.JSONDecodeError) as error:
        raise RuntimeError("canonical writer did not leave a readable request") from error
    expected = {
        "v": 1,
        "id": ledger["request_id"],
        "from": ledger["from"],
        "to": target,
        "type": ledger["type"],
        "prompt": prompt,
        "cwd": cwd,
        "ref": None,
    }
    if envelope != expected:
        raise RuntimeError("canonical writer saved an unexpected request envelope")
    return (
        "$conduct receive\n"
        "Ledger root: %s\n"
        "Run: %s\n"
        "Request: %s\n"
        "Envelope:\n%s"
    ) % (
        ledger["root"],
        ledger["run"],
        saved_path,
        saved.rstrip("\n"),
    )


def last_usable_agent_text(items):
    """Return the last nonblank string agent message without changing its text."""
    for item in reversed(items):
        if not isinstance(item, dict) or item.get("type") != "agentMessage":
            continue
        text = item.get("text")
        if isinstance(text, str) and text.strip():
            return text
    return None


def main(cwd, prompt_file, cmd=None, turn_timeout=300, ledger=None):
    with open(prompt_file, encoding="utf-8") as f:
        prompt = f.read().rstrip("\n")
    if ledger is not None:
        try:
            require_prompt_file_writer()
        except RuntimeError as error:
            print("LEDGER_WRITER_UNSUPPORTED %s" % error)
            return 2
    try:
        srv = Server(cmd)
    except OSError as e:
        print("SERVER_START_FAILED %s" % e.strerror)
        return 2
    try:
        reply = None
        for method, params in handshake(cwd):
            rid = srv.send(method, params)
            if rid is not None:
                reply = srv.wait(lambda m, rid=rid: m.get("id") == rid, 60)
                if not reply or "result" not in reply:
                    print("FAILED %s" % method)
                    return 2
        tid = reply["result"]["thread"]["id"]
        print("THREAD %s" % tid, flush=True)
        if ledger is not None:
            try:
                prompt = emit_request(cwd, prompt, tid, ledger)
            except RuntimeError as error:
                print("LEDGER_EMIT_FAILED %s" % error)
                return 2
        rid = srv.send("turn/start", turn(tid, prompt))
        started = srv.wait(lambda m: m.get("id") == rid, 60)
        if not started or "result" not in started:
            print("FAILED turn/start")
            return 2
        uid = started["result"]["turn"]["id"]
        done = srv.wait(lambda m: m.get("method") == "turn/completed"
                        and m["params"].get("threadId") == tid
                        and m["params"]["turn"].get("id") == uid, turn_timeout)
        if not done:
            print("TURN_INCOMPLETE")
            return 2
        t = done["params"]["turn"]
        if t.get("status") != "completed":
            print("TURN_%s" % str(t.get("status")).upper())
            return 2
        items = t.get("items") or [
            m["params"].get("item", {}) for m in srv.seen
            if m.get("method") == "item/completed"
            and m["params"].get("threadId") == tid and m["params"].get("turnId") == uid]
        answer = last_usable_agent_text(items)
        if answer is None:
            print("TURN_NO_USABLE_AGENT_MESSAGE")
            return 2
        sys.stdout.write(answer if answer.endswith("\n") else answer + "\n")
        return 0
    except OSError as e:
        print("SERVER_IO_FAILED %s" % (e.strerror or e))
        return 2
    finally:
        srv.close()


class CliParser(argparse.ArgumentParser):
    def error(self, message):
        self.print_usage(sys.stderr)
        self.exit(1, "%s: error: %s\n" % (self.prog, message))


def safe_id(value):
    if not SAFE_ID.fullmatch(value) or ".." in value:
        raise argparse.ArgumentTypeError("must be a safe 1-128 character identifier")
    return value


def parse_args(argv):
    parser = CliParser(description="Start one private Codex app-server turn")
    parser.add_argument("--ledger-root")
    parser.add_argument("--run", type=safe_id)
    parser.add_argument("--request-id", type=safe_id)
    parser.add_argument("--from", dest="request_from")
    parser.add_argument("--type", dest="request_type", choices=REQUEST_TYPES)
    parser.add_argument("cwd")
    parser.add_argument("prompt_file")
    args = parser.parse_args(argv)

    if not valid_cwd(args.cwd):
        parser.error("CWD must be absolute")
    if not os.path.isfile(args.prompt_file):
        parser.error("PROMPT_FILE must be an existing file")
    ledger_values = (
        args.ledger_root,
        args.run,
        args.request_id,
        args.request_from,
        args.request_type,
    )
    if any(value is not None for value in ledger_values):
        if not all(value is not None for value in ledger_values):
            parser.error(
                "ledger mode requires --ledger-root, --run, --request-id, --from, and --type"
            )
        if (not valid_cwd(args.ledger_root) or not os.path.isdir(args.ledger_root)
                or "\n" in args.ledger_root or "\r" in args.ledger_root):
            parser.error("--ledger-root must be an existing absolute directory")
        if not args.request_from.strip() or len(args.request_from) > 512:
            parser.error("--from must contain 1-512 nonblank characters")
        args.cwd = normalize_ledger_cwd(args.cwd)
        args.ledger = {
            "root": str(Path(args.ledger_root).resolve()),
            "run": args.run,
            "request_id": args.request_id,
            "from": args.request_from,
            "type": args.request_type,
        }
    else:
        args.ledger = None
    return args


if __name__ == "__main__":
    args = parse_args(sys.argv[1:])
    cli_stdout(sys.stdout)
    sys.exit(main(args.cwd, args.prompt_file, ledger=args.ledger))
