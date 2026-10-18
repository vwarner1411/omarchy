#!/bin/bash

set -euo pipefail
source "$(dirname "$0")/base-test.sh"

plugin_id="cdelcollado.bluetooth"
jq -e --arg id "$plugin_id" '
  [.bar.layout[][] | .id] as $all |
  (.bar.layout.right | map(.id)) as $right |
  ($all | map(select(. == $id)) | length) == 1 and
  ($all | index("omarchy.bluetooth")) == null and
  ($right | index($id)) == (($right | index("omarchy.agents")) + 1) and
  ($right | index("omarchy.network")) == (($right | index($id)) + 1)
' "$ROOT/config/omarchy/shell.json" >/dev/null || fail "the default bar replaces the stock Bluetooth icon between agents and network"
pass "the default bar contains one replacement Bluetooth widget in the stock position"

scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
test_home="$scratch/home"
mkdir -p "$scratch/bin" "$test_home/.config/omarchy/plugins/custom-bluetooth" "$test_home/.local/state/omarchy"
config="$test_home/.config/omarchy/shell.json"
setup_script="$ROOT/install/user/first-run/bluetooth.sh"
export TEST_CALLS="$scratch/calls" TEST_CATALOG="$scratch/catalog"
export PATH="$scratch/bin:$ROOT/bin:$PATH" OMARCHY_PATH="$ROOT"
printf '[]\n' >"$TEST_CATALOG"
: >"$TEST_CALLS"

cat >"$scratch/bin/omarchy-plugin-catalog" <<'SH'
#!/bin/bash
cat "$TEST_CATALOG"
SH
cat >"$scratch/bin/omarchy-plugin-add" <<'SH'
#!/bin/bash
printf 'add %s\n' "$*" >>"$TEST_CALLS"
[[ $* == "https://github.com/cdelcollado/btomarchy.git --enable --yes" ]] || exit 99
[[ ${TEST_ADD_FAIL:-0} == "0" ]]
SH
cat >"$scratch/bin/omarchy-plugin-enable" <<'SH'
#!/bin/bash
printf 'enable %s\n' "$*" >>"$TEST_CALLS"
[[ ${TEST_ENABLE_FAIL:-0} == "0" ]]
SH
cat >"$scratch/bin/omarchy-plugin-disable" <<'SH'
#!/bin/bash
printf 'disable %s\n' "$*" >>"$TEST_CALLS"
SH
chmod +x "$scratch/bin/"*

run_setup() {
  HOME="$test_home" bash -euo pipefail "$setup_script"
}

cp "$ROOT/config/omarchy/shell.json" "$config"
run_setup
grep -Fxq 'add https://github.com/cdelcollado/btomarchy.git --enable --yes' "$TEST_CALLS" ||
  fail "first login does not install and enable the Bluetooth replacement without a prompt"
pass "first login installs and enables the Bluetooth replacement through the plugin manager"

printf '[{"id":"%s"}]\n' "$plugin_id" >"$TEST_CATALOG"
printf 'keep local plugin edits\n' >"$test_home/.config/omarchy/plugins/custom-bluetooth/Panel.qml"
printf '{"version":1,"devices":{"AA:BB:CC:DD:EE:FF":"Hidden device"}}\n' >"$test_home/.local/state/omarchy/bluetooth-ignored.json"
cp "$config" "$scratch/original-config"
cp "$test_home/.local/state/omarchy/bluetooth-ignored.json" "$scratch/original-ignored"
: >"$TEST_CALLS"
run_setup
[[ ! -s $TEST_CALLS ]] || fail "repeat setup reinstalls or reconfigures an existing replacement"
cmp -s "$config" "$scratch/original-config" || fail "repeat setup changes bar settings"
grep -Fxq 'keep local plugin edits' "$test_home/.config/omarchy/plugins/custom-bluetooth/Panel.qml" || fail "repeat setup replaces local plugin edits"
cmp -s "$test_home/.local/state/omarchy/bluetooth-ignored.json" "$scratch/original-ignored" || fail "setup changes the hidden-device list"
pass "repeat setup preserves existing plugin code, bar settings, and hidden devices"

jq --arg id "$plugin_id" '(.bar.layout.right[] | select(.id == $id)).id = "omarchy.bluetooth"' \
  "$ROOT/config/omarchy/shell.json" >"$config"
: >"$TEST_CALLS"
run_setup
expected=$(printf 'enable %s --before omarchy.bluetooth\ndisable omarchy.bluetooth\n' "$plugin_id")
[[ $(<"$TEST_CALLS") == "$expected" ]] || fail "replacement does not activate in the stock position before disabling the stock widget" "$(<"$TEST_CALLS")"
pass "an installed replacement takes over the stock Bluetooth position before disabling it"

jq --arg id "$plugin_id" '.bar.layout.right = [{id: $id}] + .bar.layout.right' "$config" >"$scratch/duplicate-config"
cp "$scratch/duplicate-config" "$config"
: >"$TEST_CALLS"
run_setup
[[ $(<"$TEST_CALLS") == "$expected" ]] || fail "setup does not handle an already-installed second Bluetooth icon"
pass "setup replaces the stock icon even when the replacement is already on the bar"

printf '[]\n' >"$TEST_CATALOG"
: >"$TEST_CALLS"
if TEST_ADD_FAIL=1 run_setup; then
  fail "a failed download passes for successful Bluetooth setup"
fi
! grep -q '^disable ' "$TEST_CALLS" || fail "a failed download disables the stock widget"
: >"$TEST_CALLS"
run_setup
[[ $(tail -n 2 "$TEST_CALLS") == "$expected" ]] || fail "Bluetooth setup cannot retry a failed download"
pass "download failures retain the stock widget and remain retryable"

printf '[{"id":"%s"}]\n' "$plugin_id" >"$TEST_CATALOG"
: >"$TEST_CALLS"
if TEST_ENABLE_FAIL=1 run_setup; then
  fail "a replacement that cannot be enabled passes for successful setup"
fi
! grep -q '^disable ' "$TEST_CALLS" || fail "a failed activation disables the stock widget"
pass "activation failures retain the stock Bluetooth control"

printf '{"bar":{"layout":{"left":["omarchy.bluetooth"],"center":[],"right":[]}}}\n' >"$config"
: >"$TEST_CALLS"
run_setup
[[ $(<"$TEST_CALLS") == "$expected" ]] || fail "replacement misses a string-form stock entry outside the right section"
pass "replacement follows the stock entry across bar sections and legacy formats"

grep -F 'run_first_run_step "install default Bluetooth plugin"' "$ROOT/bin/omarchy-provision-first-run" >/dev/null ||
  fail "first login does not install the Bluetooth plugin as a retryable step"
grep -F 'bash -euo pipefail "$OMARCHY_PATH/install/user/first-run/bluetooth.sh"' "$ROOT/bin/omarchy-provision-first-run" >/dev/null ||
  fail "first login does not propagate Bluetooth setup errors"
pass "Bluetooth replacement is part of the retryable first-login workflow"

grep -Fx 'o.bind("SUPER + CTRL + B", "Bluetooth", "omarchy-shell shell toggle cdelcollado.bluetooth")' \
  "$ROOT/default/hypr/bindings/utilities.lua" >/dev/null || fail "the Bluetooth shortcut still targets the removed stock widget"
pass "the default Bluetooth shortcut opens the replacement panel"
