#!/bin/bash
# Test Codex SDLC Adapter - platform-aware behavior, payload format, config, install

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$SCRIPT_DIR/.."
HOOKS_DIR="$REPO_DIR/.codex/hooks"
ACTIVE_HOOKS_FILE="$REPO_DIR/.codex/hooks.json"
UNIVERSAL_PRETOOL_SCRIPT="$HOOKS_DIR/git-guard.cjs"
UNIVERSAL_SESSION_SCRIPT="$HOOKS_DIR/session-start.cjs"
UNIVERSAL_COMPACT_SCRIPT="$HOOKS_DIR/compact-guard.cjs"
PASSED=0
FAILED=0

case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) IS_WINDOWS=true ;;
    *) IS_WINDOWS=false ;;
esac

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() {
    echo -e "${GREEN}PASS${NC}: $1"
    PASSED=$((PASSED + 1))
}

fail() {
    echo -e "${RED}FAIL${NC}: $1"
    FAILED=$((FAILED + 1))
}

run_json_hook() {
    local payload="$1"
    local script_path="$2"

    if [ "$IS_WINDOWS" = "true" ]; then
        local win_path
        win_path=$(cygpath -w "$script_path")
        printf '%s' "$payload" | powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$win_path" 2>/dev/null
    else
        printf '%s' "$payload" | "$script_path" 2>/dev/null
    fi
}

run_session_hook() {
    local tmpdir="$1"
    local script_path="$2"

    if [ "$IS_WINDOWS" = "true" ]; then
        local win_path
        local win_tmp
        win_path=$(cygpath -w "$script_path")
        win_tmp=$(cygpath -w "$tmpdir")
        powershell.exe -NoProfile -Command "Set-Location '$win_tmp'; & '$win_path'" 2>/dev/null
    else
        (cd "$tmpdir" && "$script_path" 2>/dev/null)
    fi
}

run_node_json_hook() {
    local payload="$1"
    local script_path="$2"

    printf '%s' "$payload" | node "$script_path" 2>/dev/null
}

run_node_session_hook() {
    local tmpdir="$1"
    local script_path="$2"

    (cd "$tmpdir" && node "$script_path" 2>/dev/null)
}

payload_for_compact() {
    HOOK_EVENT="$1" TRIGGER_TEXT="${2:-auto}" CWD_TEXT="${3:-$PWD}" node -e 'process.stdout.write(JSON.stringify({
      cwd: process.env.CWD_TEXT,
      hook_event_name: process.env.HOOK_EVENT,
      model: "gpt-5.5",
      session_id: "session-test",
      transcript_path: null,
      trigger: process.env.TRIGGER_TEXT,
      turn_id: "turn-test"
    }));'
}

run_hook_status() {
    local payload="$1"
    local script_path="$2"

    if [ "$IS_WINDOWS" = "true" ]; then
        local win_path
        win_path=$(cygpath -w "$script_path")
        printf '%s' "$payload" | powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$win_path" >/dev/null 2>&1
    else
        printf '%s' "$payload" | "$script_path" >/dev/null 2>&1
    fi
}

run_node_hook_status() {
    local payload="$1"
    local script_path="$2"

    printf '%s' "$payload" | node "$script_path" >/dev/null 2>&1
}

payload_for_command() {
    COMMAND_TEXT="$1" node -e 'process.stdout.write(JSON.stringify({ tool_input: { command: process.env.COMMAND_TEXT } }));'
}

payload_for_command_with_workdir() {
    COMMAND_TEXT="$1" WORKDIR_TEXT="$2" node -e 'process.stdout.write(JSON.stringify({ tool_input: { command: process.env.COMMAND_TEXT, workdir: process.env.WORKDIR_TEXT } }));'
}

deep_nested_eval_command() {
    COMMAND_TEXT="git push origin main" node -e '
        let command = process.env.COMMAND_TEXT;
        for (let index = 0; index < 6; index += 1) {
            command = `eval ${JSON.stringify(command)}`;
        }
        process.stdout.write(command);
    '
}

echo "=== Codex SDLC Adapter Tests ==="
echo ""

if [ "$IS_WINDOWS" = "true" ]; then
    PRETOOL_SCRIPT="$HOOKS_DIR/git-guard.ps1"
    SESSION_SCRIPT="$HOOKS_DIR/session-start.ps1"
    HOOKS_FILE="$REPO_DIR/.codex/windows-hooks.json"
    EXPECTED_HELPER="start-sdlc.ps1"
else
    PRETOOL_SCRIPT="$HOOKS_DIR/bash-guard.sh"
    SESSION_SCRIPT="$HOOKS_DIR/session-start.sh"
    HOOKS_FILE="$REPO_DIR/.codex/unix-hooks.json"
    EXPECTED_HELPER="start-sdlc.sh"
fi

