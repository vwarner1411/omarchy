#!/bin/bash

set -euo pipefail
source "$(dirname "$0")/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const vm = require('vm')
const source = fs.readFileSync(root + '/shell/Ui/KeyboardPanel.qml', 'utf8')
const originBody = source.match(/readonly property point cardOrigin: \{([\s\S]*?)\n  \}/)[1]
const effective = source.match(/readonly property bool effectiveCenterOnBar: ([\s\S]*?)\n\s*\n/)

function position(overrides = {}, settings = {}, ownerPresent = true) {
  const context = {
    Qt: { point: (x, y) => ({x, y}) },
    anchorItem: {}, bar: {}, margin: 8, gap: 8,
    screenW: 2560, screenH: 1440, barW: 2560, barH: 26,
    barPos: 'top', contentWidth: 500, contentHeight: 600,
    anchorScreenPos: {x: 2440, y: 0}, anchorW: 100, anchorH: 26,
    centerOnBar: true,
    owner: ownerPresent ? {setting: (key, fallback) => settings[key] ?? fallback} : null,
    ...overrides
  }
  if (effective) context.effectiveCenterOnBar = vm.runInNewContext(effective[1], context)
  return vm.runInNewContext(`(function () { ${originBody} })()`, context)
}

assertDeepEqual(position({}, {centerOnBar: false}), {x: 2052, y: 34},
  'a widget override anchors a centered plugin beneath its far-right icon')
assertDeepEqual(position({anchorScreenPos: {x: 100, y: 0}}, {centerOnBar: false}), {x: 8, y: 34},
  'icon-anchored popups clamp to the left screen edge')
assertDeepEqual(position({barPos: 'bottom'}, {centerOnBar: false}), {x: 2052, y: 806},
  'bottom-bar popups remain above their icons')
assertDeepEqual(position({barPos: 'left', barW: 26, anchorScreenPos: {x: 0, y: 1200}}, {centerOnBar: false}), {x: 34, y: 832},
  'left-bar popups follow their icons and clamp vertically')
assertDeepEqual(position({barPos: 'right', barW: 26, anchorScreenPos: {x: 0, y: 1200}}, {centerOnBar: false}), {x: 2026, y: 832},
  'right-bar popups follow their icons and clamp vertically')
assertDeepEqual(position({screenW: 1080, barW: 1080, anchorScreenPos: {x: 940, y: 0}}, {centerOnBar: false}), {x: 572, y: 34},
  'portrait-monitor popups remain inside the right screen edge')
assertDeepEqual(position(), {x: 1030, y: 34},
  'a plugin with no override retains its centered default')
assertDeepEqual(position({}, {}, false), {x: 1030, y: 34},
  'a panel with no owner retains its default alignment')
assertDeepEqual(position({centerOnBar: false}), {x: 2052, y: 34},
  'an icon-anchored plugin with no override keeps its default alignment')
assertDeepEqual(position({centerOnBar: false}, {centerOnBar: true}), {x: 1030, y: 34},
  'a true widget override explicitly restores screen centering')

const defaults = JSON.parse(fs.readFileSync(root + '/config/omarchy/shell.json', 'utf8'))
const entries = Object.values(defaults.bar.layout).flat()
for (const id of ['tmn73.calendar', 'omarchy.weather']) {
  assert(entries.find(entry => entry.id === id)?.centerOnBar === false,
    `${id} defaults to opening beneath its bar icon`)
}
JS
