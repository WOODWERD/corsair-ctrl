# Changelog

What changed in Corsair Ctrl, newest first. The reasons behind each change are in [spec.md](https://github.com/WOODWERD/corsair-ctrl/blob/main/spec.md).

## v0.4.7 — 2026-11-23
- **Grab markup** replaces Grab window in the key row. It starts an area capture in [Shottr](https://shottr.cc), which opens the image for marking up. Grab area is unchanged: it copies the area to the clipboard as before. Grab markup needs Shottr installed.

## v0.4.6 — 2026-11-23
- The strip behind the macOS menu bar, at the top of the panel, now follows the Mac's light or dark appearance instead of the panel's theme. With the Mac dark and the panel light, the menu bar's white icons were on a light strip and could not be seen.

## v0.4.5 — 2026-11-22
- **Dock guard.** If the macOS Dock moves onto the Corsair, its invisible window covers the panel and the touch driver rejects every tap. Corsair Ctrl now notices within about ten seconds, restarts the Dock, checks that it came back, and shows a strip across the top of the panel while it does. It restarts the Dock at most once in ten minutes.

## v0.4.4 — 2026-11-21
- **Delete** in Flow Ctrl, beside Hands-free and Discard. A tap deletes one character backwards; hold it to keep deleting. The three buttons are now square, icon over name.

## v0.4.3 — 2026-11-21
- Grab area and Grab window press your Mac's own screenshot shortcut, read from Keyboard settings, so they work when that shortcut has been changed from the default. Screen Recording permission is not needed.

## v0.4.2 — 2026-11-21
- Turning "Open app at start" off puts that app's window back where it was.

## v0.4.1 — 2026-11-21
- The panel comes back from a restart folded or unfolded, as you left it.
- Settings can name one app to open at start. Its window is moved beside the folded panel. A window that is already full screen is left alone.

## v0.4.0 — 2026-11-21
- **Key row.** Eight keys under the Agents board: Esc, Undo, Copy, Paste, Grab area, Grab window, Prev app, Next app. The cards are shorter to make room.
- Media Ctrl's play button and progress bar follow the player: green for Spotify, red for Apple Music.
- Flow Ctrl's talk button has the same corners as Send.
- Settings has a gear icon.

## v0.3.3 — 2026-11-21
- Open apps on the Apps strip are ordered most recently used first.

## v0.3.2 — 2026-11-19
- **Fold rail.** A strip between Glance and Agents folds the panel down to Glance, so the rest of the Corsair works as a normal screen.

## v0.3.1 — 2026-11-19
- **Media Ctrl.** What is playing in Spotify or Apple Music, with transport, volume and a More view.
- A card opens its own session in Claude and shows its chat name.
- New chat and New Code session buttons.
- The Apps strip scrolls and lists every open app under the four pinned ones.

## v0.1.0 — 2026-11-19
- First build: Glance, the Agents board fed by Claude Code hooks, the Apps strip and the Flow Ctrl voice buttons.