test_pretool_blocks_commit() {
    local output
    output=$(run_json_hook '{"tool_input":{"command":"git commit -m '\''test'\''"}}' "$PRETOOL_SCRIPT")
    if echo "$output" | grep -q '"decision":"block"' \
        && echo "$output" | grep -qi 'hard manual checkpoint' \
        && ! echo "$output" | grep -qi 'Did you run tests'; then
        pass "pre-tool hook blocks git commit"
    else
        fail "pre-tool hook did not block git commit (output: $output)"
    fi
}

test_pretool_blocks_push() {
    local output
    output=$(run_json_hook '{"tool_input":{"command":"git push origin main"}}' "$PRETOOL_SCRIPT")
    if echo "$output" | grep -q '"decision":"block"' \
        && echo "$output" | grep -qi 'hard manual checkpoint' \
        && ! echo "$output" | grep -qi 'Did you self-review'; then
        pass "pre-tool hook blocks git push"
    else
        fail "pre-tool hook did not block git push (output: $output)"
    fi
}

test_universal_pretool_allows_commit_with_fresh_proof() {
    local ws
    local output

    ws=$(mktemp -d)
    mkdir -p "$ws/.codex/hooks"
    cp "$UNIVERSAL_PRETOOL_SCRIPT" "$ws/.codex/hooks/git-guard.cjs"

    (
        cd "$ws" || exit 1
        git init -q
        printf '%s\n' "proof-target" > app.txt
        git add app.txt
        node .codex/hooks/git-guard.cjs prove --reviewed --check "true" >/dev/null
    )

    output=$(cd "$ws" && run_node_json_hook "$(payload_for_command "git commit -m test")" ".codex/hooks/git-guard.cjs")
    rm -rf "$ws"

    if [ -z "$output" ]; then
        pass "universal pre-tool hook allows git commit with fresh SDLC proof"
    else
        fail "universal pre-tool hook blocked git commit despite fresh proof (output: $output)"
    fi
}

test_universal_pretool_blocks_stale_proof() {
    local ws
    local output

    ws=$(mktemp -d)
    mkdir -p "$ws/.codex/hooks"
    cp "$UNIVERSAL_PRETOOL_SCRIPT" "$ws/.codex/hooks/git-guard.cjs"

    (
        cd "$ws" || exit 1
        git init -q
        printf '%s\n' "proof-target" > app.txt
        git add app.txt
        node .codex/hooks/git-guard.cjs prove --reviewed --check "true" >/dev/null
        printf '%s\n' "changed-after-proof" >> app.txt
    )

    output=$(cd "$ws" && run_node_json_hook "$(payload_for_command "git commit -m test")" ".codex/hooks/git-guard.cjs")
    rm -rf "$ws"

    if echo "$output" | grep -q '"decision":"block"' \
        && echo "$output" | grep -qi 'proof is stale'; then
        pass "universal pre-tool hook blocks git commit when SDLC proof is stale"
    else
        fail "universal pre-tool hook did not report stale proof (output: $output)"
    fi
}

test_universal_pretool_blocks_cross_repo_proof_reuse() {
    local trusted_ws
    local target_ws
    local output

    trusted_ws=$(mktemp -d)
    target_ws=$(mktemp -d)
    mkdir -p "$trusted_ws/.codex/hooks"
    cp "$UNIVERSAL_PRETOOL_SCRIPT" "$trusted_ws/.codex/hooks/git-guard.cjs"

    (
        cd "$trusted_ws" || exit 1
        git init -q
        printf '%s\n' "trusted-proof" > app.txt
        git add app.txt
        node .codex/hooks/git-guard.cjs prove --reviewed --check "true" >/dev/null
    )

    (
        cd "$target_ws" || exit 1
        git init -q
        printf '%s\n' "target-change" > app.txt
        git add app.txt
    )

    output=$(cd "$trusted_ws" && run_node_json_hook "$(payload_for_command "git -C $target_ws commit -m test")" ".codex/hooks/git-guard.cjs")
    rm -rf "$trusted_ws" "$target_ws"

    if echo "$output" | grep -q '"decision":"block"' \
        && echo "$output" | grep -qi 'target repo'; then
        pass "universal pre-tool hook blocks cross-repo SDLC proof reuse"
    else
        fail "universal pre-tool hook allowed cross-repo proof reuse (output: $output)"
    fi
}

test_universal_pretool_blocks_cd_proof_reuse() {
    local trusted_ws
    local target_ws
    local output

    trusted_ws=$(mktemp -d)
    target_ws=$(mktemp -d)
    mkdir -p "$trusted_ws/.codex/hooks"
    cp "$UNIVERSAL_PRETOOL_SCRIPT" "$trusted_ws/.codex/hooks/git-guard.cjs"

    (
        cd "$trusted_ws" || exit 1
        git init -q
        printf '%s\n' "trusted-proof" > app.txt
        git add app.txt
        node .codex/hooks/git-guard.cjs prove --reviewed --check "true" >/dev/null
    )

    (
        cd "$target_ws" || exit 1
        git init -q
        printf '%s\n' "target-change" > app.txt
        git add app.txt
    )

    output=$(cd "$trusted_ws" && run_node_json_hook "$(payload_for_command "cd $target_ws && git commit -m test")" ".codex/hooks/git-guard.cjs")
    rm -rf "$trusted_ws" "$target_ws"

    if echo "$output" | grep -q '"decision":"block"' \
        && echo "$output" | grep -qi 'target repo'; then
        pass "universal pre-tool hook blocks cd-based SDLC proof reuse"
    else
        fail "universal pre-tool hook allowed cd-based proof reuse (output: $output)"
    fi
}

test_universal_pretool_blocks_git_env_proof_reuse() {
    local trusted_ws
    local target_ws
    local output

    trusted_ws=$(mktemp -d)
    target_ws=$(mktemp -d)
    mkdir -p "$trusted_ws/.codex/hooks"
    cp "$UNIVERSAL_PRETOOL_SCRIPT" "$trusted_ws/.codex/hooks/git-guard.cjs"

    (
        cd "$trusted_ws" || exit 1
        git init -q
        printf '%s\n' "trusted-proof" > app.txt
        git add app.txt
        node .codex/hooks/git-guard.cjs prove --reviewed --check "true" >/dev/null
    )

    (
        cd "$target_ws" || exit 1
        git init -q
        printf '%s\n' "target-change" > app.txt
        git add app.txt
    )

    output=$(cd "$trusted_ws" && run_node_json_hook "$(payload_for_command "GIT_DIR=$target_ws/.git GIT_WORK_TREE=$target_ws git commit -m test")" ".codex/hooks/git-guard.cjs")
    rm -rf "$trusted_ws" "$target_ws"

    if echo "$output" | grep -q '"decision":"block"' \
        && echo "$output" | grep -qi 'target repo'; then
        pass "universal pre-tool hook blocks GIT_DIR/GIT_WORK_TREE SDLC proof reuse"
    else
        fail "universal pre-tool hook allowed GIT_DIR/GIT_WORK_TREE proof reuse (output: $output)"
    fi
}

test_universal_pretool_blocks_exported_git_env_proof_reuse() {
    local trusted_ws
    local target_ws
    local output

    trusted_ws=$(mktemp -d)
    target_ws=$(mktemp -d)
    mkdir -p "$trusted_ws/.codex/hooks"
    cp "$UNIVERSAL_PRETOOL_SCRIPT" "$trusted_ws/.codex/hooks/git-guard.cjs"

    (
        cd "$trusted_ws" || exit 1
        git init -q
        printf '%s\n' "trusted-proof" > app.txt
        git add app.txt
        node .codex/hooks/git-guard.cjs prove --reviewed --check "true" >/dev/null
    )

    (
        cd "$target_ws" || exit 1
        git init -q
        printf '%s\n' "target-change" > app.txt
        git add app.txt
    )

    output=$(cd "$trusted_ws" && run_node_json_hook "$(payload_for_command "export GIT_DIR=$target_ws/.git GIT_WORK_TREE=$target_ws; git commit -m test")" ".codex/hooks/git-guard.cjs")
    rm -rf "$trusted_ws" "$target_ws"

    if echo "$output" | grep -q '"decision":"block"' \
        && echo "$output" | grep -qi 'target repo'; then
        pass "universal pre-tool hook blocks exported GIT_DIR/GIT_WORK_TREE SDLC proof reuse"
    else
        fail "universal pre-tool hook allowed exported GIT_DIR/GIT_WORK_TREE proof reuse (output: $output)"
    fi
}

test_universal_pretool_blocks_auto_exported_git_env_proof_reuse() {
    local trusted_ws
    local target_ws
    local output

    trusted_ws=$(mktemp -d)
    target_ws=$(mktemp -d)
    mkdir -p "$trusted_ws/.codex/hooks"
    cp "$UNIVERSAL_PRETOOL_SCRIPT" "$trusted_ws/.codex/hooks/git-guard.cjs"

    (
        cd "$trusted_ws" || exit 1
        git init -q
        printf '%s\n' "trusted-proof" > app.txt
        git add app.txt
        node .codex/hooks/git-guard.cjs prove --reviewed --check "true" >/dev/null
    )

    (
        cd "$target_ws" || exit 1
        git init -q
        printf '%s\n' "target-change" > app.txt
        git add app.txt
    )

    output=$(cd "$trusted_ws" && run_node_json_hook "$(payload_for_command "set -a; GIT_DIR=$target_ws/.git GIT_WORK_TREE=$target_ws; git commit -m test")" ".codex/hooks/git-guard.cjs")
    rm -rf "$trusted_ws" "$target_ws"

    if echo "$output" | grep -q '"decision":"block"' \
        && echo "$output" | grep -qi 'target repo'; then
        pass "universal pre-tool hook blocks auto-exported GIT_DIR/GIT_WORK_TREE SDLC proof reuse"
    else
        fail "universal pre-tool hook allowed auto-exported GIT_DIR/GIT_WORK_TREE proof reuse (output: $output)"
    fi
}

test_universal_pretool_blocks_workdir_proof_reuse() {
    local trusted_ws
    local target_ws
    local output

    trusted_ws=$(mktemp -d)
    target_ws=$(mktemp -d)
    mkdir -p "$trusted_ws/.codex/hooks"
    cp "$UNIVERSAL_PRETOOL_SCRIPT" "$trusted_ws/.codex/hooks/git-guard.cjs"

    (
        cd "$trusted_ws" || exit 1
        git init -q
        printf '%s\n' "trusted-proof" > app.txt
        git add app.txt
        node .codex/hooks/git-guard.cjs prove --reviewed --check "true" >/dev/null
    )

    (
        cd "$target_ws" || exit 1
        git init -q
        printf '%s\n' "target-change" > app.txt
        git add app.txt
    )

    output=$(cd "$trusted_ws" && run_node_json_hook "$(payload_for_command_with_workdir "git commit -m test" "$target_ws")" ".codex/hooks/git-guard.cjs")
    rm -rf "$trusted_ws" "$target_ws"

    if echo "$output" | grep -q '"decision":"block"' \
        && echo "$output" | grep -qi 'proof is missing'; then
        pass "universal pre-tool hook checks proof against Bash workdir"
    else
        fail "universal pre-tool hook reused process-cwd proof for Bash workdir (output: $output)"
    fi
}

test_universal_pretool_allows_workdir_with_fresh_proof() {
    local trusted_ws
    local target_ws
    local output

    trusted_ws=$(mktemp -d)
    target_ws=$(mktemp -d)
    mkdir -p "$trusted_ws/.codex/hooks"
    cp "$UNIVERSAL_PRETOOL_SCRIPT" "$trusted_ws/.codex/hooks/git-guard.cjs"

    (
        cd "$trusted_ws" || exit 1
        git init -q
    )

    (
        cd "$target_ws" || exit 1
        git init -q
        printf '%s\n' "target-proof" > app.txt
        git add app.txt
        node "$trusted_ws/.codex/hooks/git-guard.cjs" prove --reviewed --check "true" >/dev/null
    )

    output=$(cd "$trusted_ws" && run_node_json_hook "$(payload_for_command_with_workdir "git commit -m test" "$target_ws")" ".codex/hooks/git-guard.cjs")
    rm -rf "$trusted_ws" "$target_ws"

    if [ -z "$output" ]; then
        pass "universal pre-tool hook allows Bash workdir with fresh SDLC proof"
    else
        fail "universal pre-tool hook blocked Bash workdir despite fresh proof (output: $output)"
    fi
}

test_pretool_blocks_git_after_shell_prefixes() {
    local commands=(
        "npm test && git commit -m test"
        "cd repo; git push origin main"
        "AFTERHOURS_SKIP=1 git push origin main"
        "A[0]=x git push origin main"
        "A[0]+=x git commit -m test"
        "npm test & git push origin main"
        "(git commit -m test)"
        "sudo git commit -m test"
        "if git push origin main; then echo ok; fi"
        "for x in y; do git commit -m test; done"
        $'npm test\ngit push origin main'
        "env -u FOO git push origin main"
        'env -iS "git push origin main"'
        'env -iu FOO -S "git push origin main"'
        "sudo -u root git commit -m test"
        "sudo -HEu root git push origin main"
        "sudo -u >out root git commit -m test"
        "sudo -r sysadm_r git push origin main"
        "sudo -t sysadm_t git commit -m test"
        "sudo --role sysadm_r git push origin main"
        "sudo --type sysadm_t git commit -m test"
        'sudo -Eu root bash -c "git push origin main"'
        "if false; then :; else git push origin main; fi"
        "elif git push origin main; then echo ok; fi"
        "{ git push origin main; }"
        "FOO+=bar git commit -m test"
        ">/tmp/out git push origin main"
        "2>err git commit -m test"
        "git push>/tmp/out origin main"
        "git commit>/tmp/out -m test"
        "git push origin main # --help"
        "git commit -m test # --help"
        "git push -- --help"
        "git push origin -- --help"
        "git commit -- --help"
        "git commit -m --help"
        "git commit -F --help"
        "git commit --message --help"
        "git push origin --receive-pack --help main"
        "git push origin --repo --help main"
        "git>/tmp/out push origin main"
        "git</tmp/in commit -F -"
        "git push&>/tmp/out"
        'git --exec-path "$(git --exec-path)" push'
        'echo "$( git push origin main)"'
        "nice git push origin main"
        "nice -n 10 git commit -m test"
        "stdbuf -oL git push origin main"
        "unbuffer git push origin main"
        "arch -x86_64 git push origin main"
        "script -q /dev/null git push origin main"
        "script -c 'git push origin main' /dev/null"
        'script --command "git commit -m test" /dev/null'
        "ssh-agent git push origin main"
        "ssh-agent bash -c 'git commit -m test'"
        'su -c "git push origin main"'
        "su --session-command 'git push origin main'"
        "su --session-command='git commit -m test'"
        "doas git push origin main"
        "chrt -r 1 git push origin main"
        "taskset -c 0 git push origin main"
        "ionice -c2 git push origin main"
        $'npm test && \\\n git push origin main'
        $'git \\\n push origin main'
        "2>&1 git push origin main"
        ">&2 git commit -m test"
        "git >& 2 push origin main"
        "git 2>& 1 commit -m test"
        "env -S git push origin main"
        'env -S "git commit -m test"'
        'env -S "-- git push origin main"'
        'env -S "-i git push origin main"'
        'env -S "--ignore-environment git push origin main"'
        'env -S "-u FOO git push origin main"'
        'env -S "-C /tmp git push origin main"'
        "env -P /usr/bin git push origin main"
        "env -a fake git push origin main"
        "env --argv0 fake git commit -m test"
        "env -u >out FOO git push origin main"
        "env -P >out /usr/bin git push origin main"
        "exec -a git git push origin main"
        "noglob git push origin main"
        "noglob git commit -m test"
        'eval "git push origin main"'
        'eval -- "git push origin main"'
        'bash -c "git push origin main"'
        'bash -c -- "git push origin main"'
        "cmd /c git push origin main"
        "CMD /C git push origin main"
        "cmd /c call git push origin main"
        "cmd /c CALL git commit -m test"
        "cmd /c start git push origin main"
        'cmd /c start "title" git push origin main'
        'cmd /c start /b "title" git commit -m test'
        "cmd.exe /c git commit -m test"
        'powershell -Command "git push origin main"'
        'PowerShell -Command "git push origin main"'
        'powershell -Command "start git push origin main"'
        'powershell -Command "Start-Process git -ArgumentList push,origin,main"'
        "powershell -EncodedCommand ZwBpAHQAIABwAHUAcwBoACAAbwByAGkAZwBpAG4AIABtAGEAaQBuAA=="
        "pwsh -e ZwBpAHQAIABjAG8AbQBtAGkAdAAgAC0AbQAgAHQAZQBzAHQA"
        'powershell.exe -NoProfile -Command "git commit -m test"'
        'pwsh -c "git push origin main"'
        'PwSh -c "git commit -m test"'
        'zsh --emulate sh -c "git push origin main"'
        'fish --command="git push origin main"'
        'fish --init-command="git push origin main"'
        'fish -C "git push origin main"'
        'sh -c -- "git commit -m test"'
        "sh -c 'git \"\$@\"' sh push origin main"
        "bash -c 'exec git \"\${@}\"' bash push origin main"
        "bash -c 'sh -c \"\$*\"' bash git push origin main"
        "bash -c 'exec git \"\$@\"' bash push origin main"
        "bash -c 'git \"\$1\" origin main' bash push"
        "bash -c 'git \"\${@:1:1}\" origin main' bash push"
        "bash -c 'git \"\${*:1:1}\" origin main' bash push"
        "trap 'git push origin main' EXIT"
        "bash -c 'trap \"git push origin main\" EXIT'"
        'bash -c '\''eval -- "git push origin main"'\'''
        'bash -c >out "git push origin main"'
        'bash -O >out extglob -c "git push origin main"'
        "case main in main) git push origin main;; esac"
        "case main in main) git commit -m test;; esac"
        "git >/tmp/out push origin main"
        "git 2>err commit -m test"
        "git -C >out repo push origin main"
        "git --git-dir >out .git push origin main"
        'git -c >out alias.p=push p'
        $'# <<EOF\ngit push origin main'
        $'# <<\'EOF\'\ngit push origin main\nEOF'
        $'# cat <<EOF\ngit commit -m test\nEOF'
        $'cat <<EOF # <<NEVER\nsafe\nEOF\ngit push origin main'
        $'bash <<EOF\ngit push origin main\nEOF'
        $'sh <<EOF\ngit commit -m test\nEOF'
        $'bash <<\'EOF\'\ngit push origin main\nEOF'
        $'cat <<\\EOF\nsafe\nEOF\ngit push origin main'
        $'cat <<EOF > /tmp/run.sh\ngit push origin main\nEOF\nbash /tmp/run.sh'
        $'cat <<\'EOF\' >/tmp/run.sh\ngit commit -m test\nEOF\nsh /tmp/run.sh'
        $'cat <<EOF > /tmp/run.sh\ngit push origin main\nEOF\n. /tmp/run.sh'
        $'cat <<EOF > /tmp/run.sh\ngit commit -m test\nEOF\nsource /tmp/run.sh'
        $'cat <<EOF &> /tmp/run.sh\ngit push origin main\nEOF\nbash /tmp/run.sh'
        $'cat <<EOF &>> /tmp/run.sh\ngit commit -m test\nEOF\nsh /tmp/run.sh'
        $'cat <<EOF > run.sh\ngit push origin main\nEOF\nbash ./run.sh'
        $'cat <<\'E\\OF\' > run.sh\ngit push origin main\nE\\OF\nbash ./run.sh'
        $'cat <<EOF > run.sh && chmod +x run.sh\ngit push origin main\nEOF\nbash ./run.sh'
        $'cat > run.sh <<EOF\ngit commit -m test\nEOF\nchmod +x run.sh && ./run.sh'
        $'cat > run.sh <<EOF && chmod +x run.sh && ./run.sh\ngit push origin main\nEOF'
        $'cat > run.sh <<\'EOF\'\ngit "$@"\nEOF\nbash run.sh push origin main'
        $'cat > run.sh <<\'EOF\'\ngit "$1" origin main\nEOF\nbash run.sh push'
        $'cat > run.sh <<EOF\ngit push origin main\nEOF\nbash < run.sh'
        $'cat > run.sh <<EOF\ngit commit -m test\nEOF\nsh 0< run.sh'
        "echo git push origin main > run.sh && bash run.sh"
        "printf 'git commit -m test\n' > run.sh && sh run.sh"
        "printf 'git push origin main\n' | tee run.sh >/dev/null && bash run.sh"
        $'cat <<EOF | tee run.sh >/dev/null\ngit push origin main\nEOF\nbash run.sh'
        $'tee >/dev/null run.sh <<\'EOF\'\ngit commit -m test\nEOF\nsh run.sh'
        $'tee >/tmp/run.sh <<EOF\ngit push origin main\nEOF\nbash /tmp/run.sh'
        $'tee > /tmp/run.sh <<EOF\ngit commit -m test\nEOF\nsh /tmp/run.sh'
        $'cat <<END-OF >/dev/null\nsafe\nEND-OF\ngit push origin main'
        "timeout 30 git push origin main"
        "timeout 30 git commit -m test"
        "flock /tmp/codex-sdlc-test.lock git push origin main"
        "flock -n /tmp/codex-sdlc-test.lock git commit -m test"
        "/usr/bin/env git push origin main"
        "/bin/env git commit -m test"
        "/usr/bin/sudo git push origin main"
        "runuser -u root -- git push origin main"
        "runuser --user root -- git commit -m test"
        "/usr/bin/nohup git push origin main"
        "/usr/bin/time git push origin main"
        "/usr/bin/timeout 30 git commit -m test"
        "/usr/bin/nice git push origin main"
        "/usr/bin/git push origin main"
        "Git.exe push origin main"
        "git.exe push origin main"
        "git.exe commit -m test"
        "/mingw64/bin/git.exe commit -m test"
        '"C:/Program Files/Git/cmd/git.exe" push origin main'
        "find . -exec git push origin main \\;"
        "find . -exec /usr/bin/git commit -m test \\;"
        "find . -exec sh -c 'git push origin main' \\;"
        "xargs git push origin main"
        "xargs -i git push {}"
        "xargs --replace git commit -m test"
        "xargs -e git push origin main"
        "xargs --eof git push origin main"
        "xargs git <<< push"
        "xargs -I{} git {} <<< push"
        "watch git push origin main"
        "watch -x git push origin main"
        "watch --exec git push origin main"
        "watch --no-title git commit -m test"
        "parallel git push ::: origin main"
        "parallel -k git push ::: origin main"
        "parallel --keep-order git push ::: origin main"
        "parallel --results out git push ::: origin main"
        "parallel --tagstring tag git push ::: origin main"
        "parallel -C , git push ::: origin main"
        "parallel --colsep , git commit -m test ::: x"
        "parallel -u git commit -m test ::: x"
        "parallel git ::: push"
        "parallel git {} ::: push"
        "git submodule foreach git push origin main"
        "git submodule foreach git commit -m test"
        "git -C repo submodule foreach git push origin main"
        "git submodule foreach 'git push origin main'"
        "git lfs push origin main"
        "git lfs push origin main # --help"
        "git lfs -c lfs.dialtimeout=1 push origin main"
        "git subtree push --prefix dist origin gh-pages"
        "git subtree push --prefix dist origin gh-pages # --help"
        "git subtree --prefix dist push origin gh-pages"
        'git -c alias.p="!git push origin main" p'
        "git -c alias.p='!git \"\$1\" origin main' p push"
        'git -c alias.c="!git commit -m test" c'
        "git -c alias.p='!\$@' p git push origin main"
        "git -c alias.p='!sh -c \"\$@\"' p git push origin main"
        "git -c alias.p='!eval \"\$@\"' p 'git push origin main'"
        "git -c alias.p='!git \"\${@}\"' p push origin main"
        "git -c alias.p='!trap \"git push origin main\" EXIT' p"
        "ALIAS=push git --config-env=alias.p=ALIAS p origin main"
        "ALIAS=commit git --config-env=alias.c=ALIAS c -m test"
        "git -c alias.p='!f() { git \"\$@\"; }; f' p push origin main"
        "git -c alias.p='!f() { exec git \"\$@\"; }; f' p push origin main"
        'git -c alias.p=push p'
        'git -c alias.c=commit c'
        'git -c alias.p="push origin main" p'
        'git -c alias.p=push -c alias.q=p q origin main'
        'git -c alias.c=commit -c alias.q=c q -m test'
        'git -c alias.p="!git push origin main" p -h'
        'git -c alias.c="!git commit -m test" c -h'
        '/usr/bin/env -S "git push origin main"'
        'sudo /usr/bin/env -S "git push origin main"'
        'sudo bash -c "git push origin main"'
        'sudo eval "git push origin main"'
        'eval "$(echo git push origin main)"'
        $'eval "$(cat <<\'EOF\'\ngit push origin main\nEOF\n)"'
        'bash -c "$(echo git push origin main)"'
        '$(echo -e git\\x20push) origin main'
        '$(echo git; echo push) origin main'
        'eval "$(echo -e git\\x20push origin main)"'
        'bash -c "$(echo -e git\\x20push origin main)"'
        "zsh -c 'nocorrect git push origin main'"
        '$(echo git push origin main)'
        '$(printf "git\x20push") origin main'
        $'$(cat <<EOF\ngit push origin main\nEOF\n)'
        '$(echo git) push origin main'
        '$(printf %s git) commit -m test'
        'g$(printf it) push origin main'
        'g$(echo it) com$(printf mit) -m test'
        'git p$(printf ush) origin main'
        'git pu$(echo sh) origin main'
        'git com$(printf mit) -m test'
        'git "$(printf push)" origin main'
        'git p`printf ush` origin main'
        'g`printf it` push origin main'
        'bash -c "$(echo git) push origin main"'
        'eval "$(echo git) commit -m test"'
        'eval "$(printf '\''%q '\'' git push origin main)"'
        "bash -c \"\$(printf git; printf ' push origin main')\""
        "eval \"\$(echo -n git; echo ' commit -m test')\""
        "bash -c \"\$(printf 'git push origin main' | cat)\""
        "eval \"\$(printf 'git commit -m test' | tee /dev/null)\""
        "printf -- 'git push origin main\n' | bash"
        "printf -- 'push\n' | xargs git"
        "printf 'push\\0' | xargs -0 git"
        "printf 'push,' | xargs -d, git"
        '`echo git commit -m test`'
        'echo "$(case x in x) echo ok;; esac; git push origin main)"'
        'echo "$( (echo ok); git push origin main )"'
        'bash -c "$( (echo echo ok); echo git push origin main )"'
        $'bash -c "$(cat <<EOF\ngit push origin main\nEOF\n)"'
        $'sh -c "$(cat <<EOF\ngit commit -m test\nEOF\n)"'
        "function f { git push origin main; }; f"
        'function f() { git "$@"; }; f push origin main'
        'f() { git "$@"; }; f push origin main'
        'f() { command git "$@"; }; f push origin main'
        'f() { git "$1" origin main; }; f push'
        "coproc git push origin main"
        "setsid git push origin main"
        'bash >out -c "git push origin main"'
        'bash -O extglob -c "git push origin main"'
        "eval \$'git push origin main'"
        "eval \$'git\\x20push origin main'"
        "bash -c \$'git push origin main'"
        "bash -c \$'git\\040commit -m test'"
        "printf 'git push origin main\n' | bash"
        "printf 'git push origin main\n' |& bash"
        "echo git push origin main |& sh"
        "echo -e \"git\\x20push origin main\" | bash"
        "printf \"git\\x20push origin main\n\" | bash"
        "printf 'git push origin main\n' | cat | bash"
        "printf 'git push origin main\n' | tee /dev/null | bash"
        "printf 'git push origin main\n' | env -S \"bash -s\""
        $'cat <<EOF | xargs -I{} sh -c \'{}\'\ngit push origin main\nEOF'
        "printf 'git push origin main\n' | xargs -I{} sh -c '{}'"
        "printf 'git push origin main\n' | xargs -I{} bash -c '{}'"
        "echo git push origin main | xargs -I{} sh -c '{}'"
        $'echo ok\nxargs git <<EOF\npush\nEOF'
        $'echo ok\ncat <<EOF | xargs git\npush\nEOF'
        "parallel ::: 'git push origin main'"
        "parallel --jobs 1 ::: 'git commit -m test'"
        "flock -n -c 'git push origin main' /tmp/lock"
        "flock --command='git commit -m test' /tmp/lock"
        "su -c'git push origin main'"
        "script -c'git commit -m test' /dev/null"
        "echo git push origin main | tee >(bash)"
        "printf 'git push origin main\n' | tee >(bash)"
        "printf 'git push origin main\n' | cat > >(bash)"
        "cat > >(bash) <<< 'git push origin main'"
        "tee >(bash) <<< 'git push origin main'"
        "printf 'git push origin main\n' 2>&1 > >(bash)"
        "printf 'git push origin main\n' >| >(bash)"
        "printf 'git push origin main\n' | bash -c 'bash'"
        "bash -c 'source /dev/stdin' <<< 'git commit -m test'"
        "printf '%s ' git push origin main | bash"
        "printf 'git commit -m test\n' | sh"
        "printf '%s\n' 'git push origin main' | bash"
        "printf '%s %s %s %s\n' git commit -m test | sh"
        "echo git push origin main | bash"
        "echo git push origin main | sh -s -- arg"
        "printf '%s\n' 'git commit -m test' | bash -s arg"
        "bash <<< 'git push origin main'"
        'bash <<<$(echo git push origin main)'
        "env -S \"bash -s\" <<< 'git commit -m test'"
        "sh <<< \$'git commit -m test'"
        "<<< 'git push origin main' cat | bash"
        "bash -s arg <<< 'git push origin main'"
        "sh -s -- arg <<< \$'git commit -m test'"
        "bash /dev/fd/3 3<<< 'git push origin main'"
        "source /dev/fd/7 7<<< 'git commit -m test'"
        "bash <(echo git push origin main)"
        "bash <> <(echo git push origin main)"
        "bash 0<> <(echo git push origin main)"
        "sh <(printf 'git commit -m test\n')"
        "bash <(printf 'git push origin main\n' | cat)"
        "source <(printf 'git commit -m test\n' | tee /dev/null)"
        "bash < <(echo git push origin main)"
        "source <(echo git push origin main)"
        ". <(echo git commit -m test)"
        "/opt/homebrew/bin/bash <(echo git push origin main)"
        "env /usr/local/bin/bash <(echo git push origin main)"
        "sudo -u root bash <(echo git push origin main)"
        "env -u FOO bash <(echo git push origin main)"
        "env -P /usr/bin bash <(echo git push origin main)"
        "time -f %e bash <(echo git push origin main)"
        "cat <(git push origin main)"
        "cat <( git push origin main )"
        "cat >(git commit -m test)"
        "diff <(echo ok) <(git push origin main)"
        "echo \`git push origin main\`"
        "echo \` git push origin main\`"
        $'cat <<EOF | bash\ngit push origin main\nEOF'
        $'cat <<EOF | sh\ngit commit -m test\nEOF'
        $'cat <<EOF | /usr/bin/sudo /bin/bash\ngit push origin main\nEOF'
        $'cat <<EOF | env bash\ngit push origin main\nEOF'
        $'cat <<EOF | env -S "bash"\ngit push origin main\nEOF'
        $'tee /tmp/run.sh >/dev/null <<\'EOF\'\ngit push origin main\nEOF\nbash /tmp/run.sh'
        $'cat <<EOF > >(bash)\ngit push origin main\nEOF'
        "echo git push origin main > >(bash)"
        $'cat <<EOF 1> >(sh)\ngit commit -m test\nEOF'
        $'cat <<EOF\n$(git push origin main)\nEOF'
    )
    local failures=""
    local command
    local output

    for command in "${commands[@]}"; do
        output=$(run_json_hook "$(payload_for_command "$command")" "$PRETOOL_SCRIPT")
        if ! echo "$output" | grep -q '"decision":"block"'; then
            failures="${failures} [$command => $output]"
        fi
    done

    if [ -z "$failures" ]; then
        pass "pre-tool hook blocks git commit/push after shell prefixes"
    else
        fail "pre-tool hook allowed shell-prefix git commands:$failures"
    fi
}

