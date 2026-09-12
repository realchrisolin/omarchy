#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

PLUGIN="$ROOT/shell/plugins/panels/monitor"
PLUGIN_BIN="$PLUGIN/bin"

[[ -x $PLUGIN_BIN/monitor-state ]] || fail "miracast monitor-state helper exists"
[[ -x $PLUGIN_BIN/miracast-ctl ]] || fail "miracast-ctl exists"
[[ -x $PLUGIN_BIN/monitor-scale ]] || fail "monitor-scale exists"
[[ -f $PLUGIN/Model.js ]] || fail "monitor Model.js exists"
pass "miracast monitor plugin helpers are present"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
home_dir="$test_tmp/home"
state_dir="$home_dir/.local/state/omarchy-miracast"
config_dir="$home_dir/.config/omarchy-miracast"
monitors_file="$test_tmp/monitors.json"
hypr_log="$test_tmp/hyprctl.log"
ctl_log="$test_tmp/miracast-ctl.log"

mkdir -p "$stub_bin" "$state_dir" "$config_dir" "$home_dir/.config/hypr"

# --- helpers extracted from miracast-ctl (bash functions are not a public CLI) ---
extract_fn() {
  local name="$1" dest="$2"
  # Inclusive from "name() {" through the closing "}" of that function.
  awk -v fn="$name" '
    $0 ~ "^" fn "\\(\\) \\{$" {grab=1}
    grab {print}
    grab && $0 == "}" {exit}
  ' "$PLUGIN_BIN/miracast-ctl" >"$dest"
  [[ -s $dest ]] || fail "extracted function $name"
}

extract_fn sanitize_extend_output_name "$test_tmp/sanitize.sh"
extract_fn unique_extend_output_name "$test_tmp/unique.sh"
extract_fn extend_geometry_parts "$test_tmp/geometry.sh"
extract_fn extend_resolution "$test_tmp/extend_res.sh"
extract_fn capture_senders_alive "$test_tmp/senders.sh"

# --- stub hyprctl / brightness / scaling ---
cat >"$stub_bin/hyprctl" <<'SH'
#!/bin/bash
echo "$*" >>"${OMARCHY_TEST_HYPR_LOG:-/dev/null}"
# miracast-ctl uses both `hyprctl -j monitors` and `hyprctl monitors all -j`.
if [[ ( $1 == "-j" && $2 == "monitors" ) || ( $1 == "monitors" && $2 == "-j" ) || ( $1 == "monitors" && $2 == "all" && $3 == "-j" ) ]]; then
  cat "${OMARCHY_TEST_MONITORS:?}"
  exit 0
fi
if [[ $1 == "eval" ]]; then
  printf '%s\n' "$2" >>"${OMARCHY_TEST_HYPR_LOG:-/dev/null}"
  exit 0
fi
if [[ $1 == "dispatch" ]]; then
  exit 0
fi
if [[ $1 == "output" ]]; then
  exit 0
fi
exit 1
SH
chmod +x "$stub_bin/hyprctl"

cat >"$stub_bin/omarchy-brightness-display" <<'SH'
#!/bin/bash
echo 55
SH
chmod +x "$stub_bin/omarchy-brightness-display"

cat >"$stub_bin/omarchy-hyprland-monitor-scaling" <<'SH'
#!/bin/bash
echo 1
SH
chmod +x "$stub_bin/omarchy-hyprland-monitor-scaling"

# Recording stub for miracast-ctl when monitor-scale invokes pause/ensure.
cat >"$stub_bin/miracast-ctl" <<'SH'
#!/bin/bash
echo "$*" >>"${OMARCHY_TEST_CTL_LOG:?}"
case "${1:-}" in
  pause-capture|pause_capture) echo 'paused=0' ;;
  ensure-capture|ensure_capture) echo '{"ok":true,"captureHealthy":true}' ;;
  restart-capture|restart_capture) echo '{"ok":true,"captureRestarted":true,"captureHealthy":true}' ;;
  *) echo '{"ok":true}' ;;
esac
SH
chmod +x "$stub_bin/miracast-ctl"

export PATH="$stub_bin:$PATH"
export HOME="$home_dir"
export XDG_STATE_HOME="$home_dir/.local/state"
export XDG_CONFIG_HOME="$home_dir/.config"
export OMARCHY_TEST_MONITORS="$monitors_file"
export OMARCHY_TEST_HYPR_LOG="$hypr_log"
export OMARCHY_TEST_CTL_LOG="$ctl_log"

