// Edge Ctrl spike — bare test panel for the XENEON EDGE.
// Proves three things before any design work:
//   1. Claude Code hooks reach a local helper (cards change state).
//   2. Tapping a card can bring the Claude desktop app to the front.
//   3. Tapping the panel never steals focus from the app you're working in.
// Build: bash build.sh   Run: ./EdgeCtrlSpike   (EDGE_SCREEN=<n> to force a display)

import Cocoa
import WebKit
import Network
import ApplicationServices

let PORT: UInt16 = 47615
let CLAUDE_BUNDLE = "com.anthropic.claudefordesktop"

final class EdgePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    // The touch driver (ajvwhite) only clicks without activating the target app
    // when the window under the finger reads to Accessibility as a floating
    // dialog whose focus cannot be set. Report exactly that, and answer every
    // hit test with the window itself so the driver never sees WebKit's
    // out-of-process elements (their owner pid differs and it rejects the tap).
    override func accessibilityHitTest(_ point: NSPoint) -> Any? { self }
    override func accessibilityRole() -> NSAccessibility.Role? { .window }
    override func accessibilitySubrole() -> NSAccessibility.Subrole? { .dialog }
    override func isAccessibilityFocused() -> Bool { false }
    override func isAccessibilityMinimized() -> Bool { false }
    override func isAccessibilitySelectorAllowed(_ selector: Selector) -> Bool {
        if selector == #selector(setAccessibilityFocused(_:)) { return false }
        return super.isAccessibilitySelectorAllowed(selector)
    }
}

final class EdgeWeb: WKWebView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class App: NSObject, NSApplicationDelegate, WKScriptMessageHandler, WKNavigationDelegate {
    var panel: EdgePanel!
    var web: EdgeWeb!
    var listener: NWListener?
    var sessions: [String: [String: Any]] = [:]
    var events: [[String: Any]] = []
    var front = NSWorkspace.shared.frontmostApplication?.localizedName ?? "?"
    var stolen = 0
    let src = CGEventSource(stateID: .hidSystemState)

    var now: Double { Date().timeIntervalSince1970 }