test_pretool_allows_safe_command() {
    local output
    output=$(run_json_hook '{"tool_input":{"command":"git diff"}}' "$PRETOOL_SCRIPT")
    if [ -z "$output" ]; then
        pass "pre-tool hook allows safe commands"
    else
        fail "pre-tool hook unexpectedly blocked safe command (output: $output)"
    fi
}

test_pretool_reads_command_field() {
    local output
    output=$(run_json_hook '{"tool_input":{"command":"echo hello","file_path":"git commit -m test"}}' "$PRETOOL_SCRIPT")
    if [ -z "$output" ]; then
        pass "pre-tool hook reads tool_input.command"
    else
        fail "pre-tool hook incorrectly read file_path"
    fi
}

test_pretool_allows_non_git_command_mentions() {
    local issue_command
    local helper_echo_command
    local print_command
    local quoted_heredoc_command
    local git_global_help_command
    local git_help_command
    local git_push_help_command
    local git_alias_push_help_command
    local git_alias_commit_help_command
    local git_help_command_substitution
    local git_push_help_command_substitution
    local git_push_late_help_command
    local git_commit_late_help_command
    local git_lfs_push_help_command
    local git_subtree_push_help_command
    local quoted_python_heredoc_command
    local safe_process_substitution_after_shell_command
    local safe_process_substitution_inside_shell_payload
    local output1
    local output2
    local output3
    local output4
    local output5
    local output6
    local output7
    local output8
    local output9
    local output10
    local output11
    local output12
    local output13
    local output14
    local output15
    local output16
    local output17
    local output18
    local output19

    issue_command=$'gh issue create --title bug --body "$(cat <<EOF\ngit commit -m test should not block here\nEOF\n)"'
    helper_echo_command="find . -exec echo git push origin main \\;"
    print_command="printf %s git push origin main"
    quoted_heredoc_command=$'cat <<\'EOF\'\n$(git push origin main)\nEOF'
    git_global_help_command="git --help push"
    git_help_command="git help push"
    git_push_help_command="git push --help"
    git_alias_push_help_command="git -c alias.p=push p --help"
    git_alias_commit_help_command="git -c alias.c=commit c -h"
    git_help_command_substitution='bash -c "$(git help push)"'
    git_push_help_command_substitution='eval "$(git push --help)"'
    git_push_late_help_command="git push origin --help"
    git_commit_late_help_command="git commit -m test --help"
    git_lfs_push_help_command="git lfs push --help"
    git_lfs_global_help_command="git lfs --help push"
    git_subtree_push_help_command="git subtree push --help"
    quoted_python_heredoc_command=$'python <<\'EOF\'\n$(git push origin main)\nEOF'
    safe_process_substitution_after_shell_command='bash -c "true"; cat <(echo git push origin main)'
    safe_process_substitution_inside_shell_payload='bash -c "cat <(echo git push origin main)"'
    output1=$(run_json_hook "$(payload_for_command "$issue_command")" "$PRETOOL_SCRIPT")
    output2=$(run_json_hook "$(payload_for_command "$print_command")" "$PRETOOL_SCRIPT")
    output3=$(run_json_hook "$(payload_for_command "$helper_echo_command")" "$PRETOOL_SCRIPT")
    output4=$(run_json_hook "$(payload_for_command "$quoted_heredoc_command")" "$PRETOOL_SCRIPT")
    output5=$(run_json_hook "$(payload_for_command "$git_global_help_command")" "$PRETOOL_SCRIPT")
    output6=$(run_json_hook "$(payload_for_command "$git_help_command")" "$PRETOOL_SCRIPT")
    output7=$(run_json_hook "$(payload_for_command "$git_push_help_command")" "$PRETOOL_SCRIPT")
    output8=$(run_json_hook "$(payload_for_command "$quoted_python_heredoc_command")" "$PRETOOL_SCRIPT")
    output9=$(run_json_hook "$(payload_for_command "$git_alias_push_help_command")" "$PRETOOL_SCRIPT")
    output10=$(run_json_hook "$(payload_for_command "$git_alias_commit_help_command")" "$PRETOOL_SCRIPT")
    output11=$(run_json_hook "$(payload_for_command "$git_help_command_substitution")" "$PRETOOL_SCRIPT")
    output12=$(run_json_hook "$(payload_for_command "$git_push_help_command_substitution")" "$PRETOOL_SCRIPT")
    output13=$(run_json_hook "$(payload_for_command "$git_push_late_help_command")" "$PRETOOL_SCRIPT")
    output14=$(run_json_hook "$(payload_for_command "$git_commit_late_help_command")" "$PRETOOL_SCRIPT")
    output15=$(run_json_hook "$(payload_for_command "$git_lfs_push_help_command")" "$PRETOOL_SCRIPT")
    output16=$(run_json_hook "$(payload_for_command "$git_subtree_push_help_command")" "$PRETOOL_SCRIPT")
    output17=$(run_json_hook "$(payload_for_command "$git_lfs_global_help_command")" "$PRETOOL_SCRIPT")
    output18=$(run_json_hook "$(payload_for_command "$safe_process_substitution_after_shell_command")" "$PRETOOL_SCRIPT")
    output19=$(run_json_hook "$(payload_for_command "$safe_process_substitution_inside_shell_payload")" "$PRETOOL_SCRIPT")

    if [ -z "$output1$output2$output3$output4$output5$output6$output7$output8$output9$output10$output11$output12$output13$output14$output15$output16$output17$output18$output19" ]; then
        pass "pre-tool hook allows non-git commands that mention git commit/push"
    else
        fail "pre-tool hook blocked non-git command text (output1: $output1 output2: $output2 output3: $output3 output4: $output4 output5: $output5 output6: $output6 output7: $output7 output8: $output8 output9: $output9 output10: $output10 output11: $output11 output12: $output12 output13: $output13 output14: $output14 output15: $output15 output16: $output16 output17: $output17 output18: $output18 output19: $output19)"
    fi
}

test_pretool_does_not_crash_on_non_git_prototype_words() {
    if run_hook_status "$(payload_for_command "toString -x git push origin main")" "$PRETOOL_SCRIPT" \
        && run_hook_status "$(payload_for_command "echo \$'\\UFFFFFFFF'")" "$PRETOOL_SCRIPT"; then
        pass "pre-tool hook does not crash on non-git prototype words"
    else
        fail "pre-tool hook crashed on non-git prototype words"
    fi
}

test_pretool_blocks_deep_wrapper_recursion() {
    local command
    local output
    command=$(deep_nested_eval_command)
    output=$(run_json_hook "$(payload_for_command "$command")" "$PRETOOL_SCRIPT")

    if echo "$output" | grep -q '"decision":"block"'; then
        pass "pre-tool hook blocks deep wrapper recursion"
    else
        fail "pre-tool hook allowed deep wrapper recursion (output: $output)"
    fi
}

