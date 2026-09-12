#!/bin/bash
# Per-monitor workspace focus/move helpers: laptop numeric vs ext-N.

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

stub_dir="$tmpdir/bin"
log_file="$tmpdir/hyprctl.log"
mkdir -p "$stub_dir"

cat >"$stub_dir/hyprctl" <<'EOF'
#!/bin/bash
# Stub: -j monitors returns FOCUSED_MON from env; log other dispatches.
if [[ $1 == "-j" && $2 == "monitors" ]]; then
  mon="${FOCUSED_MON:-eDP-1}"
  printf '[{"name":"eDP-1","focused":%s},{"name":"hotyeah-TV","focused":%s}]\n' \
    "$([[ $mon == eDP-1 ]] && echo true || echo false)" \
    "$([[ $mon == hotyeah-TV ]] && echo true || echo false)"
  exit 0
fi
printf '%s\n' "$*" >>"$HYPRCTL_LOG"
EOF
chmod +x "$stub_dir/hyprctl"

run_helper() {
  local helper="$1"
  shift
  : >"$log_file"
  FOCUSED_MON="$FOCUSED_MON" HYPRCTL_LOG="$log_file" PATH="$stub_dir:$PATH" \
    "$ROOT/bin/$helper" "$@"
}

# --- focus ---
FOCUSED_MON=eDP-1 run_helper omarchy-hyprland-workspace-focus 3
rg -q 'workspace = "3"' "$log_file" || fail "focus on laptop targets numeric workspace 3"
pass "workspace-focus on laptop uses numeric id"

FOCUSED_MON=hotyeah-TV run_helper omarchy-hyprland-workspace-focus 3
rg -q 'workspace = "name:ext-3"' "$log_file" || fail "focus on external targets name:ext-3"
pass "workspace-focus on external uses name:ext-N"

if FOCUSED_MON=eDP-1 PATH="$stub_dir:$PATH" HYPRCTL_LOG="$log_file" \
  "$ROOT/bin/omarchy-hyprland-workspace-focus" 99 2>/dev/null; then
  fail "workspace-focus should reject out-of-range workspace"
fi
pass "workspace-focus rejects invalid workspace id"

# --- move ---
FOCUSED_MON=eDP-1 run_helper omarchy-hyprland-workspace-move 2
rg -q 'hl.dsp.window.move' "$log_file" || fail "move dispatches window.move"
rg -q 'workspace = "2"' "$log_file" || fail "move on laptop targets numeric workspace 2"
if rg -q 'follow = false' "$log_file"; then
  fail "default move should follow (no follow=false)"
fi
pass "workspace-move on laptop uses numeric id and follows"

FOCUSED_MON=hotyeah-TV run_helper omarchy-hyprland-workspace-move 4 --silent
rg -q 'workspace = "name:ext-4"' "$log_file" || fail "silent move on external targets name:ext-4"
rg -q 'follow = false' "$log_file" || fail "silent move sets follow = false"
pass "workspace-move --silent on external uses name:ext-N without follow"

# --- default bindings wire helpers ---
rg -q 'omarchy-hyprland-workspace-focus' "$ROOT/default/hypr/bindings/tiling.lua" ||
  fail "tiling.lua should bind SUPER+N to workspace-focus"
rg -q 'omarchy-hyprland-workspace-move' "$ROOT/default/hypr/bindings/tiling.lua" ||
  fail "tiling.lua should bind SUPER+SHIFT+N to workspace-move"
rg -q -- '--silent' "$ROOT/default/hypr/bindings/tiling.lua" ||
  fail "tiling.lua silent move should pass --silent"
if rg -q 'window.move\(\{ workspace = tostring\(workspace\)' "$ROOT/default/hypr/bindings/tiling.lua"; then
  fail "tiling.lua must not move to raw numeric workspaces for SUPER+SHIFT+N"
fi
pass "tiling.lua uses namespaced focus/move helpers"

# Personal skel bindings must not carry product SUPER+N loops
if rg -q 'omarchy-hyprland-workspace-focus' "$ROOT/config/hypr/bindings.lua"; then
  fail "config/hypr/bindings.lua is personal overrides only; keep product binds in default/"
fi
pass "skel bindings.lua stays free of product workspace binds"
