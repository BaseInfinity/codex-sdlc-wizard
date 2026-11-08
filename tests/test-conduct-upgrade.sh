#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
native_upgrade_workspace=$(mktemp -d)
native_stock_workspace=$(mktemp -d)
custom_template_workspace=$(mktemp -d)
c30_stock_workspace=$(mktemp -d)
c30_crlf_workspace=$(mktemp -d)
c30_custom_support_workspace=$(mktemp -d)
previous_stock_workspace=$(mktemp -d)
custom_reference_workspace=$(mktemp -d)
unsafe_file_workspace=$(mktemp -d)
unsafe_support_dir_workspace=$(mktemp -d)
unsafe_skill_root_workspace=$(mktemp -d)
unsafe_backup_workspace=$(mktemp -d)
invalid_entry_workspace=$(mktemp -d)
fallback_symlink_root_workspace=$(mktemp -d)
selective_backup_leaf_workspace=$(mktemp -d)
fallback_backup_leaf_workspace=$(mktemp -d)
fresh_missing_skills_workspace=$(mktemp -d)
immediate_lf_workspace=$(mktemp -d)
immediate_crlf_workspace=$(mktemp -d)
immediate_custom_helper_workspace=$(mktemp -d)
immediate_custom_template_workspace=$(mktemp -d)
absent_history_workspace=$(mktemp -d)
trap 'rm -rf "$native_upgrade_workspace" "$native_stock_workspace" "$custom_template_workspace" "$c30_stock_workspace" "$c30_crlf_workspace" "$c30_custom_support_workspace" "$previous_stock_workspace" "$custom_reference_workspace" "$unsafe_file_workspace" "$unsafe_support_dir_workspace" "$unsafe_skill_root_workspace" "$unsafe_backup_workspace" "$invalid_entry_workspace" "$fallback_symlink_root_workspace" "$selective_backup_leaf_workspace" "$fallback_backup_leaf_workspace" "$fresh_missing_skills_workspace" "$immediate_lf_workspace" "$immediate_crlf_workspace" "$immediate_custom_helper_workspace" "$immediate_custom_template_workspace" "$absent_history_workspace"' EXIT
export CODEX_HOME="$native_upgrade_workspace/codex-home"
export CODEX_SDLC_CODEX_BIN="$SCRIPT_DIR/fixtures/codex-version-stub.sh"
export CODEX_SDLC_DISABLE_REASONING=1
if [ "${CONDUCT_UPGRADE_FOCUS:-}" = "fixture-no-history" ]; then
    conduct_test_real_git="$(command -v git)"
    mkdir "$absent_history_workspace/bin"
    printf '%s\n' \
        '#!/bin/sh' \
        'case "$*" in' \
        '  *"show 33e603a253fb9aee629b494cd953fdbe38920987:"*)' \
        '    printf "%s\\n" "rejected historical show" >> "$CONDUCT_TEST_GIT_LOG"' \
        '    exit 77' \
        '    ;;' \
        'esac' \
        'exec "$CONDUCT_TEST_REAL_GIT" "$@"' \
        > "$absent_history_workspace/bin/git"
    chmod +x "$absent_history_workspace/bin/git"
    export CONDUCT_TEST_REAL_GIT="$conduct_test_real_git"
    export CONDUCT_TEST_GIT_LOG="$absent_history_workspace/git.log"
    export PATH="$absent_history_workspace/bin:$PATH"