test_session_warns_missing() {
    local tmpdir
    tmpdir=$(mktemp -d)
    local output
    output=$(run_session_hook "$tmpdir" "$SESSION_SCRIPT")
    rm -rf "$tmpdir"
    if echo "$output" | grep -q '"additionalContext"'; then
        pass "session hook warns when AGENTS.md is missing"
    else
        fail "session hook did not warn when AGENTS.md was missing"
    fi
}

test_session_silent_when_present() {
    local tmpdir
    tmpdir=$(mktemp -d)
    touch "$tmpdir/AGENTS.md"
    local output
    output=$(run_session_hook "$tmpdir" "$SESSION_SCRIPT")
    rm -rf "$tmpdir"
    if [ -z "$output" ]; then
        pass "session hook is silent when AGENTS.md exists"
    else
        fail "session hook produced output when AGENTS.md exists"
    fi
}

test_universal_pretool_blocks_commit() {
    local output
    output=$(run_node_json_hook '{"tool_input":{"command":"git commit -m '\''test'\''"}}' "$UNIVERSAL_PRETOOL_SCRIPT")
    if echo "$output" | grep -q '"decision":"block"'; then
        pass "universal pre-tool hook blocks git commit"
    else
        fail "universal pre-tool hook did not block git commit (output: $output)"
    fi
}

test_universal_pretool_blocks_git_after_shell_prefixes() {
    local commands=(
        "npm test && git commit -m test"
        "cd repo; git push origin main"
        "AFTERHOURS_SKIP=1 git push origin main"
        "A[0]=x git push origin main"
        "A[0]+=x git commit -m test"
        "npm test & git push origin main"
        "(git commit -m test)"
        "sudo git commit -m test"
        "if git push origin main; then echo ok; fi"
        "for x in y; do git commit -m test; done"
        $'npm test\ngit push origin main'
        "env -u FOO git push origin main"
        'env -iS "git push origin main"'
        'env -iu FOO -S "git push origin main"'
        "sudo -u root git commit -m test"
        "sudo -HEu root git push origin main"
        "sudo -u >out root git commit -m test"
        "sudo -r sysadm_r git push origin main"
        "sudo -t sysadm_t git commit -m test"
        "sudo --role sysadm_r git push origin main"
        "sudo --type sysadm_t git commit -m test"
        'sudo -Eu root bash -c "git push origin main"'
        "if false; then :; else git push origin main; fi"
        "elif git push origin main; then echo ok; fi"
        "{ git push origin main; }"
        "FOO+=bar git commit -m test"
        ">/tmp/out git push origin main"
        "2>err git commit -m test"
        "git push>/tmp/out origin main"
        "git commit>/tmp/out -m test"
        "git push origin main # --help"
        "git commit -m test # --help"
        "git push -- --help"
        "git push origin -- --help"
        "git commit -- --help"
        "git commit -m --help"
        "git commit -F --help"
        "git commit --message --help"
        "git push origin --receive-pack --help main"
        "git push origin --repo --help main"
        "git>/tmp/out push origin main"
        "git</tmp/in commit -F -"
        "git push&>/tmp/out"
        'git --exec-path "$(git --exec-path)" push'
        'echo "$( git push origin main)"'
        "nice git push origin main"
        "nice -n 10 git commit -m test"
        "stdbuf -oL git push origin main"
        "unbuffer git push origin main"
        "arch -x86_64 git push origin main"
        "script -q /dev/null git push origin main"
        "script -c 'git push origin main' /dev/null"
        'script --command "git commit -m test" /dev/null'
        "ssh-agent git push origin main"
        "ssh-agent bash -c 'git commit -m test'"
        'su -c "git push origin main"'
        "su --session-command 'git push origin main'"
        "su --session-command='git commit -m test'"
        "doas git push origin main"
        "chrt -r 1 git push origin main"
        "taskset -c 0 git push origin main"
        "ionice -c2 git push origin main"
        $'npm test && \\\n git push origin main'
        $'git \\\n push origin main'
        "2>&1 git push origin main"
        ">&2 git commit -m test"
        "git >& 2 push origin main"
        "git 2>& 1 commit -m test"
        "env -S git push origin main"
        'env -S "git commit -m test"'
        'env -S "-- git push origin main"'
        'env -S "-i git push origin main"'
        'env -S "--ignore-environment git push origin main"'
        'env -S "-u FOO git push origin main"'
        'env -S "-C /tmp git push origin main"'
        "env -P /usr/bin git push origin main"
        "env -a fake git push origin main"
        "env --argv0 fake git commit -m test"
        "env -u >out FOO git push origin main"
        "env -P >out /usr/bin git push origin main"
        "exec -a git git push origin main"
        "noglob git push origin main"
        "noglob git commit -m test"
        'eval "git push origin main"'
        'eval -- "git push origin main"'
        'bash -c "git push origin main"'
        'bash -c -- "git push origin main"'
        "cmd /c git push origin main"
        "CMD /C git push origin main"
        "cmd /c call git push origin main"
        "cmd /c CALL git commit -m test"
        "cmd /c start git push origin main"
        'cmd /c start "title" git push origin main'
        'cmd /c start /b "title" git commit -m test'
        "cmd.exe /c git commit -m test"
        'powershell -Command "git push origin main"'
        'PowerShell -Command "git push origin main"'
        'powershell -Command "start git push origin main"'
        'powershell -Command "Start-Process git -ArgumentList push,origin,main"'
        "powershell -EncodedCommand ZwBpAHQAIABwAHUAcwBoACAAbwByAGkAZwBpAG4AIABtAGEAaQBuAA=="
        "pwsh -e ZwBpAHQAIABjAG8AbQBtAGkAdAAgAC0AbQAgAHQAZQBzAHQA"
        'powershell.exe -NoProfile -Command "git commit -m test"'
        'pwsh -c "git push origin main"'
        'PwSh -c "git commit -m test"'
        'zsh --emulate sh -c "git push origin main"'
        'fish --command="git push origin main"'
        'fish --init-command="git push origin main"'
        'fish -C "git push origin main"'
        'sh -c -- "git commit -m test"'
        "sh -c 'git \"\$@\"' sh push origin main"
        "bash -c 'exec git \"\${@}\"' bash push origin main"
        "bash -c 'sh -c \"\$*\"' bash git push origin main"
        "bash -c 'exec git \"\$@\"' bash push origin main"
        "bash -c 'git \"\$1\" origin main' bash push"
        "bash -c 'git \"\${@:1:1}\" origin main' bash push"
        "bash -c 'git \"\${*:1:1}\" origin main' bash push"
        "trap 'git push origin main' EXIT"
        "bash -c 'trap \"git push origin main\" EXIT'"
        'bash -c '\''eval -- "git push origin main"'\'''
        'bash -c >out "git push origin main"'
        'bash -O >out extglob -c "git push origin main"'
        "case main in main) git push origin main;; esac"
        "case main in main) git commit -m test;; esac"
        "git >/tmp/out push origin main"
        "git 2>err commit -m test"
        "git -C >out repo push origin main"
        "git --git-dir >out .git push origin main"
        'git -c >out alias.p=push p'
        $'# <<EOF\ngit push origin main'
        $'# <<\'EOF\'\ngit push origin main\nEOF'
        $'# cat <<EOF\ngit commit -m test\nEOF'
        $'cat <<EOF # <<NEVER\nsafe\nEOF\ngit push origin main'
        $'bash <<EOF\ngit push origin main\nEOF'
        $'sh <<EOF\ngit commit -m test\nEOF'
        $'bash <<\'EOF\'\ngit push origin main\nEOF'
        $'cat <<\\EOF\nsafe\nEOF\ngit push origin main'
        $'cat <<EOF > /tmp/run.sh\ngit push origin main\nEOF\nbash /tmp/run.sh'
        $'cat <<\'EOF\' >/tmp/run.sh\ngit commit -m test\nEOF\nsh /tmp/run.sh'
        $'cat <<EOF > /tmp/run.sh\ngit push origin main\nEOF\n. /tmp/run.sh'
        $'cat <<EOF > /tmp/run.sh\ngit commit -m test\nEOF\nsource /tmp/run.sh'
        $'cat <<EOF &> /tmp/run.sh\ngit push origin main\nEOF\nbash /tmp/run.sh'
        $'cat <<EOF &>> /tmp/run.sh\ngit commit -m test\nEOF\nsh /tmp/run.sh'
        $'cat <<EOF > run.sh\ngit push origin main\nEOF\nbash ./run.sh'
        $'cat <<\'E\\OF\' > run.sh\ngit push origin main\nE\\OF\nbash ./run.sh'
        $'cat <<EOF > run.sh && chmod +x run.sh\ngit push origin main\nEOF\nbash ./run.sh'
        $'cat > run.sh <<EOF\ngit commit -m test\nEOF\nchmod +x run.sh && ./run.sh'
        $'cat > run.sh <<EOF && chmod +x run.sh && ./run.sh\ngit push origin main\nEOF'
        $'cat > run.sh <<\'EOF\'\ngit "$@"\nEOF\nbash run.sh push origin main'
        $'cat > run.sh <<\'EOF\'\ngit "$1" origin main\nEOF\nbash run.sh push'
        $'cat > run.sh <<EOF\ngit push origin main\nEOF\nbash < run.sh'
        $'cat > run.sh <<EOF\ngit commit -m test\nEOF\nsh 0< run.sh'
        "echo git push origin main > run.sh && bash run.sh"
        "printf 'git commit -m test\n' > run.sh && sh run.sh"
        "printf 'git push origin main\n' | tee run.sh >/dev/null && bash run.sh"
        $'cat <<EOF | tee run.sh >/dev/null\ngit push origin main\nEOF\nbash run.sh'
        $'tee >/dev/null run.sh <<\'EOF\'\ngit commit -m test\nEOF\nsh run.sh'
        $'tee >/tmp/run.sh <<EOF\ngit push origin main\nEOF\nbash /tmp/run.sh'
        $'tee > /tmp/run.sh <<EOF\ngit commit -m test\nEOF\nsh /tmp/run.sh'
        $'cat <<END-OF >/dev/null\nsafe\nEND-OF\ngit push origin main'
        "timeout 30 git push origin main"
        "timeout 30 git commit -m test"
        "flock /tmp/codex-sdlc-test.lock git push origin main"
        "flock -n /tmp/codex-sdlc-test.lock git commit -m test"
        "/usr/bin/env git push origin main"
        "/bin/env git commit -m test"
        "/usr/bin/sudo git push origin main"
        "runuser -u root -- git push origin main"
        "runuser --user root -- git commit -m test"
        "/usr/bin/nohup git push origin main"
        "/usr/bin/time git push origin main"
        "/usr/bin/timeout 30 git commit -m test"
        "/usr/bin/nice git push origin main"
        "/usr/bin/git push origin main"
        "Git.exe push origin main"
        "git.exe push origin main"
        "git.exe commit -m test"
        "/mingw64/bin/git.exe commit -m test"
        '"C:/Program Files/Git/cmd/git.exe" push origin main'
        "find . -exec git push origin main \\;"
        "find . -exec /usr/bin/git commit -m test \\;"
        "find . -exec sh -c 'git push origin main' \\;"
        "xargs git push origin main"
        "xargs -i git push {}"
        "xargs --replace git commit -m test"
        "xargs -e git push origin main"
        "xargs --eof git push origin main"
        "xargs git <<< push"
        "xargs -I{} git {} <<< push"
        "watch git push origin main"
        "watch -x git push origin main"
        "watch --exec git push origin main"
        "watch --no-title git commit -m test"
        "parallel git push ::: origin main"
        "parallel -k git push ::: origin main"
        "parallel --keep-order git push ::: origin main"
        "parallel --results out git push ::: origin main"
        "parallel --tagstring tag git push ::: origin main"
        "parallel -C , git push ::: origin main"
        "parallel --colsep , git commit -m test ::: x"
        "parallel -u git commit -m test ::: x"
        "parallel git ::: push"
        "parallel git {} ::: push"
        "git submodule foreach git push origin main"
        "git submodule foreach git commit -m test"
        "git -C repo submodule foreach git push origin main"
        "git submodule foreach 'git push origin main'"
        "git lfs push origin main"
        "git lfs push origin main # --help"
        "git lfs -c lfs.dialtimeout=1 push origin main"
        "git subtree push --prefix dist origin gh-pages"
        "git subtree push --prefix dist origin gh-pages # --help"
        "git subtree --prefix dist push origin gh-pages"
        'git -c alias.p="!git push origin main" p'
        "git -c alias.p='!git \"\$1\" origin main' p push"
        'git -c alias.c="!git commit -m test" c'
        "git -c alias.p='!\$@' p git push origin main"
        "git -c alias.p='!sh -c \"\$@\"' p git push origin main"
        "git -c alias.p='!eval \"\$@\"' p 'git push origin main'"
        "git -c alias.p='!git \"\${@}\"' p push origin main"
        "git -c alias.p='!trap \"git push origin main\" EXIT' p"
        "ALIAS=push git --config-env=alias.p=ALIAS p origin main"
        "ALIAS=commit git --config-env=alias.c=ALIAS c -m test"
        "git -c alias.p='!f() { git \"\$@\"; }; f' p push origin main"
        "git -c alias.p='!f() { exec git \"\$@\"; }; f' p push origin main"
        'git -c alias.p=push p'
        'git -c alias.c=commit c'
        'git -c alias.p="push origin main" p'
        'git -c alias.p=push -c alias.q=p q origin main'
        'git -c alias.c=commit -c alias.q=c q -m test'
        'git -c alias.p="!git push origin main" p -h'
        'git -c alias.c="!git commit -m test" c -h'
        '/usr/bin/env -S "git push origin main"'
        'sudo /usr/bin/env -S "git push origin main"'
        'sudo bash -c "git push origin main"'
        'sudo eval "git push origin main"'
        'eval "$(echo git push origin main)"'
        $'eval "$(cat <<\'EOF\'\ngit push origin main\nEOF\n)"'
        'bash -c "$(echo git push origin main)"'
        '$(echo -e git\\x20push) origin main'
        '$(echo git; echo push) origin main'
        'eval "$(echo -e git\\x20push origin main)"'
        'bash -c "$(echo -e git\\x20push origin main)"'
        "zsh -c 'nocorrect git push origin main'"
        '$(echo git push origin main)'
        '$(printf "git\x20push") origin main'
        $'$(cat <<EOF\ngit push origin main\nEOF\n)'
        '$(echo git) push origin main'
        '$(printf %s git) commit -m test'
        'g$(printf it) push origin main'
        'g$(echo it) com$(printf mit) -m test'
        'git p$(printf ush) origin main'
        'git pu$(echo sh) origin main'
        'git com$(printf mit) -m test'
        'git "$(printf push)" origin main'
        'git p`printf ush` origin main'
        'g`printf it` push origin main'
        'bash -c "$(echo git) push origin main"'
        'eval "$(echo git) commit -m test"'
        'eval "$(printf '\''%q '\'' git push origin main)"'
        "bash -c \"\$(printf git; printf ' push origin main')\""
        "eval \"\$(echo -n git; echo ' commit -m test')\""
        "bash -c \"\$(printf 'git push origin main' | cat)\""
        "eval \"\$(printf 'git commit -m test' | tee /dev/null)\""
        "printf -- 'git push origin main\n' | bash"
        "printf -- 'push\n' | xargs git"
        "printf 'push\\0' | xargs -0 git"
        "printf 'push,' | xargs -d, git"
        '`echo git commit -m test`'
        'echo "$(case x in x) echo ok;; esac; git push origin main)"'
        'echo "$( (echo ok); git push origin main )"'
        'bash -c "$( (echo echo ok); echo git push origin main )"'
        $'bash -c "$(cat <<EOF\ngit push origin main\nEOF\n)"'
        $'sh -c "$(cat <<EOF\ngit commit -m test\nEOF\n)"'
        "function f { git push origin main; }; f"
        'function f() { git "$@"; }; f push origin main'
        'f() { git "$@"; }; f push origin main'
        'f() { command git "$@"; }; f push origin main'
        'f() { git "$1" origin main; }; f push'
        "coproc git push origin main"
        "setsid git push origin main"
        'bash >out -c "git push origin main"'
        'bash -O extglob -c "git push origin main"'
        "eval \$'git push origin main'"
        "eval \$'git\\x20push origin main'"
        "bash -c \$'git push origin main'"
        "bash -c \$'git\\040commit -m test'"
        "printf 'git push origin main\n' | bash"
        "printf 'git push origin main\n' |& bash"
        "echo git push origin main |& sh"
        "echo -e \"git\\x20push origin main\" | bash"
        "printf \"git\\x20push origin main\n\" | bash"
        "printf 'git push origin main\n' | cat | bash"
        "printf 'git push origin main\n' | tee /dev/null | bash"
        "printf 'git push origin main\n' | env -S \"bash -s\""
        $'cat <<EOF | xargs -I{} sh -c \'{}\'\ngit push origin main\nEOF'
        "printf 'git push origin main\n' | xargs -I{} sh -c '{}'"
        "printf 'git push origin main\n' | xargs -I{} bash -c '{}'"
        "echo git push origin main | xargs -I{} sh -c '{}'"
        $'echo ok\nxargs git <<EOF\npush\nEOF'
        $'echo ok\ncat <<EOF | xargs git\npush\nEOF'
        "parallel ::: 'git push origin main'"
        "parallel --jobs 1 ::: 'git commit -m test'"
        "flock -n -c 'git push origin main' /tmp/lock"
        "flock --command='git commit -m test' /tmp/lock"
        "su -c'git push origin main'"
        "script -c'git commit -m test' /dev/null"
        "echo git push origin main | tee >(bash)"
        "printf 'git push origin main\n' | tee >(bash)"
        "printf 'git push origin main\n' | cat > >(bash)"
        "cat > >(bash) <<< 'git push origin main'"
        "tee >(bash) <<< 'git push origin main'"
        "printf 'git push origin main\n' 2>&1 > >(bash)"
        "printf 'git push origin main\n' >| >(bash)"
        "printf 'git push origin main\n' | bash -c 'bash'"
        "bash -c 'source /dev/stdin' <<< 'git commit -m test'"
        "printf '%s ' git push origin main | bash"
        "printf 'git commit -m test\n' | sh"
        "printf '%s\n' 'git push origin main' | bash"
        "printf '%s %s %s %s\n' git commit -m test | sh"
        "echo git push origin main | bash"
        "echo git push origin main | sh -s -- arg"
        "printf '%s\n' 'git commit -m test' | bash -s arg"
        "bash <<< 'git push origin main'"
        'bash <<<$(echo git push origin main)'
        "env -S \"bash -s\" <<< 'git commit -m test'"
        "sh <<< \$'git commit -m test'"
        "<<< 'git push origin main' cat | bash"
        "bash -s arg <<< 'git push origin main'"
        "sh -s -- arg <<< \$'git commit -m test'"
        "bash /dev/fd/3 3<<< 'git push origin main'"
        "source /dev/fd/7 7<<< 'git commit -m test'"
        "bash <(echo git push origin main)"
        "bash <> <(echo git push origin main)"
        "bash 0<> <(echo git push origin main)"
        "sh <(printf 'git commit -m test\n')"
        "bash <(printf 'git push origin main\n' | cat)"
        "source <(printf 'git commit -m test\n' | tee /dev/null)"
        "bash < <(echo git push origin main)"
        "source <(echo git push origin main)"
        ". <(echo git commit -m test)"
        "/opt/homebrew/bin/bash <(echo git push origin main)"
        "env /usr/local/bin/bash <(echo git push origin main)"
        "sudo -u root bash <(echo git push origin main)"
        "env -u FOO bash <(echo git push origin main)"
        "env -P /usr/bin bash <(echo git push origin main)"
        "time -f %e bash <(echo git push origin main)"
        "cat <(git push origin main)"
        "cat <( git push origin main )"
        "cat >(git commit -m test)"
        "diff <(echo ok) <(git push origin main)"
        "echo \`git push origin main\`"
        "echo \` git push origin main\`"
        $'cat <<EOF | bash\ngit push origin main\nEOF'
        $'cat <<EOF | sh\ngit commit -m test\nEOF'
        $'cat <<EOF | /usr/bin/sudo /bin/bash\ngit push origin main\nEOF'
        $'cat <<EOF | env bash\ngit push origin main\nEOF'
        $'cat <<EOF | env -S "bash"\ngit push origin main\nEOF'
        $'tee /tmp/run.sh >/dev/null <<\'EOF\'\ngit push origin main\nEOF\nbash /tmp/run.sh'
        $'cat <<EOF > >(bash)\ngit push origin main\nEOF'
        "echo git push origin main > >(bash)"
        $'cat <<EOF 1> >(sh)\ngit commit -m test\nEOF'
        $'cat <<EOF\n$(git push origin main)\nEOF'
    )
    local failures=""
    local command
    local output

    for command in "${commands[@]}"; do
        output=$(run_node_json_hook "$(payload_for_command "$command")" "$UNIVERSAL_PRETOOL_SCRIPT")
        if ! echo "$output" | grep -q '"decision":"block"'; then
            failures="${failures} [$command => $output]"
        fi
    done

    if [ -z "$failures" ]; then
        pass "universal pre-tool hook blocks git commit/push after shell prefixes"
    else
        fail "universal pre-tool hook allowed shell-prefix git commands:$failures"
    fi
}

