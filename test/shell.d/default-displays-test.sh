#!/bin/bash

set -euo pipefail
source "$(dirname "$0")/base-test.sh"

plugin_id="io.github.dragosol.better-displays-pro"
jq -e --arg id "$plugin_id" '
  [.bar.layout[][] | .id] as $all |
  (.bar.layout.right | map(.id)) as $right |
  ($all | map(select(. == $id)) | length) == 1 and
  ($all | index("omarchy.monitor")) == null and
  ($right | index($id)) == (($right | index("omarchy.audio")) + 1) and
  ($right | index("omarchy.power")) == (($right | index($id)) + 1)
' "$ROOT/config/omarchy/shell.json" >/dev/null || fail "the default bar replaces the stock display icon between audio and power"
pass "the default bar contains one Better Displays Pro widget in the stock position"

scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/bin" "$scratch/home/.config/omarchy" "$scratch/home/.local/state/omarchy/displays"
test_home="$scratch/home"
config="$test_home/.config/omarchy/shell.json"
setup_script="$ROOT/install/user/first-run/better-displays.sh"
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
[[ $* == "https://github.com/dragosol/omarchy-better-displays.git --enable --yes" ]] || exit 99
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
grep -Fxq 'add https://github.com/dragosol/omarchy-better-displays.git --enable --yes' "$TEST_CALLS" ||
  fail "first login does not install and enable Better Displays Pro without a prompt"
pass "first login installs and enables Better Displays Pro through the plugin manager"

printf '[{"id":"%s"}]\n' "$plugin_id" >"$TEST_CATALOG"
mkdir -p "$test_home/.config/omarchy/plugins/my-displays"
printf 'keep local plugin edits\n' >"$test_home/.config/omarchy/plugins/my-displays/Panel.qml"
printf '{"keep":"saved display profiles"}\n' >"$test_home/.local/state/omarchy/displays/profiles.json"
cp "$config" "$scratch/original-config"
: >"$TEST_CALLS"
run_setup
[[ ! -s $TEST_CALLS ]] || fail "repeat setup reinstalls or reconfigures an existing replacement"
cmp -s "$config" "$scratch/original-config" || fail "repeat setup changes bar settings"
grep -Fxq 'keep local plugin edits' "$test_home/.config/omarchy/plugins/my-displays/Panel.qml" || fail "repeat setup replaces local plugin edits"
grep -Fxq '{"keep":"saved display profiles"}' "$test_home/.local/state/omarchy/displays/profiles.json" || fail "setup changes saved display profiles"
pass "repeat setup preserves an existing plugin, bar settings, and saved display profiles"

# An older bar, or one carrying both icons, replaces the stock entry only
# after the new widget has been enabled in its place.
jq --arg id "$plugin_id" '(.bar.layout.right[] | select(.id == $id)).id = "omarchy.monitor"' \
  "$ROOT/config/omarchy/shell.json" >"$config"
: >"$TEST_CALLS"
run_setup
expected=$(printf 'enable %s --before omarchy.monitor\ndisable omarchy.monitor\n' "$plugin_id")
[[ $(<"$TEST_CALLS") == "$expected" ]] || fail "replacement does not enable at the stock position before disabling the old widget" "$(<"$TEST_CALLS")"
pass "an installed replacement takes over the stock icon position before the stock widget is disabled"

printf '[]\n' >"$TEST_CATALOG"
: >"$TEST_CALLS"
if TEST_ADD_FAIL=1 run_setup; then
  fail "a failed download passes for successful display setup"
fi
! grep -q '^disable ' "$TEST_CALLS" || fail "a failed download disables the working stock widget"
: >"$TEST_CALLS"
run_setup
[[ $(tail -n 2 "$TEST_CALLS") == "$expected" ]] || fail "display setup cannot retry a failed download"
pass "download failures keep the stock widget and can be retried"

printf '[{"id":"%s"}]\n' "$plugin_id" >"$TEST_CATALOG"
: >"$TEST_CALLS"
if TEST_ENABLE_FAIL=1 run_setup; then
  fail "a replacement that cannot be enabled passes for successful setup"
fi
! grep -q '^disable ' "$TEST_CALLS" || fail "a failed activation disables the working stock widget"
pass "activation failures do not disable the stock display control"

# Older shell.json layouts may use strings instead of objects.
printf '{"bar":{"layout":{"left":["omarchy.monitor"],"center":[],"right":[]}}}\n' >"$config"
: >"$TEST_CALLS"
run_setup
[[ $(<"$TEST_CALLS") == "$expected" ]] || fail "replacement misses a string-form stock entry outside the right section"
pass "replacement follows the stock entry across bar sections and legacy entry formats"

grep -F 'run_first_run_step "install default display plugin"' "$ROOT/bin/omarchy-provision-first-run" >/dev/null ||
  fail "first login does not install the display plugin as a retryable step"
grep -F 'bash -euo pipefail "$OMARCHY_PATH/install/user/first-run/better-displays.sh"' "$ROOT/bin/omarchy-provision-first-run" >/dev/null ||
  fail "first login does not propagate display setup errors"
pass "the default display setup is part of the retryable first-login workflow"
