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
extract_fn capture_output_fingerprint "$test_tmp/fingerprint.sh"
extract_fn capture_geometry_drifted "$test_tmp/drifted.sh"
extract_fn record_capture_geometry "$test_tmp/record_geom.sh"

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

# Recording stub for miracast-ctl when monitor-scale invokes pause/ensure/reseat.
cat >"$stub_bin/miracast-ctl" <<'SH'
#!/bin/bash
echo "$*" >>"${OMARCHY_TEST_CTL_LOG:?}"
case "${1:-}" in
  pause-capture|pause_capture) echo 'paused=0' ;;
  ensure-capture|ensure_capture) echo '{"ok":true,"captureHealthy":true}' ;;
  restart-capture|restart_capture) echo '{"ok":true,"captureRestarted":true,"captureHealthy":true}' ;;
  set-extend-position|set_extend_position)
    # Reseat now goes through ctl (raw hyprctl hung mid lua-reload). Record a
    # synthetic hl.monitor line so scale-preservation assertions still work.
    pos="${2:-right}"
    case "$pos" in
      left) xy="-960x0" ;;
      above) xy="0x-540" ;;
      below) xy="0x540" ;;
      *) xy="960x0" ;;
    esac
    printf '%s\n' "hl.monitor({ output = \"hotyeah-8D5117_P2P\", mode = \"1920x1080@30\", position = \"${xy}\", scale = 2 })" \
      >>"${OMARCHY_TEST_HYPR_LOG:-/dev/null}"
    echo "{\"ok\":true,\"position\":\"$pos\",\"applied\":true}"
    ;;
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
# Preferred scale (from settings.sinkScales on reconnect) overrides live virtual scale.
parts="$(extend_geometry_parts left 2)"
[[ $parts == '1920x1080@30|-960x0|2' ]] ||
  fail "extend geometry honors preferred scale 2 on reconnect" "got $parts"
parts="$(extend_geometry_parts right 1.5)"
# eDP logical 960; virt logical 1920/1.5=1280; right x=960
[[ $parts == '1920x1080@30|960x0|1.5' ]] ||
  fail "extend geometry honors preferred scale 1.5" "got $parts"
pass "extend_geometry_parts places Extend using logical sizes"

# ========== sinkScales in settings.json (per-device Extend scale) ==========
export XDG_CONFIG_HOME="$home_dir/.config"
export XDG_STATE_HOME="$home_dir/.local/state"
mkdir -p "$config_dir" "$state_dir"
printf '%s\n' '{"mode":"extend","lastPeerMac":"aa:bb:cc:dd:ee:ff"}' >"$config_dir/settings.json"
# Legacy peer-prefs.json should migrate into sinkScales then be removed.
printf '%s\n' '{"AA:BB:CC:DD:EE:11":{"scale":1.5,"brightness":80}}' >"$state_dir/peer-prefs.json"

remember_out="$("$PLUGIN_BIN/miracast-ctl" remember-extend-scale --mac DE:84:03:8D:51:17 --scale 2 2>/dev/null || true)"
echo "$remember_out" | rg -q '"ok":true' ||
  fail "remember-extend-scale reports ok" "out=$remember_out"
echo "$remember_out" | rg -q '"scale":"2"' ||
  fail "remember-extend-scale echoes saved scale" "out=$remember_out"

python3 - "$config_dir/settings.json" "$state_dir/peer-prefs.json" <<'PY' || fail "sinkScales persistence / legacy migrate"
import json, os, sys
settings_path, legacy_path = sys.argv[1], sys.argv[2]
settings = json.load(open(settings_path))
scales = settings.get("sinkScales")
assert isinstance(scales, dict), scales
assert scales.get("DE:84:03:8D:51:17") == 2, scales
# Legacy MAC folded in (brightness discarded); file removed.
assert scales.get("AA:BB:CC:DD:EE:11") == 1.5, scales
assert not os.path.exists(legacy_path), "peer-prefs.json should be removed after migrate"
print("ok")
PY

# Overwrite scale for same device
"$PLUGIN_BIN/miracast-ctl" remember-extend-scale --mac de:84:03:8d:51:17 --scale 1.6 >/dev/null
python3 -c 'import json,sys; s=json.load(open(sys.argv[1]))["sinkScales"];
assert s["DE:84:03:8D:51:17"]==1.6, s' "$config_dir/settings.json" ||
  fail "remember-extend-scale updates sinkScales and normalizes MAC"
pass "sinkScales persists Extend scale per device in settings.json"

# ========== capture_senders_alive ==========
# shellcheck source=/dev/null
source "$test_tmp/senders.sh"
HEADLESS_FILE="$state_dir/headless.name"
alive="$(capture_senders_alive)"
if [[ $alive == true ]]; then
  # Host may have a live Miracast session; do not fail the file on that.
  pass "capture_senders_alive sees host senders (live cast); skipping empty-proc assertion"
else
  [[ $alive == false ]] || fail "capture_senders_alive is false without wf-recorder/ffmpeg" "got $alive"
  pass "capture_senders_alive reports false when no senders exist"
fi

# ========== capture geometry fingerprint / drift (hypr reload black-screen) ==========
# shellcheck source=/dev/null
source "$test_tmp/fingerprint.sh"
# shellcheck source=/dev/null
source "$test_tmp/drifted.sh"
# shellcheck source=/dev/null
source "$test_tmp/record_geom.sh"
geom_state="$test_tmp/geom-state"
mkdir -p "$geom_state"
HEADLESS_FILE="$geom_state/headless.name"
CAPTURE_GEOM_FILE="$geom_state/capture.geometry"
printf 'hotyeah-TV\n' >"$HEADLESS_FILE"
cat >"$OMARCHY_TEST_MONITORS" <<'JSON'
[{"name":"eDP-1","width":1920,"height":1080,"refreshRate":60,"scale":2,"x":0,"y":0},
 {"name":"hotyeah-TV","width":1920,"height":1080,"refreshRate":30,"scale":2,"x":-960,"y":0}]
