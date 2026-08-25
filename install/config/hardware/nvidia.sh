if lspci | grep -qi 'nvidia'; then
  # Check which kernel is installed and set appropriate headers package
  KERNEL_HEADERS="$(pacman -Qq | grep -E '^linux(-zen|-lts|-hardened)?-headers$' | head -1)"
  if [[ -z $KERNEL_HEADERS ]]; then
    KERNEL_HEADERS="linux-headers"
  fi

  if omarchy-hw-nvidia-gsp; then
    PACKAGES=(nvidia-open-dkms nvidia-utils lib32-nvidia-utils libva-nvidia-driver)
    CONFLICTING_PACKAGES=(nvidia-dkms nvidia-580xx-dkms nvidia-580xx-utils lib32-nvidia-580xx-utils)
    GPU_ARCH="turing_plus"
  elif omarchy-hw-nvidia-without-gsp; then
    PACKAGES=(nvidia-580xx-dkms nvidia-580xx-utils lib32-nvidia-580xx-utils)
    CONFLICTING_PACKAGES=(nvidia-dkms nvidia-open-dkms nvidia-utils lib32-nvidia-utils libva-nvidia-driver)
    GPU_ARCH="maxwell_pascal_volta"
  fi

  # Bail if no supported GPU
  if [[ -z ${PACKAGES+x} ]]; then
    echo "No compatible driver for your NVIDIA GPU. See: https://wiki.archlinux.org/title/NVIDIA"
    exit 0
  fi

  # Remove conflicting NVIDIA family packages first so re-runs stay idempotent.
  remove_packages=()
  for pkg in "${CONFLICTING_PACKAGES[@]}"; do
    if pacman -Q "$pkg" &>/dev/null; then
      remove_packages+=("$pkg")
    fi
  done
  if (( ${#remove_packages[@]} > 0 )); then
    sudo pacman -Rns --noconfirm "${remove_packages[@]}"
  fi

  omarchy-pkg-add "$KERNEL_HEADERS" "${PACKAGES[@]}"

  # Configure modprobe for early KMS
  sudo tee /etc/modprobe.d/nvidia.conf <<EOF >/dev/null
options nvidia_drm modeset=1
EOF

  # Configure mkinitcpio for early loading only if modules are currently available.
  if modinfo nvidia &>/dev/null; then
    sudo tee /etc/mkinitcpio.conf.d/nvidia.conf <<EOF >/dev/null
MODULES+=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)
EOF
  else
    echo "Warning: NVIDIA kernel modules are not available yet. Skipping mkinitcpio NVIDIA module preload."
    sudo rm -f /etc/mkinitcpio.conf.d/nvidia.conf
  fi

  # Add NVIDIA environment variables based on GPU architecture
  mkdir -p "$HOME/.config/hypr"
  touch "$HOME/.config/hypr/envs.lua"

  if [[ $GPU_ARCH == "turing_plus" ]]; then
    # Turing+ (RTX 20xx, GTX 16xx, and newer) with GSP firmware support
    if ! grep -q "NVIDIA (Turing+ with GSP firmware)" "$HOME/.config/hypr/envs.lua"; then
      cat >>"$HOME/.config/hypr/envs.lua" <<'EOF'

-- NVIDIA (Turing+ with GSP firmware)
hl.env("NVD_BACKEND", "direct")
hl.env("LIBVA_DRIVER_NAME", "nvidia")
hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
EOF
    fi
  elif [[ $GPU_ARCH == "maxwell_pascal_volta" ]]; then
    # Maxwell/Pascal/Volta (GTX 9xx/10xx, GT 10xx, Quadro P/M/GV, MX series, Titan X/Xp/V) lack GSP firmware
    if ! grep -q "NVIDIA (Maxwell/Pascal/Volta without GSP firmware)" "$HOME/.config/hypr/envs.lua"; then
      cat >>"$HOME/.config/hypr/envs.lua" <<'EOF'

-- NVIDIA (Maxwell/Pascal/Volta without GSP firmware)
hl.env("NVD_BACKEND", "egl")
hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
EOF
    fi
  fi
fi