# ========== monitor-state ==========
miracast_monitors='[
  {"name":"eDP-1","mirrorOf":"none","disabled":false,"focused":true,"width":1920,"height":1080,"scale":1,"refreshRate":60,"x":0,"y":0},
  {"name":"hotyeah-8D5117_P2P","mirrorOf":"none","disabled":false,"focused":false,"width":1920,"height":1080,"scale":1,"refreshRate":30,"x":-1920,"y":0},
  {"name":"DP-1","mirrorOf":"none","disabled":false,"focused":false,"width":2560,"height":1440,"scale":1,"refreshRate":60,"x":1920,"y":0}
]'
printf '%s\n' "hotyeah-8D5117_P2P" >"$state_dir/headless.name"
printf '%s\n' "$miracast_monitors" >"$monitors_file"

mapfile -t state_lines < <(bash "$PLUGIN_BIN/monitor-state" 2>/dev/null)
(( ${#state_lines[@]} == 8 )) || fail "monitor-state answers 8 lines with Miracast present" "got ${#state_lines[@]}"
[[ ${state_lines[0]} == 55 ]] || fail "monitor-state reports brightness" "got ${state_lines[0]-}"
[[ ${state_lines[1]} == eDP-1 ]] || fail "monitor-state internal ignores Miracast output" "got ${state_lines[1]-}"
[[ ${state_lines[2]} == DP-1 ]] || fail "monitor-state external ignores Miracast output" "got ${state_lines[2]-}"
[[ ${state_lines[5]} == eDP-1 ]] || fail "monitor-state focused monitor" "got ${state_lines[5]-}"

python3 - "${state_lines[7]}" <<'PY' || fail "monitor-state JSON marks Miracast output"
import json, sys
rows = json.loads(sys.argv[1])
by = {r["name"]: r for r in rows}
assert by["hotyeah-8D5117_P2P"]["miracast"] is True
assert by["eDP-1"]["miracast"] is False
assert by["DP-1"]["miracast"] is False
assert by["hotyeah-8D5117_P2P"]["brightnessAvailable"] is False
assert by["eDP-1"]["brightnessAvailable"] is True
assert by["eDP-1"]["brightness"] == 55
PY
pass "monitor-state excludes Miracast from wired roles and flags it in JSON"

# ========== sanitize / unique naming ==========
# shellcheck source=/dev/null
source "$test_tmp/sanitize.sh"
[[ $(sanitize_extend_output_name 'hotyeah 8D5117_P2P' 'DE:84:03:8D:51:17') == 'hotyeah-8D5117_P2P' ]] ||
  fail "sanitize collapses spaces and keeps safe chars"
[[ $(sanitize_extend_output_name '!!!' 'DE:84:03:8D:51:17') == 'Miracast-8D5117' ]] ||
  fail "sanitize falls back to MAC suffix when name is empty after scrub"
[[ $(sanitize_extend_output_name 'a/b\\c*d?' '') == 'abcd' ]] ||
  fail "sanitize strips unsafe characters"
pass "sanitize_extend_output_name scrubs peer names safely"

# shellcheck source=/dev/null
source "$test_tmp/unique.sh"
printf '%s\n' '[{"name":"Miracast-ABC"},{"name":"eDP-1"}]' >"$monitors_file"
[[ $(unique_extend_output_name 'Miracast-ABC' '') == 'Miracast-ABC-2' ]] ||
  fail "unique_extend_output_name appends -2 when desired name exists"
[[ $(unique_extend_output_name 'Miracast-ABC' 'Miracast-ABC') == 'Miracast-ABC' ]] ||
  fail "unique_extend_output_name allows replacing the same output"
pass "unique_extend_output_name avoids colliding Hyprland output names"

# ========== extend geometry ==========
# shellcheck source=/dev/null
source "$test_tmp/extend_res.sh"
# shellcheck source=/dev/null
source "$test_tmp/geometry.sh"
# Override paths the sourced functions close over via globals in miracast-ctl.
HEADLESS_FILE="$state_dir/headless.name"
SETTINGS_FILE="$config_dir/settings.json"
printf '%s\n' '{"extendResolution":"1920x1080","extendRefresh":"30","fps":"30"}' >"$SETTINGS_FILE"
printf '%s\n' 'hotyeah-8D5117_P2P' >"$HEADLESS_FILE"
printf '%s\n' '[
  {"name":"eDP-1","focused":true,"width":1920,"height":1080,"scale":2,"x":0,"y":0},
  {"name":"hotyeah-8D5117_P2P","focused":false,"width":1920,"height":1080,"scale":1,"x":-1920,"y":0}
]' >"$monitors_file"

# eDP scale 2 => logical 960 wide; extend 1920x1080 @ scale 1 => logical 1920.
# right => x=960; left => x=-1920
parts="$(extend_geometry_parts right)"
[[ $parts == '1920x1080@30|960x0|1' ]] || fail "extend geometry right beside scaled eDP" "got $parts"
parts="$(extend_geometry_parts left)"
[[ $parts == '1920x1080@30|-1920x0|1' ]] || fail "extend geometry left beside scaled eDP" "got $parts"
pass "extend_geometry_parts places Extend using logical sizes"

# ========== capture_senders_alive ==========
# shellcheck source=/dev/null
source "$test_tmp/senders.sh"
HEADLESS_FILE="$state_dir/headless.name"
alive="$(capture_senders_alive)"
[[ $alive == false ]] || fail "capture_senders_alive is false without wf-recorder/ffmpeg" "got $alive"
pass "capture_senders_alive reports false when no senders exist"

# ========== monitor-scale eDP with live Miracast: pause before remap ==========
: >"$hypr_log"
: >"$ctl_log"
printf '%s\n' 'hotyeah-8D5117_P2P' >"$state_dir/headless.name"
printf '%s\n' '{"extendPosition":"right","extendResolution":"1920x1080","extendRefresh":"30","fps":"30"}' >"$config_dir/settings.json"
printf '%s\n' '[
  {"name":"eDP-1","focused":true,"width":1920,"height":1080,"scale":1,"refreshRate":60,"x":0,"y":0},
  {"name":"hotyeah-8D5117_P2P","focused":false,"width":1920,"height":1080,"scale":2,"refreshRate":30,"x":1920,"y":0}
]' >"$monitors_file"
cat >"$home_dir/.config/hypr/monitors.lua" <<'LUA'
local omarchy_gdk_scale = 1
local omarchy_monitor_scale = 1
LUA

# Put recording miracast-ctl on PATH ahead of everything; monitor-scale resolves
# CTL next to itself, so point it at a wrapper copy beside a fake plugin bin.
fake_plugin_bin="$test_tmp/fake-plugin/bin"
mkdir -p "$fake_plugin_bin"
cp "$PLUGIN_BIN/monitor-scale" "$fake_plugin_bin/monitor-scale"
cp "$stub_bin/miracast-ctl" "$fake_plugin_bin/miracast-ctl"
chmod +x "$fake_plugin_bin"/*

scale_out="$(
  HOME="$home_dir" \
    XDG_STATE_HOME="$home_dir/.local/state" \
    XDG_CONFIG_HOME="$home_dir/.config" \
    PATH="$stub_bin:$PATH" \
    OMARCHY_TEST_MONITORS="$monitors_file" \
    OMARCHY_TEST_HYPR_LOG="$hypr_log" \
    OMARCHY_TEST_CTL_LOG="$ctl_log" \
    bash "$fake_plugin_bin/monitor-scale" eDP-1 2
)"
[[ $scale_out == 2 ]] || fail "monitor-scale reports cleaned scale" "got $scale_out"

# pause-capture must be recorded before any hyprctl eval for the eDP remap.
first_ctl="$(awk 'NR==1{print; exit}' "$ctl_log")"
[[ $first_ctl == pause-capture* || $first_ctl == pause_capture* ]] ||
  fail "monitor-scale pauses capture before eDP remap when Miracast is live" "first ctl: ${first_ctl:-<empty>}"

grep -E 'ensure-capture|ensure_capture' "$ctl_log" >/dev/null ||
  fail "monitor-scale ensures capture after eDP scale settle"

# Reseat must force Extend scale back to 1 (not inherit eDP's 2).
grep -F 'scale = 1' "$hypr_log" >/dev/null ||
  fail "monitor-scale reseat forces Extend output scale 1" "hypr log: $(cat "$hypr_log")"
pass "monitor-scale pauses before eDP remap and ensures capture with Extend scale 1"

# ========== Model.js Miracast helpers ==========
run_node_test <<JS
const Model = require(path.join(root, 'shell/plugins/panels/monitor/Model.js'))

assertEqual(Model.miracastPhaseLabel('streaming'), 'Mirroring', 'phase label for streaming')
assertEqual(Model.miracastIsActive('streaming'), true, 'streaming is active')
assertEqual(Model.miracastIsActive('idle'), false, 'idle is inactive')
assertEqual(
  Model.miracastConnectionSummary('streaming', 'hotyeah-8D5117_P2P', 'DE:84', 'extend'),
  'Connected · hotyeah-8D5117_P2P · Extend',
  'connection summary while streaming extend'
)
assertEqual(
  Model.miracastDoctorSummary({ ready: true, warn_count: 2 }),
  'Ready with 2 warnings',
  'doctor summary with warnings'
)
assertEqual(
  Model.miracastDoctorSummary({ ready: false, fail_count: 1 }),
  '1 blocking issue',
  'doctor summary with failures'
)

const parsed = Model.parseDisplays(JSON.stringify([
  { name: 'eDP-1', enabled: true, focused: true, width: 1920, height: 1080, miracast: false },
  { name: 'hotyeah-8D5117_P2P', enabled: true, focused: false, width: 1920, height: 1080, miracast: true }
]))
assertEqual(parsed.enabledDisplayCount, 2, 'parseDisplays counts enabled displays')
assertEqual(parsed.displays[1].miracast, true, 'parseDisplays preserves miracast flag')
JS

pass "miracast monitor regression coverage"