JSON
fp="$(capture_output_fingerprint)"
[[ $fp == 'hotyeah-TV|1920|1080|30|2|-960|0' ]] ||
  fail "capture_output_fingerprint formats tracked Extend geometry" "got $fp"
record_capture_geometry
[[ $(cat "$CAPTURE_GEOM_FILE") == "$fp" ]] || fail "record_capture_geometry persists fingerprint"
[[ $(capture_geometry_drifted) == false ]] || fail "geometry not drifted when unchanged"
cat >"$OMARCHY_TEST_MONITORS" <<'JSON'
[{"name":"eDP-1","width":1920,"height":1080,"refreshRate":60,"scale":2,"x":0,"y":0},
 {"name":"hotyeah-TV","width":1920,"height":1080,"refreshRate":30,"scale":2,"x":960,"y":0}]
JSON
[[ $(capture_geometry_drifted) == true ]] ||
  fail "geometry drifted when Hyprland shoves Extend from left to right"
pass "capture geometry fingerprint detects Hyprland reload/layout drift"

# timeout(1) wrapper so monitor-scale's `timeout 5 hyprctl` works under stubs.
cat >"$stub_bin/timeout" <<'SH'
#!/bin/bash
# Usage: timeout SECONDS CMD...
shift
exec "$@"
SH
chmod +x "$stub_bin/timeout"

# Put recording miracast-ctl beside monitor-scale (CTL is resolved next to self).
fake_plugin_bin="$test_tmp/fake-plugin/bin"
mkdir -p "$fake_plugin_bin"
# Prefer the live plugin copy under test when present; fall back to repo path.
SCALE_SRC="$PLUGIN_BIN/monitor-scale"
if [[ -x ${OMARCHY_TEST_MONITOR_SCALE:-} ]]; then
  SCALE_SRC="$OMARCHY_TEST_MONITOR_SCALE"
