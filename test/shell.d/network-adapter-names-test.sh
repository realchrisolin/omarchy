#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

names_script="$ROOT/bin/omarchy-network-adapter-names"
stub_dir=$(mktemp -d)
trap 'rm -rf "$stub_dir"' EXIT

cat >"$stub_dir/omarchy-cmd-present" <<'STUB'
#!/bin/bash
command -v "$1" >/dev/null
STUB

cat >"$stub_dir/nmcli" <<'STUB'
#!/bin/bash
case "$*" in
  "-t -f DEVICE,TYPE device status")
    printf '%s\n' \
      'wlp3s0:wifi:connected' \
      'wlp0s20u1:wifi:disconnected' \
      'wlgeneric:wifi:disconnected' \
      'wlboth:wifi:disconnected' \
      'enp0s1:ethernet:connected'
    ;;
  "-g GENERAL.VENDOR device show wlp3s0")
    printf 'Example Incorporated\n'
    ;;
  "-g GENERAL.PRODUCT device show wlp3s0")
    printf 'Wireless 9000\n'
    ;;
  "-g GENERAL.VENDOR device show wlp0s20u1")
    printf 'Acme\n'
    ;;
  "-g GENERAL.PRODUCT device show wlp0s20u1")
    printf 'Wireless_Device\n'
    ;;
  "-g GENERAL.VENDOR device show wlgeneric")
    printf 'Example\n'
    ;;
  "-g GENERAL.PRODUCT device show wlgeneric")
    printf 'Example Widget\n'
    ;;
  "-g GENERAL.VENDOR device show wlboth")
    printf 'Wireless Adapter\n'
    ;;
  "-g GENERAL.PRODUCT device show wlboth")
    printf '802.11\n'
    ;;
  *)
    exit 1
    ;;
esac
STUB

chmod +x "$stub_dir"/*
PATH="$stub_dir:$PATH" bash "$names_script" >"$stub_dir/output"

label_for() {
  awk -F '\t' -v iface="$1" '$1 == iface { print $2 }' "$stub_dir/output"
}

[[ $(label_for wlp3s0) == "Example Wireless 9000" ]] \
  || fail "specific product keeps the vendor" "got: $(label_for wlp3s0)"
pass "specific product keeps the vendor"

[[ $(label_for wlp0s20u1) == "Acme" ]] \
  || fail "generic product falls back to the vendor" "got: $(label_for wlp0s20u1)"
pass "generic product falls back to the vendor"

[[ $(label_for wlgeneric) == "Example Widget" ]] \
  || fail "vendor already inside the product is not repeated" "got: $(label_for wlgeneric)"
pass "vendor already inside the product is not repeated"

if awk -F '\t' '$1 == "wlboth" && $2 == "" { found = 1 } END { exit !found }' "$stub_dir/output"; then
  pass "generic vendor and product leave the label empty"
else
  fail "generic vendor and product leave the label empty" "output was: $(<"$stub_dir/output")"
fi

if awk -F '\t' '$1 == "enp0s1" { found = 1 } END { exit found }' "$stub_dir/output"; then
  pass "non-wifi devices are skipped"
else
  fail "non-wifi devices are skipped" "output was: $(<"$stub_dir/output")"
fi
