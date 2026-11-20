import Cocoa

/// The four apps on the jump strip, by bundle identifier.
final class Apps {
    let ids: [String]
    private var urls: [String: URL] = [:]
    private var names: [String: String] = [:]

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

    private func lookupName(_ id: String) -> String {
        guard let u = url(id) else { return id.components(separatedBy: ".").last ?? id }
        var n = FileManager.default.displayName(atPath: u.path)
        if n.hasSuffix(".app") { n.removeLast(4) }
        // Keep tile labels short: "Autodesk Fusion" -> "Fusion", "Google Chrome" -> "Chrome".
        for prefix in ["Autodesk ", "Google ", "Microsoft ", "Adobe "] where n.hasPrefix(prefix) { n.removeFirst(prefix.count) }
        return n
    }

    func state(frontID: String) -> [[String: Any]] {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier })
        return ids.map { id in
            ["id": id, "name": name(id), "installed": url(id) != nil,
             "running": running.contains(id), "front": id == frontID]
        }
    }

    /// Each app's own icon as a PNG data URL, sent to the page once.
    func icons() -> [String: String] {
        var out: [String: String] = [:]
        let px = 128
        for id in ids {
            guard let u = url(id) else { continue }
            let img = NSWorkspace.shared.icon(forFile: u.path)
            guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                                             samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                             colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { continue }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            img.draw(in: NSRect(x: 0, y: 0, width: px, height: px), from: .zero, operation: .sourceOver, fraction: 1)
            NSGraphicsContext.restoreGraphicsState()
            if let png = rep.representation(using: .png, properties: [:]) {
                out[id] = "data:image/png;base64," + png.base64EncodedString()
            }
        }
        return out
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
