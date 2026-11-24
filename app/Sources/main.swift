// Corsair Ctrl — agent panel for the Corsair XENEON EDGE.
// A non-activating floating panel on the Corsair that shows Claude Code sessions, jumps
// between apps, and sends the Wispr Flow voice keys. See ../../spec.md.

import Cocoa
import WebKit
import ServiceManagement
import ApplicationServices

let PORT: UInt16 = 47616
let VERSION = "0.4.9"
let CLAUDE_BUNDLE = "com.anthropic.claudefordesktop"

struct Config: Codable {
    var apps: [String] = [CLAUDE_BUNDLE, "com.autodesk.fusion360", "com.google.Chrome", "com.apple.finder"]
    var weatherEnabled = true
    var place = "Austin"
    var latitude = 30.27
    var longitude = -97.74

    static func load(_ dir: URL) -> Config {
        let url = dir.appendingPathComponent("config.json")
        if let d = try? Data(contentsOf: url), let c = try? JSONDecoder().decode(Config.self, from: d) { return c }
        let c = Config()
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let d = try? enc.encode(c) { try? d.write(to: url) }
        return c
    }
}

final class App: NSObject, NSApplicationDelegate, WKScriptMessageHandler, WKNavigationDelegate {
    private var panel: CorsairPanel!
    private var web: CorsairWeb!
    private let store: SessionStore
    private let hooks: Hooks
    private let apps: Apps
    private let glance: Glance
    private let keys = Keys()
    private let links = SessionLinks()
    private let media = Media()
    private let dockGuard = DockGuard()
    private var dock = ""
    private var server: Server?
    private var front = NSWorkspace.shared.frontmostApplication
    private var markupTurn = 0
    private var shottrInstalled = false
    /// The app Grab markup uses: the one chosen in Settings, or Preview when Shottr is not installed.
    private var markupApp: String {
        shottrInstalled && UserDefaults.standard.string(forKey: "markup") != "preview" ? "shottr" : "preview"
    }
    private var touchRunning = false
    private var folded = UserDefaults.standard.bool(forKey: "folded")
    private var iconsSent: Set<String> = []
    private var loginEnabled = false
    private var lastLine = ""
    private var pageReady = false
    private var pushQueued = false
    private var titlesAt = 0.0
    private let clock: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f }()

    override init() {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/CorsairCtrl")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let cfg = Config.load(dir)
        store = SessionStore(dir: dir)
        hooks = Hooks(dir: dir, port: PORT)
        apps = Apps(ids: Array(cfg.apps.prefix(4)))
        glance = Glance(place: .init(enabled: cfg.weatherEnabled, label: cfg.place, latitude: cfg.latitude, longitude: cfg.longitude))
        super.init()
    }

    // MARK: Launch

    func applicationDidFinishLaunching(_ note: Notification) {
        NSApp.setActivationPolicy(.accessory)
        checkShottr()
        Log.write("[start] Corsair Ctrl \(VERSION)")

        // Ask once for Accessibility; the voice keys need it.
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        Log.write("[start] accessibility trusted: \(AXIsProcessTrustedWithOptions(opts))")

        server = Server(port: PORT, onEvent: { [weak self] body in self?.hookEvent(body) }, onFail: { reason in
            Log.write("[fatal] cannot listen on 127.0.0.1:\(PORT): \(reason). Is Corsair Ctrl already running?")
            NSApp.terminate(nil)
        })
        if server == nil { Log.write("[fatal] cannot create the local listener"); NSApp.terminate(nil); return }

        panel = CorsairPanel(contentRect: NSRect(x: 0, y: 0, width: 2560, height: 720),
                          styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.backgroundColor = .black

        let cfg = WKWebViewConfiguration()
        cfg.userContentController.add(self, name: "ctrl")
        web = CorsairWeb(frame: panel.contentLayoutRect, configuration: cfg)
        web.autoresizingMask = [.width, .height]
        web.navigationDelegate = self
        panel.contentView = web
        let dir = (Bundle.main.resourceURL ?? Bundle.main.bundleURL).appendingPathComponent("web")
        web.loadFileURL(dir.appendingPathComponent("index.html"), allowingReadAccessTo: dir)

        place()
        observe()
        let open = apps.state(frontID: "").filter { $0["pinned"] as? Bool == false }.compactMap { $0["name"] as? String }
        Log.write("[apps] open, most recent first: \(open.joined(separator: ", "))")
        glance.onChange = { [weak self] in self?.push() }
        media.onChange = { [weak self] in self?.push() }
        media.onNote = { [weak self] line in self?.note(line) }
        media.start()
        glance.refreshWeather()
        glance.refreshCalendar()
        placeStartApp(open: true)
        // One-off repair: `defaults write com.woodwerd.corsairctrl returnApp <bundle id>` puts that app's window back on the main display at the next start.
        if let id = UserDefaults.standard.string(forKey: "returnApp") {
            UserDefaults.standard.removeObject(forKey: "returnApp")
            returnWindow(id: id, name: id)
        }
        refreshStatus()
        dockGuard.onChange = { [weak self] state in self?.dock = state.rawValue; self?.push() }
        // One-off test: `defaults write com.woodwerd.corsairctrl dockGuardTest -bool true` makes the next start
        // behave as if the Dock were on the Corsair, which restarts the Dock once.
        if UserDefaults.standard.bool(forKey: "dockGuardTest") {
            UserDefaults.standard.removeObject(forKey: "dockGuardTest")
            Log.write("[dock] test: behaving as if the Dock were on the Corsair")
            dockGuard.pretendOnce()
        }
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.checkDock() }
        Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in self?.refreshStatus() }
        Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { [weak self] _ in self?.glance.refreshWeather() }
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.glance.refreshCalendar() }
    }

    func applicationWillTerminate(_ note: Notification) { keys.release() }

    // MARK: Screen

    /// The Corsair is the very wide screen (2560 × 720 is 3.56:1). CORSAIR_SCREEN=<n> forces one.
    private func corsairScreen() -> NSScreen? {
        if let v = ProcessInfo.processInfo.environment["CORSAIR_SCREEN"], let i = Int(v), i < NSScreen.screens.count {
            return NSScreen.screens[i]
        }
        return NSScreen.screens.first { $0.frame.width / $0.frame.height > 3.2 }
    }

    /// The app chosen in Settings is opened and its window moved into the part of the Corsair
    /// to the right of the fold rail, so it shows when the panel is folded. Done once, at
    /// start or when the choice is made; a window dragged away later is left alone.
    /// Accessibility calls can wait on the other app, so they run off the main thread.
    private func placeStartApp(open: Bool) {
        guard let id = UserDefaults.standard.string(forKey: "startApp") else { return }
        let name = UserDefaults.standard.string(forKey: "startAppName") ?? id
        if open, let u = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            let cfg = NSWorkspace.OpenConfiguration()
            cfg.activates = false
            NSWorkspace.shared.openApplication(at: u, configuration: cfg) { _, _ in }
        }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            // At login the app, its window and the Corsair itself can all arrive late: keep trying for a minute.
            for _ in 0..<60 {
                guard UserDefaults.standard.string(forKey: "startApp") == id else { return }   // the choice changed
                var target: CGRect?
                var pid: pid_t?
                DispatchQueue.main.sync {
                    guard let self, let s = self.corsairScreen(), let primary = NSScreen.screens.first else { return }
                    let left = s.frame.minX + (439 * s.frame.height / 720).rounded()
                    let v = s.visibleFrame
                    // Accessibility measures from the top left of the main screen.
                    target = CGRect(x: left, y: primary.frame.maxY - v.maxY, width: s.frame.maxX - left, height: v.height)
                    pid = NSRunningApplication.runningApplications(withBundleIdentifier: id).first?.processIdentifier
                }
                if let target, let pid, AXIsProcessTrusted() {
                    let app = AXUIElementCreateApplication(pid)
                    AXUIElementSetMessagingTimeout(app, 1)
                    var ref: CFTypeRef?
                    if AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &ref) == .success,
                       let win = (ref as? [AXUIElement])?.first {
                        // A full-screen window cannot be moved, and does not need to be when it is on the Corsair.
                        var fs: CFTypeRef?
                        AXUIElementCopyAttributeValue(win, "AXFullScreen" as CFString, &fs)
                        var at = CGPoint(x: -99999, y: -99999)
                        func whereIsIt() {
                            var pr: CFTypeRef?
                            if AXUIElementCopyAttributeValue(win, kAXPositionAttribute as CFString, &pr) == .success, let v = pr {
                                AXValueGetValue(v as! AXValue, .cgPoint, &at)
                            }
                        }
                        if fs as? Bool == true {
                            whereIsIt()
                            let here = at.x >= target.minX - 480 && at.x < target.maxX && abs(at.y - target.minY) < 60
                            Log.write("[place] \(name) is full screen \(here ? "on the Corsair" : "on another display"); left as it is")
                            DispatchQueue.main.async { self?.note(here ? "\(name) is full screen on the Corsair" : "\(name) is full screen on another display; not moved") }
                            return
                        }
                        var p = target.origin, z = target.size
                        // Remember where the window was, so turning the setting off can put it back.
                        if !open {
                            whereIsIt()
                            var was = CGSize.zero
                            var sr: CFTypeRef?
                            if AXUIElementCopyAttributeValue(win, kAXSizeAttribute as CFString, &sr) == .success, let v = sr {
                                AXValueGetValue(v as! AXValue, .cgSize, &was)
                            }
                            if was.width > 100, abs(at.x - p.x) > 40 || abs(at.y - p.y) > 40 {
                                UserDefaults.standard.set("\(Int(at.x)),\(Int(at.y)),\(Int(was.width)),\(Int(was.height))", forKey: "startAppWas")
                            }
                        }
                        if let pv = AXValueCreate(.cgPoint, &p), let zv = AXValueCreate(.cgSize, &z) {
                            AXUIElementSetAttributeValue(win, kAXPositionAttribute as CFString, pv)
                            AXUIElementSetAttributeValue(win, kAXSizeAttribute as CFString, zv)
                            AXUIElementSetAttributeValue(win, kAXPositionAttribute as CFString, pv)
                            // Trust where the window ended up, not the return codes.
                            whereIsIt()
                            let ok = abs(at.x - p.x) < 40 && abs(at.y - p.y) < 40
                            Log.write("[place] \(name) window \(ok ? "moved" : "could not be moved") to x \(Int(p.x)) y \(Int(p.y)), \(Int(z.width)) × \(Int(z.height))\(ok ? "" : "; it is at x \(Int(at.x)) y \(Int(at.y))")")
                            DispatchQueue.main.async { self?.note(ok ? "\(name) placed beside the panel" : "\(name) would not let its window be moved") }
                            return
                        }
                    }
                }
                Thread.sleep(forTimeInterval: 1)
            }
            Log.write("[place] gave up on \(name): no window, no Corsair, or no Accessibility")
        }
    }

    /// Puts an app's window back where it was before the panel moved it, or, when that is
    /// not known, onto the main display.
    private func returnWindow(id: String, name: String) {
        let saved = (UserDefaults.standard.string(forKey: "startAppWas") ?? "").split(separator: ",").compactMap { Double($0) }
        UserDefaults.standard.removeObject(forKey: "startAppWas")
        guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: id).first?.processIdentifier,
              let primary = NSScreen.screens.first else { return }
        let v = primary.visibleFrame
        var rect = CGRect(x: v.minX + v.width * 0.1, y: primary.frame.maxY - v.maxY + v.height * 0.05, width: v.width * 0.8, height: v.height * 0.9)
        if saved.count == 4 { rect = CGRect(x: saved[0], y: saved[1], width: saved[2], height: saved[3]) }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, 1)
            var ref: CFTypeRef?
            guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &ref) == .success,
                  let win = (ref as? [AXUIElement])?.first else { Log.write("[place] \(name): no window to put back"); return }
            var p = rect.origin, z = rect.size
            guard let pv = AXValueCreate(.cgPoint, &p), let zv = AXValueCreate(.cgSize, &z) else { return }
            AXUIElementSetAttributeValue(win, kAXPositionAttribute as CFString, pv)
            AXUIElementSetAttributeValue(win, kAXSizeAttribute as CFString, zv)
            AXUIElementSetAttributeValue(win, kAXPositionAttribute as CFString, pv)
            Log.write("[place] \(name) window put back at x \(Int(p.x)) y \(Int(p.y)), \(Int(z.width)) × \(Int(z.height))")
            DispatchQueue.main.async { self?.note("\(name) window put back") }
        }
    }

    /// Show on the Corsair. With no Corsair attached, hide rather than cover another display.
    /// Hands the Corsair's place on the desktop to the Dock guard, which looks off the main thread.
    private func checkDock() {
        guard let screen = corsairScreen(),
              let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return }
        dockGuard.check(display: CGDisplayBounds(id))
    }

    private func place() {
        if let s = corsairScreen() {
            // Folded, the window shrinks to Glance and the fold rail (439 of 2560), on the left,
            // and whatever is behind the rest of the screen can be seen and used.
            var frame = s.frame
            if folded { frame.size.width = (439 * s.frame.height / 720).rounded() }
            panel.setFrame(frame, display: true)
            panel.orderFrontRegardless()
        } else if panel.isVisible {
            panel.orderOut(nil)
            Log.write("[screen] no Corsair display found; panel hidden")
        }
    }

    private func observe() {
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            let a = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            // The panel is never where typing goes, so it never counts as the front app.
            if let a, a.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                self?.front = a
                if let id = a.bundleIdentifier { self?.apps.used(id) }
            }
            self?.push()
        }
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.push() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in self?.place() }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            // The touch driver activates the panel when it cannot confirm it as a passive dialog
            // in time. Hand the keyboard straight back to the app the user was in.
            Log.write("[focus] the panel became the active app; returning focus to \(self?.front?.localizedName ?? "nothing")")
            self?.front?.activate()
            self?.checkDock()
        }
    }

    // MARK: Status

    /// Picks up chat names from the Claude app for the cards on the board. A name
    /// appears a little after a session's first prompt and can be changed later, so
    /// this runs on the status timer and, no more than every three seconds, on events.
    private func refreshTitles(force: Bool = false) {
        let now = CFAbsoluteTimeGetCurrent()
        guard force || now - titlesAt > 3 else { return }
        titlesAt = now
        links.refreshTitles(store.top.map(\.id)) { [weak self] changed in if changed { self?.push() } }
    }

    private func refreshStatus() {
        hooks.refresh()
        refreshTitles(force: true)
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
            p.arguments = ["-x", "MacXeneonEdgeTouchDriver"]
            p.standardOutput = Pipe(); p.standardError = Pipe()
            let ok = (try? p.run()) != nil
            if ok { p.waitUntilExit() }
            let running = ok && p.terminationStatus == 0
            let login = SMAppService.mainApp.status == .enabled
            DispatchQueue.main.async { self?.touchRunning = running; self?.loginEnabled = login; self?.push() }
        }
    }

    private var wisprRunning: Bool {
        NSWorkspace.shared.runningApplications.contains { ($0.localizedName ?? "").contains("Wispr Flow") }
    }

    private func note(_ line: String) {
        lastLine = "\(clock.string(from: Date()))  \(line)"
        Log.write("[event] \(line)")
        push()
    }

    // MARK: Grabs

    /// Presses this Mac's own shortcut for "copy picture of selected area to the clipboard".
    /// It can be changed in System Settings > Keyboard > Keyboard Shortcuts > Screenshots,
    /// so read what it is set to rather than assume Command-Control-Shift-4.
    /// False when the shortcut is switched off.
    private func pressAreaGrab(_ what: String) -> Bool {
        var code: CGKeyCode = 21
        var flags: CGEventFlags = [.maskCommand, .maskControl, .maskShift]
        let hot = (UserDefaults(suiteName: "com.apple.symbolichotkeys")?.dictionary(forKey: "AppleSymbolicHotKeys")?["31"] as? [String: Any])
        if let hot {
            guard (hot["enabled"] as? NSNumber)?.boolValue != false else {
                note("The Mac's shortcut for copying a screen area is switched off in Keyboard settings"); return false
            }
            if let p = (hot["value"] as? [String: Any])?["parameters"] as? [NSNumber], p.count >= 3 {
                code = CGKeyCode(p[1].intValue)
                flags = CGEventFlags(rawValue: UInt64(p[2].intValue))
            }
        }
        Log.write("[grab] \(what): key code \(code), modifiers \(flags.rawValue)")
        keys.shortcut(code, flags)
        return true
    }

    /// Looks for Shottr and then calls `done` on the main thread. Launch Services is slow,
    /// so the lookup is not made on the main thread.
    private func checkShottr(_ done: @escaping () -> Void = {}) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let found = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "cc.ffitch.shottr") != nil
            DispatchQueue.main.async {
                guard let self else { return }
                if found != self.shottrInstalled { self.shottrInstalled = found; self.push() }
                done()
            }
        }
    }

    /// An area capture through Shottr, which then opens it for marking up.
    /// Not activated: Shottr draws its crosshair over whatever is in front.
    private func markupInShottr() {
        guard let url = URL(string: "shottr://grab/area") else { return }
        Log.write("[grab] markup: shottr://grab/area")
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = false
        NSWorkspace.shared.open(url, configuration: cfg) { [weak self] _, err in
            DispatchQueue.main.async {
                self?.note(err == nil ? "Grab markup: drag with the mouse. It opens in Shottr."
                                      : "Grab markup: Shottr could not be opened")
            }
        }
    }

    /// Without Shottr: copy the area to the clipboard with the Mac's own shortcut, wait for
    /// the clipboard to change, then bring Preview forward and press its New from Clipboard
    /// (Command-N). The picture is never read by this app and never written to disk.
    private func markupInPreview() {
        let before = NSPasteboard.general.changeCount
        guard pressAreaGrab("markup, Preview") else { return }
        note("Grab markup: drag with the mouse. It opens in Preview.")
        markupTurn += 1
        let turn = markupTurn
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let say = { (line: String) in DispatchQueue.main.async { self?.note(line) } }
            // The capture ends when the mouse is let go, or never if Esc cancels it.
            var changed = false
            for _ in 0..<240 {
                Thread.sleep(forTimeInterval: 0.25)
                guard let self, self.markupTurn == turn else { return }   // a newer press took over
                if NSPasteboard.general.changeCount != before { changed = true; break }
            }
            guard changed else { Log.write("[grab] markup: nothing was captured within a minute"); return }
            // Only the kinds of thing on the clipboard are looked at, not the picture.
            let kinds = NSPasteboard.general.types ?? []
            guard kinds.contains(.png) || kinds.contains(.tiff) else {
                say("Grab markup: the clipboard changed, but not to a picture"); return
            }
            guard let preview = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Preview") else {
                say("Grab markup: Preview was not found. The picture is on the clipboard."); return
            }
            let cold = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Preview").isEmpty
            let cfg = NSWorkspace.OpenConfiguration()
            cfg.activates = true
            NSWorkspace.shared.openApplication(at: preview, configuration: cfg) { app, err in
                guard let app, err == nil else { say("Grab markup: Preview could not be opened. The picture is on the clipboard."); return }
                // Command-N must land in Preview, so wait until it is the app in front.
                var front = false
                for _ in 0..<40 {
                    if app.isActive { front = true; break }
                    Thread.sleep(forTimeInterval: 0.1)
                }
                guard front else { say("Grab markup: Preview did not come forward. The picture is on the clipboard."); return }
                Thread.sleep(forTimeInterval: cold ? 1.2 : 0.3)
                DispatchQueue.main.async {
                    guard let self, self.markupTurn == turn else { return }
                    self.keys.shortcut(45, .maskCommand)   // N
                    self.note("Grab markup: opened in Preview")
                }
            }
        }
    }

    // MARK: Hook events

    private func hookEvent(_ body: Data) {
        guard let j = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] else { return }
        if let line = store.handle(j) { note(line); refreshTitles() }
    }

    // MARK: Page bridge

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        pageReady = true
        iconsSent = []
        push()
    }

    private func send(_ fn: String, _ value: Any) {
        guard pageReady, let d = try? JSONSerialization.data(withJSONObject: value),
              let js = String(data: d, encoding: .utf8) else { return }
        web.evaluateJavaScript("window.\(fn) && \(fn)(\(js))", completionHandler: nil)
    }

    /// Coalesces bursts of changes into one page update.
    private func push() {
        guard !pushQueued else { return }
        pushQueued = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.pushQueued = false
            let t0 = CFAbsoluteTimeGetCurrent()
            self.send("ctrlUpdate", self.snapshot())
            let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
            if ms > 20 { Log.write(String(format: "[slow] page update took %.0f ms on the main thread", ms)) }
        }
    }

    /// Sends the icon for any app the page has not been given yet.
    private func syncIcons(_ list: [[String: Any]]) {
        let wanted = list.compactMap { $0["id"] as? String }.filter { !iconsSent.contains($0) }
        guard !wanted.isEmpty else { return }
        iconsSent.formUnion(wanted)
        apps.icons(for: wanted) { [weak self] found in self?.send("ctrlIcons", found) }
    }

    private func snapshot() -> [String: Any] {
        let appList = apps.state(frontID: front?.bundleIdentifier ?? "")
        syncIcons(appList)
        return [
            "version": VERSION,
            "theme": UserDefaults.standard.string(forKey: "theme") ?? "auto",
            "markup": markupApp,
            "shottr": shottrInstalled,
            "sessions": store.top.map { ["id": $0.id, "name": SessionStore.folder($0),
                                         "title": links.title(for: $0.id) ?? "", "state": $0.state,
                                         "since": $0.since, "last": $0.last] },
            "apps": appList,
            "front": front?.localizedName ?? "",
            "status": [
                "hooks": hooks.installed, "lastEvent": store.lastEvent, "touch": touchRunning,
                "ax": AXIsProcessTrusted(), "wispr": wisprRunning,
                "login": loginEnabled,
            ],
            "glance": glance.snapshot(),
            "media": media.state,
            "lastLine": lastLine,
            "folded": folded,
            "dock": dock,
            "startApp": UserDefaults.standard.string(forKey: "startAppName") ?? "",
        ]
    }

    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let m = message.body as? [String: Any], let action = m["action"] as? String else { return }
        switch action {
        case "key":
            let name = m["name"] as? String ?? ""
            guard AXIsProcessTrusted() else { note("Key not sent: Accessibility is not allowed"); return }
            if keys.perform(name), name != "pttUp" { note("Key \(name) → \(front?.localizedName ?? "?")") }
        case "edit":
            let key = m["key"] as? String ?? ""
            guard AXIsProcessTrusted() else { note("Key not sent: Accessibility is not allowed"); return }
            let app = front?.localizedName ?? "?"
            switch key {
            case "backspace":
                // Held, it repeats many times a second: say so once, not for every character.
                if keys.perform(key), m["repeat"] as? Bool != true { note("Delete → \(app)") }
            case "esc", "undo", "copy", "paste":
                if keys.perform(key) { note("\(key.capitalized) → \(app)") }
            case "switch", "switch-back":
                // Pages through every open app, one per press.
                if let id = apps.next(frontID: front?.bundleIdentifier ?? "", back: key == "switch-back") {
                    apps.activate(id) { [weak self] line in self?.note(line) }
                } else { note("No other app to switch to") }
            case "grab-markup":
                // Shottr or Preview, as chosen in Settings; Preview when Shottr is not installed.
                checkShottr { [weak self] in
                    guard let self else { return }
                    if self.markupApp == "shottr" { self.markupInShottr() } else { self.markupInPreview() }
                }
            case "grab-area":
                if pressAreaGrab("area") { note("Grab area: drag with the mouse. It goes to the clipboard.") }
            default: break
            }
        case "jump":
            guard let id = m["id"] as? String else { return }
            store.markRead(id)
            let name = store.sessions[id].map(SessionStore.folder) ?? "session"
            links.lookup(id) { [weak self] local in
                guard let self else { return }
                if let local, let url = SessionLinks.session(local) {
                    SessionLinks.open(url) { ok in self.note(ok ? "Opened \(name) in Claude" : "Could not open \(name)") }
                } else {
                    // No record of this session in the Claude app: bring the app forward instead.
                    self.apps.activate(CLAUDE_BUNDLE) { _ in self.note("Opened Claude; could not find \(name)") }
                }
            }
        case "new":
            let kind = m["what"] as? String ?? "chat"
            let (url, what) = kind == "code" ? (SessionLinks.newCode, "New Code session")
                : kind == "cowork" ? (SessionLinks.newCowork, "New Cowork task") : (SessionLinks.newChat, "New chat")
            SessionLinks.open(url) { [weak self] ok in
                self?.note(ok ? "\(what) in Claude" : "\(what) could not be opened")
            }
        case "app":
            if let id = m["id"] as? String { apps.activate(id) { [weak self] line in self?.note(line) } }
        case "hooks":
            let mode = m["mode"] as? String == "remove" ? "remove" : "install"
            if let problem = hooks.apply(mode) { note(problem) }
            else { note(mode == "install" ? "Session hooks installed" : "Session hooks removed") }
        case "media":
            guard let cmd = m["cmd"] as? String else { return }
            media.command(cmd, value: (m["value"] as? NSNumber)?.doubleValue)
        case "fold":
            folded = m["on"] as? Bool ?? !folded
            UserDefaults.standard.set(folded, forKey: "folded")
            place()
            note(folded ? "Panel folded away" : "Panel brought back")
        case "startapp":
            let d = UserDefaults.standard
            if m["on"] as? Bool == true {
                guard let a = front, let id = a.bundleIdentifier, id != Bundle.main.bundleIdentifier else { note("Bring the app to the front first, then set it"); return }
                let name = a.localizedName ?? id
                d.set(id, forKey: "startApp"); d.set(name, forKey: "startAppName")
                note("\(name) will open beside the panel at start")
                placeStartApp(open: false)
            } else {
                if let id = d.string(forKey: "startApp") { returnWindow(id: id, name: d.string(forKey: "startAppName") ?? id) }
                d.removeObject(forKey: "startApp"); d.removeObject(forKey: "startAppName")
                note("No app is opened at start")
            }
            push()
        case "markup":
            if let v = m["value"] as? String, ["shottr", "preview"].contains(v) {
                UserDefaults.standard.set(v, forKey: "markup")
                checkShottr { [weak self] in
                    guard let self else { return }
                    self.note("Grab markup uses \(self.markupApp == "shottr" ? "Shottr" : "Preview")")
                }
            }
        case "theme":
            if let t = m["value"] as? String, ["auto", "light", "dark"].contains(t) {
                UserDefaults.standard.set(t, forKey: "theme"); push()
            }
        case "login":
            do {
                if m["on"] as? Bool == true { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                loginEnabled = SMAppService.mainApp.status == .enabled
                note(loginEnabled ? "Starts at login" : "Does not start at login")
            } catch { note("Start at login was not changed: \(error.localizedDescription)") }
        case "calendar":
            glance.requestCalendar()
        case "accessibility":
            if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(u)
            }
        case "log":
            Log.write("[web] \(m["text"] as? String ?? "")")
        case "quit":
            Log.write("[quit] from Settings")
            NSApp.terminate(nil)
        default: break
        }
    }
}

setvbuf(stdout, nil, _IOLBF, 0)
let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.run()
