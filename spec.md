# Corsair Ctrl — agent panel for the XENEON EDGE (spec v0.2)

> 2026-11-19 · Status: **First build running — awaiting Drew's test on the Edge.** Project at `~/Code/corsair-ctrl`. App at `app/`; build with `bash app/build.sh`. Mock at `design/index.html`. Name: **Corsair Ctrl** (Ctrl family); working name was "Edge Ctrl". Method: spec → design → build. Spike files: `spike/`. Hardware notes: `claude/xeneon-edge-notes.md` in the original CYD project folder (`~/Documents/Claude/Projects/CYD/`).

v0.2 folds the spike results into v0.1. Earlier decisions are kept as written.

## Purpose
A always-on touch panel on the Corsair XENEON EDGE (2560 × 720) beside the Mac, for testing agentic workflows: see which Claude Code sessions need attention, jump to them, and talk to Claude without touching the keyboard.

## Decisions (newest first)
- 2026-11-19 — **Folder renamed to `~/Code/corsair-ctrl`** and put under git. The spike moved to `spike/` and keeps its Edge Ctrl name. Earlier entries below that say `~/Code/edge-ctrl` refer to this folder.
- 2026-11-19 — **First hands-on test** (Drew): dictation, hold to talk, the Apps strip, hook install from the panel and a live session card all work. A tap was once rejected when the panel was slow to answer the touch driver; slow lookups moved off the main thread and the panel now hands focus back if it is ever activated.
- 2026-11-19 — **First build (v0.1.0).** `app/` builds `Corsair Ctrl.app`, bundle id `com.woodwerd.corsairctrl`, listening on 127.0.0.1:47616. Tested with simulated hook events: states, the last-eight rule and restart survival all pass. Not yet tested by hand on the Edge.
- 2026-11-19 — **Go for build** (Drew). Carried into the build without a separate ruling: the proposed Edge tier (21 px body, 65 px minimum target), Flow Ctrl's red in the Voice area, and Apple Calendar for the next event.
- 2026-11-19 — **No prompt text on disk.** The hook forwarder writes nothing; the app keeps only session id, folder, state and a short activity line ("Prompt sent", "Using Edit"). Claude's own permission message is shown as written.
- 2026-11-19 — **Weather comes from Open-Meteo** (no key). It sends the configured coordinates and nothing else, every 15 minutes. It is the app's only outside request and can be switched off in `config.json`.
- 2026-11-19 — **Apps strip shows each app's own icon**; the front app gets an ink outline, a closed app is dimmed.
- 2026-11-19 — A finished card goes back to Idle when tapped. "Claude is waiting for your input" counts as Done, not Needs you.
- 2026-11-19 — **The agent board keeps the last eight sessions** (Drew). A card stays until a ninth, more recent session pushes it off. The board does not rely on a session-ended event, and there is no paging.
- 2026-11-19 — **Named Corsair Ctrl** (Drew). Replaces the working name Edge Ctrl. The folder `~/Code/edge-ctrl`, the spike app and its bundle id keep the old name until the real app is built.
- 2026-11-19 — **Apps strip added** (Drew): a narrow area between the agent board and voice with four app tiles to jump between, starting with Claude, Fusion, the browser and Finder. Layout becomes glance | agent board | apps | voice. See `design/design.md`.
- 2026-11-19 — **Voice matches the shipped Flow Ctrl v1.1.0 face** (Drew, on reviewing the first mock): red hands-free, its icons, the black pill, Send and Send now.
- 2026-11-19 — Design started. First mock at `design/index.html`, notes at `design/design.md`.
- 2026-11-19 — Spike run on Drew's Mac; all four risks answered (see Spike results). Design can start.
- 2026-11-19 — Touch driver = **ajvwhite/MacXeneonEdgeTouchDriver**, installed from source at `~/Code/MacXeneonEdgeTouchDriver`. It works; the alax driver was not tested and is dropped unless ajvwhite fails later.
- 2026-11-19 — The panel window must read to macOS Accessibility as a **floating dialog whose focus cannot be set**, and must answer hit tests with the window itself. The driver ignores every tap otherwise. This is a hard requirement of the driver, not a style choice.
- 2026-11-19 — The app is a signed **.app bundle** (bundle id `com.woodwerd.edgectrl.spike` for the spike), signed with a stable certificate. An ad-hoc signature changes on every rebuild and breaks the Accessibility permission each time.
- 2026-11-19 — **Hold to talk stays a true hold.** The driver passes the real press length, so no tap-to-start fallback is needed.
- 2026-11-19 — Spike moved from `~/Documents/Claude/Projects/CYD/edge-ctrl/` to `~/Code/edge-ctrl/`, with the other Ctrl projects. macOS blocks Claude Code from the Documents folder.
- 2026-11-19 — Spike built: hook forwarder + installer, Swift non-activating panel (WKWebView, local server 127.0.0.1:47615, Wispr CGEvent keys), test sheet. Swift not compiled in the cloud — first build on Drew's Mac.
- 2026-11-19 — Claude Code runs in the **Claude desktop app (Code tab)**. Tap-to-jump targets that app.
- 2026-11-19 — Voice target = **Wispr Flow** (same chords as CYD Flow Ctrl).
- 2026-11-19 — Layout: glance | agent board | voice. Flow Ctrl (voice) on the **right**.
- 2026-11-19 — Agent board tracks **Claude Code sessions first** (hook-driven live state). Claude Desktop chats deferred.
- 2026-11-19 — Build path: Mac kiosk app + open-source touch driver (not iCUE widgets).

## Spike results (2026-11-19)