    func applicationDidFinishLaunching(_ note: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(opts) {
            print("Accessibility not granted yet: voice keys won't send. Allow it for Edge Ctrl Spike (or Terminal, if run as a bare binary) in System Settings > Privacy & Security > Accessibility, then relaunch.")
        }

        appendLog("[start] accessibility trusted: \(AXIsProcessTrusted())")
        let screen = pickScreen()
        panel = EdgePanel(contentRect: screen.frame,
                          styleMask: [.borderless, .nonactivatingPanel],
                          backing: .buffered, defer: false)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.backgroundColor = .black

        let cfg = WKWebViewConfiguration()
        cfg.userContentController.add(self, name: "edge")
        web = EdgeWeb(frame: NSRect(origin: .zero, size: screen.frame.size), configuration: cfg)
        web.autoresizingMask = [.width, .height]
        web.navigationDelegate = self
        panel.contentView = web

        // Inside the .app bundle the page lives in Resources; a bare binary finds it alongside.
        var dir = (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0]))
            .resolvingSymlinksInPath().deletingLastPathComponent()
        if let res = Bundle.main.resourceURL,
           FileManager.default.fileExists(atPath: res.appendingPathComponent("index.html").path) { dir = res }
        // EDGE_PAGE=<path to an .html file> shows that page instead (used to view the
        // design mock on the Edge at true size). It is loaded with ?kiosk=1.
        if let custom = ProcessInfo.processInfo.environment["EDGE_PAGE"], !custom.isEmpty,
           FileManager.default.fileExists(atPath: custom) {
            let file = URL(fileURLWithPath: custom)
            var parts = URLComponents(url: file, resolvingAgainstBaseURL: false)!
            parts.query = "kiosk=1"
            web.loadFileURL(parts.url ?? file, allowingReadAccessTo: file.deletingLastPathComponent())
            appendLog("[start] showing custom page \(custom)")
        } else {
            web.loadFileURL(dir.appendingPathComponent("index.html"), allowingReadAccessTo: dir)
        }

        panel.setFrame(screen.frame, display: true)
        panel.orderFrontRegardless()

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            let a = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.front = a?.localizedName ?? "?"
            self?.push()
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.stolen += 1
            self?.logEvent("focus", "Edge panel became the active app")
        }

        startServer()
    }

    func pickScreen() -> NSScreen {
        for (i, s) in NSScreen.screens.enumerated() {
            print("Screen \(i): \(s.localizedName) \(Int(s.frame.width))x\(Int(s.frame.height)) pt, scale \(s.backingScaleFactor)")
        }
        if let v = ProcessInfo.processInfo.environment["EDGE_SCREEN"], let i = Int(v), i < NSScreen.screens.count {
            return NSScreen.screens[i]
        }
        return NSScreen.screens.first { $0.frame.width / $0.frame.height > 3.2 } ?? NSScreen.screens.last!
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { push() }

    // MARK: JS -> native

    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let m = message.body as? [String: Any], let action = m["action"] as? String else { return }
        switch action {
        case "jump": jump(m["id"] as? String)
        case "key": voice(m["name"] as? String ?? "")
        case "touch": logEvent("touch", m["text"] as? String ?? "")
        case "debug": appendLog("[web] " + (m["text"] as? String ?? ""))
        default: break
        }
    }

    func jump(_ id: String?) {
        let app = NSRunningApplication.runningApplications(withBundleIdentifier: CLAUDE_BUNDLE).first
            ?? NSWorkspace.shared.runningApplications.first { $0.localizedName == "Claude" }
        guard let a = app, let url = a.bundleURL else { logEvent("jump", "Claude app not running"); return }
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: cfg) { _, err in
            DispatchQueue.main.async {
                self.logEvent("jump", err == nil ? "Claude fronted (\(String((id ?? "").prefix(8))))" : "failed: \(err!.localizedDescription)")
            }
        }
    }

    // MARK: Voice keys (Wispr Flow chord Ctrl+Opt+T, same as CYD Flow Ctrl)

    let kT: CGKeyCode = 17, kCtrl: CGKeyCode = 59, kOpt: CGKeyCode = 58
    let kRet: CGKeyCode = 36, kEsc: CGKeyCode = 53, kSpace: CGKeyCode = 49

    func key(_ k: CGKeyCode, _ down: Bool, _ flags: CGEventFlags) {
        guard let e = CGEvent(keyboardEventSource: src, virtualKey: k, keyDown: down) else { return }
        e.flags = flags
        e.post(tap: .cghidEventTap)
    }
    func chordDown() {
        key(kCtrl, true, .maskControl)
        key(kOpt, true, [.maskControl, .maskAlternate])
        usleep(12_000)
        key(kT, true, [.maskControl, .maskAlternate])
    }
    func chordUp() {
        key(kT, false, [.maskControl, .maskAlternate])
        key(kOpt, false, .maskControl)
        key(kCtrl, false, [])
    }
    func tapChord() { chordDown(); usleep(60_000); chordUp() }

    func voice(_ name: String) {
        switch name {
        case "pttDown": chordDown()
        case "pttUp": chordUp()
        case "handsFree": tapChord(); usleep(120_000); tapChord()
        case "stop": tapChord()
        case "send": key(kRet, true, []); key(kRet, false, [])
        case "discard": key(kEsc, true, []); key(kEsc, false, [])
        case "newChat": key(kSpace, true, .maskAlternate); key(kSpace, false, .maskAlternate)
        default: return
        }
        logEvent("key", "\(name) → \(front)")
    }

    // MARK: Hook events

    func handle(_ body: Data) {
        guard let j = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] else {
            logEvent("bad", "unparsed hook body"); return
        }
        let ev = j["hook_event_name"] as? String ?? "?"
        let sid = j["session_id"] as? String ?? "unknown"
        let cwd = j["cwd"] as? String ?? ""
        let folder = cwd.isEmpty ? "?" : URL(fileURLWithPath: cwd).lastPathComponent
        var s = sessions[sid] ?? ["id": sid, "cwd": cwd, "state": "idle", "since": now, "last": ""]
        if !cwd.isEmpty { s["cwd"] = cwd }
        func mark(_ st: String, _ last: String?) {
            if s["state"] as? String != st { s["state"] = st; s["since"] = now }
            if let l = last { s["last"] = l }
        }
        switch ev {
        case "SessionStart": mark("idle", "Session started (\(j["source"] as? String ?? "?"))")
        case "UserPromptSubmit": mark("working", "› " + String((j["prompt"] as? String ?? "").prefix(90)))
        case "PreToolUse": mark("working", "Tool: \(j["tool_name"] as? String ?? "?")")
        case "Notification": mark("needs", j["message"] as? String ?? "Needs you")
        case "Stop": mark("done", nil)
        case "SessionEnd":
            sessions[sid] = nil
            logEvent(ev, "\(sid.prefix(8)) \(folder)")
            return
        default: break
        }
        sessions[sid] = s
        logEvent(ev, "\(sid.prefix(8)) \(folder)")
    }

    func logEvent(_ kind: String, _ detail: String) {
        events.insert(["t": now, "kind": kind, "detail": detail], at: 0)
        if events.count > 14 { events.removeLast(events.count - 14) }
        print("[\(kind)] \(detail)")
        appendLog("[\(kind)] \(detail)")
        push()
    }

    // stdout is lost when launched as an app, so keep a small log file too.
    let logURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/EdgeCtrl/panel.log")
    func appendLog(_ line: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        guard let d = "\(stamp) \(line)\n".data(using: .utf8) else { return }
        try? FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let h = try? FileHandle(forWritingTo: logURL) { h.seekToEndOfFile(); h.write(d); try? h.close() }
        else { try? d.write(to: logURL) }
    }

    func push() {
        guard web != nil else { return }
        let payload: [String: Any] = ["sessions": Array(sessions.values), "events": events,
                                      "front": front, "stolen": stolen]
        guard let d = try? JSONSerialization.data(withJSONObject: payload),
              let js = String(data: d, encoding: .utf8) else { return }
        web.evaluateJavaScript("window.edgeUpdate && edgeUpdate(\(js))", completionHandler: nil)
    }

    // MARK: Tiny local HTTP server (127.0.0.1 only)

    func startServer() {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: PORT)!)
        params.allowLocalEndpointReuse = true
        do { listener = try NWListener(using: params) } catch { print("Server failed: \(error)"); return }
        listener?.newConnectionHandler = { [weak self] c in
            c.start(queue: .main)
            self?.read(c, Data())
        }
        listener?.stateUpdateHandler = { st in print("Listener on 127.0.0.1:\(PORT): \(st)") }
        listener?.start(queue: .main)
    }

    func read(_ c: NWConnection, _ buffer: Data) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, done, err in
            guard let self else { return }
            var buf = buffer
            if let d = data { buf.append(d) }
            if let r = buf.range(of: Data("\r\n\r\n".utf8)) {
                let head = String(decoding: buf[..<r.lowerBound], as: UTF8.self)
                let len = head.components(separatedBy: "\r\n")
                    .first { $0.lowercased().hasPrefix("content-length:") }
                    .flatMap { Int($0.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)) } ?? 0
                let body = buf[r.upperBound...]
                if body.count >= len {
                    self.handle(Data(body.prefix(len)))
                    let resp = "HTTP/1.1 204 No Content\r\nConnection: close\r\n\r\n"
                    c.send(content: Data(resp.utf8), completion: .contentProcessed { _ in c.cancel() })
                    return
                }
            }
            if done || err != nil { c.cancel(); return }
            self.read(c, buf)
        }
    }
}

setvbuf(stdout, nil, _IOLBF, 0)  // flush each line so logs show up when output is redirected
let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.run()
