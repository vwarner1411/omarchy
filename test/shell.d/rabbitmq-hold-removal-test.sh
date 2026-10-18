#!/bin/bash

set -euo pipefail
source "$(dirname "$0")/base-test.sh"
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
mkdir "$scratch/bin"

cat >"$scratch/bin/sudo" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$TEST_LOG"
case "$1" in
  cp) exec "$@" ;;
  install) exec install -m 0644 "${@: -2}" ;;
  *) exit 99 ;;
esac
SH
chmod +x "$scratch/bin/sudo"
sed "s|pacman_conf=/etc/pacman.conf|pacman_conf=$scratch/pacman.conf|" \
  "$ROOT/migrations/1788741028.sh" >"$scratch/migration.sh"

cat >"$scratch/pacman.conf" <<'CONF'
[options]
IgnorePkg = rabbitmq
IgnorePkg = erlang erlang-*
IgnorePkg = firefox rabbitmq vim erlang erlang-* # keep rabbitmq in this comment
Architecture = auto
[omarchy]
Server = https://example.test/stable/$arch
CONF
cp "$scratch/pacman.conf" "$scratch/original"
export TEST_LOG="$scratch/calls"
export PATH="$scratch/bin:$PATH"
bash -euo pipefail "$scratch/migration.sh"
grep -Fxq 'IgnorePkg = firefox vim # keep rabbitmq in this comment' "$scratch/pacman.conf" ||
  fail "retiring broker holds preserves unrelated holds and comments"
[[ $(grep -c '^IgnorePkg' "$scratch/pacman.conf") == 1 ]] || fail "empty hold directives are removed"
cmp -s "$scratch/original" "$scratch/pacman.conf.before-rabbitmq-hold-removal" || fail "the original pacman config is backed up"
grep -Fxq 'Server = https://example.test/stable/$arch' "$scratch/pacman.conf" || fail "repository settings survive"
pass "retiring RabbitMQ removes only its package holds and preserves the original config"

: >"$TEST_LOG"
bash -euo pipefail "$scratch/migration.sh"
[[ ! -s $TEST_LOG ]] || fail "repeat hold cleanup modifies the system"
pass "retired hold cleanup is idempotent"

for channel in stable rc edge; do
  ! pacman-conf --config="$ROOT/default/pacman/pacman-$channel.conf" IgnorePkg 2>/dev/null |
    grep -Eq '^rabbitmq$|^erlang$|^erlang-\*$' || fail "a channel still holds retired broker packages"
done
pass "no package channel recreates the retired broker holds"
