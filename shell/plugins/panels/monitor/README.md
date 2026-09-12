# Display / Miracast panel (`omarchy.monitor`)

Omarchy Display panel with Miracast (Wi‑Fi Display) controls. Runtime settings
live in `~/.config/omarchy-miracast/settings.json` and are merged with defaults
from `bin/miracast-ctl` on each read.

## Settings defaults

| Key | Default | Notes |
|-----|---------|--------|
| `mode` | `mirror` | `mirror` or `extend` |
| `extendPosition` | `right` | `left` / `right` / `above` / `below` |
| `streamMode` | `1280x720p30` | Preferred CEA-style mode id |
| `fps` | `20` | Fallback when `streamMode` is unset |
| `outputRes` | `1280x720` | Encoded size (fallback) |
| `extendResolution` | `1280x720` | Extend virtual output size (fallback) |
| `bitrate` | `8M` | Pipe-path / fallback bitrate; DMA path uses CQP (not this ceiling) |
| `videoEncoder` | `auto` | `auto` → VAAPI / QSV / software |
| *(env)* `FLUXCAST_WFD_CAPTURE_ENCODE` | `auto` when GPU encoder | `auto`/`vaapi` = wf-recorder DMA-BUF (incl. scaled outputs); `pipe` = legacy raw→hwupload |
| *(env)* `FLUXCAST_WFD_DMABUF_ALLOW_SCALED` | allow (default) | `0`/`false` = force pipe when Hyprland scale ≠ 1 |
| `captureEncode` | `dmabuf` | RENDER ENGINE: `dmabuf` (GPU·DMA-BUF) / `vaapi` (GPU·VAAPI) / `cpu` |
| *(env)* `FLUXCAST_WFD_VAAPI_QP` | `18` | DMA CQP quantizer (lower = sharper / more bitrate) |
| `sinkScales` | `{}` | Per-sink Extend scale, keyed by MAC (overrides default) |
| `defaultExtendScale` | `1` | Extend scale when unset — **1** is cheapest for Hyprland |
| `onlyExpandFocusedDisplay` | `false` | `false` = expand all display rows; `true` = accordion (focused only) |

### Display panel expansion

```json
"onlyExpandFocusedDisplay": false
```

- **`false` (default):** all enabled outputs expand when the panel opens; newly
  connected outputs expand too. Rows can still be collapsed individually.
- **`true`:** only one row expanded (follows focused output) — previous accordion.

While Miracast is connected, the Miracast display row shows **CAST MODE** /
**EXTEND POSITION** first (← ↑ ↓ → when Extend), then **SCALE**, **STREAM
MODE**, and **RENDER ENGINE**. Scan / firewall / doctor / Stop remain under
the **MIRACAST** section.

With focus on the CAST MODE / EXTEND POSITION row and Extend active, vim
**hjkl** set position: **h** ← left, **j** ↓ below, **k** ↑ above, **l** → right.

**RENDER ENGINE** (connected only): `dmabuf` / `vaapi` / `cpu` — default DMA-BUF.
GPU failures fall back to CPU; the active pill tracks the resolved encode path.
See `miracast-ctl set-capture-encode` and `captureEncode` in settings.

Capture uses continuous `wf-recorder -D` by default (better for Hyprland on Extend
than damage-aware). While connected, Hyprland animations are disabled and restored
on stop; borders/gaps stay so focus and workspace UI keep working.

## Virtual output lifecycle (eDP safety)

Miracast **must not** call `hyprctl output remove` / `monitor,disable` during
connect or disconnect — those calls have frozen the primary display for
30–90s. Stop leaves the virtual output in place; the next Extend session
**reuses** it. Orphan cleanup is never automatic on the hot path.

## FluxCast patches

See `patches/fluxcast/APPLY.md` for optional FluxCast tree patches (VAAPI
power bias, capture rebind, etc.).
