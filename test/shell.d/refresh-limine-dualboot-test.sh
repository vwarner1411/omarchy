#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

boot_dir="$test_tmp/boot"
stub_bin="$test_tmp/bin"
omarchy_path="$test_tmp/omarchy"
mkdir -p "$boot_dir/EFI/Linux" "$stub_bin" "$omarchy_path/default/limine" "$test_tmp/sys/firmware/efi"

limine_config="$boot_dir/limine.conf"
original_config="$test_tmp/limine.conf.original"
cat >"$original_config" <<'EOF'
/Omarchy
protocol: efi
path: boot():/EFI/Linux/omarchy_linux.efi

/Windows 11
protocol: efi
path: guid(12345678-9ABC-DEF0-1234-56789ABCDEF0):/EFI/Microsoft/Boot/bootmgfw.efi
EOF
cp "$original_config" "$limine_config"

cat >"$omarchy_path/default/limine/limine.conf" <<'EOF'
default_entry: 2
interface_branding: Omarchy Bootloader
EOF

cat >"$stub_bin/sudo" <<'STUB'
#!/bin/bash
exec "$@"
STUB

cat >"$stub_bin/findmnt" <<'STUB'
#!/bin/bash
printf '%s\n' "${BOOT_FSTYPE:-vfat}"
STUB

cat >"$stub_bin/limine-update" <<'STUB'
#!/bin/bash
printf '%s\n' limine-update >>"$STEP_LOG"
STUB

cat >"$stub_bin/limine-snapper-sync" <<'STUB'
#!/bin/bash
printf '%s\n' limine-snapper-sync >>"$STEP_LOG"
STUB

cat >"$stub_bin/omarchy-setup-dualboot" <<'STUB'
#!/bin/bash
printf 'omarchy-setup-dualboot %s\n' "$*" >>"$STEP_LOG"
cat >"$LIMINE_CONFIG" <<EOF
/Omarchy
protocol: efi
path: boot():/EFI/Linux/omarchy_linux.efi

/Windows 11
protocol: efi
path: guid(${2}):/EFI/Microsoft/Boot/bootmgfw.efi
EOF
STUB

chmod +x "$stub_bin"/*

refresh_under_test="$test_tmp/omarchy-refresh-limine"
sed \
  -e "s#/boot/EFI/Linux#$boot_dir/EFI/Linux#g" \
  -e "s#/boot/limine.conf#$limine_config#g" \
  -e "s#/etc/machine-id#$test_tmp/machine-id#g" \
  -e "s#/sys/firmware/efi#$test_tmp/sys/firmware/efi#g" \
  "$ROOT/bin/omarchy-refresh-limine" >"$refresh_under_test"
printf '%s\n' test-machine-id >"$test_tmp/machine-id"

run_refresh() {
  STEP_LOG="$test_tmp/steps" \
    LIMINE_CONFIG="$limine_config" \
    OMARCHY_PATH="$omarchy_path" \
    PATH="$stub_bin:$ROOT/bin:$PATH" \
    BOOT_FSTYPE="${BOOT_FSTYPE:-vfat}" \
    bash "$refresh_under_test" >"$test_tmp/out" 2>"$test_tmp/err"
}

if BOOT_FSTYPE=ext4 run_refresh; then
  fail "a Limine refresh accepts a non-VFAT /boot mount"
fi
cmp -s "$original_config" "$limine_config" ||
  fail "a rejected Limine refresh changes the existing config"
pass "a Limine refresh rejects a non-VFAT /boot before changing its config"

: >"$test_tmp/steps"
run_refresh || fail "a Limine refresh with an existing dual-boot menu reports a failure" "$(cat "$test_tmp/err")"

grep -q '^/Omarchy$' "$limine_config" || fail "a Limine refresh loses the Omarchy entry"
grep -q '^/Windows 11$' "$limine_config" || fail "a Limine refresh loses the Windows entry"
grep -q '^omarchy-setup-dualboot --windows-partuuid 12345678-9ABC-DEF0-1234-56789ABCDEF0$' "$test_tmp/steps" ||
  fail "a Limine refresh does not restore the captured Windows ESP PARTUUID"

backup_config=$(find "$boot_dir" -maxdepth 1 -type f -name 'limine.conf.bak.*' -print -quit)
[[ -n $backup_config ]] || fail "a Limine refresh does not back up the existing config"
cmp -s "$original_config" "$backup_config" || fail "the Limine backup does not contain the original config"

expected_steps=$'limine-update\nlimine-snapper-sync\nomarchy-setup-dualboot --windows-partuuid 12345678-9ABC-DEF0-1234-56789ABCDEF0'
[[ $(cat "$test_tmp/steps") == "$expected_steps" ]] ||
  fail "a Limine refresh restores dual boot in the wrong order" "$(cat "$test_tmp/steps")"
pass "a Limine refresh backs up and restores both dual-boot entries"
