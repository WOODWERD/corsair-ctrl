# Corsair Ctrl

A touch panel for the Corsair XENEON EDGE (2560 × 720) beside the Mac. It shows the Claude Code sessions you last worked in, opens any of them or starts a new chat or Code session, jumps between four apps, and carries the Flow Ctrl voice buttons for Wispr Flow. Part of the WOODWERD Ctrl family.

Unofficial. Not affiliated with or endorsed by Corsair, Anthropic, Wispr, Spotify or Apple. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

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
- The Corsair connected for picture and USB, set to its native 2560 × 720.
- The touch driver: [ajvwhite/MacXeneonEdgeTouchDriver](https://github.com/ajvwhite/MacXeneonEdgeTouchDriver), installed with its `Scripts/install.sh` and allowed under Accessibility and Input Monitoring.
- Wispr Flow, with push to talk set to Ctrl + Opt + T (the same chord as CYD Flow Ctrl).
- For Media Ctrl's track info: Spotify or Apple Music. Anything else gets media keys only.

## Build and run
```
bash ~/Code/corsair-ctrl/app/build.sh
open "$HOME/Code/corsair-ctrl/app/build/Corsair Ctrl.app"
```
The panel appears on the Corsair. With no Corsair attached it stays hidden rather than cover another display.

To quit: Settings > Quit on the panel, or `pkill -x CorsairCtrl`.

## First run
1. **Accessibility.** macOS asks to let Corsair Ctrl control the computer. Allow it; the voice buttons send keys and cannot work without it. Until then the Voice area is disabled and says why.
2. **Session hooks.** Tap **Install session hooks** on the board (or in Settings). This adds seven hooks to `~/.claude/settings.json`, after backing the file up beside it. Sessions already open pick the hooks up when they are next started.
3. **Calendar.** Tap the **Next** row in Glance to connect Apple Calendar.
4. **Media.** The first time Spotify or Music is open, macOS asks to let Corsair Ctrl control it. Allow it to see what is playing. Without it the transport buttons still work as media keys.

## What it stores and sends
- **Sessions:** for each of the last 24 sessions it saves the session id, working folder, state, a short activity line and two times, in `~/Library/Application Support/CorsairCtrl/sessions.json`. Prompt text and tool input are received from the hook and discarded; neither is written anywhere. Chat names are read from the Claude app when needed and kept in memory only.
- **Log:** `~/Library/Logs/CorsairCtrl/app.log`, capped at about 1 MB. Event names and folder names only.
- **Weather:** every 15 minutes it asks Open-Meteo for the forecast at the coordinates in `config.json` (Austin by default). That request is the only thing the app sends off this Mac. Set `weatherEnabled` to `false` to turn it off.
- **Local listener:** `127.0.0.1:47616`, this Mac only.

## Settings file
`~/Library/Application Support/CorsairCtrl/config.json`, written on first run:
- `apps`: the four bundle identifiers on the Apps strip.
- `weatherEnabled`, `place`, `latitude`, `longitude`.

Restart the app after editing it.

## Known limits
- A card gets its chat name and opens its own session by reading three fields (two ids and the title) from the Claude app's private session records. If a Claude update moves those records, cards show the folder only and fall back to just bringing Claude forward.
- The panel's hands-free state is its own guess. If you stop Wispr from the Mac instead of the panel, tap Discard to reset it.
- The top 34 px are left empty because macOS draws its menu bar there.
- One finger only: tap, hold and drag. No pinch or two-finger gestures.
