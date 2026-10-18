#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

boot_dir="$test_tmp/boot"
stub_bin="$test_tmp/bin"
mkdir -p \
  "$boot_dir/EFI/Linux" \
  "$boot_dir/EFI/BOOT" \
  "$stub_bin" \
  "$test_tmp/sys/firmware/efi/efivars"

limine_config="$boot_dir/limine.conf"
original_config="$test_tmp/limine.conf.original"
cat >"$original_config" <<'EOF'
/Omarchy
protocol: efi
path: boot():/EFI/Linux/omarchy_linux.efi
cmdline: quiet splash root=PARTUUID=559cf303-a5c7-4184-9063-9c5f539d8d71 rw rootfstype=btrfs

/Windows 11
protocol: efi
path: guid(85197C7F-189B-499D-A385-B498F595BE81):/EFI/Microsoft/Boot/bootmgfw.efi
EOF
cp "$original_config" "$limine_config"
printf '%s\n' legacy-alternate >"$boot_dir/EFI/BOOT/limine.conf"
printf '%s\n' uki >"$boot_dir/EFI/Linux/omarchy_linux.efi"
printf '%s\n' test-machine-id >"$test_tmp/machine-id"

cat >"$stub_bin/sudo" <<'STUB'
#!/bin/bash
exec "$@"
STUB

cat >"$stub_bin/findmnt" <<'STUB'
#!/bin/bash
printf '%s\n' vfat
STUB

cat >"$stub_bin/limine-update" <<'STUB'
#!/bin/bash
exit 0
STUB

cat >"$stub_bin/efibootmgr" <<'STUB'
#!/bin/bash
printf '%s\n' 'Boot0000* Windows Boot Manager'
STUB

cat >"$stub_bin/limine-entry-tool" <<'STUB'
#!/bin/bash
[[ $* == "--get-cmdline linux-omarchy" ]] || exit 99
[[ ${KERNEL_CMDLINE_FAIL:-0} == "0" ]] || exit 1
printf '%s\n' 'quiet splash root=PARTUUID=559cf303-a5c7-4184-9063-9c5f539d8d71 rw rootfstype=btrfs initramfs_async=0 systemd.tty.term.console=dumb'
STUB

chmod +x "$stub_bin"/*

dualboot_under_test="$test_tmp/omarchy-setup-dualboot"
sed \
  -e "s#/boot/#$boot_dir/#g" \
  -e "s#/etc/machine-id#$test_tmp/machine-id#g" \
  -e "s#/etc/default/limine#$test_tmp/default-limine#g" \
  -e "s#/var/lib/omarchy/migrations/1789325478#$test_tmp/kernel-verified#g" \
  -e "s#/sys/firmware/efi/efivars#$test_tmp/sys/firmware/efi/efivars#g" \
  "$ROOT/bin/omarchy-setup-dualboot" >"$dualboot_under_test"

run_dualboot() {
  PATH="$stub_bin:$ROOT/bin:$PATH" \
    bash "$dualboot_under_test" "$@" >"$test_tmp/out" 2>"$test_tmp/err"
}

run_dualboot --windows-partuuid 85197C7F-189B-499D-A385-B498F595BE81 ||
  fail "dual-boot setup with a valid Windows PARTUUID reports a failure" "$(cat "$test_tmp/err")"

entry_count=$(grep -c '^/' "$limine_config")
(( entry_count == 2 )) || fail "dual-boot setup writes entries other than Omarchy and Windows"
grep -q '^path: boot():/EFI/Linux/omarchy_linux.efi$' "$limine_config" ||
  fail "dual-boot setup loses the stable Omarchy UKI path"
grep -q '^cmdline: quiet splash root=PARTUUID=559cf303-a5c7-4184-9063-9c5f539d8d71 rw rootfstype=btrfs$' "$limine_config" ||
  fail "dual-boot setup loses the working kernel cmdline"
grep -q '^path: guid(85197c7f-189b-499d-a385-b498f595be81):/EFI/Microsoft/Boot/bootmgfw.efi$' "$limine_config" ||
  fail "dual-boot setup writes the wrong Windows loader path"

backup_dir=$(find "$boot_dir" -maxdepth 1 -type d -name 'backup-limine-*' -print -quit)
[[ -n $backup_dir ]] || fail "dual-boot setup does not create a backup directory"
cmp -s "$original_config" "$backup_dir/${limine_config#/}" ||
  fail "dual-boot setup does not back up the original canonical config"
grep -q '^legacy-alternate$' "$backup_dir/${boot_dir#/}/EFI/BOOT/limine.conf" ||
  fail "dual-boot setup does not back up an alternate config before removing it"
[[ ! -e $boot_dir/EFI/BOOT/limine.conf ]] || fail "dual-boot setup leaves an alternate Limine config active"
pass "dual-boot setup preserves the working boot state and backs up replaced configs"

cp "$original_config" "$limine_config"
if run_dualboot --windows-partuuid not-a-guid; then
  fail "dual-boot setup accepts an invalid Windows PARTUUID"
fi
cmp -s "$original_config" "$limine_config" || fail "a rejected Windows PARTUUID changes the Limine config"
pass "dual-boot setup rejects an invalid Windows PARTUUID before changing the config"

printf '%s\n' new-uki >"$boot_dir/EFI/Linux/omarchy_linux-omarchy.efi"
run_dualboot --windows-partuuid 85197C7F-189B-499D-A385-B498F595BE81 || fail "an unverified kernel leaves a usable menu"
grep -q '^path: boot():/EFI/Linux/omarchy_linux.efi$' "$limine_config" ||
  fail "an unverified kernel replaces the working boot entry"
pass "a newly installed kernel is not selected before its driver and image verification"

touch "$test_tmp/kernel-verified"
run_dualboot --windows-partuuid 85197C7F-189B-499D-A385-B498F595BE81 || fail "the verified kernel can be selected"
grep -q '^path: boot():/EFI/Linux/omarchy_linux-omarchy.efi$' "$limine_config" ||
  fail "dual-boot restoration switches back to the old kernel after migration"
grep -q '^path: guid(85197c7f-189b-499d-a385-b498f595be81):/EFI/Microsoft/Boot/bootmgfw.efi$' "$limine_config" ||
  fail "selecting the new kernel loses Windows"
[[ -f $boot_dir/EFI/Linux/omarchy_linux.efi ]] || fail "the recovery kernel image is removed"
grep -q 'initramfs_async=0 systemd.tty.term.console=dumb$' "$limine_config" ||
  fail "the flat menu discards the new kernel's boot fixes"
pass "the flat menu selects the verified Omarchy kernel and preserves Windows and the old image"

cp "$limine_config" "$test_tmp/verified-menu"
if KERNEL_CMDLINE_FAIL=1 run_dualboot --windows-partuuid 85197C7F-189B-499D-A385-B498F595BE81; then
  fail "an unreadable kernel command line passes validation"
fi
cmp -s "$limine_config" "$test_tmp/verified-menu" || fail "a command-line failure overwrites the menu"
pass "the new kernel command line is required before replacing the menu"

rm "$boot_dir/EFI/Linux/omarchy_linux-omarchy.efi"
if run_dualboot --windows-partuuid 85197C7F-189B-499D-A385-B498F595BE81; then
  fail "a missing verified boot image passes validation"
fi
cmp -s "$limine_config" "$test_tmp/verified-menu" || fail "a missing boot image overwrites the menu"
pass "a missing verified boot image fails before replacing the menu"
