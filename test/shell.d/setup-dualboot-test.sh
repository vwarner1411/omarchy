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

chmod +x "$stub_bin"/*

dualboot_under_test="$test_tmp/omarchy-setup-dualboot"
sed \
  -e "s#/boot/#$boot_dir/#g" \
  -e "s#/etc/machine-id#$test_tmp/machine-id#g" \
  -e "s#/etc/default/limine#$test_tmp/default-limine#g" \
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
