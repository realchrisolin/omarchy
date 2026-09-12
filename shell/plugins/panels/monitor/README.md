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
| `bitrate` | `4M` | Trimmed further on battery / power-saver |
| `videoEncoder` | `auto` | `auto` → VAAPI / QSV / software |
| *(env)* `FLUXCAST_WFD_CAPTURE_ENCODE` | `auto` when GPU encoder | `auto`/`vaapi` = wf-recorder DMA-BUF; `pipe` = legacy raw→hwupload |
| `sinkScales` | `{}` | Per-sink Extend scale, keyed by MAC |
| `onlyExpandFocusedDisplay` | `false` | `false` = expand all display rows; `true` = accordion (focused only) |

### Display panel expansion

```json
"onlyExpandFocusedDisplay": false
```

- **`false` (default):** all enabled outputs expand when the panel opens; newly
  connected outputs expand too. Rows can still be collapsed individually.
- **`true`:** only one row expanded (follows focused output) — previous accordion.

While Miracast is connected, cast session controls (**CAST MODE**, **EXTEND
POSITION**, **STREAM MODE**) appear under the Miracast display row next to
**SCALE**. Scan / firewall / doctor / Stop remain under the **MIRACAST** section.

## Virtual output lifecycle (eDP safety)

Miracast **must not** call `hyprctl output remove` / `monitor,disable` during
connect or disconnect — those calls have frozen the primary display for
30–90s. Stop leaves the virtual output in place; the next Extend session
**reuses** it. Orphan cleanup is never automatic on the hot path.

## FluxCast patches

See `patches/fluxcast/APPLY.md` for optional FluxCast tree patches (VAAPI
power bias, capture rebind, etc.).
