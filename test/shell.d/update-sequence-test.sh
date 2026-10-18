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
  omarchy-refresh-sddm
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
case "${0##*/}" in
omarchy-update-system-pkgs)
  # Model omarchy-settings replacing the login theme with upstream's version.
  printf 'upstream theme without a user chooser\n' >"$TEST_SDDM_THEME"
  ;;
omarchy-refresh-sddm)
  cp "$OMARCHY_PATH/default/sddm/omarchy/Main.qml" "$TEST_SDDM_THEME"
  ;;
omarchy-migrate)
  if [[ ${NESTED_PACKAGE_UPDATE:-0} == "1" ]]; then
    printf 'upstream theme installed by a migration\n' >"$TEST_SDDM_THEME"
  fi
  ;;
esac
[[ ${FAILING_STEP:-} != "${0##*/}" ]] || exit "${FAILING_STATUS:-1}"
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
    TEST_SDDM_THEME="$test_tmp/Main.qml" \
    OMARCHY_PATH="${TEST_OMARCHY_PATH:-/usr/share/omarchy}" \
    FAILING_STEP="${FAILING_STEP:-}" \
    FAILING_STATUS="${FAILING_STATUS:-1}" \
    NESTED_PACKAGE_UPDATE="${NESTED_PACKAGE_UPDATE:-0}" \
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
    ${2:+omarchy-refresh-sddm} \
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

# The checkout's QML survives a git merge, but SDDM loads the package-owned
# copy under /usr/share/sddm. A migration can replace it a second time.
TEST_OMARCHY_PATH="$ROOT" NESTED_PACKAGE_UPDATE=1 run_update -y || fail "a dev-linked update reports a failure"
diff <(expected_steps '' dev) <(steps_run) >"$test_tmp/order" ||
  fail "a dev-linked update restores SDDM after migrations and package work" "$(cat "$test_tmp/order")"
cmp -s "$ROOT/default/sddm/omarchy/Main.qml" "$test_tmp/Main.qml" ||
  fail "a package update leaves the fork's user chooser installed"
pass "a dev-linked update restores the fork's login theme after package replacement"

if TEST_OMARCHY_PATH="$ROOT" FAILING_STEP=omarchy-update-mise run_update -y; then
  fail "a failed tool upgrade passes for a successful update"
fi
cmp -s "$ROOT/default/sddm/omarchy/Main.qml" "$test_tmp/Main.qml" ||
  fail "a later update failure loses the fork's login theme"
pass "the fork's login theme survives a later update failure"

if TEST_OMARCHY_PATH="$ROOT" NESTED_PACKAGE_UPDATE=1 FAILING_STEP=omarchy-migrate run_update -y; then
  fail "a failed migration passes for a successful update"
fi
cmp -s "$ROOT/default/sddm/omarchy/Main.qml" "$test_tmp/Main.qml" ||
  fail "a failed nested package transaction loses the fork's login theme"
pass "a migration failure still restores the login theme after its package transaction"

if TEST_OMARCHY_PATH="$ROOT" FAILING_STEP=omarchy-refresh-sddm run_update -y; then
  fail "a failed SDDM restoration passes for a successful update"
fi
if grep -q '^omarchy-update-restart ' "$test_tmp/steps"; then
  fail "a failed SDDM restoration offers a reboot"
fi
pass "a failed login theme restoration stops the update before offering a reboot"

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

for failing_step in omarchy-update-system-pkgs omarchy-migrate omarchy-refresh-sddm; do
  if TEST_OMARCHY_PATH="$ROOT" NESTED_PACKAGE_UPDATE=1 FAILING_STEP="$failing_step" run_update -y; then
    fail "a failed $failing_step passes for a successful update"
  fi
  grep -q '^omarchy-setup-dualboot --windows-partuuid 12345678-9ABC-DEF0-1234-56789ABCDEF0$' "$test_tmp/steps" ||
    fail "a failed $failing_step skips restoring the Windows boot menu"
  if grep -q '^omarchy-update-restart ' "$test_tmp/steps"; then
    fail "a failed $failing_step offers a reboot"
  fi
done
pass "package, migration, and login restoration failures still restore the Windows boot menu"

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

for failure_status in 1 127; do
  if FAILING_STEP=omarchy-snapshot FAILING_STATUS="$failure_status" run_update -y; then
    fail "an update proceeds without a system snapshot"
  fi
  if grep -qE '^omarchy-update-(dev|keyring|system-pkgs|restart) ' "$test_tmp/steps"; then
    fail "a missing backup changes packages or offers a reboot"
  fi
done
pass "a failed or unavailable snapshot prevents all package changes"
