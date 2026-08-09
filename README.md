# Macstify

A macOS screen saver that recreates *Mystify Your Mind* from Windows 95: polygons drift across the
screen, bounce off the edges and leave a trail of their past outlines behind, while their colors
cycle through the spectrum.

![Macstify](docs/screenshot.png)

Requires macOS 13 or later. Universal (Apple silicon and Intel).

## Install

```sh
xcodebuild -project Macstify.xcodeproj -scheme Macstify -configuration Release -derivedDataPath build build
mkdir -p ~/Library/"Screen Savers"
cp -R build/Build/Products/Release/Macstify.saver ~/Library/"Screen Savers"/
```

Then open System Settings → Screen Saver and pick **Macstify**.

macOS keeps the loaded bundle cached, so when you install a newer build over an older one, the old
version may keep running. Force a reload with:

```sh
killall legacyScreenSaver
```

and quit and reopen System Settings.

## Options

![Options](docs/options.png)

| Option | Default | Range | |
| --- | --- | --- | --- |
| Shapes | 2 | 1–8 | Polygons on screen. |
| Vertices | 4 | 3–12 | Corners per polygon. Each corner moves on its own, which is what makes the shape churn. |
| Trail length | 12 | 1–40 | Outlines kept on screen, the live one included. |
| Speed | 1.00× | 0.2–3.0 | Vertex travel, measured against the screen's shorter edge, so the pace feels the same on any display. |
| Line width | 1.5 pt | 0.5–4.0 | |
| Color speed | 1.00× | 0.0–3.0 | Hue cycling rate. `0.00×` freezes each shape on its starting color. |

Settings are stored per user through `ScreenSaverDefaults` under `jp.winebarrel.Macstify`.

## Development

`Sources/MacstifyEngine.swift` holds the simulation and drawing, and depends on nothing but a
`CGRect` and a `CGContext`. `MacstifyPreview` is a development harness around it:

```sh
xcodebuild -project Macstify.xcodeproj -scheme MacstifyPreview -configuration Release -derivedDataPath build build
P=build/Build/Products/Release/MacstifyPreview.app/Contents/MacOS/MacstifyPreview

$P                                    # live window
$P --options                          # live window with the Options sheet open
$P --snapshot out.png --frames 900    # render frames offscreen, write a PNG
$P --snapshot out.png --preview       # as the small System Settings thumbnail
$P --snapshot out.png --speed 4       # override the saved speed for one render
$P --snapshot out.png --options       # render the Options sheet itself
```

The live window hosts the real `MacstifyView`; snapshots drive the engine directly, which is how
`--speed` applies to a single render without touching your saved settings. `--size` is in points and
snapshots are written at 2x, as on a Retina display.

The screenshots above were produced with `--snapshot`.

### Thumbnail

The picker in System Settings shows `Contents/Resources/thumbnail.png` and `thumbnail@2x.png`
(90×58 and 180×116, the sizes Apple's own savers use). Without them macOS substitutes a generic
placeholder image. `COMBINE_HIDPI_IMAGES` is off so the two stay separate PNGs instead of being
merged into a single `thumbnail.tiff`, which the picker does not pick up.

Trail spacing is proportional to the screen's shorter edge while line width is absolute, so a
render this small collapses into a fat line at the stored speed. `--speed` compensates:

```sh
$P --snapshot Resources/thumbnail@2x.png --preview --size 90x58 --speed 4 --frames 600
sips -Z 90 Resources/thumbnail@2x.png --out Resources/thumbnail.png
```

## Signing

The build is ad-hoc signed, which is enough for a saver you build and install yourself. Copying the
bundle to another Mac means it arrives quarantined, and Gatekeeper will refuse it — that needs a
Developer ID signature and notarization.

## License

[CC0 1.0 Universal](LICENSE).
