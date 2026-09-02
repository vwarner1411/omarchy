echo "Hold Erlang at the RabbitMQ-supported release"

pacman_conf=/etc/pacman.conf
hold="IgnorePkg = erlang erlang-*"

has_erlang_hold() {
  local ignored
  ignored=$(pacman-conf --config="$pacman_conf" IgnorePkg 2>/dev/null || true)
  grep -qxF "erlang" <<<"$ignored" && grep -qxF "erlang-*" <<<"$ignored"
}

if [[ ! -f $pacman_conf ]]; then
  echo "$pacman_conf does not exist; cannot protect RabbitMQ from an unsupported Erlang upgrade." >&2
  exit 1
fi

has_erlang_hold && exit 0

if ! sudo sed -i "/^\[options\]$/a $hold" "$pacman_conf"; then
  echo "Administrator privileges are required to hold Erlang. Run omarchy-migrate again from a terminal." >&2
  exit 1
fi

if ! has_erlang_hold; then
  echo "Could not add the Erlang hold to $pacman_conf." >&2
  exit 1
fi
