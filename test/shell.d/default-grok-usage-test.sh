#!/bin/bash

set -euo pipefail
source "$(dirname "$0")/base-test.sh"

plugin_id="vt.grok-usage"
jq -e --arg id "$plugin_id" '
  ([.plugins[] | .id] | map(select(. == $id)) | length) == 1 and
  ([.bar.layout[][] | .id] | map(select(. == "omarchy.agents")) | length) == 1 and
  ([.bar.layout[][] | .id] | index($id)) == null
' "$ROOT/config/omarchy/shell.json" >/dev/null || fail "Grok defaults do not retain the stock Agents widget with one background collector"
pass "Grok uses one background collector and keeps the stock Agents widget"

scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/bin" "$scratch/incoming" "$scratch/home/.config/omarchy" "$scratch/home/.grok"

cat >"$scratch/incoming/manifest.json" <<'JSON'
{
  "schemaVersion": 1,
  "id": "vt.grok-usage",
  "name": "Grok Usage",
  "version": "0.3.1",
  "kinds": ["service"],
  "entryPoints": { "service": "Service.qml" }
}
JSON
printf 'import QtQuick\nItem {}\n' >"$scratch/incoming/Service.qml"
git -C "$scratch/incoming" init -q
git -C "$scratch/incoming" add .
git -C "$scratch/incoming" -c user.name=Test -c user.email=test@example.com commit -qm initial

cat >"$scratch/bin/git" <<'SH'
#!/bin/bash
if [[ $1 == "clone" ]]; then
  printf '%s\n' "$*" >>"$TEST_GIT_LOG"
  [[ $2 == "--" && $3 == "https://github.com/vitally/omarchy-grok-usage.git" ]] || exit 99
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
  "shell enablePlugin vt.grok-usage {}") echo ok ;;
  *) exit 99 ;;
esac
SH
chmod +x "$scratch/bin/git" "$scratch/bin/omarchy-shell"

test_home="$scratch/home"
export OMARCHY_PATH="$ROOT" PATH="$scratch/bin:$ROOT/bin:$PATH"
export TEST_PLUGIN_REPO="$scratch/incoming"
export TEST_GIT_LOG="$scratch/git.log" TEST_SHELL_LOG="$scratch/shell.log"
setup_script="$ROOT/install/user/first-run/grok-usage.sh"
cp "$ROOT/config/omarchy/shell.json" "$test_home/.config/omarchy/shell.json"
printf '{"fixture":"preserve existing sign in"}\n' >"$test_home/.grok/auth.json"
cp "$test_home/.grok/auth.json" "$scratch/auth-before"

run_setup() {
  HOME="$test_home" bash -euo pipefail "$setup_script"
}

run_setup >"$scratch/output" 2>&1 || fail "first login installs Grok Usage" "$(<"$scratch/output")"
[[ -f $test_home/.config/omarchy/plugins/$plugin_id/Service.qml ]] || fail "the Grok collector is not installed"
grep -Fxq "shell enablePlugin $plugin_id {}" "$TEST_SHELL_LOG" || fail "the background collector is not enabled without a prompt"
cmp -s "$test_home/.grok/auth.json" "$scratch/auth-before" || fail "setup changes Grok credentials"
pass "first login installs and enables the collector without touching credentials"

printf 'keep local edits\n' >"$test_home/.config/omarchy/plugins/$plugin_id/Service.qml"
jq '.plugins = [] | .disabledPlugins = ["vt.grok-usage"]' "$test_home/.config/omarchy/shell.json" >"$scratch/settings-before"
cp "$scratch/settings-before" "$test_home/.config/omarchy/shell.json"
: >"$TEST_GIT_LOG"
: >"$TEST_SHELL_LOG"
run_setup >/dev/null
[[ ! -s $TEST_GIT_LOG && ! -s $TEST_SHELL_LOG ]] || fail "repeat setup reinstalls or re-enables an existing collector"
cmp -s "$test_home/.config/omarchy/shell.json" "$scratch/settings-before" || fail "repeat setup changes plugin or bar settings"
grep -Fxq 'keep local edits' "$test_home/.config/omarchy/plugins/$plugin_id/Service.qml" || fail "setup overwrites plugin code"
cmp -s "$test_home/.grok/auth.json" "$scratch/auth-before" || fail "repeat setup changes credentials"
pass "repeat setup preserves plugin edits disabled state bar layout and sign in"

mv "$test_home/.config/omarchy/plugins/$plugin_id" "$test_home/.config/omarchy/plugins/custom-folder"
run_setup >/dev/null
[[ ! -s $TEST_GIT_LOG && ! -s $TEST_SHELL_LOG ]] || fail "setup misses a collector installed under another folder name"
pass "an existing collector is recognized by manifest id"

test_home="$scratch/failed-home"
mkdir -p "$test_home"
if TEST_CLONE_FAIL=1 run_setup >"$scratch/failure" 2>&1; then
  fail "a failed collector download passes for success"
fi
[[ ! -e $test_home/.config/omarchy/plugins/$plugin_id ]] || fail "a failed download leaves an installed collector"
run_setup >/dev/null 2>&1 || fail "collector installation cannot retry a failed download"
pass "failed downloads remain retryable"

grep -F 'run_first_run_step "install default Grok usage plugin"' "$ROOT/bin/omarchy-provision-first-run" >/dev/null ||
  fail "Grok Usage setup is not a retryable first-login step"
grep -F 'bash -euo pipefail "$OMARCHY_PATH/install/user/first-run/grok-usage.sh"' "$ROOT/bin/omarchy-provision-first-run" >/dev/null ||
  fail "first login ignores Grok Usage setup failures"
pass "first login retries collector setup failures"
