import Foundation

struct Session: Codable {
    var id: String
    var cwd: String
    var state: String      // needs | working | done | idle
    var since: Double      // when it entered this state
    var last: String       // short activity line; never prompt text
    var active: Double     // most recent event of any kind
}

/// Keeps the most recently active Claude Code sessions. The board shows the newest
/// eight; a card leaves only when a ninth, newer session pushes it off. Saved to disk
/// so the board survives an app restart. Prompt text and tool input are discarded.
final class SessionStore {
    private(set) var sessions: [String: Session] = [:]
    private(set) var lastEvent: Double = 0
    private let url: URL
    private let keep = 24

    init(dir: URL) {
        url = dir.appendingPathComponent("sessions.json")
        if let d = try? Data(contentsOf: url), let list = try? JSONDecoder().decode([Session].self, from: d) {
            for s in list { sessions[s.id] = s }
        }
    }

    private func save() {
        let list = sessions.values.sorted { $0.active > $1.active }.prefix(keep)
        sessions = Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })
        if let d = try? JSONEncoder().encode(Array(list)) { try? d.write(to: url, options: .atomic) }
    }

    /// The eight shown on the board.
    var top: [Session] { Array(sessions.values.sorted { $0.active > $1.active }.prefix(8)) }

    static func folder(_ s: Session) -> String {
        s.cwd.isEmpty ? String(s.id.prefix(8)) : URL(fileURLWithPath: s.cwd).lastPathComponent
    }

    private static func short(_ text: String, _ n: Int = 90) -> String {
        let one = text.replacingOccurrences(of: "\n", with: " ")
        return one.count > n ? String(one.prefix(n - 1)) + "…" : one
    }

    private static func toolName(_ raw: String) -> String {
        // mcp__server__tool reads better as its last part
        raw.hasPrefix("mcp__") ? (raw.components(separatedBy: "__").last ?? raw) : raw
    }

    /// Applies one hook event. Returns a one-line description for the log, or nil if ignored.
    func handle(_ j: [String: Any]) -> String? {
        guard let ev = j["hook_event_name"] as? String,
              let sid = j["session_id"] as? String, !sid.isEmpty else { return nil }
        let now = Date().timeIntervalSince1970
        let cwd = j["cwd"] as? String ?? ""
        lastEvent = now

        if ev == "SessionEnd" {
            let name = sessions[sid].map(SessionStore.folder) ?? String(sid.prefix(8))
            sessions[sid] = nil
            save()
            return "SessionEnd \(name)"
        }

        var s = sessions[sid] ?? Session(id: sid, cwd: cwd, state: "idle", since: now, last: "", active: now)
        if !cwd.isEmpty { s.cwd = cwd }
        s.active = now
        func mark(_ state: String, _ last: String?) {
            if s.state != state { s.state = state; s.since = now }
            if let last { s.last = last }
        }
        switch ev {
        case "SessionStart": mark("idle", "Session started")
        case "UserPromptSubmit": mark("working", "Prompt sent")
        case "PreToolUse": mark("working", "Using \(SessionStore.toolName(j["tool_name"] as? String ?? "a tool"))")
        case "PostToolUse": mark("working", nil)
        case "Stop": mark("done", "Finished")
        case "Notification":
            let msg = j["message"] as? String ?? ""
            let low = msg.lowercased()
            if low.contains("waiting for your input") || low.contains("idle") {
                // Claude is simply waiting for the next prompt. That is Done, not Needs you.
                if s.state == "working" { mark("done", "Waiting for your reply") }
            } else {
                mark("needs", msg.isEmpty ? "Needs you" : SessionStore.short(msg))
            }
        default: break
        }
        sessions[sid] = s
        save()
        return "\(ev) \(SessionStore.folder(s))"
    }

    /// Tapping a finished card counts as having seen it.
    func markRead(_ id: String) {
        guard var s = sessions[id], s.state == "done" else { return }
        s.state = "idle"; s.since = Date().timeIntervalSince1970
        sessions[id] = s
        save()
    }
}
