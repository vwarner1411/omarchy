echo "Remove retired RabbitMQ and Erlang package holds"

pacman_conf=/etc/pacman.conf
staged=$(mktemp)
trap 'rm -f "$staged"' EXIT

awk '
  /^[[:space:]]*IgnorePkg[[:space:]]*=/ {
    sub(/^[[:space:]]*IgnorePkg[[:space:]]*=[[:space:]]*/, "")
    comment = ""
    if (match($0, /[[:space:]]*#/)) {
      comment = substr($0, RSTART)
      $0 = substr($0, 1, RSTART - 1)
    }
    kept = ""
    count = split($0, packages, /[[:space:]]+/)
    for (i = 1; i <= count; i++) {
      package = packages[i]
      if (package == "" || package == "rabbitmq" || package == "erlang" || package == "erlang-*") continue
      kept = kept (kept == "" ? "" : " ") package
    }
    if (kept != "") print "IgnorePkg = " kept comment
    else if (comment != "") print comment
    next
  }
  { print }
' "$pacman_conf" >"$staged"

if ! cmp -s "$pacman_conf" "$staged"; then
  sudo cp -a "$pacman_conf" "$pacman_conf.before-rabbitmq-hold-removal"
  sudo install -m 0644 -o root -g root "$staged" "$pacman_conf"
fi
