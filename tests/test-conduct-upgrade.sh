#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
native_upgrade_workspace=$(mktemp -d)
previous_stock_workspace=$(mktemp -d)
custom_reference_workspace=$(mktemp -d)
trap 'rm -rf "$native_upgrade_workspace" "$previous_stock_workspace" "$custom_reference_workspace"' EXIT
export CODEX_HOME="$native_upgrade_workspace/codex-home"
export CODEX_SDLC_CODEX_BIN="$SCRIPT_DIR/fixtures/codex-version-stub.sh"
export CODEX_SDLC_DISABLE_REASONING=1
printf '%s\n' '{"name":"conduct-upgrade","scripts":{"test":"node --test"}}' > "$native_upgrade_workspace/package.json"
mkdir "$native_upgrade_workspace/src"
(cd "$native_upgrade_workspace" && bash "$REPO_DIR/setup.sh" --yes >/dev/null)
cp "$SCRIPT_DIR/fixtures/conduct-cli-v1.md" "$CODEX_HOME/skills/conduct/SKILL.md"
rm -f "$CODEX_HOME/skills/conduct/scripts/codex-thread.py"
rm "$CODEX_HOME/skills/conduct/scripts/codex-native.py" "$CODEX_HOME/skills/conduct/references/codex-native.md"
printf '\n%s\n' '# USER CUSTOM PROTOCOL' >> "$CODEX_HOME/skills/conduct/references/protocol.md"
(cd "$native_upgrade_workspace" && bash "$REPO_DIR/update.sh" >/dev/null)
test -f "$CODEX_HOME/skills/conduct/scripts/codex-native.py"
test -f "$CODEX_HOME/skills/conduct/references/codex-native.md"
cmp "$REPO_DIR/skill-sources/conduct/SKILL.template.md" "$CODEX_HOME/skills/conduct/SKILL.md"
grep -Fq 'USER CUSTOM PROTOCOL' "$CODEX_HOME/skills/conduct/references/protocol.md"
echo 'PASS: stock CLI conduct upgrades to native adapter without replacing custom protocol'

export CODEX_HOME="$custom_reference_workspace/codex-home"
printf '%s\n' '{"name":"conduct-custom-reference-upgrade","scripts":{"test":"node --test"}}' > "$custom_reference_workspace/package.json"
mkdir "$custom_reference_workspace/src"
(cd "$custom_reference_workspace" && bash "$REPO_DIR/setup.sh" --yes >/dev/null)
cp "$SCRIPT_DIR/fixtures/conduct-peer-recovery-v1.md" "$CODEX_HOME/skills/conduct/SKILL.md"
cp "$SCRIPT_DIR/fixtures/conduct-peer-recovery-codex-native-v1.md" "$CODEX_HOME/skills/conduct/references/codex-native.md"
cp "$SCRIPT_DIR/fixtures/conduct-peer-recovery-claude-desktop-v1.md" "$CODEX_HOME/skills/conduct/references/claude-desktop.md"
printf '\n%s\n' '# USER CUSTOM CODEX NATIVE REFERENCE' >> "$CODEX_HOME/skills/conduct/references/codex-native.md"
printf '\n%s\n' '# USER CUSTOM CLAUDE DESKTOP REFERENCE' >> "$CODEX_HOME/skills/conduct/references/claude-desktop.md"
cp "$CODEX_HOME/skills/conduct/references/codex-native.md" "$custom_reference_workspace/codex-native.before"
cp "$CODEX_HOME/skills/conduct/references/claude-desktop.md" "$custom_reference_workspace/claude-desktop.before"
rm -f "$CODEX_HOME/skills/conduct/scripts/codex-thread.py"
(cd "$custom_reference_workspace" && bash "$REPO_DIR/update.sh" >/dev/null)
test -f "$CODEX_HOME/skills/conduct/scripts/codex-thread.py"
cmp "$REPO_DIR/skill-sources/conduct/SKILL.template.md" "$CODEX_HOME/skills/conduct/SKILL.md"
cmp "$custom_reference_workspace/codex-native.before" "$CODEX_HOME/skills/conduct/references/codex-native.md"
cmp "$custom_reference_workspace/claude-desktop.before" "$CODEX_HOME/skills/conduct/references/claude-desktop.md"
echo 'PASS: previous Conduct upgrade preserves customized reference files'

export CODEX_HOME="$previous_stock_workspace/codex-home"
printf '%s\n' '{"name":"conduct-thread-upgrade","scripts":{"test":"node --test"}}' > "$previous_stock_workspace/package.json"
mkdir "$previous_stock_workspace/src"
(cd "$previous_stock_workspace" && bash "$REPO_DIR/setup.sh" --yes >/dev/null)
cp "$SCRIPT_DIR/fixtures/conduct-peer-recovery-v1.md" "$CODEX_HOME/skills/conduct/SKILL.md"
cp "$SCRIPT_DIR/fixtures/conduct-peer-recovery-codex-native-v1.md" "$CODEX_HOME/skills/conduct/references/codex-native.md"
cp "$SCRIPT_DIR/fixtures/conduct-peer-recovery-claude-desktop-v1.md" "$CODEX_HOME/skills/conduct/references/claude-desktop.md"
rm -f "$CODEX_HOME/skills/conduct/scripts/codex-thread.py"
printf '\n%s\n' '# USER CUSTOM THREAD PROTOCOL' >> "$CODEX_HOME/skills/conduct/references/protocol.md"
(cd "$previous_stock_workspace" && bash "$REPO_DIR/update.sh" >/dev/null)
test -f "$CODEX_HOME/skills/conduct/scripts/codex-thread.py" || {
    echo 'FAIL: previous stock Conduct did not receive scripts/codex-thread.py' >&2
    exit 1
}
cmp "$REPO_DIR/skill-sources/conduct/SKILL.template.md" "$CODEX_HOME/skills/conduct/SKILL.md"
cmp "$REPO_DIR/skill-sources/conduct/references/codex-native.md" "$CODEX_HOME/skills/conduct/references/codex-native.md" || {
    echo 'FAIL: previous stock Conduct kept stale codex-native.md' >&2
    exit 1
}
cmp "$REPO_DIR/skill-sources/conduct/references/claude-desktop.md" "$CODEX_HOME/skills/conduct/references/claude-desktop.md" || {
    echo 'FAIL: previous stock Conduct kept stale claude-desktop.md' >&2
    exit 1
}
grep -Fq 'USER CUSTOM THREAD PROTOCOL' "$CODEX_HOME/skills/conduct/references/protocol.md"
echo 'PASS: previous stock Conduct gains codex-thread and current references without replacing custom protocol'