test_universal_pretool_allows_non_git_command_mentions() {
    local issue_command
    local helper_echo_command
    local print_command
    local quoted_heredoc_command
    local git_global_help_command
    local git_help_command
    local git_push_help_command
    local git_alias_push_help_command
    local git_alias_commit_help_command
    local git_help_command_substitution
    local git_push_help_command_substitution
    local git_push_late_help_command
    local git_commit_late_help_command
    local git_lfs_push_help_command
    local git_subtree_push_help_command
    local quoted_python_heredoc_command
    local safe_process_substitution_after_shell_command
    local safe_process_substitution_inside_shell_payload
    local output1
    local output2
    local output3
    local output4
    local output5
    local output6
    local output7
    local output8
    local output9
    local output10
    local output11
    local output12
    local output13
    local output14
    local output15
    local output16
    local output17
    local output18
    local output19

    issue_command=$'gh issue create --title bug --body "$(cat <<EOF\ngit commit -m test should not block here\nEOF\n)"'
    helper_echo_command="find . -exec echo git push origin main \\;"
    print_command="printf %s git push origin main"
    quoted_heredoc_command=$'cat <<\'EOF\'\n$(git push origin main)\nEOF'
    git_global_help_command="git --help push"
    git_help_command="git help push"
    git_push_help_command="git push --help"
    git_alias_push_help_command="git -c alias.p=push p --help"
    git_alias_commit_help_command="git -c alias.c=commit c -h"
    git_help_command_substitution='bash -c "$(git help push)"'
    git_push_help_command_substitution='eval "$(git push --help)"'
    git_push_late_help_command="git push origin --help"
    git_commit_late_help_command="git commit -m test --help"
    git_lfs_push_help_command="git lfs push --help"
    git_lfs_global_help_command="git lfs --help push"
    git_subtree_push_help_command="git subtree push --help"
    quoted_python_heredoc_command=$'python <<\'EOF\'\n$(git push origin main)\nEOF'
    safe_process_substitution_after_shell_command='bash -c "true"; cat <(echo git push origin main)'
    safe_process_substitution_inside_shell_payload='bash -c "cat <(echo git push origin main)"'
    output1=$(run_node_json_hook "$(payload_for_command "$issue_command")" "$UNIVERSAL_PRETOOL_SCRIPT")
    output2=$(run_node_json_hook "$(payload_for_command "$print_command")" "$UNIVERSAL_PRETOOL_SCRIPT")
    output3=$(run_node_json_hook "$(payload_for_command "$helper_echo_command")" "$UNIVERSAL_PRETOOL_SCRIPT")
    output4=$(run_node_json_hook "$(payload_for_command "$quoted_heredoc_command")" "$UNIVERSAL_PRETOOL_SCRIPT")
    output5=$(run_node_json_hook "$(payload_for_command "$git_global_help_command")" "$UNIVERSAL_PRETOOL_SCRIPT")
    output6=$(run_node_json_hook "$(payload_for_command "$git_help_command")" "$UNIVERSAL_PRETOOL_SCRIPT")
    output7=$(run_node_json_hook "$(payload_for_command "$git_push_help_command")" "$UNIVERSAL_PRETOOL_SCRIPT")
    output8=$(run_node_json_hook "$(payload_for_command "$quoted_python_heredoc_command")" "$UNIVERSAL_PRETOOL_SCRIPT")
    output9=$(run_node_json_hook "$(payload_for_command "$git_alias_push_help_command")" "$UNIVERSAL_PRETOOL_SCRIPT")
    output10=$(run_node_json_hook "$(payload_for_command "$git_alias_commit_help_command")" "$UNIVERSAL_PRETOOL_SCRIPT")
    output11=$(run_node_json_hook "$(payload_for_command "$git_help_command_substitution")" "$UNIVERSAL_PRETOOL_SCRIPT")
    output12=$(run_node_json_hook "$(payload_for_command "$git_push_help_command_substitution")" "$UNIVERSAL_PRETOOL_SCRIPT")
    output13=$(run_node_json_hook "$(payload_for_command "$git_push_late_help_command")" "$UNIVERSAL_PRETOOL_SCRIPT")
    output14=$(run_node_json_hook "$(payload_for_command "$git_commit_late_help_command")" "$UNIVERSAL_PRETOOL_SCRIPT")
    output15=$(run_node_json_hook "$(payload_for_command "$git_lfs_push_help_command")" "$UNIVERSAL_PRETOOL_SCRIPT")
    output16=$(run_node_json_hook "$(payload_for_command "$git_subtree_push_help_command")" "$UNIVERSAL_PRETOOL_SCRIPT")
    output17=$(run_node_json_hook "$(payload_for_command "$git_lfs_global_help_command")" "$UNIVERSAL_PRETOOL_SCRIPT")
    output18=$(run_node_json_hook "$(payload_for_command "$safe_process_substitution_after_shell_command")" "$UNIVERSAL_PRETOOL_SCRIPT")
    output19=$(run_node_json_hook "$(payload_for_command "$safe_process_substitution_inside_shell_payload")" "$UNIVERSAL_PRETOOL_SCRIPT")

    if [ -z "$output1$output2$output3$output4$output5$output6$output7$output8$output9$output10$output11$output12$output13$output14$output15$output16$output17$output18$output19" ]; then
        pass "universal pre-tool hook allows non-git commands that mention git commit/push"
    else
        fail "universal pre-tool hook blocked non-git command text (output1: $output1 output2: $output2 output3: $output3 output4: $output4 output5: $output5 output6: $output6 output7: $output7 output8: $output8 output9: $output9 output10: $output10 output11: $output11 output12: $output12 output13: $output13 output14: $output14 output15: $output15 output16: $output16 output17: $output17 output18: $output18 output19: $output19)"
    fi
}

test_universal_pretool_does_not_crash_on_non_git_prototype_words() {
    if run_node_hook_status "$(payload_for_command "toString -x git push origin main")" "$UNIVERSAL_PRETOOL_SCRIPT" \
        && run_node_hook_status "$(payload_for_command "echo \$'\\UFFFFFFFF'")" "$UNIVERSAL_PRETOOL_SCRIPT"; then
        pass "universal pre-tool hook does not crash on non-git prototype words"
    else
        fail "universal pre-tool hook crashed on non-git prototype words"
    fi
}

test_universal_pretool_blocks_deep_wrapper_recursion() {
    local command
    local output
    command=$(deep_nested_eval_command)
    output=$(run_node_json_hook "$(payload_for_command "$command")" "$UNIVERSAL_PRETOOL_SCRIPT")

    if echo "$output" | grep -q '"decision":"block"'; then
        pass "universal pre-tool hook blocks deep wrapper recursion"
    else
        fail "universal pre-tool hook allowed deep wrapper recursion (output: $output)"
    fi
}

test_universal_session_warns_missing() {
    local tmpdir
    tmpdir=$(mktemp -d)
    local output
    output=$(run_node_session_hook "$tmpdir" "$UNIVERSAL_SESSION_SCRIPT")
    rm -rf "$tmpdir"
    if echo "$output" | grep -q '"additionalContext"'; then
        pass "universal session hook warns when AGENTS.md is missing"
    else
        fail "universal session hook did not warn when AGENTS.md was missing"
    fi
}

test_universal_compact_guard_emits_lifecycle_context() {
    local tmpdir output

    tmpdir=$(mktemp -d)
    (
        cd "$tmpdir" || exit 1
        git init -q
        printf '%s\n' "work in progress" > app.txt
    )

    output=$(run_node_json_hook "$(payload_for_compact PreCompact auto "$tmpdir")" "$UNIVERSAL_COMPACT_SCRIPT")
    rm -rf "$tmpdir"

    if echo "$output" | grep -q '"continue":true' \
        && echo "$output" | grep -q 'systemMessage' \
        && echo "$output" | grep -q 'SDLC compact guard' \
        && echo "$output" | grep -q 'dirty worktree'; then
        pass "universal compact guard emits SDLC lifecycle context before compaction"
    else
        fail "universal compact guard did not emit expected PreCompact context (output: $output)"
    fi
}

