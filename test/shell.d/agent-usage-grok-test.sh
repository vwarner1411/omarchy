#!/bin/bash

set -euo pipefail
source "$(dirname "$0")/base-test.sh"
require_command jq
require_command node

scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
test_home="$scratch/home"
plugin_dir="$test_home/.config/omarchy/plugins/custom grok folder"
usage_dir="$scratch/state/omarchy/agents/usage"
mkdir -p "$plugin_dir/scripts" "$usage_dir"
export TEST_GROK_CALLS="$scratch/calls"
export OMARCHY_PATH="$ROOT" PATH="$ROOT/bin:$PATH"
: >"$TEST_GROK_CALLS"
cp "$ROOT/config/omarchy/shell.json" "$test_home/.config/omarchy/shell.json"
cat >"$plugin_dir/manifest.json" <<'JSON'
{"schemaVersion":1,"id":"vt.grok-usage","name":"Grok Usage","version":"0.3.1","kinds":["service"],"entryPoints":{"service":"Service.qml"}}
JSON
printf 'import QtQuick\nItem {}\n' >"$plugin_dir/Service.qml"
cat >"$plugin_dir/scripts/omarchy-agent-usage-grok.js" <<'JS'
const fs = require('fs')
fs.appendFileSync(process.env.TEST_GROK_CALLS, JSON.stringify(process.argv.slice(2)) + '\n')
console.log(JSON.stringify({schemaVersion:1,id:'grok',name:'Grok',ready:true,updatedAt:new Date().toISOString(),limits:[{label:'Weekly',percent:0.02}]}))
JS

update() {
  HOME="$test_home" XDG_STATE_HOME="$scratch/state" XDG_CACHE_HOME="$scratch/cache" \
    "$ROOT/bin/omarchy-agent-usage-update" "$@"
}

printf '{"id":"grok","limits":[{"percent":0.01}]}\n' >"$usage_dir/grok.json"
update --limits-only grok
jq -e '.limits[0].percent == 0.02' "$usage_dir/grok.json" >/dev/null ||
  fail "opening the AI panel leaves Grok at its old usage value"
grep -Fxq '["--limits-only"]' "$TEST_GROK_CALLS" || fail "Grok does not receive the panel limits refresh"
pass "AI-panel limits refresh updates Grok through its installed collector"

update --force grok
grep -Fxq '["--force"]' "$TEST_GROK_CALLS" || fail "manual refresh does not bypass the Grok cache"
pass "manual AI-panel refresh forwards force to Grok"

mkdir -p "$scratch/bin" "$test_home/.local/share/mise/shims"
export TEST_GROK_NODE_SHIM="$test_home/.local/share/mise/shims/node"
export TEST_GROK_NODE_BINARY
TEST_GROK_NODE_BINARY=$(type -P node)
cat >"$scratch/bin/omarchy-cmd-present" <<'SH'
#!/bin/bash
[[ $1 == "$TEST_GROK_NODE_SHIM" ]]
SH
cat >"$TEST_GROK_NODE_SHIM" <<'SH'
#!/bin/bash
exec "$TEST_GROK_NODE_BINARY" "$@"
SH
chmod +x "$scratch/bin/omarchy-cmd-present" "$TEST_GROK_NODE_SHIM"
saved_path="$PATH"
PATH="$scratch/bin:$PATH" update --limits-only grok
jq -e '.limits[0].percent == 0.02' "$usage_dir/grok.json" >/dev/null || fail "the graphical-session shim fallback does not collect Grok"
PATH="$saved_path"
pass "Grok finds the mise Node shim outside the interactive PATH"

cp "$usage_dir/grok.json" "$scratch/record-before"
: >"$TEST_GROK_CALLS"
update --limits-only --except grok grok
[[ ! -s $TEST_GROK_CALLS ]] || fail "a disabled Grok provider still calls the collector"
cmp -s "$usage_dir/grok.json" "$scratch/record-before" || fail "excluding Grok overwrites its record"
pass "the provider exclusion suppresses Grok collection"

jq '.plugins = []' "$ROOT/config/omarchy/shell.json" >"$test_home/.config/omarchy/shell.json"
update grok
[[ ! -s $TEST_GROK_CALLS ]] || fail "a disabled service still collects usage"
jq -e '.id == "grok" and .ready == false and .limits == []' "$usage_dir/grok.json" >/dev/null ||
  fail "a disabled Grok service leaves a stale visible subscription"
pass "disabling the Grok service stops collection without updater errors"

jq '.disabledPlugins = ["vt.grok-usage"]' "$ROOT/config/omarchy/shell.json" >"$test_home/.config/omarchy/shell.json"
update grok
[[ ! -s $TEST_GROK_CALLS ]] || fail "an explicit service opt-out is ignored"
pass "an explicit disabled-plugin entry is respected"

cp "$ROOT/config/omarchy/shell.json" "$test_home/.config/omarchy/shell.json"
mv "$plugin_dir" "$scratch/uninstalled-plugin"
update grok
jq -e '.id == "grok" and .ready == false and .limits == []' "$usage_dir/grok.json" >/dev/null ||
  fail "a missing optional plugin makes usage refresh fail"
[[ ! -s $TEST_GROK_CALLS ]] || fail "the missing collector was run"
pass "a missing optional Grok plugin produces an empty record without errors"