fi
FIXTURE_DIR="$SCRIPT_DIR/fixtures" node <<'NODE'
const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const expected = {
  "conduct-c30-skill.md": "0ecd37f0e2f90ef43893999444f5afa68bcf1539178d8adb3092b7c623a11b34",
  "conduct-c30-codex-native.md": "4e6742e6f3f1bc0fd0bf38a7ab63982f148a5d0e274c722b5f0b23cf091b6db8",
  "conduct-c30-codex-thread.py": "41790af2f70eb9312113a54174afa2f861426f4bc43b87d7babaf3fd97ecf2e2",
  "conduct-c30-conduct.cjs": "53ed69e212151d6eddc850e1bc651d1b1b534e4513b1ae3eda95eb9d2cf5d9a6",
  "conduct-c30-codex-native.py": "f07314fba9e4a0cf2c552f469d01edaf1fedefeba60d930fcb1849e3e561f260",
  "conduct-33e-codex-thread.py": "5f7d210b26201b0ba9a65fd69a089d42160212f117be43f7900e16939c8d6458",
};
for (const [file, hash] of Object.entries(expected)) {
  const actual = crypto.createHash("sha256").update(fs.readFileSync(path.join(process.env.FIXTURE_DIR, file))).digest("hex");
  if (actual !== hash) throw new Error(`${file} is not the exact c30b1bb predecessor`);
}
NODE
grep -Fq '53ed69e212151d6eddc850e1bc651d1b1b534e4513b1ae3eda95eb9d2cf5d9a6' "$REPO_DIR/update.sh"
grep -Fq 'f07314fba9e4a0cf2c552f469d01edaf1fedefeba60d930fcb1849e3e561f260' "$REPO_DIR/update.sh"
write_crlf_fixture() {
    SOURCE_FILE="$1" TARGET_FILE="$2" node <<'NODE'
const fs = require("node:fs");
const source = fs.readFileSync(process.env.SOURCE_FILE, "utf8");
fs.writeFileSync(process.env.TARGET_FILE, source.replace(/\r?\n/g, "\r\n"));
NODE
}
prepare_c30_workspace() {
    local workspace="$1"
    local package_name="$2"
    export CODEX_HOME="$workspace/codex-home"
    printf '%s\n' "{\"name\":\"$package_name\",\"scripts\":{\"test\":\"node --test\"}}" > "$workspace/package.json"
    mkdir "$workspace/src"
    (cd "$workspace" && bash "$REPO_DIR/setup.sh" --yes >/dev/null)
    cp "$SCRIPT_DIR/fixtures/conduct-c30-skill.md" "$CODEX_HOME/skills/conduct/SKILL.md"
}
expect_unsafe_conduct_repair() {
    local workspace="$1"
    local output="$workspace/update.out"
    if (cd "$workspace" && bash "$REPO_DIR/update.sh") >"$output" 2>&1; then
        echo "FAIL: unsafe Conduct repair destination was accepted in $workspace" >&2
        exit 1
    fi
    grep -Fq 'Unsafe Conduct repair destination' "$output"
}
install_fixed_date() {
    local workspace="$1"
    local fixed_bin="$workspace/fixed-bin"
    mkdir "$fixed_bin"
    printf '%s\n' '#!/bin/sh' 'printf "%s\\n" 1700000000' > "$fixed_bin/date"
    chmod +x "$fixed_bin/date"
    printf '%s\n' "$fixed_bin"
}
run_fallback_symlink_root_regression() {
    local workspace="$fallback_symlink_root_workspace"
    local output="$workspace/update.out"
    prepare_c30_workspace "$workspace" "conduct-fallback-symlink-root"
    rm -rf "$CODEX_HOME/skills"
    mkdir -p "$workspace/external-skills/conduct"
    printf '%s\n' 'external fallback sentinel' > "$workspace/external-skills/conduct/sentinel.txt"
    ln -s "$workspace/external-skills" "$CODEX_HOME/skills"
    if (cd "$workspace" && bash "$REPO_DIR/update.sh") >"$output" 2>&1; then
        echo 'FAIL: Conduct fallback accepted a symlinked skills root with missing SKILL.md' >&2
        return 1
    fi
    grep -Fq 'Unsafe Conduct repair destination' "$output"
    test -L "$CODEX_HOME/skills"
    grep -Fq 'external fallback sentinel' "$workspace/external-skills/conduct/sentinel.txt"
}
run_selective_backup_leaf_regression() {
    local workspace="$selective_backup_leaf_workspace"
    local fixed_bin
    local backup_base
    prepare_c30_workspace "$workspace" "conduct-selective-backup-leaf"
    fixed_bin="$(install_fixed_date "$workspace")"
    backup_base="$CODEX_HOME/backups/skills/conduct-template.bak.1700000000"
    mkdir -p "$CODEX_HOME/backups/skills"
    printf '%s\n' 'external selective backup sentinel' > "$workspace/external-template-backup"
    ln -s "$workspace/external-template-backup" "$backup_base"
    (cd "$workspace" && PATH="$fixed_bin:$PATH" bash "$REPO_DIR/update.sh" >/dev/null)
    if ! grep -Fq 'external selective backup sentinel' "$workspace/external-template-backup"; then
        echo 'FAIL: Conduct selective backup overwrote a preexisting symlink target' >&2
        return 1
    fi
    test -L "$backup_base"
    test -f "$backup_base.1"
    test ! -L "$backup_base.1"
    cmp "$SCRIPT_DIR/fixtures/conduct-c30-skill.md" "$backup_base.1"
}
run_fallback_backup_leaf_regression() {
    local workspace="$fallback_backup_leaf_workspace"
    local fixed_bin
    local backup_base
    prepare_c30_workspace "$workspace" "conduct-fallback-backup-leaf"
    rm "$CODEX_HOME/skills/conduct/SKILL.md"
    printf '%s\n' 'user fallback data' > "$CODEX_HOME/skills/conduct/user-sentinel.txt"
    fixed_bin="$(install_fixed_date "$workspace")"
    backup_base="$CODEX_HOME/backups/skills/conduct.bak.1700000000"
    mkdir -p "$CODEX_HOME/backups/skills" "$workspace/external-directory-backup"
    printf '%s\n' 'external directory backup sentinel' > "$workspace/external-directory-backup/sentinel.txt"
    ln -s "$workspace/external-directory-backup" "$backup_base"
    (cd "$workspace" && PATH="$fixed_bin:$PATH" bash "$REPO_DIR/update.sh" >/dev/null)
    grep -Fq 'external directory backup sentinel' "$workspace/external-directory-backup/sentinel.txt"
    if [ "$(find "$workspace/external-directory-backup" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')" != "1" ]; then
        echo 'FAIL: Conduct fallback backup copied through a preexisting symlink' >&2
        return 1
    fi
    test -L "$backup_base"
    test -d "$backup_base.1"
    test ! -L "$backup_base.1"
    grep -Fq 'user fallback data' "$backup_base.1/user-sentinel.txt"
}
run_fresh_missing_codex_home_regression() {
    local workspace="$fresh_missing_skills_workspace"
    prepare_c30_workspace "$workspace" "conduct-fresh-missing-skills"
    test "$CODEX_HOME" = "$workspace/codex-home"
    rm -rf "$workspace/codex-home"
    (cd "$workspace" && bash "$REPO_DIR/update.sh" >/dev/null)
    test -f "$CODEX_HOME/skills/conduct/SKILL.md"
    cmp "$REPO_DIR/skill-sources/conduct/SKILL.template.md" "$CODEX_HOME/skills/conduct/SKILL.md"
}
run_c30_crlf_writer_regression() {
    local workspace="$c30_crlf_workspace"
    prepare_c30_workspace "$workspace" "conduct-c30-crlf-stock-upgrade"
    write_crlf_fixture \
        "$SCRIPT_DIR/fixtures/conduct-c30-codex-thread.py" \
        "$CODEX_HOME/skills/conduct/scripts/codex-thread.py"
    write_crlf_fixture \
        "$SCRIPT_DIR/fixtures/conduct-c30-codex-native.py" \
        "$CODEX_HOME/skills/conduct/scripts/codex-native.py"
    write_crlf_fixture \
        "$SCRIPT_DIR/fixtures/conduct-c30-conduct.cjs" \
        "$CODEX_HOME/skills/conduct/scripts/conduct.cjs"
    (cd "$workspace" && bash "$REPO_DIR/update.sh" >/dev/null)
    cmp "$REPO_DIR/skill-sources/conduct/scripts/codex-thread.py" "$CODEX_HOME/skills/conduct/scripts/codex-thread.py"
    cmp "$REPO_DIR/skill-sources/conduct/scripts/codex-native.py" "$CODEX_HOME/skills/conduct/scripts/codex-native.py"
    cmp "$REPO_DIR/skill-sources/conduct/scripts/conduct.cjs" "$CODEX_HOME/skills/conduct/scripts/conduct.cjs"
}
run_c30_custom_writer_regression() {
    local workspace="$c30_custom_support_workspace"
    prepare_c30_workspace "$workspace" "conduct-c30-custom-writer-upgrade"
    write_crlf_fixture \
        "$SCRIPT_DIR/fixtures/conduct-c30-conduct.cjs" \
        "$CODEX_HOME/skills/conduct/scripts/conduct.cjs"
    printf '\r\n%s\r\n' '// GENUINE C30 CONDUCT WRITER CUSTOMIZATION' >> "$CODEX_HOME/skills/conduct/scripts/conduct.cjs"
    cp "$CODEX_HOME/skills/conduct/scripts/conduct.cjs" "$workspace/conduct.before"
    (cd "$workspace" && bash "$REPO_DIR/update.sh" >/dev/null)
    cmp "$workspace/conduct.before" "$CODEX_HOME/skills/conduct/scripts/conduct.cjs"
}
initialize_current_conduct_workspace() {
    local workspace="$1"
    local package_name="$2"
    export CODEX_HOME="$workspace/codex-home"
    printf '%s\n' "{\"name\":\"$package_name\",\"scripts\":{\"test\":\"node --test\"}}" > "$workspace/package.json"
    mkdir "$workspace/src"
    (cd "$workspace" && bash "$REPO_DIR/setup.sh" --yes >/dev/null)
}
snapshot_current_conduct_docs() {
    local workspace="$1"
    local document
    for document in \
        SKILL.md \
        references/protocol.md \
        references/codex-native.md \
        references/claude-desktop.md; do
        mkdir -p "$workspace/docs-before/$(dirname "$document")"
        cp "$CODEX_HOME/skills/conduct/$document" "$workspace/docs-before/$document"
    done
}
assert_current_conduct_docs_unchanged() {
    local workspace="$1"
    local document
    for document in \
        SKILL.md \
        references/protocol.md \
        references/codex-native.md \
        references/claude-desktop.md; do
        cmp "$workspace/docs-before/$document" "$CODEX_HOME/skills/conduct/$document"
    done
}
run_immediate_stock_helper_regression() {
    local workspace="$1"
    local line_endings="$2"
    local first_output="$workspace/first-update.out"
    local second_output="$workspace/second-update.out"
    initialize_current_conduct_workspace "$workspace" "conduct-immediate-${line_endings}-helper-upgrade"
    if [ "$line_endings" = "crlf" ]; then
        write_crlf_fixture \
            "$SCRIPT_DIR/fixtures/conduct-33e-codex-thread.py" \
            "$CODEX_HOME/skills/conduct/scripts/codex-thread.py"
    else
        cp \
            "$SCRIPT_DIR/fixtures/conduct-33e-codex-thread.py" \
            "$CODEX_HOME/skills/conduct/scripts/codex-thread.py"
    fi
    snapshot_current_conduct_docs "$workspace"
    (cd "$workspace" && bash "$REPO_DIR/update.sh" >"$first_output")
    if ! grep -Fq 'Applied: skills/conduct' "$first_output"; then
        echo "FAIL: ordinary update did not recognize the immediate $line_endings stock helper" >&2
        return 1
    fi
    grep -Fq '5f7d210b26201b0ba9a65fd69a089d42160212f117be43f7900e16939c8d6458' "$REPO_DIR/update.sh"
    cmp "$REPO_DIR/skill-sources/conduct/scripts/codex-thread.py" "$CODEX_HOME/skills/conduct/scripts/codex-thread.py"
    assert_current_conduct_docs_unchanged "$workspace"
    (cd "$workspace" && bash "$REPO_DIR/update.sh" >"$second_output")
    grep -Fq 'No changes applied.' "$second_output"
    if grep -Fq 'Applied: skills/conduct' "$second_output"; then
        echo "FAIL: second update repeated Conduct repair after the $line_endings helper refresh" >&2
        return 1
    fi
    assert_current_conduct_docs_unchanged "$workspace"
}
run_immediate_custom_helper_regression() {
    local workspace="$immediate_custom_helper_workspace"
    initialize_current_conduct_workspace "$workspace" "conduct-immediate-custom-helper"
    cp \
        "$SCRIPT_DIR/fixtures/conduct-33e-codex-thread.py" \
        "$CODEX_HOME/skills/conduct/scripts/codex-thread.py"
    printf '\n%s\n' '# GENUINE 33E HELPER CUSTOMIZATION' >> "$CODEX_HOME/skills/conduct/scripts/codex-thread.py"
    cp "$CODEX_HOME/skills/conduct/scripts/codex-thread.py" "$workspace/codex-thread.before"
    (cd "$workspace" && bash "$REPO_DIR/update.sh" >/dev/null)
    cmp "$workspace/codex-thread.before" "$CODEX_HOME/skills/conduct/scripts/codex-thread.py"
}
run_immediate_custom_template_regression() {
    local workspace="$immediate_custom_template_workspace"
    initialize_current_conduct_workspace "$workspace" "conduct-immediate-custom-template"
    cp \
        "$SCRIPT_DIR/fixtures/conduct-33e-codex-thread.py" \
        "$CODEX_HOME/skills/conduct/scripts/codex-thread.py"
    printf '\n%s\n' '# GENUINE CURRENT TEMPLATE CUSTOMIZATION' >> "$CODEX_HOME/skills/conduct/SKILL.md"
    cp "$CODEX_HOME/skills/conduct/SKILL.md" "$workspace/skill.before"
    cp "$CODEX_HOME/skills/conduct/scripts/codex-thread.py" "$workspace/codex-thread.before"
    (cd "$workspace" && bash "$REPO_DIR/update.sh" >/dev/null)
    cmp "$workspace/skill.before" "$CODEX_HOME/skills/conduct/SKILL.md"
    cmp "$workspace/codex-thread.before" "$CODEX_HOME/skills/conduct/scripts/codex-thread.py"
}
run_immediate_helper_regressions() {
    (run_immediate_stock_helper_regression "$immediate_lf_workspace" lf)
    (run_immediate_stock_helper_regression "$immediate_crlf_workspace" crlf)
    (run_immediate_custom_helper_regression)
    (run_immediate_custom_template_regression)
}
run_fixture_without_history_regression() {
    git --version >/dev/null
    if git show 33e603a253fb9aee629b494cd953fdbe38920987:skill-sources/conduct/scripts/codex-thread.py \
        >/dev/null 2>&1; then
        echo 'FAIL: fixture-no-history git shim exposed the historical helper object' >&2
        return 1
    fi
    grep -Fxq 'rejected historical show' "$CONDUCT_TEST_GIT_LOG"
}
case "${CONDUCT_UPGRADE_FOCUS:-}" in
    fallback-symlink-root) run_fallback_symlink_root_regression; exit ;;
    selective-backup-leaf) run_selective_backup_leaf_regression; exit ;;
    fallback-backup-leaf) run_fallback_backup_leaf_regression; exit ;;
    fresh-missing-codex-home) run_fresh_missing_codex_home_regression; exit ;;
    c30-crlf-writer) run_c30_crlf_writer_regression; exit ;;
    c30-custom-writer) run_c30_custom_writer_regression; exit ;;
    immediate-helper) run_immediate_helper_regressions; exit ;;
    fixture-no-history) run_fixture_without_history_regression; exit ;;
    '') ;;
    *) echo "Unknown CONDUCT_UPGRADE_FOCUS: $CONDUCT_UPGRADE_FOCUS" >&2; exit 1 ;;
