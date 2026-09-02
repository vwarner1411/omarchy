echo "Hold RabbitMQ at the Erlang 27-compatible release"

pacman_conf=/etc/pacman.conf
hold="IgnorePkg = rabbitmq"

has_rabbitmq_hold() {
  local ignored
  ignored=$(pacman-conf --config="$pacman_conf" IgnorePkg 2>/dev/null || true)
  grep -qxF "rabbitmq" <<<"$ignored"
}

if [[ ! -f $pacman_conf ]]; then
  echo "$pacman_conf does not exist; cannot protect RabbitMQ from an incompatible upgrade." >&2
  exit 1
fi

has_rabbitmq_hold && exit 0

if ! sudo sed -i "/^\[options\]$/a $hold" "$pacman_conf"; then
  echo "Administrator privileges are required to hold RabbitMQ. Run omarchy-migrate again from a terminal." >&2
  exit 1
fi

if ! has_rabbitmq_hold; then
  echo "Could not add the RabbitMQ hold to $pacman_conf." >&2
  exit 1
fi