test_universal_compact_guard_handles_post_compact() {
    local tmpdir output

    tmpdir=$(mktemp -d)
    output=$(run_node_json_hook "$(payload_for_compact PostCompact manual "$tmpdir")" "$UNIVERSAL_COMPACT_SCRIPT")
    rm -rf "$tmpdir"

    if echo "$output" | grep -q '"continue":true' \
        && echo "$output" | grep -q 'PostCompact' \
        && echo "$output" | grep -q 'reread'; then
        pass "universal compact guard emits post-compact recovery context"
    else
        fail "universal compact guard did not emit expected PostCompact context (output: $output)"
    fi
}

test_universal_node_hooks_work_in_type_module_repos() {
    local tmpdir
    local session_command
    local pretool_command
    local session_output
    local pretool_output
    local all_passed=true

    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.codex/hooks"
    cp "$ACTIVE_HOOKS_FILE" "$tmpdir/.codex/hooks.json"
    cp "$HOOKS_DIR"/git-guard.* "$tmpdir/.codex/hooks/" 2>/dev/null || true
    cp "$HOOKS_DIR"/session-start.* "$tmpdir/.codex/hooks/" 2>/dev/null || true
    cp "$HOOKS_DIR"/compact-guard.* "$tmpdir/.codex/hooks/" 2>/dev/null || true
    printf '%s\n' '{"type":"module"}' > "$tmpdir/package.json"

    session_command=$(node -e 'const config = require(process.argv[1]); process.stdout.write(config.hooks.SessionStart[0].hooks[0].command);' "$tmpdir/.codex/hooks.json")
    pretool_command=$(node -e 'const config = require(process.argv[1]); process.stdout.write(config.hooks.PreToolUse[0].hooks[0].command);' "$tmpdir/.codex/hooks.json")
    compact_command=$(node -e 'const config = require(process.argv[1]); process.stdout.write(config.hooks.PreCompact[0].hooks[0].command);' "$tmpdir/.codex/hooks.json")

    echo "$session_command" | grep -q '\.cjs' || all_passed=false
    echo "$pretool_command" | grep -q '\.cjs' || all_passed=false
    echo "$compact_command" | grep -q '\.cjs' || all_passed=false

    session_output=$(cd "$tmpdir" && sh -c "$session_command" 2>&1) || all_passed=false
    pretool_output=$(cd "$tmpdir" && printf '%s' '{"tool_input":{"command":"git commit -m test"}}' | sh -c "$pretool_command" 2>&1) || all_passed=false
    compact_output=$(cd "$tmpdir" && printf '%s' "$(payload_for_compact PreCompact auto "$tmpdir")" | sh -c "$compact_command" 2>&1) || all_passed=false

    echo "$session_output" | grep -q '"additionalContext"' || all_passed=false
    echo "$pretool_output" | grep -q '"decision":"block"' || all_passed=false
    echo "$compact_output" | grep -q '"continue":true' || all_passed=false
    echo "$session_output$pretool_output$compact_output" | grep -q 'require is not defined' && all_passed=false

    rm -rf "$tmpdir"

    if [ "$all_passed" = "true" ]; then
        pass "universal Node hooks work in type=module repos"
    else
        fail "universal Node hooks fail in type=module repos"
    fi
}

test_hooks_json_matcher() {
    local matcher
    matcher=$(grep -o '"matcher":[[:space:]]*"[^"]*"' "$HOOKS_FILE" | head -1 | sed 's/.*"matcher":[[:space:]]*"\([^"]*\)"/\1/')
    if [ "$matcher" = "^Bash\$" ]; then
        pass "hook matcher is ^Bash$"
    else
        fail "hook matcher is '$matcher'"
    fi
}

test_hooks_json_valid() {
    if grep -q '"PreToolUse"' "$HOOKS_FILE" \
        && grep -q '"SessionStart"' "$HOOKS_FILE" \
        && grep -q '"PreCompact"' "$HOOKS_FILE" \
        && grep -q '"PostCompact"' "$HOOKS_FILE" \
        && grep -q 'node \.codex/hooks/compact-guard\.cjs' "$HOOKS_FILE" \
        && ! grep -q '"PermissionRequest"' "$HOOKS_FILE" \
        && ! grep -q '"PostToolUse"' "$HOOKS_FILE" \
        && ! grep -q '"UserPromptSubmit"' "$HOOKS_FILE"; then
        pass "hook config uses the current compact lifecycle hooks without over-wiring noisy events"
    else
        fail "hook config does not match the current compact-aware quiet hook set"
    fi
}

test_live_hooks_file_uses_universal_node_hooks() {
    if grep -q 'node \.codex/hooks/git-guard\.cjs' "$ACTIVE_HOOKS_FILE" \
        && grep -q 'node \.codex/hooks/session-start\.cjs' "$ACTIVE_HOOKS_FILE" \
        && grep -q 'node \.codex/hooks/compact-guard\.cjs' "$ACTIVE_HOOKS_FILE" \
        && ! grep -q 'powershell\.exe' "$ACTIVE_HOOKS_FILE" \
        && ! grep -q 'bash-guard\.sh' "$ACTIVE_HOOKS_FILE" \
        && ! grep -q 'session-start\.sh' "$ACTIVE_HOOKS_FILE"; then
        pass "live hooks.json uses universal Node hook entrypoints"
    else
        fail "live hooks.json still uses platform-specific hook commands"
    fi
}

test_live_hooks_file_is_windows_safe() {
    if [ "$IS_WINDOWS" != "true" ]; then
        return
    fi

    if grep -q 'node \.codex/hooks/git-guard\.cjs' "$ACTIVE_HOOKS_FILE" \
        && grep -q 'node \.codex/hooks/session-start\.cjs' "$ACTIVE_HOOKS_FILE" \
        && grep -q 'node \.codex/hooks/compact-guard\.cjs' "$ACTIVE_HOOKS_FILE" \
        && ! grep -q 'powershell\.exe' "$ACTIVE_HOOKS_FILE" \
        && ! grep -q '\.sh' "$ACTIVE_HOOKS_FILE"; then
        pass "live hooks.json uses universal Node hooks on Windows"
    else
        fail "live hooks.json still points at platform-specific hooks on Windows"
    fi
}

test_config_enables_hooks() {
    if grep -q '^hooks = true' "$REPO_DIR/.codex/config.toml" 2>/dev/null \
        && ! grep -v '^[[:space:]]*#' "$REPO_DIR/.codex/config.toml" | grep -q '^codex_hooks\s*='; then
        pass "config.toml enables codex hooks with the current feature flag"
    else
        fail "config.toml missing hooks = true or still has active codex_hooks"
    fi
}

test_install_preserves_agents_md() {
    local tmpdir
    tmpdir=$(mktemp -d)
    echo "CUSTOM AGENTS CONTENT" > "$tmpdir/AGENTS.md"
    (cd "$tmpdir" && CODEX_HOME="$tmpdir/.codex-home" bash "$REPO_DIR/install.sh" >/dev/null 2>&1)
    local content
    content=$(cat "$tmpdir/AGENTS.md")
    rm -rf "$tmpdir"
    if [ "$content" = "CUSTOM AGENTS CONTENT" ]; then
        pass "install.sh preserves existing AGENTS.md"
    else
        fail "install.sh overwrote existing AGENTS.md"
    fi
}

test_install_creates_sdlc_docs() {
    local tmpdir
    tmpdir=$(mktemp -d)
    (cd "$tmpdir" && CODEX_HOME="$tmpdir/.codex-home" bash "$REPO_DIR/install.sh" >/dev/null 2>&1)

    local all_present=true
    for f in "SDLC-LOOP.md" "START-SDLC.md" "PROVE-IT.md" "$EXPECTED_HELPER"; do
        if [ ! -f "$tmpdir/$f" ]; then
            all_present=false
            break
        fi
    done

    rm -rf "$tmpdir"

    if [ "$all_present" = "true" ]; then
        pass "install.sh creates the explicit SDLC docs and helper"
    else
        fail "install.sh did not create the expected SDLC docs/helper"
    fi
}

test_install_creates_skill() {
    local tmpdir
    tmpdir=$(mktemp -d)
    (cd "$tmpdir" && CODEX_HOME="$tmpdir/.codex-home" bash "$REPO_DIR/install.sh" >/dev/null 2>&1)
    local all_present=true
    for skill in "setup-wizard" "update-wizard" "feedback"; do
        if [ ! -f "$tmpdir/.codex-home/skills/$skill/SKILL.md" ]; then
            all_present=false
            break
        fi
    done
    if [ -d "$tmpdir/.codex-home/skills/sdlc" ]; then
        all_present=false
    fi
    if [ ! -f "$tmpdir/.agents/skills/sdlc/SKILL.md" ]; then
        all_present=false
    fi
    if [ -e "$tmpdir/.agents/skills/adlc/SKILL.md" ]; then
        all_present=false
    fi
    if [ -d "$tmpdir/.codex-home/skills/codex-sdlc" ]; then
        all_present=false
    fi
    if [ "$all_present" = "true" ]; then
        pass "install.sh creates global helper skills and one repo-scoped sdlc entrypoint"
    else
        fail "install.sh created duplicate global/repo sdlc skills or missed helper skills"
    fi
    rm -rf "$tmpdir"
}

test_install_keeps_skill_backups_out_of_skills_and_prunes_legacy_sdlc() {
    local tmpdir
    tmpdir=$(mktemp -d)

    mkdir -p "$tmpdir/.codex-home/skills/sdlc" "$tmpdir/.codex-home/skills/codex-sdlc"
    echo "USER OWNED" > "$tmpdir/.codex-home/skills/sdlc/marker.txt"
    echo "LEGACY" > "$tmpdir/.codex-home/skills/codex-sdlc/marker.txt"

    (cd "$tmpdir" && CODEX_HOME="$tmpdir/.codex-home" bash "$REPO_DIR/install.sh" >/dev/null 2>&1)

    local backup_count
    local leaked_backup_count
    local legacy_backup_count
    backup_count=$(find "$tmpdir/.codex-home/backups/skills" -maxdepth 1 -name 'sdlc.bak.*' 2>/dev/null | wc -l | tr -d ' ')
    legacy_backup_count=$(find "$tmpdir/.codex-home/backups/skills" -maxdepth 1 -name 'codex-sdlc.bak.*' 2>/dev/null | wc -l | tr -d ' ')
    leaked_backup_count=$(find "$tmpdir/.codex-home/skills" -maxdepth 1 \( -name 'sdlc.bak.*' -o -name 'codex-sdlc.bak.*' \) | wc -l | tr -d ' ')
    local legacy_present=false
    local user_skill_preserved=false
    [ -d "$tmpdir/.codex-home/skills/codex-sdlc" ] && legacy_present=true
    grep -q 'USER OWNED' "$tmpdir/.codex-home/skills/sdlc/marker.txt" 2>/dev/null && user_skill_preserved=true

    rm -rf "$tmpdir"

    if [ "$backup_count" = "0" ] &&
       [ "$legacy_backup_count" -ge 1 ] &&
       [ "$leaked_backup_count" = "0" ] &&
       [ "$legacy_present" = "false" ] &&
       [ "$user_skill_preserved" = "true" ]; then
        pass "install.sh preserves user-owned global sdlc and prunes legacy codex-sdlc"
    else
        fail "install.sh overwrote user-owned sdlc, leaked backups, or left legacy codex-sdlc installed"
    fi
}

test_install_merges_config() {
    local all_passed=true

    local tmpdir1
    tmpdir1=$(mktemp -d)
    mkdir -p "$tmpdir1/.codex"
    printf '[features]\ncodex_hooks = false\n' > "$tmpdir1/.codex/config.toml"
    (cd "$tmpdir1" && CODEX_HOME="$tmpdir1/.codex-home" bash "$REPO_DIR/install.sh" >/dev/null 2>&1)
    if ! grep -q '^hooks = true' "$tmpdir1/.codex/config.toml" \
        || grep -v '^[[:space:]]*#' "$tmpdir1/.codex/config.toml" | grep -q '^codex_hooks\s*='; then
        fail "install.sh case 1: did not migrate deprecated codex_hooks=false to hooks=true"
        all_passed=false
    fi
    rm -rf "$tmpdir1"

    local tmpdir2
    tmpdir2=$(mktemp -d)
    mkdir -p "$tmpdir2/.codex"
    printf '[features]\ncodex_hooks = true\n' > "$tmpdir2/.codex/config.toml"
    (cd "$tmpdir2" && CODEX_HOME="$tmpdir2/.codex-home" bash "$REPO_DIR/install.sh" >/dev/null 2>&1)
    if ! grep -q '^hooks = true' "$tmpdir2/.codex/config.toml" \
        || grep -v '^[[:space:]]*#' "$tmpdir2/.codex/config.toml" | grep -q '^codex_hooks\s*='; then
        fail "install.sh case 2: did not migrate deprecated codex_hooks=true to hooks=true"
        all_passed=false
    fi
    rm -rf "$tmpdir2"

    local tmpdir3
    tmpdir3=$(mktemp -d)
    mkdir -p "$tmpdir3/.codex"
    printf '[features]\nsome_other = true\n' > "$tmpdir3/.codex/config.toml"
    (cd "$tmpdir3" && CODEX_HOME="$tmpdir3/.codex-home" bash "$REPO_DIR/install.sh" >/dev/null 2>&1)
    if ! grep -q '^hooks = true' "$tmpdir3/.codex/config.toml"; then
        fail "install.sh case 3: did not add hooks under existing [features]"
        all_passed=false
    elif ! grep -x 'hooks = true' "$tmpdir3/.codex/config.toml" >/dev/null 2>&1; then
        fail "install.sh case 3: hooks not on its own line"
        all_passed=false
    fi
    rm -rf "$tmpdir3"

    local tmpdir4
    tmpdir4=$(mktemp -d)
    mkdir -p "$tmpdir4/.codex"
    printf '[model]\nname = "o3"\n' > "$tmpdir4/.codex/config.toml"
    (cd "$tmpdir4" && CODEX_HOME="$tmpdir4/.codex-home" bash "$REPO_DIR/install.sh" >/dev/null 2>&1)
    if ! grep -q '^hooks = true' "$tmpdir4/.codex/config.toml"; then
        fail "install.sh case 4: did not add [features] section"
        all_passed=false
    fi
    rm -rf "$tmpdir4"

    local tmpdir5
    tmpdir5=$(mktemp -d)
    mkdir -p "$tmpdir5/.codex"
    printf '[features]\n# codex_hooks = false\n' > "$tmpdir5/.codex/config.toml"
    (cd "$tmpdir5" && CODEX_HOME="$tmpdir5/.codex-home" bash "$REPO_DIR/install.sh" >/dev/null 2>&1)
    if ! grep -v '^[[:space:]]*#' "$tmpdir5/.codex/config.toml" | grep -q '^hooks = true'; then
        fail "install.sh case 5: commented codex_hooks prevented hooks=true insertion"
        all_passed=false
    fi
    rm -rf "$tmpdir5"

    local tmpdir6
    tmpdir6=$(mktemp -d)
    mkdir -p "$tmpdir6/.codex"
    printf '[features]\n# codex_hooks = true\n' > "$tmpdir6/.codex/config.toml"
    (cd "$tmpdir6" && CODEX_HOME="$tmpdir6/.codex-home" bash "$REPO_DIR/install.sh" >/dev/null 2>&1)
    if ! grep -v '^[[:space:]]*#' "$tmpdir6/.codex/config.toml" | grep -q '^hooks = true'; then
        fail "install.sh case 6: commented codex_hooks treated as real"
        all_passed=false
    fi
    rm -rf "$tmpdir6"

    if [ "$all_passed" = "true" ]; then
        pass "install.sh migrates deprecated codex_hooks and writes hooks=true"
    fi
}

