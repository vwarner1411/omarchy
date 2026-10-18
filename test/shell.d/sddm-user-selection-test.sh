#!/bin/bash

set -euo pipefail
source "$(dirname "$0")/base-test.sh"

runner=/usr/lib/qt6/bin/qmltestrunner
if [[ ! -x $runner || ! -d /usr/lib/qt6/qml/SddmComponents ]]; then
  pass "Qt Quick Test or SDDM components unavailable; skipping greeter interaction test"
  exit 0
fi

ulimit -c 0
GSETTINGS_BACKEND=memory QT_QPA_PLATFORMTHEME= QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software \
  "$runner" -input "$SHELL_TEST_DIR/fixtures/sddm-user-selection" -o -,txt
