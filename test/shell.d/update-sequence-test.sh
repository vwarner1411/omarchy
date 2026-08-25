#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
mkdir -p "$stub_bin"

update_under_test="$test_tmp/omarchy-update"
sed \
  -e "s#/boot/limine.conf#$test_tmp/limine.conf#g" \
  "$ROOT/bin/omarchy-update" >"$update_under_test"
chmod +x "$update_under_test"

# Every step omarchy-update runs, recorded in order with the unattended flag it
# was handed. One of them can be told to fail.
steps=(
  omarchy-update-lock
  omarchy-update-requires-free-space
  omarchy-update-confirm
  omarchy-update-pkg-prune
  omarchy-snapshot
  omarchy-update-stay-awake
  omarchy-update-dev
  omarchy-update-keyring
  omarchy-update-system-pkgs
  omarchy-migrate
  omarchy-hook
  omarchy-update-aur-pkgs
  omarchy-update-mise
  omarchy-update-orphan-pkgs
  omarchy-update-analyze-logs
  omarchy-update-status
  omarchy-update-restart
)

for step in "${steps[@]}"; do
  cat >"$stub_bin/$step" <<'STUB'
#!/bin/bash
printf '%s unattended=%s\n' "${0##*/}" "${OMARCHY_UPDATE_UNATTENDED:-}" >>"$STEP_LOG"
[[ ${FAILING_STEP:-} != "${0##*/}" ]] || exit 1
STUB
  chmod +x "$stub_bin/$step"
done

cat >"$stub_bin/omarchy-setup-dualboot" <<'STUB'
#!/bin/bash
printf '%s %s\n' "${0##*/}" "$*" >>"$STEP_LOG"
STUB
chmod +x "$stub_bin/omarchy-setup-dualboot"

# OMARCHY_UPDATE_LOGGED stands in for the script(1) wrapper the update re-execs
# itself under; the stubbed lock reports itself already held.
run_update() {
  : >"$test_tmp/steps"
  STEP_LOG="$test_tmp/steps" \
    FAILING_STEP="${FAILING_STEP:-}" \
    OMARCHY_UPDATE_LOGGED=1 \
    PATH="$stub_bin:$ROOT/bin:$PATH" \
    bash "$update_under_test" "$@" >"$test_tmp/out" 2>"$test_tmp/err"
}

steps_run() {
  cut -d' ' -f1 "$test_tmp/steps"
}

# Every step of a whole update, in order. $1 asks for the one a person confirms.
# Stay Awake bookends the work, so it is here twice.
expected_steps() {
  printf '%s\n' \
    omarchy-update-lock \
    omarchy-update-requires-free-space \
    ${1:+omarchy-update-confirm} \
    omarchy-update-pkg-prune \
    omarchy-snapshot \
    omarchy-update-stay-awake \
    omarchy-update-dev \
    omarchy-update-keyring \
    omarchy-update-system-pkgs \
    omarchy-migrate \
    omarchy-hook \
    omarchy-update-aur-pkgs \
    omarchy-update-mise \
    omarchy-update-orphan-pkgs \
    omarchy-update-analyze-logs \
    omarchy-update-status \
    omarchy-update-stay-awake \
    omarchy-update-restart
}

run_update -y || fail "an update where everything works reports a failure"
diff <(expected_steps) <(steps_run) >"$test_tmp/order" ||
  fail "an update where everything works does not run every step in order" "$(cat "$test_tmp/order")"
pass "an update where every step works runs all of them, in order"

grep -q '^omarchy-update-system-pkgs unattended=1$' "$test_tmp/steps" ||
  fail "-y does not mark the update unattended"
run_update </dev/null || fail "a confirmed update reports a failure"
diff <(expected_steps confirmed) <(steps_run) >"$test_tmp/order" ||
  fail "a confirmed update runs a different set of steps" "$(cat "$test_tmp/order")"
grep -q '^omarchy-update-system-pkgs unattended=$' "$test_tmp/steps" ||
  fail "an update a person confirmed is treated as unattended"
pass "-y is what marks an update unattended, not the update itself"

cat >"$test_tmp/limine.conf" <<'EOF'
/Omarchy
protocol: efi
path: boot():/EFI/Linux/omarchy_linux.efi

/Windows 11
protocol: efi
path: guid(12345678-9ABC-DEF0-1234-56789ABCDEF0):/EFI/Microsoft/Boot/bootmgfw.efi
EOF

run_update -y || fail "an update with a dual-boot menu reports a failure"
grep -q '^omarchy-setup-dualboot --windows-partuuid 12345678-9ABC-DEF0-1234-56789ABCDEF0$' "$test_tmp/steps" ||
  fail "an update does not preserve the Windows ESP PARTUUID"

orphan_line=$(grep -n '^omarchy-update-orphan-pkgs ' "$test_tmp/steps" | cut -d: -f1)
dualboot_line=$(grep -n '^omarchy-setup-dualboot ' "$test_tmp/steps" | cut -d: -f1)
analyze_line=$(grep -n '^omarchy-update-analyze-logs ' "$test_tmp/steps" | cut -d: -f1)
if ! ((orphan_line < dualboot_line && dualboot_line < analyze_line)); then
  fail "the dual-boot menu is not restored after package work and before update reporting"
fi
pass "an update restores the existing dual-boot menu before reporting success"

rm -f "$test_tmp/limine.conf"

# Migrations ship with the packages the upgrade installs and are written against
# them. Running them against what is still on disk is the failure this ordering
# exists to prevent, so the update stops where the packages did.
if FAILING_STEP=omarchy-update-system-pkgs run_update -y; then
  fail "an update whose packages did not upgrade passes for a whole one"
fi
for step in omarchy-migrate omarchy-hook omarchy-update-aur-pkgs omarchy-update-restart; do
  if grep -q "^$step " "$test_tmp/steps"; then
    fail "a blocked package upgrade still runs $step"
  fi
done
pass "a blocked package upgrade stops the update before it migrates"