esac
run_immediate_helper_regressions
echo 'PASS: immediate stock helper refresh is selective, stable, and customization-safe'
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

export CODEX_HOME="$native_stock_workspace/codex-home"
printf '%s\n' '{"name":"conduct-native-stock-upgrade","scripts":{"test":"node --test"}}' > "$native_stock_workspace/package.json"
mkdir "$native_stock_workspace/src"
(cd "$native_stock_workspace" && bash "$REPO_DIR/setup.sh" --yes >/dev/null)
cp "$SCRIPT_DIR/fixtures/conduct-native-v1.md" "$CODEX_HOME/skills/conduct/SKILL.md"
cp "$SCRIPT_DIR/fixtures/conduct-peer-recovery-codex-native-v1.md" "$CODEX_HOME/skills/conduct/references/codex-native.md"
cp "$SCRIPT_DIR/fixtures/conduct-peer-recovery-claude-desktop-v1.md" "$CODEX_HOME/skills/conduct/references/claude-desktop.md"
rm -f "$CODEX_HOME/skills/conduct/scripts/codex-thread.py"
(cd "$native_stock_workspace" && bash "$REPO_DIR/update.sh" >/dev/null)
test -f "$CODEX_HOME/skills/conduct/scripts/codex-thread.py"
cmp "$REPO_DIR/skill-sources/conduct/SKILL.template.md" "$CODEX_HOME/skills/conduct/SKILL.md"
cmp "$REPO_DIR/skill-sources/conduct/references/codex-native.md" "$CODEX_HOME/skills/conduct/references/codex-native.md"
cmp "$REPO_DIR/skill-sources/conduct/references/claude-desktop.md" "$CODEX_HOME/skills/conduct/references/claude-desktop.md"
echo 'PASS: c8 stock Conduct template upgrades to current runtime and references'