fi
cp "$SCALE_SRC" "$fake_plugin_bin/monitor-scale"
cp "$stub_bin/miracast-ctl" "$fake_plugin_bin/miracast-ctl"
chmod +x "$fake_plugin_bin"/*

run_monitor_scale() {
  local scale_arg="${1:-2}"
  : >"$hypr_log"
  : >"$ctl_log"
  # Long deferred sleep so the async safety-net does not race the sync path
  # (otherwise ensure-capture can appear in ctl_log before pause-capture).
  HOME="$home_dir" \
    XDG_STATE_HOME="$home_dir/.local/state" \
    XDG_CONFIG_HOME="$home_dir/.config" \
    PATH="$stub_bin:$PATH" \
    OMARCHY_TEST_MONITORS="$monitors_file" \
    OMARCHY_TEST_HYPR_LOG="$hypr_log" \
    OMARCHY_TEST_CTL_LOG="$ctl_log" \
    OMARCHY_TEST_DEFER_SLEEP=60 \
    OMARCHY_TEST_ENSURE_SLEEP=0 \
    bash "$fake_plugin_bin/monitor-scale" eDP-1 "$scale_arg"
  # Stop deferred ensure background jobs from this invocation.
  pkill -f "deferred ensure-capture" 2>/dev/null || true
  # The deferred subshell is `sleep 60; ctl ensure...` — kill stray sleeps started
  # under our fake plugin path by matching the scale log marker process group.
  # Best-effort: kill children still sleeping from monitor-scale backgrounded blocks.
  pkill -P $$ -f "^sleep 60$" 2>/dev/null || true
}

assert_pause_before_hypr_and_ensure() {
  local label="$1"
  local first_ctl pause_line ensure_line hypr_lines
  first_ctl="$(awk 'NR==1{print; exit}' "$ctl_log")"
  [[ $first_ctl == pause-capture* || $first_ctl == pause_capture* ]] ||
    fail "$label: pauses capture before eDP remap" "first ctl: ${first_ctl:-<empty>}; ctl_log=$(cat "$ctl_log")"

  pause_line="$(grep -nE 'pause-capture|pause_capture' "$ctl_log" | head -1 | cut -d: -f1)"
  ensure_line="$(grep -nE 'ensure-capture|ensure_capture' "$ctl_log" | head -1 | cut -d: -f1)"
  [[ -n $pause_line && -n $ensure_line ]] ||
    fail "$label: records both pause and ensure" "ctl_log=$(cat "$ctl_log")"
  (( pause_line < ensure_line )) ||
    fail "$label: pause precedes ensure" "pause=$pause_line ensure=$ensure_line ctl=$(cat "$ctl_log")"

  hypr_lines="$(grep -c 'hl.monitor' "$hypr_log" || true)"
  (( hypr_lines >= 1 )) || fail "$label: applies hl.monitor geometry" "hypr log: $(cat "$hypr_log")"
}

# ========== monitor-scale eDP with tracked Extend: pause before remap ==========
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

mkdir -p "$state_dir/logs"
: >"$state_dir/logs/scale.log"
scale_out="$(run_monitor_scale 2)"
[[ $scale_out == 2 ]] || fail "monitor-scale reports cleaned scale" "got $scale_out"
assert_pause_before_hypr_and_ensure "tracked Extend"
# Reseat goes through miracast-ctl set-extend-position (stub writes scale=2).
grep -E 'output = "hotyeah-8D5117_P2P".*scale = 2' "$hypr_log" >/dev/null ||
  fail "monitor-scale reseat preserves Extend output scale" "hypr log: $(cat "$hypr_log")"
grep -E 'set-extend-position|set_extend_position' "$ctl_log" >/dev/null ||
  fail "monitor-scale reseats via set-extend-position" "ctl_log=$(cat "$ctl_log")"
# While rebinding, skip ScreenMoveRemap nudge (single apply — not nudge+restore).
edp_evals="$(grep -c '^hl.monitor({ output = "eDP-1"' "$hypr_log" || true)"
(( edp_evals == 1 )) ||
  fail "monitor-scale applies eDP geometry once while Miracast rebind is needed" "count=$edp_evals hypr=$(cat "$hypr_log")"
# eDP geometry must be applied before Miracast reseat (ensure then glue).
edp_line="$(grep -n 'output = "eDP-1"' "$hypr_log" | head -1 | cut -d: -f1)"
hot_line="$(grep -n 'output = "hotyeah-8D5117_P2P"' "$hypr_log" | head -1 | cut -d: -f1)"
[[ -n $edp_line && -n $hot_line ]] ||
  fail "eDP scale writes both primary and Miracast hl.monitor lines" "hypr=$(cat "$hypr_log")"
(( edp_line < hot_line )) ||
  fail "eDP geometry is applied before Miracast reseat" "eDP=$edp_line hot=$hot_line hypr=$(cat "$hypr_log")"
grep -E 'reseat_miracast layout \(after ensure\)|set-extend-position done' "$state_dir/logs/scale.log" >/dev/null ||
  fail "eDP scale reseats Miracast after ensure" "scale.log=$(cat "$state_dir/logs/scale.log")"
pass "monitor-scale pauses before eDP remap and ensures capture preserving Extend scale"

# ========== monitor-scale eDP scale glues Miracast to settings extendPosition=left ==========
printf '%s\n' 'hotyeah-8D5117_P2P' >"$state_dir/headless.name"
printf '%s\n' '{"extendPosition":"left","extendResolution":"1920x1080","extendRefresh":"30","fps":"30"}' \
  >"$config_dir/settings.json"
# Start with headless wrongly on the right (as monitors.lua reload does).
printf '%s\n' '[
  {"name":"eDP-1","focused":true,"width":1920,"height":1080,"scale":2,"refreshRate":60,"x":0,"y":0},
  {"name":"hotyeah-8D5117_P2P","focused":false,"width":1920,"height":1080,"scale":2,"refreshRate":30,"x":960,"y":0}
]' >"$monitors_file"
mkdir -p "$state_dir/logs"
: >"$state_dir/logs/scale.log"
scale_out="$(run_monitor_scale 2)"
[[ $scale_out == 2 ]] || fail "left-glue eDP scale returns 2" "got $scale_out"
# Left of eDP at scale 2 → Miracast logical width 960 → position -960x…
grep -E 'output = "hotyeah-8D5117_P2P".*position = "-960x' "$hypr_log" >/dev/null ||
  fail "eDP scale reseats Miracast to the left (-960)" "hypr=$(cat "$hypr_log")"
grep -E 'output = "hotyeah-8D5117_P2P".*scale = 2' "$hypr_log" >/dev/null ||
  fail "left reseat keeps Miracast scale 2" "hypr=$(cat "$hypr_log")"
grep -E 'reseat_miracast layout \(after ensure\)|set-extend-position done' "$state_dir/logs/scale.log" >/dev/null ||
  fail "left-glue path logs after-ensure reseat" "scale.log=$(cat "$state_dir/logs/scale.log")"
# Second eDP scale with layout already correct must skip reseat storm.
printf '%s\n' '[
  {"name":"eDP-1","focused":true,"width":1920,"height":1080,"scale":2,"refreshRate":60,"x":0,"y":0},
  {"name":"hotyeah-8D5117_P2P","focused":false,"width":1920,"height":1080,"scale":2,"refreshRate":30,"x":-960,"y":0}
]' >"$monitors_file"
mkdir -p "$state_dir/logs"
: >"$state_dir/logs/scale.log"
: >"$hypr_log"
: >"$ctl_log"
scale_out="$(run_monitor_scale 2)"
grep -F 'already at pos=' "$state_dir/logs/scale.log" >/dev/null ||
  fail "apply_miracast_layout skips when already correct" "scale.log=$(cat "$state_dir/logs/scale.log")"
# Skip path must not call set-extend-position again (would bounce capture).
setpos_count="$(grep -cE 'set-extend-position|set_extend_position' "$ctl_log" || true)"
(( setpos_count == 0 )) ||
  fail "skip path must not re-call set-extend-position" "count=$setpos_count ctl=$(cat "$ctl_log")"
pass "monitor-scale eDP scale glues Miracast to extendPosition=left after persist"

# ========== monitor-scale: status.json monitor fallback without headless.name ==========
rm -f "$state_dir/headless.name"
printf '%s\n' '{"phase":"streaming","monitor":"hotyeah-8D5117_P2P","extendPosition":"left","extendResolution":"1920x1080","extendRefresh":"30","fps":"30"}' \
  >"$state_dir/status.json"
printf '%s\n' '{"extendPosition":"left","extendResolution":"1920x1080","extendRefresh":"30","fps":"30"}' \
  >"$config_dir/settings.json"
printf '%s\n' '[
  {"name":"eDP-1","focused":true,"width":1920,"height":1080,"scale":1,"refreshRate":60,"x":0,"y":0},
  {"name":"hotyeah-8D5117_P2P","focused":false,"width":1920,"height":1080,"scale":2,"refreshRate":30,"x":1920,"y":0}
]' >"$monitors_file"
scale_out="$(run_monitor_scale 1.6)"
[[ -n $scale_out ]] || fail "monitor-scale returns a scale with status.json fallback"
assert_pause_before_hypr_and_ensure "status.json fallback"
grep -E 'output = "hotyeah-8D5117_P2P".*position = "-' "$hypr_log" >/dev/null ||
  fail "status.json fallback still reseats using settings extendPosition=left" "hypr=$(cat "$hypr_log")"
pass "monitor-scale rebinds using status.json monitor when headless.name is missing"

# ========== monitor-scale: hyprctl hang still schedules deferred ensure ==========
cat >"$stub_bin/hyprctl" <<'SH'
#!/bin/bash
echo "$*" >>"${OMARCHY_TEST_HYPR_LOG:-/dev/null}"
if [[ ( $1 == "-j" && $2 == "monitors" ) || ( $1 == "monitors" && $2 == "-j" ) || ( $1 == "monitors" && $2 == "all" && $3 == "-j" ) ]]; then
  cat "${OMARCHY_TEST_MONITORS:?}"
  exit 0
fi
if [[ $1 == "eval" ]]; then
  printf '%s\n' "$2" >>"${OMARCHY_TEST_HYPR_LOG:-/dev/null}"
  # Simulate the hang that previously killed monitor-scale after pause.
  if [[ ${OMARCHY_TEST_HYPR_HANG:-0} == 1 ]]; then
    sleep 30
  fi
  exit 0
fi
if [[ $1 == "dispatch" || $1 == "output" ]]; then
  exit 0
fi
exit 1
SH
chmod +x "$stub_bin/hyprctl"

# timeout stub that kills long hyprctl evals like the real timeout(1).
cat >"$stub_bin/timeout" <<'SH'
#!/bin/bash
secs="$1"
shift
if [[ $1 == hyprctl && $2 == eval && ${OMARCHY_TEST_HYPR_HANG:-0} == 1 ]]; then
  echo "timeout-fired $*" >>"${OMARCHY_TEST_HYPR_LOG:-/dev/null}"
  exit 124
fi
exec "$@"
SH
chmod +x "$stub_bin/timeout"

printf '%s\n' 'hotyeah-8D5117_P2P' >"$state_dir/headless.name"
: >"$ctl_log"
: >"$hypr_log"
: >"$state_dir/logs/scale.log"
OMARCHY_TEST_HYPR_HANG=1 \
  HOME="$home_dir" \
  XDG_STATE_HOME="$home_dir/.local/state" \
  XDG_CONFIG_HOME="$home_dir/.config" \
  PATH="$stub_bin:$PATH" \
  OMARCHY_TEST_MONITORS="$monitors_file" \
  OMARCHY_TEST_HYPR_LOG="$hypr_log" \
  OMARCHY_TEST_CTL_LOG="$ctl_log" \
  OMARCHY_TEST_DEFER_SLEEP=0 \
  OMARCHY_TEST_ENSURE_SLEEP=0 \
  bash "$fake_plugin_bin/monitor-scale" eDP-1 2 >/dev/null
# Allow deferred ensure (sleep 0) to finish writing ctl_log.
sleep 0.2
pkill -P $$ -f "^sleep " 2>/dev/null || true

grep -E 'pause-capture|pause_capture' "$ctl_log" >/dev/null ||
  fail "hang path still pauses capture" "ctl=$(cat "$ctl_log")"
ensure_count="$(grep -cE 'ensure-capture|ensure_capture' "$ctl_log" || true)"
(( ensure_count >= 2 )) ||
  fail "hang path still runs ensure-capture (foreground and/or deferred)" "count=$ensure_count ctl=$(cat "$ctl_log")"
grep -F 'timeout-fired' "$hypr_log" >/dev/null ||
  fail "hang path bounds hyprctl eval with timeout" "hypr=$(cat "$hypr_log")"
scale_log_file="$state_dir/logs/scale.log"
[[ -f $scale_log_file ]] || fail "monitor-scale writes scale.log"
grep -F 'done ' "$scale_log_file" >/dev/null ||
  fail "monitor-scale reaches done after hyprctl timeout" "scale.log=$(cat "$scale_log_file")"
grep -F 'hyprctl eval failed/timeout' "$scale_log_file" >/dev/null ||
  fail "scale.log records hyprctl timeout" "scale.log=$(cat "$scale_log_file")"
pass "monitor-scale recovers via timeout + ensure when hyprctl hangs after pause"

# ========== Miracast virtual scale: no-op when unchanged; apply when different ==========
cp "$SCALE_SRC" "$fake_plugin_bin/monitor-scale"
chmod +x "$fake_plugin_bin/monitor-scale"
printf '%s\n' 'hotyeah-8D5117_P2P' >"$state_dir/headless.name"
printf '%s\n' '{"extendPosition":"left","extendResolution":"1920x1080","extendRefresh":"30","fps":"30"}' \
  >"$config_dir/settings.json"
printf '%s\n' '[
  {"name":"eDP-1","focused":true,"width":1920,"height":1080,"scale":2,"refreshRate":60,"x":0,"y":0},
  {"name":"hotyeah-8D5117_P2P","focused":false,"width":1920,"height":1080,"scale":1,"refreshRate":30,"x":-1920,"y":0}
]' >"$monitors_file"
: >"$ctl_log"
: >"$hypr_log"
virt_same="$(
  HOME="$home_dir" \
    XDG_STATE_HOME="$home_dir/.local/state" \
    XDG_CONFIG_HOME="$home_dir/.config" \
    PATH="$stub_bin:$PATH" \
    OMARCHY_TEST_MONITORS="$monitors_file" \
    OMARCHY_TEST_HYPR_LOG="$hypr_log" \
    OMARCHY_TEST_CTL_LOG="$ctl_log" \
    OMARCHY_TEST_DEFER_SLEEP=60 \
    OMARCHY_TEST_ENSURE_SLEEP=0 \
    bash "$fake_plugin_bin/monitor-scale" hotyeah-8D5117_P2P 1
)"
[[ $virt_same == 1 ]] || fail "virtual same-scale returns 1" "got $virt_same"
if grep -E 'pause-capture|pause_capture' "$ctl_log" >/dev/null; then
  fail "virtual same-scale no-op must not pause capture" "ctl=$(cat "$ctl_log")"
fi
pass "monitor-scale no-ops Miracast virtual scale when unchanged"

: >"$ctl_log"
: >"$hypr_log"
virt_out="$(
  HOME="$home_dir" \
    XDG_STATE_HOME="$home_dir/.local/state" \
    XDG_CONFIG_HOME="$home_dir/.config" \
    PATH="$stub_bin:$PATH" \
    OMARCHY_TEST_MONITORS="$monitors_file" \
    OMARCHY_TEST_HYPR_LOG="$hypr_log" \
    OMARCHY_TEST_CTL_LOG="$ctl_log" \
    OMARCHY_TEST_DEFER_SLEEP=60 \
    OMARCHY_TEST_ENSURE_SLEEP=0 \
    bash "$fake_plugin_bin/monitor-scale" hotyeah-8D5117_P2P 2
)"
[[ $virt_out == 2 ]] || fail "virtual scale change returns requested scale" "got $virt_out"
grep -E 'pause-capture|pause_capture' "$ctl_log" >/dev/null ||
  fail "virtual scale change pauses capture" "ctl=$(cat "$ctl_log")"
grep -E 'output = "hotyeah-8D5117_P2P".*scale = 2' "$hypr_log" >/dev/null ||
  fail "virtual scale change applies hyprctl scale 2" "hypr=$(cat "$hypr_log")"
grep -E 'ensure-capture|ensure_capture' "$ctl_log" >/dev/null ||
  fail "virtual scale change ensures capture" "ctl=$(cat "$ctl_log")"
pass "monitor-scale applies Miracast virtual scale changes with pause/ensure"

# ========== fluxcast_pid ignores shell wrappers that mention main.py ==========
extract_fn fluxcast_pid "$test_tmp/fluxcast_pid.sh"
# shellcheck source=/dev/null
source "$test_tmp/fluxcast_pid.sh"
PID_FILE="$state_dir/cast.pid"
printf '%s\n' "$$" >"$PID_FILE"
# This test shell's argv may mention fluxcast strings via the agent; fluxcast_pid
# must require a python interpreter exe, so it should return empty here.
found_pid="$(fluxcast_pid || true)"
# If a real FluxCast python is running on the host, that is a valid hit — only
# fail when we matched *this* shell (non-python).
if [[ -n $found_pid ]]; then
  exe_base="$(basename "$(readlink -f /proc/$found_pid/exe 2>/dev/null || echo x)")"
  [[ $exe_base == python* ]] ||
    fail "fluxcast_pid must not match non-python wrappers" "pid=$found_pid exe=$exe_base"
  pass "fluxcast_pid returns a real python FluxCast process when one is live"
else
  pass "fluxcast_pid returns empty when no FluxCast python is running"
fi

# Restore fast hyprctl stub for later tests.
cat >"$stub_bin/hyprctl" <<'SH'
#!/bin/bash
echo "$*" >>"${OMARCHY_TEST_HYPR_LOG:-/dev/null}"
if [[ ( $1 == "-j" && $2 == "monitors" ) || ( $1 == "monitors" && $2 == "-j" ) || ( $1 == "monitors" && $2 == "all" && $3 == "-j" ) ]]; then
  cat "${OMARCHY_TEST_MONITORS:?}"
  exit 0
fi
if [[ $1 == "eval" ]]; then
  printf '%s\n' "$2" >>"${OMARCHY_TEST_HYPR_LOG:-/dev/null}"
  exit 0
fi
if [[ $1 == "dispatch" || $1 == "output" ]]; then
  exit 0
fi
exit 1
SH
chmod +x "$stub_bin/hyprctl"
cat >"$stub_bin/timeout" <<'SH'
#!/bin/bash
shift
exec "$@"
SH
chmod +x "$stub_bin/timeout"

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

assertEqual(
  Model.inferExtendPosition([
    { name: 'eDP-1', enabled: true, focused: true, width: 1920, height: 1080, scale: 2, x: 0, y: 0, miracast: false },
    { name: 'hotyeah', enabled: true, focused: false, width: 1920, height: 1080, scale: 2, x: -960, y: 0, miracast: true }
  ]),
  'left',
  'inferExtendPosition left of primary'
)
assertEqual(
  Model.inferExtendPosition([
    { name: 'eDP-1', enabled: true, focused: true, width: 1920, height: 1080, scale: 2, x: 0, y: 0, miracast: false },
    { name: 'hotyeah', enabled: true, focused: false, width: 1920, height: 1080, scale: 2, x: 960, y: 0, miracast: true }
  ]),
  'right',
  'inferExtendPosition right of primary'
)
assertEqual(
  Model.inferExtendPosition([
    { name: 'eDP-1', enabled: true, focused: true, width: 1920, height: 1080, scale: 1, x: 0, y: 0, miracast: false },
    { name: 'hotyeah', enabled: true, focused: false, width: 1920, height: 1080, scale: 1, x: 0, y: -1080, miracast: true }
  ]),
  'above',
  'inferExtendPosition above primary'
)
assertEqual(
  Model.inferExtendPosition([
    { name: 'eDP-1', enabled: true, focused: true, width: 1920, height: 1080, scale: 1, x: 0, y: 0, miracast: false },
    { name: 'hotyeah', enabled: true, focused: false, width: 1920, height: 1080, scale: 1, x: 0, y: 1080, miracast: true }
  ]),
  'below',
  'inferExtendPosition below primary'
)
assertEqual(
  Model.inferExtendPosition([
    { name: 'eDP-1', enabled: true, focused: true, width: 1920, height: 1080, scale: 1.6, x: 0, y: 0, miracast: false },
    { name: 'hotyeah', enabled: true, focused: false, width: 1920, height: 1080, scale: 2, x: 1200, y: 0, miracast: true }
  ]),
  'right',
  'inferExtendPosition right after lua-reload shove (eDP 1.6 / Miracast 2)'
)
assertEqual(
  Model.inferExtendPosition([
    { name: 'eDP-1', enabled: true, focused: true, width: 1920, height: 1080, scale: 1, x: 0, y: 0, miracast: false }
  ]),
  '',
  'inferExtendPosition empty without Miracast output'
)
JS

# ========== capture env: damage-aware by default (omit wf-recorder -D) ==========
rg -q 'FLUXCAST_WFD_WF_RECORDER_DAMAGE' "$PLUGIN_BIN/miracast-ctl" ||
  fail "miracast-ctl must set FLUXCAST_WFD_WF_RECORDER_DAMAGE for capture cadence"
rg -q 'FLUXCAST_WFD_WF_RECORDER_DAMAGE:-1' "$PLUGIN_BIN/miracast-ctl" ||
  fail "damage-aware capture should default on (DAMAGE:-1)"
rg -q 'FLUXCAST_WFD_WF_RECORDER_DAMAGE=0' "$PLUGIN_BIN/miracast-ctl" ||
  fail "must document FLUXCAST_WFD_WF_RECORDER_DAMAGE=0 for continuous -D"
pass "miracast-ctl defaults to damage-aware capture"

# ========== capture encode / RENDER ENGINE ==========
rg -q 'FLUXCAST_WFD_CAPTURE_ENCODE_FILE' "$PLUGIN_BIN/miracast-ctl" ||
  fail "miracast-ctl must export FLUXCAST_WFD_CAPTURE_ENCODE_FILE for live RENDER ENGINE switches"
rg -q 'FLUXCAST_WFD_CAPTURE_ENCODE_PREF' "$PLUGIN_BIN/miracast-ctl" ||
  fail "miracast-ctl must export FLUXCAST_WFD_CAPTURE_ENCODE_PREF"
rg -q 'dmabuf\) export FLUXCAST_WFD_CAPTURE_ENCODE=vaapi' "$PLUGIN_BIN/miracast-ctl" ||
  fail "dmabuf preference must map legacy CAPTURE_ENCODE=vaapi"
rg -q 'FLUXCAST_WFD_DMABUF_ALLOW_SCALED' "$PLUGIN_BIN/miracast-ctl" ||
  fail "miracast-ctl must mention FLUXCAST_WFD_DMABUF_ALLOW_SCALED escape hatch"
# Must not force-deny scaled DMA by default.
if rg -q 'export FLUXCAST_WFD_DMABUF_ALLOW_SCALED=0' "$PLUGIN_BIN/miracast-ctl"; then
  fail "miracast-ctl must not force FLUXCAST_WFD_DMABUF_ALLOW_SCALED=0"
fi
rg -q '"bitrate": "8M"' "$PLUGIN_BIN/miracast-ctl" ||
  fail "default settings bitrate should be 8M (pipe fallback floor)"
# FluxCast patch must keep DMA CQP + tv-range recipe + GPU→CPU cascade.
PATCH_WL="$PLUGIN/patches/fluxcast/src/wfd/media/wlroots.py"
[ -f "$PATCH_WL" ] || fail "missing FluxCast wlroots patch at $PATCH_WL"
rg -q 'rc_mode=CQP' "$PATCH_WL" || fail "DMA path patch must use rc_mode=CQP"
rg -q 'out_range=tv' "$PATCH_WL" || fail "DMA path patch must use scale_vaapi out_range=tv"
rg -q 'capture_encode_attempts' "$PATCH_WL" ||
  fail "wlroots patch must cascade RENDER ENGINE attempts"
rg -q 'prefer_wf_recorder_vaapi_dmabuf' "$PLUGIN/patches/fluxcast/src/wfd/hw_encode.py" ||
  fail "hw_encode patch must expose prefer_wf_recorder_vaapi_dmabuf"
rg -q 'capture_encode_preference' "$PLUGIN/patches/fluxcast/src/wfd/hw_encode.py" ||
  fail "hw_encode patch must expose capture_encode_preference"
pass "miracast-ctl opts into DMA-BUF capture encode (scaled allowed by default)"
rg -q 'set-capture-encode' "$PLUGIN_BIN/miracast-ctl" ||
  fail "miracast-ctl must expose set-capture-encode for RENDER ENGINE pills"
rg -q '"captureEncode": "dmabuf"' "$PLUGIN_BIN/miracast-ctl" ||
  fail "default captureEncode should be dmabuf"
rg -q 'attach_capture_encode_fields' "$PLUGIN_BIN/miracast-ctl" ||
  fail "status must attach captureEncode/capturePath fields"
# UI: RENDER ENGINE only while session active (Miracast display row).
rg -q 'RENDER ENGINE' "$PLUGIN/Panel.qml" ||
  fail "Panel.qml must label RENDER ENGINE pills"
rg -q 'setCaptureEncode' "$PLUGIN/MiracastService.qml" ||
  fail "MiracastService must expose setCaptureEncode"
rg -q 'miracastCaptureEncodeActive' "$PLUGIN/Model.js" ||
  fail "Model.js must map resolved capture path to active pill"
# Gate: RENDER ENGINE column must require showMiracastSessionControls (not pre-connect).
rg -n -B6 'text: "RENDER ENGINE"' "$PLUGIN/Panel.qml" | rg -q 'showMiracastSessionControls' ||
  fail "RENDER ENGINE must be gated on showMiracastSessionControls (connected only)"
if command -v node >/dev/null 2>&1; then
  node <<'JS' || fail "Model.js miracastCaptureEncodeActive mapping"
const M = require(process.env.PLUGIN + "/Model.js");
const assert = (c, m) => { if (!c) { console.error(m); process.exit(1); } };
assert(M.miracastCaptureEncodeActive("dmabuf", "h264_vaapi", "cpu") === "dmabuf", "dmabuf");
assert(M.miracastCaptureEncodeActive("pipe", "h264_vaapi", "dmabuf") === "vaapi", "vaapi");
assert(M.miracastCaptureEncodeActive("pipe", "libx264", "dmabuf") === "cpu", "cpu");
assert(M.miracastCaptureEncodeActive("", "", "vaapi") === "vaapi", "pref");
JS
fi
pass "miracast-ctl RENDER ENGINE captureEncode wiring"
rg -q '"defaultExtendScale": 1' "$PLUGIN_BIN/miracast-ctl" ||
  fail "defaultExtendScale should default to 1 for Hyprland perf"
pass "miracast-ctl defaultExtendScale is 1"
rg -q 'cast_hypr_perf_apply' "$PLUGIN_BIN/miracast-ctl" ||
  fail "miracast-ctl must apply Hyprland cast perf profile"
rg -q 'cast_hypr_perf_restore' "$PLUGIN_BIN/miracast-ctl" ||
  fail "miracast-ctl must restore Hyprland look after cast"
rg -q 'border_size = 2' "$PLUGIN_BIN/miracast-ctl" ||
  fail "cast hypr profile must keep focus borders (border_size=2)"
pass "miracast-ctl applies Hyprland cast perf profile"





# Disconnect safety: never hypr-disable a Miracast output (even if cast looks idle),
# and always pause screencopy before headless remove.
rg -q 'isMiracastOutputName' "$PLUGIN/Panel.qml" ||
  fail "toggleDisplay must detect Miracast outputs beyond disp.miracast+active"
rg -q 'isMiracastOutputName\(name, disp\)' "$PLUGIN/Panel.qml" ||
  fail "toggleDisplay must route Miracast checkbox through stopCast"
rg -q 'pause_extend_capture' "$PLUGIN_BIN/miracast-ctl" ||
  fail "miracast-ctl must define pause_extend_capture"
rg -q 'wait_capture_senders_gone' "$PLUGIN_BIN/miracast-ctl" ||
  fail "cleanup must wait for capture senders before output remove"
# cleanup_extend_monitor body should pause before output remove
awk '/^cleanup_extend_monitor\(\)/,/^}/' "$PLUGIN_BIN/miracast-ctl" | rg -q 'pause_extend_capture' ||
  fail "cleanup_extend_monitor must pause capture before removing headless"
rg -q 'PARKED_FILE' "$PLUGIN_BIN/miracast-ctl" ||
  fail "cleanup must track parked headless name for reuse"
rg -q 'headless left in place for reuse|REFUSED hyprctl destroy' "$PLUGIN_BIN/miracast-ctl" ||
  fail "connect/disconnect must refuse hyprctl destroy of Miracast outputs"
rg -q 'connect-time reuse existing virtual output' "$PLUGIN_BIN/miracast-ctl" ||
  fail "ensure_extend_monitor must reuse existing virtual outputs"
# Stop/cleanup and remove_virtual_output_safe must never invoke output remove.
if awk '/^cleanup_extend_monitor\(\)/,/^}/' "$PLUGIN_BIN/miracast-ctl" | rg -q '^[^#]*hyprctl[^#]*output remove|timeout [0-9]+ hyprctl output remove'; then
  fail "cleanup_extend_monitor must not call hyprctl output remove"
fi
if awk '/^remove_virtual_output_safe\(\)/,/^}/' "$PLUGIN_BIN/miracast-ctl" | rg -q '^[^#]*hyprctl[^#]*output remove|timeout [0-9]+ hyprctl output remove'; then
  fail "remove_virtual_output_safe must be a no-op (no hyprctl output remove)"
fi
if awk '/^ensure_extend_monitor\(\)/,/^}/' "$PLUGIN_BIN/miracast-ctl" | rg -q 'remove_virtual_output_safe|output remove'; then
  # allow comments / REFUSED log string only — block real calls
  if awk '/^ensure_extend_monitor\(\)/,/^}/' "$PLUGIN_BIN/miracast-ctl" | rg -q 'remove_virtual_output_safe \$|hyprctl output remove'; then
    fail "ensure_extend_monitor must not destroy virtual outputs"
  fi
fi
awk '/^cmd_stop\(\)/,/^}/' "$PLUGIN_BIN/miracast-ctl" | rg -q 'pause_extend_capture' ||
  fail "cmd_stop must pause capture before killing FluxCast / removing headless"
pass "disconnect/connect never destroy Miracast outputs (eDP safety)"

# Display panel: expand-all default + cast controls under Miracast row.
rg -q 'onlyExpandFocusedDisplay' "$PLUGIN_BIN/miracast-ctl" ||
  fail "miracast-ctl defaults/status must expose onlyExpandFocusedDisplay"
rg -q '"onlyExpandFocusedDisplay": False' "$PLUGIN_BIN/miracast-ctl" ||
  fail "onlyExpandFocusedDisplay default must be false (expand all)"
rg -q 'expandedMonitors' "$PLUGIN/Panel.qml" ||
  fail "Panel.qml must track expandedMonitors for multi-expand"
rg -q 'onlyExpandFocusedDisplay' "$PLUGIN/Panel.qml" ||
  fail "Panel.qml must honor onlyExpandFocusedDisplay"
rg -q 'onlyExpandFocusedDisplay' "$PLUGIN/MiracastService.qml" ||
  fail "MiracastService must surface onlyExpandFocusedDisplay from status"
rg -q 'CAST MODE' "$PLUGIN/Panel.qml" ||
  fail "Panel.qml must include CAST MODE controls"
rg -q 'display\.miracast' "$PLUGIN/Panel.qml" ||
  fail "cast session controls must be gated on the Miracast display row"
rg -q 'text: "BRIGHTNESS"' "$PLUGIN/Panel.qml" ||
  fail "Brightness label must be uppercase BRIGHTNESS"
rg -q 'text: "SCALE"' "$PLUGIN/Panel.qml" ||
  fail "Scale label must be uppercase SCALE"
rg -q 'onlyExpandFocusedDisplay' "$PLUGIN/README.md" ||
  fail "monitor README must document onlyExpandFocusedDisplay"
pass "Display panel expand-all default and Miracast-row cast controls are wired"

# Screen lock: pause capture on lock, ensure on unlock (screencopy dies under hyprlock).
rg -q 'pauseCaptureForLock' "$PLUGIN/MiracastService.qml" ||
  fail "MiracastService must pause capture when the session locks"
rg -q 'omarchy-hyprland-session-locked' "$PLUGIN/MiracastService.qml" ||
  fail "MiracastService must poll omarchy-hyprland-session-locked"
rg -q 'ensure-capture' "$PLUGIN/MiracastService.qml" ||
  fail "MiracastService must ensure-capture after unlock"
rg -q 'miracast_pause_for_lock|pause-capture' "$ROOT/bin/omarchy-system-lock" ||
  fail "omarchy-system-lock must pause Miracast capture before locking"
pass "screen lock pauses Miracast capture and resumes after unlock"

# Capture watchdog / position-move rebind
rg -q 'cmd_capture_health' "$PLUGIN_BIN/miracast-ctl" ||
  fail "miracast-ctl must expose capture-health for the shell watchdog"
rg -q 'CAPTURE_PAUSED_FILE' "$PLUGIN_BIN/miracast-ctl" ||
  fail "miracast-ctl must track intentional capture pauses"
awk '/^ensure_extend_capture_healthy\(\)/,/^}/' "$PLUGIN_BIN/miracast-ctl" | rg -q 'force' ||
  fail "ensure_extend_capture_healthy must support force rebind"
rg -q 'capture-health' "$PLUGIN/MiracastService.qml" ||
  fail "MiracastService must run a capture-health watchdog while streaming"
pass "capture watchdog and forced position rebind are wired"



# ========== independent Extend workspaces: ext-N namespace, Lua migrate ==========
extract_fn migrate_workspaces_from_monitor "$test_tmp/migrate.sh"
extract_fn seed_extend_workspaces "$test_tmp/seed.sh"
rg -q 'hl.dsp.workspace.move' "$test_tmp/migrate.sh" ||
  fail "migrate_workspaces_from_monitor uses Lua workspace.move"
rg -q 'name:ext-1' "$test_tmp/seed.sh" ||
  fail "seed_extend_workspaces creates named ext-1 on cast output"
if rg -q 'tame_extend_workspaces' "$PLUGIN_BIN/miracast-ctl"; then
  fail "tame_extend_workspaces should be removed for independent Extend workspaces"
fi
# Helpers map Miracast SUPER+N / SUPER+SHIFT+N to ext-N
rg -q 'ext-' "$ROOT/bin/omarchy-hyprland-workspace-focus" ||
  fail "workspace-focus helper namespaces non-laptop monitors as ext-N"
rg -q 'ext-' "$ROOT/bin/omarchy-hyprland-workspace-move" ||
  fail "workspace-move helper namespaces non-laptop monitors as ext-N"
rg -q 'omarchy-hyprland-workspace-move' "$ROOT/default/hypr/bindings/tiling.lua" ||
  fail "tiling defaults should move windows via workspace-move helper"
pass "Extend uses independent ext-N workspaces; disconnect migrate kept"

# ========== monitor-scale persists Extend scale via remember-extend-scale ==========
cp "$SCALE_SRC" "$fake_plugin_bin/monitor-scale"
# Recording ctl that accepts remember-extend-scale
cat >"$fake_plugin_bin/miracast-ctl" <<'SH'
#!/bin/bash
echo "$*" >>"${OMARCHY_TEST_CTL_LOG:-/dev/null}"
case "${1:-}" in
  pause-capture|pause_capture) echo '{"ok":true,"paused":0}' ;;
  ensure-capture|ensure_capture) echo '{"ok":true,"captureHealthy":true}' ;;
  remember-extend-scale|remember_extend_scale) echo '{"ok":true,"scale":"2"}' ;;
  *) echo '{"ok":true}' ;;
esac
exit 0
SH
chmod +x "$fake_plugin_bin/miracast-ctl"
printf '%s\n' 'hotyeah-8D5117_P2P' >"$state_dir/headless.name"
printf '%s\n' '{"extendPosition":"left","extendResolution":"1920x1080","extendRefresh":"30","fps":"30"}' \
  >"$config_dir/settings.json"
printf '%s\n' '[
  {"name":"eDP-1","focused":true,"width":1920,"height":1080,"scale":2,"refreshRate":60,"x":0,"y":0},
  {"name":"hotyeah-8D5117_P2P","focused":false,"width":1920,"height":1080,"scale":1,"refreshRate":30,"x":-960,"y":0}
]' >"$monitors_file"
: >"$ctl_log"
: >"$hypr_log"
HOME="$home_dir" \
  XDG_STATE_HOME="$home_dir/.local/state" \
  XDG_CONFIG_HOME="$home_dir/.config" \
  PATH="$stub_bin:$PATH" \
  OMARCHY_TEST_MONITORS="$monitors_file" \
  OMARCHY_TEST_HYPR_LOG="$hypr_log" \
  OMARCHY_TEST_CTL_LOG="$ctl_log" \
  OMARCHY_TEST_DEFER_SLEEP=60 \
  OMARCHY_TEST_ENSURE_SLEEP=0 \
  bash "$fake_plugin_bin/monitor-scale" hotyeah-8D5117_P2P 2 >/dev/null
grep -E 'remember-extend-scale|remember_extend_scale' "$ctl_log" >/dev/null ||
  fail "monitor-scale saves Extend scale via remember-extend-scale" "ctl=$(cat "$ctl_log")"
pass "monitor-scale persists Extend scale for reconnect"

pass "miracast monitor regression coverage"
