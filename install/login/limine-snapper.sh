EFI=""
CMDLINE=""

if command -v limine &>/dev/null; then
  sudo tee /etc/mkinitcpio.conf.d/omarchy_hooks.conf <<EOF >/dev/null
HOOKS=(base udev plymouth keyboard autodetect microcode modconf kms keymap consolefont block encrypt filesystems fsck btrfs-overlayfs)
EOF
  sudo tee /etc/mkinitcpio.conf.d/thunderbolt_module.conf <<EOF >/dev/null
MODULES+=(thunderbolt)
EOF

  # Detect boot mode
  if [[ -d /sys/firmware/efi ]]; then
    EFI=true
  fi

  # In EFI mode we expect /boot to be the mounted ESP.
  if [[ -n $EFI ]]; then
    boot_fstype="$(findmnt -n -o FSTYPE /boot 2>/dev/null || true)"
    if [[ $boot_fstype != "vfat" ]]; then
      echo "Error: /boot is not a vfat ESP mount (found '$boot_fstype'). Refusing to rewrite Limine config." >&2
      exit 1
    fi
  fi

  # Find config location
  if [[ -f /boot/limine.conf ]]; then
    limine_config="/boot/limine.conf"
  elif [[ -f /boot/EFI/arch-limine/limine.conf ]]; then
    limine_config="/boot/EFI/arch-limine/limine.conf"
  elif [[ -f /boot/EFI/BOOT/limine.conf ]]; then
    limine_config="/boot/EFI/BOOT/limine.conf"
  elif [[ -f /boot/EFI/limine/limine.conf ]]; then
    limine_config="/boot/EFI/limine/limine.conf"
  elif [[ -f /boot/limine/limine.conf ]]; then
    limine_config="/boot/limine/limine.conf"
  else
    echo "Error: Limine config not found" >&2
    exit 1
  fi

  CMDLINE="$(grep "^[[:space:]]*cmdline:" "$limine_config" | head -1 | sed 's/^[[:space:]]*cmdline:[[:space:]]*//' || true)"
  if [[ -z $CMDLINE ]] && [[ -r /proc/cmdline ]]; then
    CMDLINE="$(sed -E 's/(^| )BOOT_IMAGE=[^ ]+//g; s/^ +//; s/ +$//' /proc/cmdline)"
  fi

  if [[ -z $CMDLINE ]]; then
    CMDLINE="rw"
  fi

  # Write /etc/default/limine before installing limine-mkinitcpio-hook, whose
  # post-transaction deploy hook reads this file while building entries.
  escaped_cmdline="$(printf '%s\n' "$CMDLINE" | sed 's/[&|]/\\&/g')"
  sudo cp "$OMARCHY_PATH/default/limine/default.conf" /etc/default/limine
  sudo sed -i "s|@@CMDLINE@@|$escaped_cmdline|g" /etc/default/limine

  # Append any drop-in kernel cmdline configs (from hardware fix scripts, etc.)
  for dropin in /etc/limine-entry-tool.d/*.conf; do
    [[ -f $dropin ]] && sudo tee -a /etc/default/limine <"$dropin" >/dev/null
  done

  # UKI and EFI fallback are EFI only
  if [[ -z $EFI ]]; then
    sudo sed -i '/^ENABLE_UKI=/d; /^ENABLE_LIMINE_FALLBACK=/d' /etc/default/limine
  fi

  # Remove alternative config locations that can shadow /boot/limine.conf.
  sudo rm -f /boot/EFI/arch-limine/limine.conf
  sudo rm -f /boot/EFI/BOOT/limine.conf
  sudo rm -f /boot/EFI/limine/limine.conf
  sudo rm -f /boot/limine/limine.conf

  # Rebuild the canonical config knowing limine-update will repopulate the entries.
  sudo cp "$OMARCHY_PATH/default/limine/limine.conf" /boot/limine.conf

  sudo pacman -S --noconfirm --needed limine-snapper-sync limine-mkinitcpio-hook

  # Only snapshot root — /home is user data; rolling it back loses user work.
  if ! sudo snapper list-configs 2>/dev/null | grep -q "root"; then
    sudo snapper -c root create-config /
  fi
  sudo cp "$OMARCHY_PATH/default/snapper/root" /etc/snapper/configs/root

  # Disable btrfs quotas — full qgroup accounting is a major performance drag.
  sudo btrfs quota disable / 2>/dev/null || true

  chrootable_systemctl_enable limine-snapper-sync.service
fi

echo "Re-enabling mkinitcpio hooks..."

# Restore the specific mkinitcpio pacman hooks
if [[ -f /usr/share/libalpm/hooks/90-mkinitcpio-install.hook.disabled ]]; then
  sudo mv /usr/share/libalpm/hooks/90-mkinitcpio-install.hook.disabled /usr/share/libalpm/hooks/90-mkinitcpio-install.hook
fi

if [[ -f /usr/share/libalpm/hooks/60-mkinitcpio-remove.hook.disabled ]]; then
  sudo mv /usr/share/libalpm/hooks/60-mkinitcpio-remove.hook.disabled /usr/share/libalpm/hooks/60-mkinitcpio-remove.hook
fi

echo "mkinitcpio hooks re-enabled"

if command -v limine-update &>/dev/null; then
  sudo limine-update
fi

if [[ -f /boot/limine.conf ]] &&
  ! grep -Eq '^/(Omarchy|Arch Linux)' /boot/limine.conf &&
  ! grep -Eq '^[[:space:]]*protocol:[[:space:]]*linux' /boot/limine.conf; then
  echo "Warning: limine-update generated no Linux entry, adding direct fallback entry."
  direct_cmdline="$CMDLINE"
  if [[ $direct_cmdline != *quiet* ]]; then
    direct_cmdline="$direct_cmdline quiet splash"
  fi

  sudo tee -a /boot/limine.conf <<EOF >/dev/null

/Arch Linux (Direct Fallback)
protocol: linux
kernel_path: boot():/vmlinuz-linux
cmdline: $direct_cmdline
EOF

  if [[ -f /boot/intel-ucode.img ]]; then
    echo "module_path: boot():/intel-ucode.img" | sudo tee -a /boot/limine.conf >/dev/null
  fi

  if [[ -f /boot/amd-ucode.img ]]; then
    echo "module_path: boot():/amd-ucode.img" | sudo tee -a /boot/limine.conf >/dev/null
  fi

  echo "module_path: boot():/initramfs-linux.img" | sudo tee -a /boot/limine.conf >/dev/null
fi

# Verify that limine-update actually added an Omarchy-capable boot entry.
if [[ -f /boot/limine.conf ]] &&
  ! grep -Eq '^/(Omarchy|Arch Linux)' /boot/limine.conf &&
  ! grep -Eq '^[[:space:]]*protocol:[[:space:]]*linux' /boot/limine.conf; then
  echo "Error: limine-update failed to add boot entries to /boot/limine.conf" >&2
  exit 1
fi

if [[ -n $EFI ]] && efibootmgr &>/dev/null; then
  # Remove the archinstall-created Limine entry
  while IFS= read -r bootnum; do
    sudo efibootmgr -b "$bootnum" -B >/dev/null 2>&1
  done < <(efibootmgr | grep -E "^Boot[0-9]{4}\*? Arch Linux Limine" | sed 's/^Boot\([0-9]\{4\}\).*/\1/')
fi