export CODEX_HOME="$custom_template_workspace/codex-home"
printf '%s\n' '{"name":"conduct-native-custom-upgrade","scripts":{"test":"node --test"}}' > "$custom_template_workspace/package.json"
mkdir "$custom_template_workspace/src"
(cd "$custom_template_workspace" && bash "$REPO_DIR/setup.sh" --yes >/dev/null)
cp "$SCRIPT_DIR/fixtures/conduct-native-v1.md" "$CODEX_HOME/skills/conduct/SKILL.md"
printf '\n%s\n' '# GENUINE USER CUSTOMIZATION' >> "$CODEX_HOME/skills/conduct/SKILL.md"
cp "$CODEX_HOME/skills/conduct/SKILL.md" "$custom_template_workspace/conduct.before"
rm -f "$CODEX_HOME/skills/conduct/scripts/codex-thread.py"
(cd "$custom_template_workspace" && bash "$REPO_DIR/update.sh" >/dev/null)
cmp "$custom_template_workspace/conduct.before" "$CODEX_HOME/skills/conduct/SKILL.md"
test ! -e "$CODEX_HOME/skills/conduct/scripts/codex-thread.py"
echo 'PASS: c8-derived customized Conduct template remains untouched'

cp "$SCRIPT_DIR/fixtures/conduct-c30-skill.md" "$CODEX_HOME/skills/conduct/SKILL.md"
printf '\n%s\n' '# GENUINE C30 TEMPLATE CUSTOMIZATION' >> "$CODEX_HOME/skills/conduct/SKILL.md"
cp "$CODEX_HOME/skills/conduct/SKILL.md" "$custom_template_workspace/conduct-c30.before"
cp "$SCRIPT_DIR/fixtures/conduct-c30-codex-native.md" "$CODEX_HOME/skills/conduct/references/codex-native.md"
cp "$SCRIPT_DIR/fixtures/conduct-c30-codex-thread.py" "$CODEX_HOME/skills/conduct/scripts/codex-thread.py"
cp "$SCRIPT_DIR/fixtures/conduct-c30-conduct.cjs" "$CODEX_HOME/skills/conduct/scripts/conduct.cjs"
cp "$SCRIPT_DIR/fixtures/conduct-c30-codex-native.py" "$CODEX_HOME/skills/conduct/scripts/codex-native.py"
(cd "$custom_template_workspace" && bash "$REPO_DIR/update.sh" >/dev/null)
cmp "$custom_template_workspace/conduct-c30.before" "$CODEX_HOME/skills/conduct/SKILL.md"
cmp "$SCRIPT_DIR/fixtures/conduct-c30-codex-native.md" "$CODEX_HOME/skills/conduct/references/codex-native.md"
cmp "$SCRIPT_DIR/fixtures/conduct-c30-codex-thread.py" "$CODEX_HOME/skills/conduct/scripts/codex-thread.py"
cmp "$SCRIPT_DIR/fixtures/conduct-c30-conduct.cjs" "$CODEX_HOME/skills/conduct/scripts/conduct.cjs"
cmp "$SCRIPT_DIR/fixtures/conduct-c30-codex-native.py" "$CODEX_HOME/skills/conduct/scripts/codex-native.py"
echo 'PASS: c30-derived customized Conduct template leaves predecessor support untouched'

