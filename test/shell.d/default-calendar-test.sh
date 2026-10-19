#!/bin/bash

set -euo pipefail
source "$(dirname "$0")/base-test.sh"

plugin_id="tmn73.calendar"
jq -e --arg id "$plugin_id" '
  [.bar.layout[][] | .id] as $ids |
  ($ids | map(select(. == $id)) | length) == 1 and
  ($ids | index("omarchy.clock")) == null and
  .bar.layout.right[-1].id == $id and .bar.layout.center == []
' "$ROOT/config/omarchy/shell.json" >/dev/null || fail "the default calendar replaces the stock clock at the far right"
pass "the default bar has one replacement calendar at the far right"

scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
test_home="$scratch/home"
mkdir -p "$scratch/bin" "$test_home/.config/omarchy/plugins/tmn73.calendar"
export TEST_CONFIG="$test_home/.config/omarchy/shell.json"
export TEST_CALLS="$scratch/calls" TEST_CATALOG="$scratch/catalog"
export PATH="$scratch/bin:$ROOT/bin:$PATH" OMARCHY_PATH="$ROOT"
setup_script="$ROOT/install/user/first-run/calendar.sh"
: >"$TEST_CALLS"
printf '[]\n' >"$TEST_CATALOG"

cat >"$scratch/bin/omarchy-plugin-catalog" <<'SH'
#!/bin/bash
cat "$TEST_CATALOG"
SH
cat >"$scratch/bin/omarchy-plugin-add" <<'SH'
#!/bin/bash
printf 'add %s\n' "$*" >>"$TEST_CALLS"
[[ $* == "https://github.com/tmn73/omarchy-calendar.git --enable --yes" ]] || exit 99
[[ ${TEST_ADD_FAIL:-0} == "0" ]] || exit 1
omarchy-plugin-enable tmn73.calendar
SH
cat >"$scratch/bin/omarchy-plugin-enable" <<'SH'
#!/bin/bash
set -euo pipefail
printf 'enable %s\n' "$*" >>"$TEST_CALLS"
[[ $1 == "tmn73.calendar" && ${TEST_ENABLE_FAIL:-0} == "0" ]] || exit 1
jq '
  def entry_id: if type == "object" then .id else . end;
  if any(.bar.layout[][]; entry_id == "tmn73.calendar") then . else
    .bar.layout[][] |= (if entry_id == "omarchy.clock" then
      (if type == "object" then . else {} end) + {id: "tmn73.calendar"}
    else . end)
  end
' "$TEST_CONFIG" >"$TEST_CONFIG.tmp"
mv "$TEST_CONFIG.tmp" "$TEST_CONFIG"
SH
cat >"$scratch/bin/omarchy-plugin-disable" <<'SH'
#!/bin/bash
set -euo pipefail
printf 'disable %s\n' "$*" >>"$TEST_CALLS"
[[ $1 == "omarchy.clock" ]] || exit 99
jq 'del(.bar.layout[][] | select((if type == "object" then .id else . end) == "omarchy.clock"))' \
  "$TEST_CONFIG" >"$TEST_CONFIG.tmp"
