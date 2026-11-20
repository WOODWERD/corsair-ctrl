# Corsair Ctrl

A touch panel for the Corsair XENEON EDGE (2560 × 720) beside the Mac. It shows the Claude Code sessions you last worked in, jumps between four apps, and carries the Flow Ctrl voice buttons for Wispr Flow. Part of the WOODWERD Ctrl family.

Unofficial. Not affiliated with or endorsed by Corsair, Anthropic or Wispr.

```
corsair-ctrl/
  spec.md             what it is and every decision, newest first
  design/             the approved mock (index.html) and design notes (design.md)
  app/                the app
    Sources/          Swift: panel window, sessions, hooks, voice keys, apps, weather and calendar
    web/              the panel's face (HTML, CSS, JS, bundled fonts)
    build.sh          builds and signs app/build/Corsair Ctrl.app
  spike/              the test panel that proved the idea; kept for reference
```

## Needs
- macOS 14 or later, with Xcode or the Command Line Tools.
- The EDGE connected for picture and USB, set to its native 2560 × 720.
- The touch driver: [ajvwhite/MacXeneonEdgeTouchDriver](https://github.com/ajvwhite/MacXeneonEdgeTouchDriver), installed with its `Scripts/install.sh` and allowed under Accessibility and Input Monitoring.
- Wispr Flow, with push to talk set to Ctrl + Opt + T (the same chord as CYD Flow Ctrl).

## Build and run
```
bash ~/Code/corsair-ctrl/app/build.sh
open "$HOME/Code/corsair-ctrl/app/build/Corsair Ctrl.app"
```
The panel appears on the EDGE. With no EDGE attached it stays hidden rather than cover another display.

To quit: Settings > Quit on the panel, or `pkill -x CorsairCtrl`.

## First run
1. **Accessibility.** macOS asks to let Corsair Ctrl control the computer. Allow it; the voice buttons send keys and cannot work without it. Until then the Voice area is disabled and says why.
2. **Session hooks.** Tap **Install session hooks** on the board (or in Settings). This adds seven hooks to `~/.claude/settings.json`, after backing the file up beside it. Sessions already open pick the hooks up when they are next started.
3. **Calendar.** Tap the **Next** row in Glance to connect Apple Calendar.

## What it stores and sends
- **Sessions:** for each of the last 24 sessions it saves the session id, working folder, state, a short activity line and two times, in `~/Library/Application Support/CorsairCtrl/sessions.json`. Prompt text and tool input are received from the hook and discarded; neither is written anywhere.
- **Log:** `~/Library/Logs/CorsairCtrl/app.log`, capped at about 1 MB. Event names and folder names only.
- **Weather:** every 15 minutes it asks Open-Meteo for the forecast at the coordinates in `config.json` (Austin by default). That request is the only thing the app sends off this Mac. Set `weatherEnabled` to `false` to turn it off.
- **Local listener:** `127.0.0.1:47616`, this Mac only.

## Settings file
`~/Library/Application Support/CorsairCtrl/config.json`, written on first run:
- `apps`: the four bundle identifiers on the Apps strip.
- `weatherEnabled`, `place`, `latitude`, `longitude`.

Restart the app after editing it.

## Known limits
- A card opens the Claude app but cannot land on that exact session.
- The panel's hands-free state is its own guess. If you stop Wispr from the Mac instead of the panel, tap Discard to reset it.
- The top 34 px are left empty because macOS draws its menu bar there.
- One finger only: tap, hold and drag. No pinch or two-finger gestures.