export CODEX_HOME="$c30_stock_workspace/codex-home"
printf '%s\n' '{"name":"conduct-c30-stock-upgrade","scripts":{"test":"node --test"}}' > "$c30_stock_workspace/package.json"
mkdir "$c30_stock_workspace/src"
(cd "$c30_stock_workspace" && bash "$REPO_DIR/setup.sh" --yes >/dev/null)
cp "$SCRIPT_DIR/fixtures/conduct-c30-skill.md" "$CODEX_HOME/skills/conduct/SKILL.md"
cp "$SCRIPT_DIR/fixtures/conduct-c30-codex-native.md" "$CODEX_HOME/skills/conduct/references/codex-native.md"
cp "$SCRIPT_DIR/fixtures/conduct-c30-codex-thread.py" "$CODEX_HOME/skills/conduct/scripts/codex-thread.py"
cp "$SCRIPT_DIR/fixtures/conduct-c30-conduct.cjs" "$CODEX_HOME/skills/conduct/scripts/conduct.cjs"
cp "$SCRIPT_DIR/fixtures/conduct-c30-codex-native.py" "$CODEX_HOME/skills/conduct/scripts/codex-native.py"
(cd "$c30_stock_workspace" && bash "$REPO_DIR/update.sh" >/dev/null)
cmp "$REPO_DIR/skill-sources/conduct/SKILL.template.md" "$CODEX_HOME/skills/conduct/SKILL.md"
cmp "$REPO_DIR/skill-sources/conduct/references/codex-native.md" "$CODEX_HOME/skills/conduct/references/codex-native.md"
cmp "$REPO_DIR/skill-sources/conduct/scripts/codex-thread.py" "$CODEX_HOME/skills/conduct/scripts/codex-thread.py"
cmp "$REPO_DIR/skill-sources/conduct/scripts/conduct.cjs" "$CODEX_HOME/skills/conduct/scripts/conduct.cjs"
cmp "$REPO_DIR/skill-sources/conduct/scripts/codex-native.py" "$CODEX_HOME/skills/conduct/scripts/codex-native.py"
grep -Fq -- '--ledger-root' "$CODEX_HOME/skills/conduct/SKILL.md"
grep -Fq -- '--request-id' "$CODEX_HOME/skills/conduct/references/codex-native.md"
grep -Fq -- '--ledger-root' "$CODEX_HOME/skills/conduct/scripts/codex-thread.py"
if grep -Fq -- '--create-only' \
    "$CODEX_HOME/skills/conduct/SKILL.md" \
    "$CODEX_HOME/skills/conduct/references/codex-native.md" \
    "$CODEX_HOME/skills/conduct/scripts/codex-thread.py"; then
    echo 'FAIL: exact c30 stock Conduct retained the unsupported create-only workflow' >&2
    exit 1
