#!/bin/bash

set -euo pipefail
source "$(dirname "$0")/base-test.sh"

scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/bin" "$scratch/incoming" "$scratch/home"

plugin_id="igor-alexandrov.tailscale"
cat >"$scratch/incoming/manifest.json" <<'JSON'
{
  "schemaVersion": 1,
  "id": "igor-alexandrov.tailscale",
  "name": "Tailscale",
  "version": "0.1.0",
  "kinds": ["bar-widget"],
  "entryPoints": { "barWidget": "Panel.qml" },
  "barWidget": { "displayName": "Tailscale", "defaultSection": "right" }
}
JSON
printf 'import QtQuick\nItem {}\n' >"$scratch/incoming/Panel.qml"
git -C "$scratch/incoming" init -q
git -C "$scratch/incoming" add .
git -C "$scratch/incoming" -c user.name=Test -c user.email=test@example.com commit -qm initial

cat >"$scratch/bin/git" <<'SH'
#!/bin/bash
if [[ $1 == "clone" ]]; then
  printf '%s\n' "$*" >>"$TEST_GIT_LOG"
  [[ $2 == "--" && $3 == "https://github.com/igor-alexandrov/omarchy-tailscale.git" ]] || exit 99
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
  "shell enablePlugin igor-alexandrov.tailscale {}")
    [[ ${TEST_ENABLE_FAIL:-0} == "0" ]] || { echo "activation failed"; exit 0; }
    echo ok
    ;;
  "shell enablePlugin omarchy.tailscale {}") echo ok ;;
  "shell setPluginEnabled omarchy.tailscale false")
    config="$HOME/.config/omarchy/shell.json"
    jq 'del(.bar.layout[][] | select((if type == "object" then .id else . end) == "omarchy.tailscale"))' \
      "$config" >"$config.tmp"
    mv "$config.tmp" "$config"
    echo ok
    ;;
  *) exit 99 ;;
esac
SH
chmod +x "$scratch/bin/git" "$scratch/bin/omarchy-shell"

test_home="$scratch/home"
export OMARCHY_PATH="$ROOT" PATH="$scratch/bin:$ROOT/bin:$PATH"
export TEST_PLUGIN_REPO="$scratch/incoming"
export TEST_GIT_LOG="$scratch/git.log" TEST_SHELL_LOG="$scratch/shell.log"
setup_script="$ROOT/install/user/first-run/tailscale.sh"

run_setup() {
  HOME="$test_home" bash -euo pipefail "$setup_script"
}

run_setup >"$scratch/output" 2>&1 ||
  fail "first login installs Tailscale" "$(<"$scratch/output")"
[[ -f $test_home/.config/omarchy/plugins/$plugin_id/Panel.qml ]] || fail "the plugin is installed in the user plugin directory"
grep -Fxq "shell enablePlugin $plugin_id {}" "$TEST_SHELL_LOG" || fail "the new plugin is enabled without a prompt"
pass "first login installs and enables Tailscale through the plugin manager"

printf 'keep my local changes\n' >"$test_home/.config/omarchy/plugins/$plugin_id/Panel.qml"
printf '{"bar":{"layout":{"right":[{"id":"igor-alexandrov.tailscale","refreshIntervalSec":120}]}},"disabledPlugins":["igor-alexandrov.tailscale"]}\n' >"$test_home/.config/omarchy/shell.json"
cp "$test_home/.config/omarchy/shell.json" "$scratch/original-settings"
: >"$TEST_GIT_LOG"
: >"$TEST_SHELL_LOG"
run_setup >/dev/null
[[ ! -s $TEST_GIT_LOG && ! -s $TEST_SHELL_LOG ]] || fail "repeat setup clones, enables, or moves an existing installation"
grep -Fxq 'keep my local changes' "$test_home/.config/omarchy/plugins/$plugin_id/Panel.qml" || fail "repeat setup replaces local plugin changes"
cmp -s "$test_home/.config/omarchy/shell.json" "$scratch/original-settings" || fail "repeat setup changes user settings"
pass "repeat setup preserves plugin edits, placement, refresh interval, and disabled state"

mv "$test_home/.config/omarchy/plugins/$plugin_id" "$test_home/.config/omarchy/plugins/custom-folder"
run_setup >/dev/null
[[ ! -s $TEST_GIT_LOG && ! -s $TEST_SHELL_LOG ]] || fail "setup misses a plugin installed under a different directory name"
pass "an existing Tailscale plugin is recognized by manifest id rather than folder name"

test_home="$scratch/failed-home"
mkdir -p "$test_home"
if TEST_CLONE_FAIL=1 run_setup >"$scratch/failure" 2>&1; then
  fail "a failed plugin download passes for successful first-login setup"
fi
[[ ! -e $test_home/.config/omarchy/plugins/$plugin_id ]] || fail "a failed download leaves an installed plugin"
TEST_CLONE_FAIL=0 run_setup >/dev/null 2>&1 || fail "plugin setup cannot retry a failed download"
pass "a failed Tailscale download fails the setup step and remains retryable"

config="$test_home/.config/omarchy/shell.json"
write_duplicate_config() {
  jq --arg id "$plugin_id" '
    (.bar.layout.right[] | select(.id == $id)).refreshIntervalSec = 120 |
    .bar.layout.right += [{id: "omarchy.tailscale"}]
  ' "$ROOT/config/omarchy/shell.json" >"$config"
  : >"$TEST_SHELL_LOG"
}