mv "$TEST_CONFIG.tmp" "$TEST_CONFIG"
SH
cat >"$scratch/bin/omarchy-bar" <<'SH'
#!/bin/bash
set -euo pipefail
printf 'bar %s\n' "$*" >>"$TEST_CALLS"
[[ $# == 6 && $1 == "move" && $2 == "tmn73.calendar" && $3 == "--section" && $4 == "right" && $5 == "--index" && $6 =~ ^[0-9]+$ ]] || exit 99
[[ ${TEST_MOVE_FAIL:-0} == "0" ]] || exit 1
jq '
  def entry_id: if type == "object" then .id else . end;
  [.bar.layout[][] | select(entry_id == "tmn73.calendar")][0] as $entry |
  del(.bar.layout[][] | select(entry_id == "tmn73.calendar")) |
  .bar.layout.right += [$entry]
' "$TEST_CONFIG" >"$TEST_CONFIG.tmp"
mv "$TEST_CONFIG.tmp" "$TEST_CONFIG"
SH
chmod +x "$scratch/bin/"*

run_setup() {
  HOME="$test_home" bash -euo pipefail "$setup_script"
}

assert_calendar() {
  jq -e '.bar.layout.right[-1].id == "tmn73.calendar" and
    ([.bar.layout[][] | if type == "object" then .id else . end] | index("omarchy.clock")) == null' \
    "$TEST_CONFIG" >/dev/null || fail "calendar setup does not leave one replacement at the far right"
}

cp "$ROOT/config/omarchy/shell.json" "$TEST_CONFIG"
run_setup
grep -Fxq 'add https://github.com/tmn73/omarchy-calendar.git --enable --yes' "$TEST_CALLS" ||
  fail "first login does not install and enable Calendar without prompting"
assert_calendar
pass "first login installs and enables Calendar through the plugin manager"

printf '[{"id":"tmn73.calendar"}]\n' >"$TEST_CATALOG"
printf 'keep plugin edits\n' >"$test_home/.config/omarchy/plugins/tmn73.calendar/Panel.qml"
printf '{"backend":"keep this account configuration"}\n' >"$test_home/.config/omarchy/calendar-sync.json"
cp "$TEST_CONFIG" "$scratch/config-before"
: >"$TEST_CALLS"
run_setup
[[ ! -s $TEST_CALLS ]] || fail "repeated setup reinstalls or moves an already-correct calendar"
cmp -s "$TEST_CONFIG" "$scratch/config-before" || fail "repeated setup changes widget settings"
grep -Fxq 'keep plugin edits' "$test_home/.config/omarchy/plugins/tmn73.calendar/Panel.qml" || fail "setup overwrites plugin code"
grep -Fxq '{"backend":"keep this account configuration"}' "$test_home/.config/omarchy/calendar-sync.json" || fail "setup changes account or sync settings"
pass "repeat setup preserves installed code widget settings and account configuration"

jq '
  .bar.layout.center = [{id: "omarchy.clock", format: "HH:mm:ss", formatAlt: "yyyy-MM-dd"}] |
  del(.bar.layout.right[] | select(.id == "tmn73.calendar"))
' "$ROOT/config/omarchy/shell.json" >"$scratch/legacy.json"
cp "$scratch/legacy.json" "$TEST_CONFIG"
: >"$TEST_CALLS"
run_setup
assert_calendar
jq -e '.bar.layout.right[-1].format == "HH:mm:ss" and .bar.layout.right[-1].formatAlt == "yyyy-MM-dd"' "$TEST_CONFIG" >/dev/null ||
  fail "replacement discards stock clock formats"
diff <(jq -S 'del(.bar.layout[][] | select(.id == "omarchy.clock"))' "$scratch/legacy.json") \
  <(jq -S 'del(.bar.layout[][] | select(.id == "tmn73.calendar"))' "$TEST_CONFIG") >/dev/null ||
  fail "replacement changes unrelated widgets or settings"
pass "replacement inherits clock formats and moves only the calendar to the far right"

cp "$scratch/legacy.json" "$TEST_CONFIG"
: >"$TEST_CALLS"
if TEST_ENABLE_FAIL=1 run_setup; then fail "activation failure passes for success"; fi
cmp -s "$TEST_CONFIG" "$scratch/legacy.json" || fail "activation failure changes the stock clock"
! grep -q '^disable ' "$TEST_CALLS" || fail "activation failure disables the working clock"
pass "activation failure retains the working stock clock"

printf '[]\n' >"$TEST_CATALOG"
: >"$TEST_CALLS"
if TEST_ADD_FAIL=1 run_setup; then fail "download failure passes for success"; fi
cmp -s "$TEST_CONFIG" "$scratch/legacy.json" || fail "download failure changes the stock clock"
! grep -q '^disable ' "$TEST_CALLS" || fail "download failure disables the working clock"
run_setup
assert_calendar
pass "failed downloads retain the stock clock and can be retried"

printf '[{"id":"tmn73.calendar"}]\n' >"$TEST_CATALOG"
cp "$scratch/legacy.json" "$TEST_CONFIG"
if TEST_MOVE_FAIL=1 run_setup; then fail "placement failure passes for success"; fi
run_setup
assert_calendar
pass "a failed placement is retried even after the clone replaced the stock widget"

jq '.bar.layout.center = [{id: "omarchy.clock", format: "keep replacement format instead"}] |
  .bar.layout.right |= ([.[] | select(.id == "tmn73.calendar")] + [.[] | select(.id != "tmn73.calendar")])' \
  "$ROOT/config/omarchy/shell.json" >"$TEST_CONFIG"
: >"$TEST_CALLS"
run_setup
assert_calendar
grep -Fxq 'disable omarchy.clock' "$TEST_CALLS" || fail "setup leaves a duplicate stock clock"
jq -e '.bar.layout.right[-1].format == "ddd d MMM HH:mm"' "$TEST_CONFIG" >/dev/null || fail "setup overwrites existing replacement formats"
pass "duplicate stock clocks are removed without overwriting replacement settings"

printf '{"bar":{"layout":{"left":["omarchy.clock"],"center":[],"right":["omarchy.tray","omarchy.audio"]}}}\n' >"$TEST_CONFIG"
run_setup
assert_calendar
pass "setup handles legacy string entries outside the right-hand section"

grep -F 'run_first_run_step "install default calendar plugin"' "$ROOT/bin/omarchy-provision-first-run" >/dev/null ||
  fail "Calendar setup is not a retryable first-login step"
grep -F 'bash -euo pipefail "$OMARCHY_PATH/install/user/first-run/calendar.sh"' "$ROOT/bin/omarchy-provision-first-run" >/dev/null ||
  fail "first login ignores Calendar setup failures"
for binding_file in applications utilities; do
  grep -F '"Calendar", "omarchy-shell shell toggle omarchy.clock"' "$ROOT/default/hypr/bindings/$binding_file.lua" >/dev/null ||
    fail "Calendar shortcut in $binding_file does not use the clone-aware route"
done
! grep -F 'app.hey.com/calendar' "$ROOT/default/hypr/bindings/applications.lua" >/dev/null || fail "Calendar shortcut still opens HEY"
pass "Calendar installs at first login and both shortcuts use clone-aware calendar routing"