fi
echo 'PASS: exact c30 stock Conduct upgrades template, native reference, and thread helper coherently'

run_c30_crlf_writer_regression
echo 'PASS: exact CRLF c30 runtime predecessors upgrade coherently'

export CODEX_HOME="$c30_custom_support_workspace/codex-home"
printf '%s\n' '{"name":"conduct-c30-custom-support-upgrade","scripts":{"test":"node --test"}}' > "$c30_custom_support_workspace/package.json"
mkdir "$c30_custom_support_workspace/src"
(cd "$c30_custom_support_workspace" && bash "$REPO_DIR/setup.sh" --yes >/dev/null)
cp "$SCRIPT_DIR/fixtures/conduct-c30-skill.md" "$CODEX_HOME/skills/conduct/SKILL.md"
cp "$SCRIPT_DIR/fixtures/conduct-c30-codex-native.md" "$CODEX_HOME/skills/conduct/references/codex-native.md"
write_crlf_fixture \
    "$SCRIPT_DIR/fixtures/conduct-c30-codex-thread.py" \
    "$CODEX_HOME/skills/conduct/scripts/codex-thread.py"
write_crlf_fixture \
    "$SCRIPT_DIR/fixtures/conduct-c30-conduct.cjs" \
    "$CODEX_HOME/skills/conduct/scripts/conduct.cjs"