write_duplicate_config
jq 'del(.bar.layout[][] | select(.id == "omarchy.tailscale"))' "$config" >"$scratch/deduplicated"
run_setup >/dev/null
expected=$(printf 'shell enablePlugin %s {}\nshell setPluginEnabled omarchy.tailscale false\n' "$plugin_id")
[[ $(<"$TEST_SHELL_LOG") == "$expected" ]] || fail "setup does not enable the replacement before disabling the stock Tailscale icon" "$(<"$TEST_SHELL_LOG")"
cmp -s "$config" "$scratch/deduplicated" || fail "deduplication changes replacement settings, its position, or unrelated widgets"
pass "setup removes the stock Tailscale icon without moving or resetting the replacement"

: >"$TEST_SHELL_LOG"
run_setup >/dev/null
[[ ! -s $TEST_SHELL_LOG ]] || fail "repeated setup changes an already-deduplicated bar"
cmp -s "$config" "$scratch/deduplicated" || fail "repeated setup changes bar settings"
pass "Tailscale deduplication is idempotent"

write_duplicate_config
cp "$config" "$scratch/before-failure"
if TEST_ENABLE_FAIL=1 run_setup >"$scratch/activation-failure" 2>&1; then
  fail "failed Tailscale activation passes for successful setup"
fi
! grep -Fq 'setPluginEnabled omarchy.tailscale false' "$TEST_SHELL_LOG" || fail "failed activation removes the working stock widget"
cmp -s "$config" "$scratch/before-failure" || fail "failed activation changes the bar"
pass "failed activation keeps the stock Tailscale control"

write_duplicate_config
jq --arg id "$plugin_id" '.disabledPlugins = [$id]' "$config" >"$scratch/explicitly-disabled"
cp "$scratch/explicitly-disabled" "$config"
run_setup >/dev/null
[[ ! -s $TEST_SHELL_LOG ]] || fail "setup overrides an explicitly disabled replacement"
cmp -s "$config" "$scratch/explicitly-disabled" || fail "setup changes an explicit opt-out"
pass "an explicitly disabled replacement leaves the stock control and settings untouched"

# Exercise the real service installer without touching packages, networking,
# systemd, or the desktop. Its plugin commands still use the real CLI above.
export TEST_SERVICE_LOG="$scratch/service.log"
cat >"$scratch/bin/service-stub" <<'SH'
#!/bin/bash
printf '%s %s\n' "${0##*/}" "$*" >>"$TEST_SERVICE_LOG"
SH
chmod +x "$scratch/bin/service-stub"
for command in sudo systemctl omarchy-pkg-add omarchy-webapp-install; do
  ln -s service-stub "$scratch/bin/$command"
done

write_duplicate_config
HOME="$test_home" bash "$ROOT/bin/omarchy-install-service-tailscale" >"$scratch/service-output" 2>&1 ||
  fail "Tailscale service setup fails with the preferred plugin installed" "$(<"$scratch/service-output")"
[[ $(<"$TEST_SHELL_LOG") == "$expected" ]] || fail "Tailscale service setup still enables the stock widget instead of the replacement" "$(<"$TEST_SHELL_LOG")"
cmp -s "$config" "$scratch/deduplicated" || fail "Tailscale service setup changes unrelated bar settings"
: >"$TEST_SHELL_LOG"
HOME="$test_home" bash "$ROOT/bin/omarchy-install-service-tailscale" >/dev/null
[[ ! -s $TEST_SHELL_LOG ]] || fail "repeated Tailscale service setup brings back a second icon"
pass "Tailscale service setup uses the preferred widget and does not recreate duplicates"

write_duplicate_config
if HOME="$test_home" TEST_ENABLE_FAIL=1 bash "$ROOT/bin/omarchy-install-service-tailscale" >"$scratch/service-failure" 2>&1; then
  fail "Tailscale service setup hides plugin activation errors"
fi
! grep -Fq 'setPluginEnabled omarchy.tailscale false' "$TEST_SHELL_LOG" || fail "failed service setup removes the working stock control"
pass "Tailscale service setup propagates activation failures without removing the stock control"

jq -e --arg id "$plugin_id" '
  [.bar.layout[][] | .id] as $all |
  (.bar.layout.right | map(.id)) as $right |
  ($all | map(select(. == $id)) | length) == 1 and
  ($all | index("omarchy.tailscale")) == null and
  ($right | index($id)) == (($right | index("omarchy.network")) + 1) and
  $right[-1] == "tmn73.calendar" and .bar.layout.center == []
' "$ROOT/config/omarchy/shell.json" >/dev/null || fail "the default bar does not place one Tailscale plugin beside Network while keeping the calendar far right"
grep -F 'run_first_run_step "install default Tailscale plugin"' "$ROOT/bin/omarchy-provision-first-run" >/dev/null ||
  fail "first login does not run Tailscale installation as a retryable step"
grep -F 'bash -euo pipefail "$OMARCHY_PATH/install/user/first-run/tailscale.sh"' "$ROOT/bin/omarchy-provision-first-run" >/dev/null ||
  fail "first-login setup does not propagate Tailscale installation errors"
pass "the default bar includes one Tailscale plugin and first login installs it as a retryable step"