test_install_backs_up_hooks_json() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.codex"
    echo '{"old": true}' > "$tmpdir/.codex/hooks.json"
    (cd "$tmpdir" && CODEX_HOME="$tmpdir/.codex-home" bash "$REPO_DIR/install.sh" >/dev/null 2>&1)
    local backup_count
    backup_count=$(find "$tmpdir/.codex" -maxdepth 1 -name 'hooks.json.bak.*' | wc -l | tr -d ' ')
    rm -rf "$tmpdir"
    if [ "$backup_count" -ge 1 ]; then
        pass "install.sh backs up existing hooks.json"
    else
        fail "install.sh did not create a hooks.json backup"
    fi
}

test_agents_md_size() {
    local size
    size=$(wc -c < "$REPO_DIR/AGENTS.md" 2>/dev/null | tr -d ' ')
    if [ -n "$size" ] && [ "$size" -lt 32768 ]; then
        pass "AGENTS.md is under the Codex limit"
    else
        fail "AGENTS.md is too large or missing"
    fi
}

test_setup_skill_has_confidence_setup_contract() {
    local skill="$REPO_DIR/skills/setup-wizard/SKILL.md"

    if grep -q 'resolved (detected)' "$skill" \
        && grep -q 'resolved (inferred)' "$skill" \
        && grep -q 'unresolved' "$skill" \
        && grep -q 'Do not ask a fixed checklist' "$skill"; then
        pass "setup-wizard carries the confidence-driven setup contract"
    else
        fail "setup-wizard is missing the upstream confidence-driven setup contract"
    fi
}

test_update_skill_has_idempotent_update_contract() {
    local skill="$REPO_DIR/skills/update-wizard/SKILL.md"

    if grep -q 'match' "$skill" \
        && grep -q 'missing' "$skill" \
        && grep -q 'customized' "$skill" \
        && grep -q 'drift / broken' "$skill" \
        && grep -q 'Never overwrite customizations blindly' "$skill"; then
        pass "update-wizard carries the idempotent selective-update contract"
    else
        fail "update-wizard is missing the idempotent selective-update contract"
    fi
}

test_skills_document_hooks_feature_rename() {
    local setup_skill="$REPO_DIR/skills/setup-wizard/SKILL.md"
    local update_skill="$REPO_DIR/skills/update-wizard/SKILL.md"
    local all_passed=true

    grep -Fq '[features].hooks' "$setup_skill" || all_passed=false
    grep -Fq '/hooks' "$setup_skill" || all_passed=false
    grep -Fq '[features].hooks' "$update_skill" || all_passed=false
    grep -Fq 'codex_hooks' "$update_skill" || all_passed=false
    grep -Eqi 'deprecated.*codex_hooks|codex_hooks.*deprecated' "$update_skill" || all_passed=false
    grep -Eqi 'replacement.*hooks|hooks.*replacement' "$update_skill" || all_passed=false

    if [ "$all_passed" = "true" ]; then
        pass "setup/update skills document the hooks feature flag rename and /hooks review"
    else
        fail "setup/update skills should document [features].hooks, codex_hooks migration, and /hooks review"
    fi
}

test_update_skill_frontloads_package_upgrade_boundary() {
    local skill="$REPO_DIR/skills/update-wizard/SKILL.md"
    local readme="$REPO_DIR/README.md"

    if grep -Fq 'Package upgrade preflight' "$skill" \
        && grep -Fq 'Before scanning repo drift' "$skill" \
        && grep -Fq 'Package upgrade means consuming the newest published' "$skill" \
        && grep -Fq 'Repo repair/sync means inspecting and repairing local SDLC artifacts' "$skill" \
        && grep -Fq 'does not self-update the active Codex session' "$skill" \
        && grep -Fq 'npm view codex-sdlc-wizard version' "$skill" \
        && grep -Fq 'npx codex-sdlc-wizard@latest update' "$skill" \
        && grep -Fq 'restart/reopen Codex' "$skill" \
        && grep -Fq 'Package upgrade vs repo repair' "$readme" \
        && grep -Fq 'Repo repair/sync inside Codex' "$readme"; then
        pass "update-wizard frontloads package upgrade vs repo repair guidance"
    else
        fail "update-wizard does not frontload package upgrade vs repo repair guidance"
    fi
}

test_helper_skill_metadata_uses_codex_sdlc_not_xdlc() {
    local setup_skill="$REPO_DIR/skills/setup-wizard/SKILL.md"
    local update_skill="$REPO_DIR/skills/update-wizard/SKILL.md"
    local setup_openai="$REPO_DIR/skills/setup-wizard/agents/openai.yaml"
    local update_openai="$REPO_DIR/skills/update-wizard/agents/openai.yaml"
    local all_passed=true

    if grep -REiq 'Codex[[:space:]]+XDLC|XDLC[[:space:]]+adapter|host adapter core|core metadata' \
        "$setup_skill" "$update_skill" "$setup_openai" "$update_openai" "$REPO_DIR/SKILL.md" "$REPO_DIR/agents/openai.yaml" 2>/dev/null; then
        all_passed=false
    fi

    grep -Fq 'Codex SDLC' "$setup_skill" || all_passed=false
    grep -Fq 'Codex SDLC' "$update_skill" || all_passed=false
    grep -Fq 'Codex SDLC' "$setup_openai" || all_passed=false
    grep -Fq 'Codex SDLC' "$update_openai" || all_passed=false

    if grep -Eq 'invoke `?\$setup-wizard|invoke `?\$update-wizard|use /skills and invoke' "$REPO_DIR/install.ps1"; then
        all_passed=false
    fi

    if [ "$all_passed" = "true" ]; then
        pass "helper skill metadata says Codex SDLC and avoids XDLC/palette leakage"
    else
        fail "helper skill metadata should say Codex SDLC and avoid XDLC/palette leakage"
    fi
}

test_setup_and_update_skills_stop_before_product_remediation() {
    local setup_skill="$REPO_DIR/skills/setup-wizard/SKILL.md"
    local update_skill="$REPO_DIR/skills/update-wizard/SKILL.md"
    local all_passed=true

    for skill in "$setup_skill" "$update_skill"; do
        if ! grep -q 'do not edit application code' "$skill"; then
            fail "$(basename "$(dirname "$skill")") does not forbid application code edits during setup/update"
            all_passed=false
        fi

        if ! grep -q 'application tests' "$skill"; then
            fail "$(basename "$(dirname "$skill")") does not protect application tests during setup/update"
            all_passed=false
        fi

        if ! grep -q 'verification is diagnostic' "$skill"; then
            fail "$(basename "$(dirname "$skill")") does not make verification diagnostic by default"
            all_passed=false
        fi

        if ! grep -q '\$sdlc' "$skill"; then
            fail "$(basename "$(dirname "$skill")") does not hand product regressions to sdlc"
            all_passed=false
        fi

        if ! grep -q 'exit and reopen Codex' "$skill"; then
            fail "$(basename "$(dirname "$skill")") does not explicitly recommend restarting Codex after hook/skill changes"
            all_passed=false
        fi

        if ! grep -q 'do not need to rerun' "$skill"; then
            fail "$(basename "$(dirname "$skill")") does not say restart does not require rerunning setup/update"
            all_passed=false
        fi

        if ! grep -q 'codex resume -m' "$skill"; then
            fail "$(basename "$(dirname "$skill")") does not recommend model-explicit codex resume for interrupted sessions"
            all_passed=false
        fi

        if ! grep -q -- '--dangerously-bypass-approvals-and-sandbox' "$skill"; then
            fail "$(basename "$(dirname "$skill")") does not document the full-trust resume variant"
            all_passed=false
        fi
    done

    if [ "$all_passed" = "true" ]; then
        pass "setup/update skills stop before unrelated product remediation and recommend restart/resume"
    fi
}

test_feedback_skill_has_privacy_prompt_and_dedupe() {
    local skill="$REPO_DIR/skills/feedback/SKILL.md"

    if grep -q 'May I scan\?' "$skill" \
        && grep -q 'Check for duplicates' "$skill" \
        && grep -q 'No source code' "$skill"; then
        pass "feedback carries the privacy-first scan and dedupe contract"
    else
        fail "feedback is missing the privacy-first scan and dedupe contract"
    fi
}

test_setup_docs_include_codex_desktop_handoff() {
    local skill="$REPO_DIR/skills/setup-wizard/SKILL.md"
    local loop="$REPO_DIR/SDLC-LOOP.md"

    if grep -q 'Codex Desktop handoff' "$loop" \
        && grep -q 'macOS and Windows' "$loop" \
        && grep -q 'codex app .' "$loop" \
        && grep -q 'credentials, MFA, tenant consent' "$loop" \
        && grep -q 'Codex Desktop handoff' "$skill" \
        && grep -q 'computer-use' "$skill"; then
        pass "setup docs include Codex Desktop handoff guidance"
    else
        fail "setup docs are missing Codex Desktop handoff guidance"
    fi
}

test_setup_docs_include_m365_auth_lane_guidance() {
    local skill="$REPO_DIR/skills/setup-wizard/SKILL.md"
    local loop="$REPO_DIR/SDLC-LOOP.md"

    if grep -q 'Microsoft 365 auth lane' "$loop" \
        && grep -q 'Graph PowerShell' "$loop" \
        && grep -q 'Get-MgContext' "$loop" \
        && grep -q 'tenant id plus expected work account' "$loop" \
        && grep -q 'personal Microsoft account' "$loop" \
        && grep -q 'read-only' "$loop" \
        && grep -q '.reviews/' "$loop" \
        && grep -q 'Microsoft 365 auth lane' "$skill" \
        && grep -q 'Graph PowerShell' "$skill" \
        && grep -q 'tenant-bound' "$skill"; then
        pass "setup docs include Microsoft 365 auth-lane guidance"
    else
        fail "setup docs are missing Microsoft 365 auth-lane guidance"
    fi
}

test_setup_docs_include_task_routing_gate() {
    local skill="$REPO_DIR/skills/setup-wizard/SKILL.md"
    local loop="$REPO_DIR/SDLC-LOOP.md"
    local sdlc_skill="$REPO_DIR/skills/sdlc/SKILL.md"

    if grep -q 'Task routing gate' "$loop" \
        && grep -q 'Identify the execution lane before giving instructions' "$loop" \
        && grep -q 'Microsoft browser sign-in' "$loop" \
        && grep -q 'developer program qualification' "$loop" \
        && grep -q 'Desktop/computer-use' "$loop" \
        && grep -q 'credentials, MFA, tenant consent' "$loop" \
        && grep -q 'Task routing gate' "$skill" \
        && grep -q 'before giving CLI or browser instructions' "$skill" \
        && grep -q 'Microsoft browser sign-in' "$skill" \
        && grep -q 'Task routing gate' "$sdlc_skill" \
        && grep -q 'before giving execution steps' "$sdlc_skill"; then
        pass "setup docs include task-routing gate for Desktop/computer-use boundaries"
    else
        fail "setup docs are missing the task-routing gate for Desktop/computer-use boundaries"
    fi
}

test_sdlc_skill_has_docsync_learning_and_merge_guard() {
    local skill="$REPO_DIR/skills/sdlc/SKILL.md"

    if grep -q 'docs update' "$skill" \
        && grep -q 'capture learnings' "$skill" \
        && grep -q 'NEVER AUTO-MERGE' "$skill"; then
        pass "sdlc carries doc-sync, learning capture, and merge-guard rules"
    else
        fail "sdlc is missing upstream SDLC enforcement rules"
    fi
}

test_repo_defaults_to_xhigh_reasoning() {
    local all_passed=true

    if ! grep -Eiq 'gpt-5\.5.*xhigh|xhigh.*gpt-5\.5' "$REPO_DIR/AGENTS.md"; then
        fail "AGENTS.md does not set gpt-5.5 xhigh as the default reasoning policy"
        all_passed=false
    fi

    if ! grep -q 'Default to `xhigh`' "$REPO_DIR/README.md"; then
        fail "README.md does not set xhigh as the default reasoning policy"
        all_passed=false
    fi

    if ! grep -q 'default: `xhigh`' "$REPO_DIR/skills/sdlc/SKILL.md"; then
        fail "sdlc skill does not set xhigh as the default reasoning policy"
        all_passed=false
    fi

    if ! grep -q 'Default to `xhigh`' "$REPO_DIR/SDLC-LOOP.md"; then
        fail "SDLC-LOOP.md does not set xhigh as the default reasoning policy"
        all_passed=false
    fi

    if ! grep -q 'Use xhigh reasoning by default' "$REPO_DIR/START-SDLC.md"; then
        fail "START-SDLC.md does not set xhigh as the default reasoning policy"
        all_passed=false
    fi

    if grep -Eq 'gpt-5\.4(["` ,]|$)' \
        "$REPO_DIR/.codex/config.toml" \
        "$REPO_DIR/lib/codex-config.sh" \
        "$REPO_DIR/install.sh" \
        "$REPO_DIR/install.ps1" \
        "$REPO_DIR/README.md"; then
        fail "repo model/config surface still contains non-mini gpt-5.4"
        all_passed=false
    fi

    if ! grep -q 'codex resume -m gpt-5.5' "$REPO_DIR/install.ps1" ||
       ! grep -q 'model_reasoning_effort=`"xhigh`"' "$REPO_DIR/install.ps1"; then
        fail "PowerShell installer does not print model-explicit gpt-5.5 xhigh resume guidance"
        all_passed=false
    fi

    if ! grep -q -- '--dangerously-bypass-approvals-and-sandbox' "$REPO_DIR/install.ps1" ||
       grep -q -- '--full-auto' "$REPO_DIR/install.ps1"; then
        fail "PowerShell installer does not print current canonical full-trust guidance"
        all_passed=false
    fi

    if ! grep -Fq '.codex\hooks\git-guard.cjs' "$REPO_DIR/install.ps1" ||
       ! grep -Fq '.codex\hooks\session-start.cjs' "$REPO_DIR/install.ps1" ||
       ! grep -Fq '.codex\hooks\compact-guard.cjs' "$REPO_DIR/install.ps1" ||
       grep -Eq 'Copy-Item.*(git-guard|session-start)\.js' "$REPO_DIR/install.ps1"; then
        fail "PowerShell installer does not install the universal .cjs hook runtime"
        all_passed=false
    fi

    if [ "$all_passed" = "true" ]; then
        pass "repo contract defaults to xhigh reasoning"
    fi
}

