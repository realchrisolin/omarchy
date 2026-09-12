# FluxCast patches (required for best results)

These files extend [FluxCast](https://github.com/IlyaP358/fluxcast) for the
Omarchy Display Miracast panel. Upstream FluxCast defaults stay non-breaking
(`libx264`, `wf-recorder -D`). Omarchy opts into GPU encode and quieter
capture via environment variables set by `miracast-ctl`.

| File | Purpose |
|------|---------|
| `src/wfd/hw_encode.py` | Optional VAAPI/QSV encode; battery / power-saver bias when GPU is opted in |
| `src/wfd/mode_state.py` | Persist sink-advertised stream modes for the UI (`FLUXCAST_WFD_MODE_STATE`) |
| `src/wfd/media/wlroots.py` | Wire HW encode plan; damage-aware `wf-recorder` when `FLUXCAST_WFD_WF_RECORDER_DAMAGE=1` |
| `src/wfd/rtsp/handler.py` | Write mode state after RTSP negotiation; bare-Session M16 keepalives |

## Apply

```bash
# Point at your FluxCast source tree (AppImage extract or git checkout)
export FLUXCAST_ROOT=/path/to/fluxcast

cp patches/fluxcast/src/wfd/hw_encode.py          "$FLUXCAST_ROOT/src/wfd/"
cp patches/fluxcast/src/wfd/mode_state.py         "$FLUXCAST_ROOT/src/wfd/"
cp patches/fluxcast/src/wfd/media/wlroots.py      "$FLUXCAST_ROOT/src/wfd/media/"
cp patches/fluxcast/src/wfd/rtsp/handler.py       "$FLUXCAST_ROOT/src/wfd/rtsp/"
```

Then:

```bash
export FLUXCAST_ROOT=/path/to/fluxcast
./bin/miracast-ctl doctor
```

`miracast-ctl` exports (when casting):

- `FLUXCAST_WFD_ENCODER` from settings `videoEncoder` (default `auto` → VAAPI/QSV when available)
- `FLUXCAST_WFD_WF_RECORDER_DAMAGE=1` (omit `wf-recorder -D` for quieter Hyprland capture)
- `FLUXCAST_WFD_MODE_STATE` for stream-mode pills in the Display panel

Without these patches the panel still works against stock FluxCast, but you
lose GPU encode opt-in wiring, damage-aware capture, and live **STREAM MODE**
capability discovery from the sink.
