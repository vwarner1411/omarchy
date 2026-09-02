#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

migration="$ROOT/migrations/1788366977.sh"
hold="IgnorePkg = erlang erlang-*"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

for channel in stable rc edge; do
  config="$ROOT/default/pacman/pacman-$channel.conf"
  [[ $(grep -cFx "$hold" "$config") == 1 ]] ||
    fail "$channel pacman config holds Erlang exactly once"

  ignored=$(pacman-conf --config="$config" IgnorePkg)
  grep -qxF "erlang" <<<"$ignored" || fail "$channel pacman config holds the erlang package"
  grep -qxF "erlang-*" <<<"$ignored" || fail "$channel pacman config holds split Erlang packages"
done
pass "all pacman channels hold the unsupported Erlang upgrade"

stub_bin="$test_dir/bin"
config="$test_dir/pacman.conf"
test_migration="$test_dir/migration.sh"
mkdir -p "$stub_bin"

cat >"$stub_bin/sudo" <<'SH'
#!/bin/bash
exec "$@"
SH
chmod +x "$stub_bin/sudo"

prepare_migration() {
  cp "$migration" "$test_migration"
  sed -i "s|pacman_conf=/etc/pacman.conf|pacman_conf=$config|" "$test_migration"
}

write_config() {
  cat >"$config" <<'CONF'
[options]
HoldPkg = pacman glibc
Architecture = auto
CONF
}

run_migration() {
  PATH="$stub_bin:$PATH" bash -euo pipefail "$test_migration" >/dev/null
}

prepare_migration
write_config
run_migration || fail "migration adds the Erlang hold"
[[ $(grep -cFx "$hold" "$config") == 1 ]] || fail "migration writes one Erlang hold"
run_migration || fail "migration reruns after adding the Erlang hold"
[[ $(grep -cFx "$hold" "$config") == 1 ]] || fail "migration is idempotent"
pass "migration adds the Erlang hold idempotently"

cat >"$config" <<'CONF'
[options]
IgnorePkg = firefox erlang erlang-*
Architecture = auto
CONF
run_migration || fail "migration accepts an equivalent existing hold"
[[ $(grep -c '^IgnorePkg' "$config") == 1 ]] || fail "migration preserves an equivalent existing hold"
pass "migration recognizes an equivalent existing Erlang hold"

cat >"$stub_bin/sudo" <<'SH'
#!/bin/bash
exit 1
SH
write_config
if run_migration; then
  fail "migration must remain pending when privilege elevation fails"
fi
pass "migration retries when it cannot write pacman configuration"
