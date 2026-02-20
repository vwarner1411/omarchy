# in-place luks + limine runbook (omarchy + windows dual boot)

this runbook encrypts only linux root (`/dev/nvme0n1p6`) in place, keeps windows partitions untouched, backs up limine config first, and sets a flat limine menu with:

- `Omarchy`
- `Windows 11`

## prerequisites

- full disk image backup first (clonezilla)
- boot from partedmagic/live environment (not the installed root)
- confirm partition layout still matches:
  - windows esp: `/dev/nvme0n1p1`
  - omarchy boot esp: `/dev/nvme0n1p5`
  - omarchy root: `/dev/nvme0n1p6`

## 1) preflight (read-only checks)

```bash
set -euo pipefail

DISK=/dev/nvme0n1
WIN_ESP=${DISK}p1
BOOT_ESP=${DISK}p5
ROOT_PART=${DISK}p6
MAPPER=cryptroot

[[ -d /sys/firmware/efi/efivars ]] && echo "UEFI mode" || { echo "not UEFI"; exit 1; }

lsblk -f "$DISK"
blkid "$WIN_ESP" "$BOOT_ESP" "$ROOT_PART"

mkdir -p /mnt
mount "$ROOT_PART" /mnt
btrfs filesystem usage /mnt
umount /mnt
```

## 2) create tail slack for luks datashift

```bash
mount "$ROOT_PART" /mnt
btrfs filesystem resize -256M /mnt
umount /mnt
```

## 3) in-place encrypt root (long step)

```bash
cryptsetup reencrypt --encrypt --type luks2 \
  --pbkdf argon2id --iter-time 4000 \
  --reduce-device-size 32M \
  --progress-frequency 10 \
  "$ROOT_PART"
```

if interrupted:

```bash
cryptsetup reencrypt --resume-only "$ROOT_PART"
```

## 4) open encrypted root and mount system

```bash
cryptsetup open "$ROOT_PART" "$MAPPER"

mount "/dev/mapper/$MAPPER" /mnt
mkdir -p /mnt/boot /mnt/win_esp
mount "$BOOT_ESP" /mnt/boot
mount "$WIN_ESP" /mnt/win_esp
```

## 5) backup limine config + luks header

```bash
TS=$(date +%F_%H%M%S)
mkdir -p /mnt/boot/backup-"$TS"

cp -av /mnt/boot/limine.conf /mnt/boot/backup-"$TS"/limine.conf.bak
cp -av /mnt/etc/default/limine /mnt/boot/backup-"$TS"/default.limine.bak
cryptsetup luksHeaderBackup "$ROOT_PART" --header-backup-file /mnt/boot/backup-"$TS"/nvme0n1p6.luks2.header
```

also copy `/mnt/boot/backup-$TS/` to external media before reboot.

## 6) update kernel cmdline for encrypted root

```bash
LUKS_UUID=$(blkid -s UUID -o value "$ROOT_PART")
WIN_GUID=$(blkid -s PARTUUID -o value "$WIN_ESP")

sed -i "s|^KERNEL_CMDLINE\\[default\\].*|KERNEL_CMDLINE[default]=\"cryptdevice=UUID=${LUKS_UUID}:${MAPPER} root=/dev/mapper/${MAPPER} zswap.enabled=0 rw rootfstype=btrfs\"|" /mnt/etc/default/limine
```

## 7) chroot and rebuild boot artifacts

```bash
for d in dev proc sys run; do
  mount --rbind /$d /mnt/$d
  mount --make-rslave /mnt/$d
done

chroot /mnt /bin/bash -c '
set -euo pipefail
if [[ ! -f /etc/mkinitcpio.conf.d/omarchy_hooks.conf ]] || ! grep -q " encrypt " /etc/mkinitcpio.conf.d/omarchy_hooks.conf; then
  cat > /etc/mkinitcpio.conf.d/omarchy_hooks.conf <<EOF
HOOKS=(base udev plymouth keyboard autodetect microcode modconf kms keymap consolefont block encrypt filesystems fsck btrfs-overlayfs)
EOF
fi
limine-mkinitcpio
'

for d in run sys proc dev; do
  umount -R /mnt/$d
done
```

## 8) replace limine.conf with a flat menu (omarchy + windows)

```bash
cat > /mnt/boot/limine.conf <<EOF
timeout: 5
default_entry: 1
interface_branding: Omarchy Bootloader
interface_branding_color: 2
hash_mismatch_panic: no

term_background: 1a1b26
backdrop: 1a1b26
term_palette: 15161e;f7768e;9ece6a;e0af68;7aa2f7;bb9af7;7dcfff;a9b1d6
term_palette_bright: 414868;f7768e;9ece6a;e0af68;7aa2f7;bb9af7;7dcfff;c0caf5
term_foreground: c0caf5
term_foreground_bright: c0caf5
term_background_bright: 24283b

/Omarchy
protocol: linux
kernel_path: boot():/vmlinuz-linux
cmdline: cryptdevice=UUID=${LUKS_UUID}:${MAPPER} root=/dev/mapper/${MAPPER} zswap.enabled=0 rw rootfstype=btrfs quiet splash
module_path: boot():/intel-ucode.img
module_path: boot():/initramfs-linux.img

/Windows 11
protocol: efi
path: guid(${WIN_GUID}):/EFI/Microsoft/Boot/bootmgfw.efi
EOF

ls -l /mnt/win_esp/EFI/Microsoft/Boot/bootmgfw.efi
```

## 9) optional autologin disable

```bash
rm -f /mnt/etc/sddm.conf.d/autologin.conf
```

## 10) cleanup and reboot

```bash
umount -R /mnt
cryptsetup close "$MAPPER"
reboot
```

## rollback if boot fails

- boot live media
- mount `/dev/nvme0n1p5` at `/mnt/boot`
- restore `/mnt/boot/backup-<timestamp>/limine.conf.bak` to `/mnt/boot/limine.conf`
- verify `/mnt/boot/vmlinuz-linux` and `/mnt/boot/initramfs-linux.img` exist
- if needed, restore full clonezilla image