write_crlf_fixture \
    "$SCRIPT_DIR/fixtures/conduct-c30-codex-native.py" \
    "$CODEX_HOME/skills/conduct/scripts/codex-native.py"
printf '\n%s\n' '# GENUINE C30 REFERENCE CUSTOMIZATION' >> "$CODEX_HOME/skills/conduct/references/codex-native.md"
printf '\n%s\n' '# GENUINE C30 HELPER CUSTOMIZATION' >> "$CODEX_HOME/skills/conduct/scripts/codex-thread.py"
printf '\n%s\n' '// GENUINE C30 CONDUCT WRITER CUSTOMIZATION' >> "$CODEX_HOME/skills/conduct/scripts/conduct.cjs"
printf '\n%s\n' '# GENUINE C30 NATIVE ADAPTER CUSTOMIZATION' >> "$CODEX_HOME/skills/conduct/scripts/codex-native.py"
cp "$CODEX_HOME/skills/conduct/references/codex-native.md" "$c30_custom_support_workspace/codex-native-reference.before"
cp "$CODEX_HOME/skills/conduct/scripts/codex-thread.py" "$c30_custom_support_workspace/codex-thread.before"
cp "$CODEX_HOME/skills/conduct/scripts/conduct.cjs" "$c30_custom_support_workspace/conduct.before"
cp "$CODEX_HOME/skills/conduct/scripts/codex-native.py" "$c30_custom_support_workspace/codex-native-adapter.before"
(cd "$c30_custom_support_workspace" && bash "$REPO_DIR/update.sh" >/dev/null)
cmp "$REPO_DIR/skill-sources/conduct/SKILL.template.md" "$CODEX_HOME/skills/conduct/SKILL.md"
cmp "$c30_custom_support_workspace/codex-native-reference.before" "$CODEX_HOME/skills/conduct/references/codex-native.md"
cmp "$c30_custom_support_workspace/codex-thread.before" "$CODEX_HOME/skills/conduct/scripts/codex-thread.py"
cmp "$c30_custom_support_workspace/conduct.before" "$CODEX_HOME/skills/conduct/scripts/conduct.cjs"
cmp "$c30_custom_support_workspace/codex-native-adapter.before" "$CODEX_HOME/skills/conduct/scripts/codex-native.py"
echo 'PASS: c30 stock template upgrades without replacing customized reference or helper'

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

prepare_c30_workspace "$unsafe_file_workspace" "conduct-unsafe-file-upgrade"
rm "$CODEX_HOME/skills/conduct/scripts/conduct.cjs"
cp "$SCRIPT_DIR/fixtures/conduct-c30-codex-native.py" "$unsafe_file_workspace/external-native.py"
cp "$unsafe_file_workspace/external-native.py" "$unsafe_file_workspace/external-native.before"
rm "$CODEX_HOME/skills/conduct/scripts/codex-native.py"
ln -s "$unsafe_file_workspace/external-native.py" "$CODEX_HOME/skills/conduct/scripts/codex-native.py"
expect_unsafe_conduct_repair "$unsafe_file_workspace"
test ! -e "$CODEX_HOME/skills/conduct/scripts/conduct.cjs"
test -L "$CODEX_HOME/skills/conduct/scripts/codex-native.py"
cmp "$unsafe_file_workspace/external-native.before" "$unsafe_file_workspace/external-native.py"
cmp "$SCRIPT_DIR/fixtures/conduct-c30-skill.md" "$CODEX_HOME/skills/conduct/SKILL.md"
echo 'PASS: Conduct repair rejects a symlinked file before any copy and preserves its external target'