test_package_has_npm_release_surface() {
    local package_json="$REPO_DIR/package.json"
    local bin_script="$REPO_DIR/bin/codex-sdlc-wizard.js"
    local all_passed=true

    if [ ! -f "$package_json" ]; then
        fail "package.json is missing"
        return
    fi

    if [ ! -f "$bin_script" ]; then
        fail "bin/codex-sdlc-wizard.js is missing"
        return
    fi

    if ! grep -q '"name"[[:space:]]*:[[:space:]]*"codex-sdlc-wizard"' "$package_json"; then
        fail "package.json is missing the codex-sdlc-wizard package name"
        all_passed=false
    fi

    if ! grep -q '"codex-sdlc-wizard"[[:space:]]*:[[:space:]]*"bin/codex-sdlc-wizard.js"' "$package_json"; then
        fail "package.json is missing the codex-sdlc-wizard bin entry"
        all_passed=false
    fi

    for path in \
        ".agents/" \
        "agents/" \
        "bin/" \
        "skills/" \
        ".codex/config.toml" \
        ".codex/hooks.json" \
        ".codex/unix-hooks.json" \
        ".codex/windows-hooks.json" \
        ".codex/hooks/" \
        "templates/" \
        "lib/" \
        "install.sh" \
        "install.ps1" \
        "setup.sh" \
        "check.sh" \
        "update.sh" \
        "SKILL.md" \
        "AGENTS.md" \
        "README.md" \
        "ROADMAP.md" \
        "SDLC-LOOP.md" \
        "START-SDLC.md" \
        "PROVE-IT.md" \
        "UPSTREAM_VERSION" \
        "start-sdlc.sh" \
        "start-sdlc.ps1"; do
        if ! grep -Fq "\"$path\"" "$package_json"; then
            fail "package.json files is missing $path"
            all_passed=false
        fi
    done

    if grep -Fq '".codex/"' "$package_json"; then
        fail "package.json uses a broad .codex/ allowlist that can leak backup files"
        all_passed=false
    fi

    if [ "$all_passed" = "true" ]; then
        pass "package.json ships the npm release surface for the current Codex wizard"
    fi
}

test_package_cli_is_honest_about_supported_flags() {
    local output
    local exit_code

    output=$(node "$REPO_DIR/bin/codex-sdlc-wizard.js" --help 2>&1)
    exit_code=$?

    if [ "$exit_code" -ne 0 ]; then
        fail "npm CLI help failed"
        return
    fi

    if echo "$output" | grep -q -- '--model-profile' &&
       echo "$output" | grep -q 'mixed' &&
       echo "$output" | grep -q 'maximum' &&
       echo "$output" | grep -Fq 'Type "full-trust"'; then
        pass "npm CLI help advertises the supported model-profile flag"
    else
        fail "npm CLI help is missing the supported model-profile flag"
    fi
}

test_package_uses_single_canonical_sdlc_skill_name() {
    local all_passed=true
    local bad_slash_sdlc

    [ -f "$REPO_DIR/skills/sdlc/SKILL.md" ] || all_passed=false
    [ ! -e "$REPO_DIR/skills/codex-sdlc" ] || all_passed=false
    grep -q '^name: sdlc$' "$REPO_DIR/skills/sdlc/SKILL.md" || all_passed=false
    grep -q '^  display_name: sdlc$' "$REPO_DIR/skills/sdlc/agents/openai.yaml" || all_passed=false
    grep -Fq 'Canonical entrypoint: `$sdlc`' "$REPO_DIR/README.md" || all_passed=false
    grep -Fq 'Codex treats same-name skills from different scopes as distinct choices' "$REPO_DIR/README.md" || all_passed=false
    grep -Fq 'normal setup installs global helper skills only' "$REPO_DIR/README.md" || all_passed=false
    grep -Fq 'Canonical entrypoint: `$sdlc`' "$REPO_DIR/skills/sdlc/SKILL.md" || all_passed=false
    grep -Fq 'do not pretend Codex has a native `/sdlc` command' "$REPO_DIR/skills/sdlc/SKILL.md" || all_passed=false
    grep -RE '\$codex-sdlc([^A-Za-z0-9_-]|$)' "$REPO_DIR/README.md" "$REPO_DIR/SKILL.md" "$REPO_DIR/skills" 2>/dev/null && all_passed=false
    bad_slash_sdlc=$(grep -REin '(invoke|run|use|type|call|start|enter|execute)[[:space:]]+(the[[:space:]]+)?`?/sdlc`?' "$REPO_DIR/README.md" "$REPO_DIR/SKILL.md" "$REPO_DIR/skills" "$REPO_DIR/START-SDLC.md" "$REPO_DIR/SDLC-LOOP.md" 2>/dev/null || true)
    [ -z "$bad_slash_sdlc" ] || all_passed=false

    if [ "$all_passed" = "true" ]; then
        pass "package exposes one canonical SDLC skill name, display name, and entrypoint: sdlc"
    else
        fail "package still exposes duplicate or legacy SDLC skill naming"
    fi
}

test_package_cli_help_documents_bootstrap_profile_policy() {
    local output
    output=$(node "$REPO_DIR/bin/codex-sdlc-wizard.js" --help 2>&1)

    if echo "$output" | grep -Eqi 'default.*adaptive setup|adaptive setup.*default' &&
       echo "$output" | grep -Eqi 'setup.*maximum|bootstrap.*maximum' &&
       echo "$output" | grep -Eqi 'routine work.*mixed|day-to-day.*mixed|after bootstrap.*mixed'; then
        pass "npm CLI help documents adaptive setup as the default and the bootstrap profile policy"
    else
        fail "npm CLI help does not document the adaptive default and bootstrap-versus-routine profile policy"
    fi
}

test_package_cli_help_explains_update_version_boundary() {
    local output
    output=$(node "$REPO_DIR/bin/codex-sdlc-wizard.js" --help 2>&1)

    if echo "$output" | grep -Fq 'npx codex-sdlc-wizard@latest update' &&
       echo "$output" | grep -Fq 'does not self-update the npm package'; then
        pass "npm CLI help explains that update uses the invoked package version"
    else
        fail "npm CLI help does not explain how to consume the newest package during update"
    fi
}

test_package_cli_help_mentions_check() {
    local output
    local exit_code

    output=$(node "$REPO_DIR/bin/codex-sdlc-wizard.js" --help 2>&1)
    exit_code=$?

    if [ "$exit_code" -ne 0 ]; then
        fail "npm CLI help failed while checking for check command"
        return
    fi

    if echo "$output" | grep -q 'check'; then
        pass "npm CLI help advertises the check command"
    else
        fail "npm CLI help is missing the check command"
    fi
}

test_package_cli_help_mentions_update() {
    local output
    local exit_code

    output=$(node "$REPO_DIR/bin/codex-sdlc-wizard.js" --help 2>&1)
    exit_code=$?

    if [ "$exit_code" -ne 0 ]; then
        fail "npm CLI help failed while checking for update command"
        return
    fi

    if echo "$output" | grep -q 'update'; then
        pass "npm CLI help advertises the update command"
    else
        fail "npm CLI help is missing the update command"
    fi
}

test_package_cli_runs_check_command() {
    local tmpdir
    tmpdir=$(mktemp -d)
    local output
    local exit_code

    set +e
    output=$(cd "$tmpdir" && node "$REPO_DIR/bin/codex-sdlc-wizard.js" check 2>&1)
    exit_code=$?
    set -e

    rm -rf "$tmpdir"

    if [ "$exit_code" -eq 0 ] \
        && echo "$output" | grep -q '"repo_state"[[:space:]]*:[[:space:]]*"uninitialized"' \
        && echo "$output" | grep -q '"reason"[[:space:]]*:[[:space:]]*"manifest_missing"'; then
        pass "npm CLI runs check.sh and reports uninitialized repos"
    else
        fail "npm CLI check command did not return the expected uninitialized repo payload"
    fi
}

test_package_cli_runs_update_command() {
    local tmpdir
    tmpdir=$(mktemp -d)
    local output
    local exit_code

    set +e
    output=$(cd "$tmpdir" && node "$REPO_DIR/bin/codex-sdlc-wizard.js" update check-only 2>&1)
    exit_code=$?
    set -e

    rm -rf "$tmpdir"

    if [ "$exit_code" -ne 0 ] \
        && echo "$output" | grep -qi 'uninitialized' \
        && echo "$output" | grep -q '\$setup-wizard'; then
        pass "npm CLI runs update.sh and reports uninitialized repos"
    else
        fail "npm CLI update command did not report the expected uninitialized repo guidance"
    fi
}

test_readme_mentions_npx_entrypoint() {
    if grep -q 'npx codex-sdlc-wizard' "$REPO_DIR/README.md" \
        && grep -q 'npx codex-sdlc-wizard@latest' "$REPO_DIR/README.md" \
        && grep -q 'npx codex-sdlc-wizard check' "$REPO_DIR/README.md"; then
        pass "README documents the npm entrypoint"
    else
        fail "README is missing the npm entrypoint"
    fi
}

test_e2e_requires_explicit_token_opt_in() {
    if grep -q 'CODEX_E2E:-0' "$REPO_DIR/tests/test-e2e.sh" \
        && grep -q 'CODEX_E2E=1 bash tests/test-e2e.sh' "$REPO_DIR/README.md" \
        && grep -qi 'token-consuming' "$REPO_DIR/README.md"; then
        pass "E2E tests require explicit token-consuming opt-in"
    else
        fail "E2E tests should be opt-in so normal verification does not consume tokens"
    fi
}

test_docs_document_proof_stamp_gate() {
    if grep -q 'git-guard.cjs prove --reviewed' "$REPO_DIR/PROVE-IT.md" \
        && grep -q 'git-guard.cjs prove --reviewed' "$REPO_DIR/README.md" \
        && grep -q 'fresh SDLC proof' "$REPO_DIR/README.md" \
        && grep -q 'target repo root' "$REPO_DIR/README.md" \
        && grep -q 'target repo root' "$REPO_DIR/PROVE-IT.md"; then
        pass "docs document the proof-stamp git gate"
    else
        fail "docs should explain the proof-stamp git gate"
    fi
}

test_pretool_blocks_commit
test_pretool_blocks_push
test_pretool_blocks_git_after_shell_prefixes
test_pretool_allows_safe_command
test_pretool_reads_command_field
test_pretool_allows_non_git_command_mentions
test_pretool_does_not_crash_on_non_git_prototype_words
test_pretool_blocks_deep_wrapper_recursion
test_session_warns_missing
test_session_silent_when_present
test_universal_pretool_blocks_commit
test_universal_pretool_allows_commit_with_fresh_proof
test_universal_pretool_blocks_stale_proof
test_universal_pretool_blocks_cross_repo_proof_reuse
test_universal_pretool_blocks_cd_proof_reuse
test_universal_pretool_blocks_git_env_proof_reuse
test_universal_pretool_blocks_exported_git_env_proof_reuse
test_universal_pretool_blocks_auto_exported_git_env_proof_reuse
test_universal_pretool_blocks_workdir_proof_reuse
test_universal_pretool_allows_workdir_with_fresh_proof
test_universal_pretool_blocks_git_after_shell_prefixes
test_universal_pretool_allows_non_git_command_mentions
test_universal_pretool_does_not_crash_on_non_git_prototype_words
test_universal_pretool_blocks_deep_wrapper_recursion
test_universal_session_warns_missing
test_universal_compact_guard_emits_lifecycle_context
test_universal_compact_guard_handles_post_compact
test_universal_node_hooks_work_in_type_module_repos
test_hooks_json_matcher
test_hooks_json_valid
test_live_hooks_file_uses_universal_node_hooks
test_live_hooks_file_is_windows_safe
test_config_enables_hooks
test_install_preserves_agents_md
test_install_creates_sdlc_docs
test_install_creates_skill
test_install_keeps_skill_backups_out_of_skills_and_prunes_legacy_sdlc
test_install_merges_config
test_install_backs_up_hooks_json
test_agents_md_size
test_setup_skill_has_confidence_setup_contract
test_update_skill_has_idempotent_update_contract
test_skills_document_hooks_feature_rename
test_update_skill_frontloads_package_upgrade_boundary
test_helper_skill_metadata_uses_codex_sdlc_not_xdlc
test_setup_and_update_skills_stop_before_product_remediation
test_feedback_skill_has_privacy_prompt_and_dedupe
test_setup_docs_include_codex_desktop_handoff
test_setup_docs_include_m365_auth_lane_guidance
test_setup_docs_include_task_routing_gate
test_sdlc_skill_has_docsync_learning_and_merge_guard
test_repo_defaults_to_xhigh_reasoning
test_package_has_npm_release_surface
test_package_uses_single_canonical_sdlc_skill_name
test_package_cli_is_honest_about_supported_flags
test_package_cli_help_documents_bootstrap_profile_policy
test_package_cli_help_explains_update_version_boundary
test_package_cli_help_mentions_check
test_package_cli_help_mentions_update
test_package_cli_runs_check_command
test_package_cli_runs_update_command
test_readme_mentions_npx_entrypoint
test_e2e_requires_explicit_token_opt_in
test_docs_document_proof_stamp_gate

echo ""
echo "=== Results: $PASSED passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
    exit 1
fi
