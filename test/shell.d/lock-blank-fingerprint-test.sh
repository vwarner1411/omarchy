#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const serviceQml = fs.readFileSync(path.join(root, 'shell/plugins/lock/Service.qml'), 'utf8')
const lock = requireFromRoot('shell/plugins/lock/LockModel.js')

assertEqual(
  lock.blankDelaySeconds({ lock: 960, displayOff: 3600 }, 5),
  2640,
  'display-off delay is relative to the configured lock timeout'
)
assertEqual(lock.blankDelaySeconds({ lock: 960 }, 5), 5, 'missing display-off timeout keeps the default delay')
assertEqual(lock.blankDelaySeconds({ lock: 960, displayOff: 900 }, 5), 0, 'display-off before lock blanks immediately')

assert(
  /interval: root\.blankDelaySeconds \* 1000/.test(serviceQml),
  'the blank timer uses the configured delay'
)

// The fingerprint PAM stays armed for the whole lock waiting for a finger, so
// `authenticating` is true from lock until unlock on every machine with a
// reader enrolled. Gating the blank on it leaves the panel lit all night.
assert(
  /if \(root\.lockRequested && !root\.authenticatingPassword\) root\.runBlank\(\)/.test(serviceQml),
  'only a password check in flight stops the blank timer from blanking'
)

assert(
  !/idleBlankTimer[\s\S]*?!root\.authenticating\)/.test(serviceQml),
  'the blank timer never gates on the combined authenticating state'
)

assert(
  /onAuthenticatingPasswordChanged: \{\s*if \(!lockRequested\) return\s*if \(authenticatingPassword\) idleBlankTimer\.stop\(\)\s*else armBlankTimer\(\)/.test(serviceQml),
  'the blank timer is held off by password entry and re-armed when it finishes'
)

assert(
  !/onAuthenticatingChanged:/.test(serviceQml),
  'the combined authenticating state no longer drives the blank timer'
)
JS