| Risk | Result | Evidence |
|---|---|---|
| 1. Hooks fire from the desktop app's Code tab | Passed | `UserPromptSubmit`, `PreToolUse` and `Stop` arrive with session id and working folder. `SessionStart`, `Notification` and `SessionEnd` not yet seen. |
| 2. Jump to a specific session | Partly | A card tap brings the Claude app to the front. Landing on the exact session is unsolved; the fallback in v0.1 stands. |
| 3. Non-activating panel + touch driver | Passed | Taps land on the right buttons and the front app never changes. Needed the Accessibility change recorded in Decisions. |
| 4. Hold through the driver | Passed | Presses read 239, 470 and 726 ms. A full 2-second hold to talk has not been tried. |
| Dictation lands in the working app | Passed once | Hands-free, speak, Stop put Wispr text into TextEdit with TextEdit still in front. Not repeated since the app was re-signed. |
| Scale | Passed | Panel reports `2560×720 pt · 1x`. |

Not yet checked: the amber **Needs you** state (no permission request came through during the spike), and the voice keys after re-signing.

## Layout (native 2560 × 720, 1x, no scaling)
Golden-ratio split, proportions only — nothing drawn:
2560 → 1582 + 978; 978 → 604 + 374. The Apps strip (144) is cut from the 1582, so the agent board is 1438.

| Zone | x | Width | Content |
|---|---|---|---|
| Glance | 0 | 374 | Time, weather, next calendar event |
| Agent board | 374 | 1438 | One card per active Claude Code session |
| Apps | 1812 | 144 | Four tiles to jump between apps |
| Voice (Flow Ctrl) | 1956 | 604 | Hold to talk · Hands-free/Stop · Send · Send now · Discard · New chat |

Touch is one finger only. The driver supports tap, double-tap, hold and drag, plus an optional one-finger scroll mode. No pinch or two-finger gestures. Large targets; minimum target to be set during design.

The top 30 pt of the EDGE is the macOS menu bar when the display has one. Taps there go to the menu bar, not the panel. Design should keep controls clear of it or hide the menu bar on that display.

## Zone specs

### Agent board
- Card per Claude Code session: project/folder name, state, time in state, last activity line.
- States: **Needs you** (permission request or question) · **Working** · **Done** (finished, unread) · **Idle**.
- Sort within the eight: Needs you first, then Working, then Done, then Idle; newest first within a state.
- Tap a card → bring the Claude desktop app to the front, on that session if possible.
- Holds the eight most recently active sessions. "Active" means the session sent any hook event; the newest event sets its place in the eight. Older sessions fall off. No paging, no scrolling gestures.
- Source: Claude Code hooks (SessionStart, UserPromptSubmit, PreToolUse, Notification, Stop, SessionEnd) post events to the local helper.
- The eight are saved (session id, folder, state, short last-activity line, time) so the board comes back after an app restart. The spike kept them in memory only and lost them on every restart.
- A `SessionEnd` event, if one arrives, removes that card early. The spike never saw one from the desktop app, so nothing depends on it.

### Voice (Flow Ctrl)
- Same behaviour as CYD Flow Ctrl: Hold to talk (Wispr chord Ctrl+Opt+T held), Hands-free (double-tap chord), Stop, Send (Return), Discard (Esc), New chat.
- Keys sent by the Mac helper via CGEvent — not BLE. This needs the Accessibility permission for the app.
- Panel must **never take focus**, so dictation lands in the app Drew is working in.

### Apps
- Four tiles: Claude, Fusion, the browser, Finder. Tap a tile to bring that app to the front; if it is not running, start it.
- The tile for the front app is marked. A tile for an app that is not running says so.
- Uses the same route as tap-to-jump, which the spike proved for Claude.

### Glance
- Time, current weather (Austin), next calendar event.
- Weather + calendar refresh on an interval; show last good data with a stale marker when offline.

## Architecture
- **Corsair Ctrl.app** (Swift): non-activating, borderless floating panel pinned to the EDGE display; hosts the web UI in a WKWebView. Presents to Accessibility as a floating dialog (see Decisions). Signed with a stable certificate. Starts at login.
- **Web UI** (HTML/CSS/JS): WOODWERD Digital design system. Can later be repackaged as an iCUE widget.
- **Helper** (in the app): local endpoint receiving Claude Code hook events; session registry; keystroke sender; focus/jump action.
- **Touch driver**: ajvwhite/MacXeneonEdgeTouchDriver. Runs as a login service; needs Accessibility + Input Monitoring. It only clicks inside app windows — the bare desktop and menu bar do not respond.

## Privacy note
The spike's hook forwarder writes every hook event, including full prompt text from every Claude Code session on the Mac, to `~/Library/Logs/EdgeCtrl/hooks.jsonl` in plain text. That covers all focus areas. The real app should keep only what the cards need (session id, folder, state, a short last-activity line) and should not store prompt text on disk. Remove the spike hooks with `bash ~/Code/edge-ctrl/hooks/install-hooks.sh remove`.

## Out of scope for v1
Claude Desktop chat list · media controls · system stats · multi-touch · iCUE widget packaging · Windows.

## Open questions
1. Calendar source: Google Calendar (drew@woodwerd.com) or Apple Calendar?
2. Jump to the exact session: is there any route into a specific Code tab session, or does the card just name it?
3. Menu bar on the EDGE: hide it, or design around the top 30 pt?

Closed: which touch driver wins the test (ajvwhite) · agent board overflow (keep the last eight).

## Verify on first build
Panel never steals focus from the front app · taps land in the right zone at 1x · hook events arrive and cards change state · Needs-you card turns amber on a permission request · tap-to-jump fronts the Claude app · Wispr chords work with any app in front · board survives an app restart · runs at login with the EDGE attached.
