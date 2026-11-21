# Corsair Ctrl — Claude instructions

Corsair Ctrl is a Mac app that turns the Corsair XENEON EDGE (2560 × 720 touch display) into a control panel: Glance, a fold rail, the Agents board of Claude Code sessions with a key row under it, the Apps strip, Media Ctrl and Flow Ctrl. A Swift app hosts one web page in a panel that never takes focus.

## Read first
1. `~/WOODWERD-Claude/conventions.md` and `context/`.
2. [spec.md](spec.md), in this repo. It is the source of truth: a status line that gets overwritten, and decisions that are append-only, dated, newest first.
3. The WOODWERD Digital design system (the `woodwerd-digital` skill) before any design change.
4. [README.md](README.md) for what a user sees and does.

Focus area: AI and tech lab. RANGERA and AVINI never cross into this repo.

## Words
- The display is **the Corsair**, never "the Edge". "XENEON EDGE" is used only where the product is named in full.
- The areas are Glance, Agents, Apps, Media Ctrl and Flow Ctrl. WOODWERD is always capitalized.

## Build and run
- `bash app/build.sh` compiles `app/Sources/*.swift`, copies `app/web/` into the bundle and signs it. There is no Xcode project.
- `pkill -x CorsairCtrl` then `open "app/build/Corsair Ctrl.app"` restarts it. The running panel does not pick up a page edit until it is rebuilt.
- Log: `~/Library/Logs/CorsairCtrl/app.log`. Every key press, hook event and window move writes a line. Read it before saying something works.
- `app/web/index.html` opened in a browser is the preview: with no app behind it, it shows sample data. Flags: `?theme=dark`, `nohooks`, `noax`, `nomedia`, `keys`, `empty`.
- Site: `bash tools/site.sh` prepares `docs/`, then `mkdocs build --strict` with `WOODWERD/ctrl-docs-theme` checked out as `docs-theme/`. The Pages workflow does the same on every push to `main`.

## Rules that are easy to break
- **Keep the main thread free.** The touch driver gives the panel 50 ms to answer each Accessibility query and drops the tap otherwise. AppleScript, Accessibility calls to other apps, Launch Services, EventKit and anything that starts a process run on a background queue.
- **The panel window's Accessibility shape is a requirement of the touch driver**, not a style choice: a floating dialog whose focus cannot be set, answering hit tests with itself. See `app/Sources/Panel.swift` and the spec before touching it.
- **Sign with a stable certificate.** An ad hoc signature changes on each build and macOS drops the Accessibility permission.
- **No prompt text on disk.** Hook payloads are read and discarded. Session titles stay in memory. Nothing personal goes in the log, tests, sample data or screenshots; `docs/panel.png` is taken from the page's sample data.
- **The panel must never take focus**, so keys and dictation land in the app the user was working in.
- **One class name, one meaning in the page.** `app/web/index.html` is a single file; a new style named like an old one has already broken a button once.
- **Moving another app's window is visible and surprising.** Do it only on an explicit user action, and keep a way back.

## With each version
Bump `VERSION` in `app/Sources/main.swift`, the version string in `app/build.sh`, the sample-data version in `app/web/index.html` and `extra.version` in `mkdocs.yml`. Add a dated decision to `spec.md`, update its status line, and add a plain entry to `CHANGELOG.md`, in the same commit.

## Working with Drew
- Call him Drew. Plain and direct, no exclamation points.
- Spec first: spec, then design, then build. Show a change on the Corsair before calling it done.
- Give exact commands, say what each does, and flag anything risky first.
- Commit or push only when asked. The repo `WOODWERD/corsair-ctrl` is public: before each commit, scan the staged changes for emails, personal paths and secrets.
- Say what was tested by hand, what was only checked in the browser preview, and what was not tested.
