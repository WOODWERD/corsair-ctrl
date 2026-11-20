import Cocoa

/// The Apps strip: four pinned apps first, then every other app that is open.
final class Apps {
    let ids: [String]                       // the pinned four, by bundle identifier
    private var urls: [String: URL] = [:]
    private var names: [String: String] = [:]
    private let work = DispatchQueue(label: "com.woodwerd.corsairctrl.icons", qos: .utility)
    private let own = Bundle.main.bundleIdentifier ?? ""

    /// Launch Services lookups are slow enough to matter on the main thread, so do them once.
    init(ids: [String]) {
        self.ids = ids
        for id in ids {
            urls[id] = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
            names[id] = lookupName(id)
        }
    }

    private func url(_ id: String) -> URL? { urls[id] }
    private func name(_ id: String) -> String { names[id] ?? id }

    /// Keep tile labels short: "Autodesk Fusion" -> "Fusion", "Google Chrome" -> "Chrome".
    private static func short(_ name: String) -> String {
        var n = name
        if n.hasSuffix(".app") { n.removeLast(4) }
        for prefix in ["Autodesk ", "Google ", "Microsoft ", "Adobe "] where n.hasPrefix(prefix) { n.removeFirst(prefix.count) }
        return n
    }

    private func lookupName(_ id: String) -> String {
        guard let u = url(id) else { return id.components(separatedBy: ".").last ?? id }
        return Apps.short(FileManager.default.displayName(atPath: u.path))
    }

    /// Pinned apps in their fixed order, then the other open apps by name. Only apps that
    /// show in the Dock count as open; background helpers are left out.
    func state(frontID: String) -> [[String: Any]] {
        let open = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        let running = Set(open.compactMap { $0.bundleIdentifier })
        var out: [[String: Any]] = ids.map { id in
            ["id": id, "name": name(id), "installed": url(id) != nil, "pinned": true,
             "running": running.contains(id), "front": id == frontID]
        }
        var seen = Set(ids)
        var extras: [[String: Any]] = []
        for app in open {
            guard let id = app.bundleIdentifier, id != own, !seen.contains(id), let u = app.bundleURL else { continue }
            seen.insert(id)
            urls[id] = u
            if names[id] == nil { names[id] = Apps.short(app.localizedName ?? u.deletingPathExtension().lastPathComponent) }
            extras.append(["id": id, "name": name(id), "installed": true, "pinned": false, "running": true, "front": id == frontID])
        }
        extras.sort { ($0["name"] as! String).localizedCaseInsensitiveCompare($1["name"] as! String) == .orderedAscending }
        out.append(contentsOf: extras)
        return out
    }

    /// Each app's own icon as a PNG data URL. Drawn on a background queue; the callback is on main.
    func icons(for wanted: [String], done: @escaping ([String: String]) -> Void) {
        let paths = wanted.compactMap { id in url(id).map { (id, $0.path) } }
        work.async {
            var out: [String: String] = [:]
            let px = 128
            for (id, path) in paths {
                let img = NSWorkspace.shared.icon(forFile: path)
                guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                                                 samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
                      let ctx = NSGraphicsContext(bitmapImageRep: rep) else { continue }
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = ctx
                img.draw(in: NSRect(x: 0, y: 0, width: px, height: px), from: .zero, operation: .sourceOver, fraction: 1)
                NSGraphicsContext.restoreGraphicsState()
                if let png = rep.representation(using: .png, properties: [:]) {
                    out[id] = "data:image/png;base64," + png.base64EncodedString()
                }
            }
            DispatchQueue.main.async { done(out) }
        }
    }

    /// Brings the app forward, starting it if needed. Same route the spike proved for Claude.
    func activate(_ id: String, done: @escaping (String) -> Void) {
        guard let u = url(id) else { done("\(id) is not installed"); return }
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = true
        NSWorkspace.shared.openApplication(at: u, configuration: cfg) { _, err in
            let label = self.name(id)
            DispatchQueue.main.async { done(err == nil ? "Switched to \(label)" : "Could not open \(label): \(err!.localizedDescription)") }
        }
    }
}
