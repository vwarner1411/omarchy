#!/bin/bash

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

[[ $(rg '^proc_sorting[[:space:]]*=' "$ROOT/config/btop/btop.conf") == 'proc_sorting = "cpu direct"' ]] ||
  fail "btop defaults to direct CPU usage sorting"
pass "btop defaults to direct CPU usage sorting"
