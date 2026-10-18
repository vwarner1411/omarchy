#!/bin/bash

set -euo pipefail
source "$(dirname "$0")/base-test.sh"

scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/bin" "$scratch/incoming" "$scratch/home"

plugin_id="io.github.edgarsilva.hw-monitor"
cat >"$scratch/incoming/manifest.json" <<'JSON'
{
  "schemaVersion": 1,
  "id": "io.github.edgarsilva.hw-monitor",
  "name": "Hardware Monitor",
  "version": "1.0.0",
  "kinds": ["bar-widget"],
  "entryPoints": { "barWidget": "Widget.qml" },
  "barWidget": { "displayName": "Hardware Monitor", "defaultSection": "right" }
}
JSON
printf 'import QtQuick\nItem {}\n' >"$scratch/incoming/Widget.qml"
git -C "$scratch/incoming" init -q
git -C "$scratch/incoming" add .
git -C "$scratch/incoming" -c user.name=Test -c user.email=test@example.com commit -qm initial

cat >"$scratch/bin/git" <<'SH'
#!/bin/bash
if [[ $1 == "clone" ]]; then
  printf '%s\n' "$*" >>"$TEST_GIT_LOG"
  [[ $2 == "--" && $3 == "https://github.com/edgarsilva/omarchy-hw-monitor.git" ]] || exit 99
  [[ ${TEST_CLONE_FAIL:-0} == "0" ]] || exit 1
  exec /usr/bin/git clone -- "$TEST_PLUGIN_REPO" "$4"
fi
exec /usr/bin/git "$@"
SH

cat >"$scratch/bin/omarchy-shell" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$TEST_SHELL_LOG"
case "$*" in
  "shell rescanPlugins") ;;
  "shell listPlugins") omarchy-plugin-catalog ;;
  "shell enablePlugin io.github.edgarsilva.hw-monitor {}") echo ok ;;
  *) exit 99 ;;
esac
SH
chmod +x "$scratch/bin/git" "$scratch/bin/omarchy-shell"

test_home="$scratch/home"
export OMARCHY_PATH="$ROOT" PATH="$scratch/bin:$ROOT/bin:$PATH"
export TEST_PLUGIN_REPO="$scratch/incoming"
export TEST_GIT_LOG="$scratch/git.log" TEST_SHELL_LOG="$scratch/shell.log"
setup_script="$ROOT/install/user/first-run/hardware-monitor.sh"

run_setup() {
  HOME="$test_home" bash -euo pipefail "$setup_script"
}

run_setup >"$scratch/output" 2>&1 ||
  fail "first login installs Hardware Monitor" "$(<"$scratch/output")"
[[ -f $test_home/.config/omarchy/plugins/$plugin_id/Widget.qml ]] || fail "the plugin is installed in the user plugin directory"
grep -Fxq "shell enablePlugin $plugin_id {}" "$TEST_SHELL_LOG" || fail "the new plugin is enabled without a prompt"
pass "first login installs and enables the default hardware monitor through the plugin manager"

printf 'keep my local changes\n' >"$test_home/.config/omarchy/plugins/$plugin_id/Widget.qml"
printf '{"bar":{"layout":{"right":[{"id":"io.github.edgarsilva.hw-monitor","mode":"labels"}]}}}\n' >"$test_home/.config/omarchy/shell.json"
cp "$test_home/.config/omarchy/shell.json" "$scratch/original-settings"
: >"$TEST_GIT_LOG"
: >"$TEST_SHELL_LOG"
run_setup >/dev/null
[[ ! -s $TEST_GIT_LOG && ! -s $TEST_SHELL_LOG ]] || fail "repeat setup clones, enables, or moves an existing installation"
grep -Fxq 'keep my local changes' "$test_home/.config/omarchy/plugins/$plugin_id/Widget.qml" || fail "repeat setup replaces local plugin changes"
cmp -s "$test_home/.config/omarchy/shell.json" "$scratch/original-settings" || fail "repeat setup changes user settings"
pass "repeat setup preserves existing plugin code, settings, and placement"

mv "$test_home/.config/omarchy/plugins/$plugin_id" "$test_home/.config/omarchy/plugins/custom-folder"
run_setup >/dev/null
[[ ! -s $TEST_GIT_LOG && ! -s $TEST_SHELL_LOG ]] || fail "setup misses a plugin installed under a different directory name"
pass "an existing plugin is recognized by manifest id rather than folder name"

test_home="$scratch/failed-home"
mkdir -p "$test_home"
if TEST_CLONE_FAIL=1 run_setup >"$scratch/failure" 2>&1; then
  fail "a failed plugin download passes for successful first-login setup"
fi
[[ ! -e $test_home/.config/omarchy/plugins/$plugin_id ]] || fail "a failed download leaves an installed plugin"
TEST_CLONE_FAIL=0 run_setup >/dev/null 2>&1 || fail "plugin setup cannot retry a failed download"
pass "a failed download fails the setup step and remains retryable"

jq -e --arg id "$plugin_id" '
  (.bar.layout.right | map(.id)) as $ids |
  ($ids | map(select(. == $id)) | length) == 1 and
  ($ids | index($id)) == (($ids | index("omarchy.tray")) + 1)
' "$ROOT/config/omarchy/shell.json" >/dev/null || fail "the default bar does not place Hardware Monitor immediately after the tray"
grep -F 'run_first_run_step "install default hardware monitor plugin"' "$ROOT/bin/omarchy-provision-first-run" >/dev/null ||
  fail "first login does not run plugin installation as a retryable step"
grep -F 'bash -euo pipefail "$OMARCHY_PATH/install/user/first-run/hardware-monitor.sh"' "$ROOT/bin/omarchy-provision-first-run" >/dev/null ||
  fail "first-login setup does not propagate plugin installation errors"
pass "the default bar includes the plugin and first login installs it as a retryable step"