prepare_c30_workspace "$unsafe_support_dir_workspace" "conduct-unsafe-support-dir-upgrade"
rm -rf "$CODEX_HOME/skills/conduct/references"
mkdir "$unsafe_support_dir_workspace/external-references"
printf '%s\n' 'external sentinel' > "$unsafe_support_dir_workspace/external-references/sentinel.txt"
ln -s "$unsafe_support_dir_workspace/external-references" "$CODEX_HOME/skills/conduct/references"
expect_unsafe_conduct_repair "$unsafe_support_dir_workspace"
test -L "$CODEX_HOME/skills/conduct/references"
test ! -e "$unsafe_support_dir_workspace/external-references/protocol.md"
grep -Fq 'external sentinel' "$unsafe_support_dir_workspace/external-references/sentinel.txt"
cmp "$SCRIPT_DIR/fixtures/conduct-c30-skill.md" "$CODEX_HOME/skills/conduct/SKILL.md"
echo 'PASS: Conduct repair rejects a symlinked support directory without writing through it'

prepare_c30_workspace "$unsafe_skill_root_workspace" "conduct-unsafe-skill-root-upgrade"
rm -rf "$CODEX_HOME/skills/conduct"
mkdir "$unsafe_skill_root_workspace/external-conduct"
cp "$SCRIPT_DIR/fixtures/conduct-c30-skill.md" "$unsafe_skill_root_workspace/external-conduct/SKILL.md"
ln -s "$unsafe_skill_root_workspace/external-conduct" "$CODEX_HOME/skills/conduct"
expect_unsafe_conduct_repair "$unsafe_skill_root_workspace"
test -L "$CODEX_HOME/skills/conduct"
test ! -e "$unsafe_skill_root_workspace/external-conduct/scripts"
cmp "$SCRIPT_DIR/fixtures/conduct-c30-skill.md" "$unsafe_skill_root_workspace/external-conduct/SKILL.md"
echo 'PASS: Conduct repair rejects a symlinked skill root without writing through it'

prepare_c30_workspace "$unsafe_backup_workspace" "conduct-unsafe-backup-upgrade"
rm -rf "$CODEX_HOME/backups/skills"
mkdir "$unsafe_backup_workspace/external-backups"
printf '%s\n' 'backup sentinel' > "$unsafe_backup_workspace/external-backups/sentinel.txt"
ln -s "$unsafe_backup_workspace/external-backups" "$CODEX_HOME/backups/skills"
expect_unsafe_conduct_repair "$unsafe_backup_workspace"
test -L "$CODEX_HOME/backups/skills"
test "$(find "$unsafe_backup_workspace/external-backups" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')" = "1"
grep -Fq 'backup sentinel' "$unsafe_backup_workspace/external-backups/sentinel.txt"
cmp "$SCRIPT_DIR/fixtures/conduct-c30-skill.md" "$CODEX_HOME/skills/conduct/SKILL.md"
echo 'PASS: Conduct repair rejects a symlinked backup destination without writing through it'

prepare_c30_workspace "$invalid_entry_workspace" "conduct-invalid-entry-upgrade"
rm "$CODEX_HOME/skills/conduct/scripts/conduct.cjs"
mkdir "$CODEX_HOME/skills/conduct/scripts/conduct.cjs"
printf '%s\n' 'user-owned invalid entry' > "$CODEX_HOME/skills/conduct/scripts/conduct.cjs/sentinel.txt"
expect_unsafe_conduct_repair "$invalid_entry_workspace"
test -d "$CODEX_HOME/skills/conduct/scripts/conduct.cjs"
grep -Fq 'user-owned invalid entry' "$CODEX_HOME/skills/conduct/scripts/conduct.cjs/sentinel.txt"
cmp "$SCRIPT_DIR/fixtures/conduct-c30-skill.md" "$CODEX_HOME/skills/conduct/SKILL.md"
echo 'PASS: Conduct repair diagnoses and preserves a user-owned invalid destination entry'

run_fallback_symlink_root_regression
echo 'PASS: Conduct fallback rejects a symlinked skills root with missing SKILL.md'

run_selective_backup_leaf_regression
echo 'PASS: Conduct selective backup allocation preserves a preexisting leaf and chooses a unique file'

run_fallback_backup_leaf_regression
echo 'PASS: Conduct fallback backup allocation preserves a preexisting leaf and chooses a unique directory'

run_fresh_missing_codex_home_regression
echo 'PASS: Conduct repair permits a legitimately missing CODEX_HOME tree'
