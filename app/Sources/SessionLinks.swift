import Cocoa

/// Opens things in the Claude desktop app through its own `claude://` links:
/// a new chat, a new Code session, or one specific Code session. Also reads each
/// session's chat name for its card.
///
/// A hook reports a session by its CLI id (a UUID). The app's link wants its own id
/// (`local_…`). The app keeps both, and the chat name, near the top of each session
/// record under ~/Library/Application Support/Claude/claude-code-sessions, so only
/// those three fields are used. This leans on the app's private file layout; if a record cannot
/// be found the caller falls back to bringing Claude forward and the card shows its folder.
///
/// Chat names are held in memory only. They are never written to disk or to the log.
final class SessionLinks {
    private struct Record { let local: String; let file: URL }
    private var map: [String: String] = [:]             // main thread
    private(set) var titles: [String: String] = [:]     // main thread; CLI id → chat name
    private var index: [String: Record] = [:]           // work queue
    private var lastScan = 0.0                          // work queue
    private var seen: [URL: (at: Date, title: String?)] = [:]   // work queue; skips unchanged records
    private let headBytes = 16384
    private let work = DispatchQueue(label: "com.woodwerd.corsairctrl.links", qos: .userInitiated)
    private let root = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Claude/claude-code-sessions")
    private let localRe = try! NSRegularExpression(pattern: "\"sessionId\"\\s*:\\s*\"(local_[A-Za-z0-9-]{1,64})\"")
    private let cliRe = try! NSRegularExpression(pattern: "\"cliSessionId\"\\s*:\\s*\"([0-9a-fA-F-]{36})\"")

    static let newChat = URL(string: "claude://claude.ai/new?surface=chat")!
    static let newCode = URL(string: "claude://code/new")!
    static let newCowork = URL(string: "claude://cowork/new")!
    static func session(_ local: String) -> URL? { URL(string: "claude://code/continue?session=\(local)") }

    private func first(_ re: NSRegularExpression, _ text: String) -> String? {
        guard let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }

    private func head(_ file: URL) -> String? {
        guard let h = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? h.close() }
        return String(decoding: h.readData(ofLength: headBytes), as: UTF8.self)
    }

    private func scan() -> [String: Record] {
        var found: [String: Record] = [:]
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return found }
        for case let file as URL in walker where file.lastPathComponent.hasPrefix("local_") && file.pathExtension == "json" {
            guard let text = head(file) else { continue }
            if let local = first(localRe, text), let cli = first(cliRe, text) {
                found[cli.lowercased()] = Record(local: local, file: file)
            }
        }
        return found
    }

    /// The record's own top-level title. The whole record is parsed so a title nested
    /// in some other field is never mistaken for it; a record is re-read only when its
    /// file has changed.
    private func title(_ file: URL) -> String? {
        let at = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
        if let hit = seen[file], hit.at == at { return hit.title }
        var found: String?
        if let d = try? Data(contentsOf: file), d.count < 8_000_000,
           let j = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
           let t = (j["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
            found = String(t.prefix(200))
        }
        seen[file] = (at, found)
        return found
    }

    /// Re-reads the chat names for these sessions (the board's eight). Only their own
    /// records are opened; the whole folder is walked just when a session is not yet
    /// known, and then at most every five seconds. Calls back on the main thread with
    /// whether any name changed.
    func refreshTitles(_ ids: [String], done: @escaping (Bool) -> Void) {
        let keys = ids.map { $0.lowercased() }
        work.async { [weak self] in
            guard let self else { return }
            let now = CFAbsoluteTimeGetCurrent()
            if keys.contains(where: { self.index[$0] == nil }), now - self.lastScan > 5 {
                self.index = self.scan()
                self.lastScan = now
            }
            self.seen = self.seen.filter { e in keys.contains { self.index[$0]?.file == e.key } }
            var names: [String: String] = [:], locals: [String: String] = [:]
            for k in keys {
                guard let r = self.index[k] else { continue }
                locals[k] = r.local
                if let t = self.title(r.file) { names[k] = t }
            }
            DispatchQueue.main.async {
                let changed = names != self.titles
                self.titles = names
                self.map.merge(locals) { _, new in new }
                done(changed)
            }
        }
    }

    func title(for cli: String) -> String? { titles[cli.lowercased()] }

    /// Finds the app's id for a hook session id. Calls back on the main thread.
    func lookup(_ cli: String, done: @escaping (String?) -> Void) {
        let key = cli.lowercased()
        if let hit = map[key] { done(hit); return }
        work.async { [weak self] in
            guard let self else { return }
            self.index = self.scan()
            self.lastScan = CFAbsoluteTimeGetCurrent()
            let fresh = self.index.mapValues { $0.local }
            DispatchQueue.main.async {
                self.map = fresh
                done(fresh[key])
            }
        }
    }

    /// Opens a claude:// link, which also brings the Claude app forward.
    static func open(_ url: URL, done: @escaping (Bool) -> Void) {
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = true
        NSWorkspace.shared.open(url, configuration: cfg) { _, err in
            DispatchQueue.main.async { done(err == nil) }
        }
    }
}
