#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
native_upgrade_workspace=$(mktemp -d)
trap 'rm -rf "$native_upgrade_workspace"' EXIT
export CODEX_HOME="$native_upgrade_workspace/codex-home"
export CODEX_SDLC_CODEX_BIN="$SCRIPT_DIR/fixtures/codex-version-stub.sh"
export CODEX_SDLC_DISABLE_REASONING=1
printf '%s\n' '{"name":"conduct-upgrade","scripts":{"test":"node --test"}}' > "$native_upgrade_workspace/package.json"
mkdir "$native_upgrade_workspace/src"
(cd "$native_upgrade_workspace" && bash "$REPO_DIR/setup.sh" --yes >/dev/null)
cp "$SCRIPT_DIR/fixtures/conduct-cli-v1.md" "$CODEX_HOME/skills/conduct/SKILL.md"
rm "$CODEX_HOME/skills/conduct/scripts/codex-native.py" "$CODEX_HOME/skills/conduct/references/codex-native.md"
printf '\n%s\n' '# USER CUSTOM PROTOCOL' >> "$CODEX_HOME/skills/conduct/references/protocol.md"
(cd "$native_upgrade_workspace" && bash "$REPO_DIR/update.sh" >/dev/null)
test -f "$CODEX_HOME/skills/conduct/scripts/codex-native.py"
test -f "$CODEX_HOME/skills/conduct/references/codex-native.md"
cmp "$REPO_DIR/skill-sources/conduct/SKILL.template.md" "$CODEX_HOME/skills/conduct/SKILL.md"
grep -Fq 'USER CUSTOM PROTOCOL' "$CODEX_HOME/skills/conduct/references/protocol.md"
echo 'PASS: stock CLI conduct upgrades to native adapter without replacing custom protocol'
