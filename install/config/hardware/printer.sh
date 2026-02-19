enable_service_with_warning() {
  local unit="$1"
  if ! chrootable_systemctl_enable "$unit"; then
    echo "Warning: failed to enable/start $unit" >&2
  fi
}

enable_service_with_warning cups.service

# Disable multicast dns in resolved. Avahi will provide this for better network printer discovery
sudo mkdir -p /etc/systemd/resolved.conf.d
echo -e "[Resolve]\nMulticastDNS=no" | sudo tee /etc/systemd/resolved.conf.d/10-disable-multicast.conf
enable_service_with_warning avahi-daemon.service

# Enable mDNS resolution for .local domains
sudo sed -i 's/^hosts:.*/hosts: mymachines mdns_minimal [NOTFOUND=return] resolve files myhostname dns/' /etc/nsswitch.conf

# Enable automatically adding remote printers
if [[ ! -f /etc/cups/cups-browsed.conf ]]; then
  echo 'CreateRemotePrinters Yes' | sudo tee /etc/cups/cups-browsed.conf >/dev/null
elif ! grep -q '^CreateRemotePrinters Yes' /etc/cups/cups-browsed.conf; then
  echo 'CreateRemotePrinters Yes' | sudo tee -a /etc/cups/cups-browsed.conf
fi

enable_service_with_warning cups-browsed.service
