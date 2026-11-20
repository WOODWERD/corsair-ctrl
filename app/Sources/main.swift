// Corsair Ctrl — agent panel for the Corsair XENEON EDGE.
// A non-activating floating panel on the Corsair that shows Claude Code sessions, jumps
// between apps, and sends the Wispr Flow voice keys. See ../../spec.md.

import Cocoa
import WebKit
import ServiceManagement
import ApplicationServices

let PORT: UInt16 = 47616
let VERSION = "0.3.1"
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
    private var server: Server?
    private var front = NSWorkspace.shared.frontmostApplication
    private var touchRunning = false
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
        glance.onChange = { [weak self] in self?.push() }
        media.onChange = { [weak self] in self?.push() }
        media.onNote = { [weak self] line in self?.note(line) }
        media.start()
        glance.refreshWeather()
        glance.refreshCalendar()
        refreshStatus()
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

    /// Show on the Corsair. With no Corsair attached, hide rather than cover another display.
    private func place() {
        if let s = corsairScreen() {
            panel.setFrame(s.frame, display: true)
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
            if let a, a.processIdentifier != ProcessInfo.processInfo.processIdentifier { self?.front = a }
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
        ]
    }

    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let m = message.body as? [String: Any], let action = m["action"] as? String else { return }
        switch action {
        case "key":
            let name = m["name"] as? String ?? ""
            guard AXIsProcessTrusted() else { note("Key not sent: Accessibility is not allowed"); return }
            if keys.perform(name), name != "pttUp" { note("Key \(name) → \(front?.localizedName ?? "?")") }
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
