
# Macstify

[![CI](https://github.com/winebarrel/Macstify/actions/workflows/ci.yml/badge.svg)](https://github.com/winebarrel/Macstify/actions/workflows/ci.yml)
[![AI Generated](https://img.shields.io/badge/AI%20Generated-Claude-orange?logo=anthropic)](https://claude.ai/claude-code)

A macOS screen saver that recreates *Mystify Your Mind* from Windows 95: polygons drift across the
screen, bounce off the edges and leave a trail of their past outlines behind, while their colors
cycle through the spectrum.

![](https://github.com/user-attachments/assets/1cf00b65-e92e-471a-a8c9-d34067adf3cf)

## Options

![](https://github.com/user-attachments/assets/e4a73109-1fe3-4ceb-8551-257e5ffeb734)

| Option | Default | Range | |
| --- | --- | --- | --- |
| Shapes | 2 | 1–8 | Polygons on screen. |
| Vertices | 4 | 3–12 | Corners per polygon. Each corner moves on its own, which is what makes the shape churn. |
| Trail length | 12 | 1–40 | Outlines kept on screen, the live one included. |
| Speed | 1.00× | 0.2–3.0 | Vertex travel, measured against the screen's shorter edge, so the pace feels the same on any display. |
| Line width | 1.5 pt | 0.5–4.0 | |
| Color speed | 1.00× | 0.0–3.0 | Hue cycling rate. `0.00×` freezes each shape on its starting color. |

Settings are stored per user through `ScreenSaverDefaults` under `jp.winebarrel.Macstify`.

## Known issue: the Options button does nothing

On macOS 26 the Options button stops responding, reliably if you switch the screen
saver away and back. Nothing appears, and nothing is logged.

This is a bug in the host, not in the saver. System Settings spawns duplicate
`legacyScreenSaver` instances and loses track of them, so the configure sheet is
handed over, attached and ordered in — against a remote view window that is no
longer on screen. Traced from inside a screen saver bundle, the sheet reports
`isVisible == true` with a live `sheetParent`, while `occlusionState` never gains
`.visible`: attached to a ghost, and never drawn. Which window the host attaches
the sheet to is not something `configureSheet` can influence.

Apple has it as FB19201567, along with FB19204084 for the `ScreenSaverView`
instances that pile up alongside; neither is fixed as of 26.1b3. See
[macOS 26 Tahoe Screen Saver issues](https://developer.apple.com/forums/thread/787444).

Until it is fixed, restart the host:

```sh
killall legacyScreenSaver
```

then quit System Settings and open it again.
