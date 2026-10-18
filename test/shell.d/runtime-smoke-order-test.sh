#!/bin/bash

set -euo pipefail
source "$(dirname "$0")/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const smoke = fs.readFileSync(path.join(root, 'test/shell.d/runtime-smoke-test.sh'), 'utf8')
const registrationCheck = smoke.indexOf('pass "each widget registers its IPC handler once per screen"')
const settledBar = smoke.indexOf('pass "default bar layout renders expected module slots"')

assert(settledBar >= 0 && registrationCheck > settledBar,
  'IPC registration is checked after the initial bar has settled')

for (const mutation of [
  'jq \'.name = "After Hot Reload"\'',
  'shell_ipc shell setPluginEnabled',
  'shell_ipc_quiet shell rescanPlugins'
]) {
  assert(smoke.indexOf(mutation) > registrationCheck,
    `initial IPC registration is checked before ${mutation}`)
}
JS
