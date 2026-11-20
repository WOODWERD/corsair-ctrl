# Corsair Ctrl — design draft

> 2026-11-19 · Status: **Draft for Drew's review.** Nothing here is approved. Mock: `design/index.html`. Spec: `../spec.md` (v0.2). System: WOODWERD Digital.

Name: **Corsair Ctrl** (Drew, 2026-11-19). The working name was Edge Ctrl; only the spike in `spike/` still uses it.

## How to view
- Serve the folder and open it: `python3 -m http.server 47620 --bind 127.0.0.1 --directory ~/Code/corsair-ctrl/design`, then `http://localhost:47620/`.
- The selectors above the panel switch states. They are review chrome, not product.
- `?kiosk=1` shows the panel alone at true size, for viewing on the Corsair. `&theme=light` or `&theme=dark` forces a theme.

## Frame
2560 × 720, 1x. Four rows, all Fibonacci:

| Row | y | Height | Holds |
|---|---|---|---|
| Menu bar reserve | 0 | 34 | Nothing. macOS draws its menu bar over the top 30 pt. |
| Product header | 34 | 55 | Name at the far left, then the toolkit line, purpose, three live indicators, 2 px accent rule |
| Areas | 89 | 576 | Glance 374 · Agents 1438 · Apps 144 · Voice 604 |
| Footer | 665 | 55 | Maker's mark, tagline, last event line, version |

## Corsair tier (proposed addition to WOODWERD Digital)
- Physical: 14.5 in, about 355 × 100 mm, about 7.2 px/mm.
- Minimum touch target: 65 px (a 9 mm fingertip). Every control in the mock is 65 px or taller; the main ones are 89.
- Type: the root-phi scale applies here, from a 21 px body. 13 micro · 16.5 caption · 21 body · 26.7 h3 · 34 h2 · 55 h1.
- Spacing 3 5 8 13 21 34 55 89. Radius 8 controls, 13 containers.

## Areas

### 01 Glance
Clock, date, Austin weather, next calendar event, and a Settings button. Offline shows the last good data with the time it was read and a hollow dot. No guess is shown as live.

### 02 Agents
- Eight slots, four by two. Card: state, folder name, last activity (two lines), time in state, short session id.
- Needs you: orange outline and tint, sorted first. Working: pulsing green dot. Done: solid green dot. Idle: hollow dot, no surface.
- The area band carries the verdict: "2 need you", "3 working" or "Nothing waiting".
- The board holds the eight sessions Drew most recently worked in (decided 2026-11-19). A session stays until a ninth, newer one pushes it off; it does not depend on the session being closed. No paging.
- Within those eight, the order is Needs you, Working, Done, Idle, newest first in each group.
- Empty and not-set-up states say what is true and what to do.

### 03 Apps
Added 2026-11-19 at Drew's request: a narrow strip between Agents and Voice for jumping between the four apps he moves among most (Claude, Fusion, the browser, Finder).
- Four tiles stacked, each about 117 × 119 px. Tap one to bring that app forward.
- The app in front is ink-filled. An app that is not running shows a hollow dot; tapping it starts it.
- The mock shows letter tiles. The real app shows each app's own icon.
- Its 144 px comes out of the Agents width, so cards are 339 px wide instead of 375 and a long folder name such as "woodwerd-website" now ends in an ellipsis.

### 04 Voice
The Flow Ctrl v1.1.0 landscape face, scaled up: status and chips on top, the black pill, the cue line, Send and Send now. Colours and icons come from `cyd-flow-ctrl` (`src/theme.h`, `tools/make_icons.py`), redrawn as vectors so they stay sharp at this size.
- Status reads "Flow Ctrl" with "Lands in TextEdit" under it, naming the app the words will go to.
- Hands-free: red-outline chip with the slashed hand. Running, it fills red, the trash chip turns to a red-tinted ×, the waveform runs red, and the cue reads "2:14 · tap to stop".
- Hold to talk: the pill gains its outer ring and a white waveform; cue reads "Listening · release to paste"; Send and Send now dim.
- New chat sits where the CYD has its page selector. Transforms stay out, per the spec.
- No Accessibility permission: every control is disabled and the area says why.

### Settings sheet
Opens over the Glance column only. Theme (System, Light, Dark), status rows, Quit, Done. The spike had no way to quit from the panel.

## Answers proposed for the spec's open questions
1. **Board overflow:** settled by Drew. Keep the last eight sessions; older ones fall off. No paging.
2. **Calendar source:** Apple Calendar through EventKit. It is one permission prompt and no sign-in code, and it shows Google calendars too if the WOODWERD Google account is added in macOS Calendar.
3. **Exact session:** not solved. The card names the folder and session id; a tap opens Claude.
4. **Menu bar:** design around it. The top 34 px stays empty rather than changing a system-wide setting.

## Raised by the Apps strip
- The spec's golden split (374 · 1582 · 604) no longer holds exactly. The strip is a plain Fibonacci width cut from the Agents area.
- Which four apps, and whether the list is fixed or set in Settings, is not decided. The mock assumes Claude, Fusion, Chrome and Finder.

## Raised, not decided
These touch the design system or go past the spec. Each needs a yes or no from Drew.

1. **A new screen tier.** WOODWERD Digital has no tier for this panel. The Corsair tier above is a proposal.
2. **A display type step.** The clock uses 89 px, the phi-cubed step. The system's scale stops at 2.618 (55 px here).
3. **Bands.** The system says every surface carries a toolkit strip, header, content and footer. Here the toolkit line sits inside the header and there is no All tools menu, because a kiosk panel has nowhere to navigate to.
4. **Flow Ctrl's red.** Changed 2026-11-19 after Drew's review: the Voice area now matches the shipped Flow Ctrl face, red hands-free included. That sits outside WOODWERD Digital's rule that red means error only. Flow Ctrl's own theme defines red as "live or destructive", so either the system gains that meaning or Flow Ctrl is the stated exception.
5. **Flow Ctrl's chip colours.** The Voice area uses Flow Ctrl's surface and red tokens (`--chip`, `--pill`, `--live` and friends) beside the system tokens used everywhere else on the panel.
6. **Working state.** Shown as a pulsing green dot. The system ties "pulsing" to the attention colour, so this is an interpretation.
7. **Extra tokens.** `--attention-tint`, `--on-ok` and `--primary-soft` are not in the system's table.
8. **Send now is back in**, to match Flow Ctrl v1.1.0; the spec's list does not include it. The Transforms page is still left out.
9. **Added beyond the spec:** the Settings sheet with Quit, "Dictation lands in", and installing hooks from Settings.
10. **Toolkit pitch.** The system's open decision 7 (the kit is outgrowing the board) applies. The header says "Ctrl · a WOODWERD toolkit" and gives no CYD pitch.

## Checked
Rendered at 2560 × 720 in light and dark. On the Corsair itself the panel reported all five font files loaded (Inter 400, 500, 600; JetBrains Mono 400, 500) at 2560 × 720, 1x. No control is under 65 px. No text overflows its box in the sample states. Shown on the Corsair; Drew's review is in progress.
