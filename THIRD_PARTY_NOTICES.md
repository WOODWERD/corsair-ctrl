# Third-party notices

Corsair Ctrl itself is © 2026 WOODWERD LLC, MIT-licensed (see `LICENSE`). It distributes, depends on, or talks to the following.

## Fonts (bundled in `app/web/fonts/` and `design/fonts/`)

| Font | License | Files |
|---|---|---|
| [Inter](https://github.com/rsms/inter) 400/500/600 | SIL Open Font License 1.1 | `inter-latin-*.woff2`, licence alongside in `LICENSE-Inter-OFL.txt` |
| [JetBrains Mono](https://github.com/JetBrains/JetBrainsMono) 400/500 | SIL Open Font License 1.1 | `jetbrains-mono-latin-*.woff2`, licence alongside in `LICENSE-JetBrainsMono-OFL.txt` |

The `.woff2` files are Latin subsets of these fonts. Under the OFL they are Modified Versions: they remain under the OFL, are not sold on their own, and the file names use the original names only to identify their origin.

## Icons

The interface icons are original WOODWERD drawings and MIT like the rest of the project. The Media Ctrl icons come from [WOODWERD/cyd-media-ctrl](https://github.com/WOODWERD/cyd-media-ctrl) and the Flow Ctrl icons are redrawn from [WOODWERD/cyd-flow-ctrl](https://github.com/WOODWERD/cyd-flow-ctrl).

The app icons on the Apps strip are read from the apps installed on the Mac at run time. None are stored in this repository.

## Used at run time, not distributed

| Component | Notes |
|---|---|
| [ajvwhite/MacXeneonEdgeTouchDriver](https://github.com/ajvwhite/MacXeneonEdgeTouchDriver) | The touch driver for the display. Installed separately from its own repository, under its own licence. |
| [Open-Meteo](https://open-meteo.com/) | Weather data, licensed [CC BY 4.0](https://open-meteo.com/en/license). The app sends only the configured coordinates. |

## Trademarks and affiliation

Corsair Ctrl is an independent, unofficial project. It is not affiliated with, endorsed by, or supported by any of the companies below.

- **Corsair** and **XENEON EDGE** are trademarks of Corsair Memory, Inc. "Corsair Ctrl" is used descriptively, for a controller that runs on that display, and is not claimed as a brand.
- **Claude** and **Claude Code** are trademarks of Anthropic, PBC. The app receives Claude Code's documented hook events, opens the Claude desktop app through its `claude://` links, and reads two session identifiers from that app's local records. That record layout is not a published interface and may change.
- **Wispr Flow** is a trademark of Wispr AI, Inc. The app sends ordinary keyboard shortcuts. No Wispr artwork, logos or code are used; the waveform pill is an original drawing.
- **Shottr** belongs to its developer. The app opens Shottr's own `shottr://grab/area` link and nothing else. No Shottr artwork, logos or code are used.
- **Spotify** is a trademark of Spotify AB. **Apple Music**, **macOS** and **AppleScript** are trademarks of Apple Inc. The app controls these players through their published AppleScript interfaces.

The **WOODWERD** name and badge logo (the mark in the panel's footer) are trademarks of WOODWERD LLC and are **not** covered by the MIT licence. You may build and use this project as published; if you fork it for your own product, replace the mark with your own.
