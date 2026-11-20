import Foundation

/// Adds or removes the Corsair Ctrl hooks in ~/.claude/settings.json. Only runs when
/// the user asks from Settings. Backs the file up first and leaves other hooks alone.
/// The forwarder script posts each event to this app and writes nothing to disk.
final class Hooks {
    private let script: URL
    private let settings = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/settings.json")
    private let port: UInt16
    private(set) var installed = false

    init(dir: URL, port: UInt16) {
        script = dir.appendingPathComponent("corsair-hook.sh")
        self.port = port
        refresh()
    }

    private var command: String { "bash \"\(script.path)\"" }

    func refresh() {
        let text = (try? String(contentsOf: settings, encoding: .utf8)) ?? ""
        installed = text.contains("corsair-hook.sh")
    }

    private func writeScript() throws {
        let body = """
        #!/bin/bash
        # Corsair Ctrl hook forwarder. Claude Code pipes one JSON event to stdin; this posts
        # it to the panel on this Mac and keeps nothing. Never blocks Claude: 1 s timeout, exit 0.
        payload="$(cat)"
        curl -s -m 1 -X POST -H 'Content-Type: application/json' \\
          --data-binary "$payload" http://127.0.0.1:\(port)/event >/dev/null 2>&1 || true
        exit 0

        """
        try body.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
    }

    /// mode: "install" or "remove". Returns nil on success or a message saying what went wrong.
    func apply(_ mode: String) -> String? {
        let fm = FileManager.default
        do {
            if mode == "install" { try writeScript() }
            try fm.createDirectory(at: settings.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !fm.fileExists(atPath: settings.path) { try "{}\n".write(to: settings, atomically: true, encoding: .utf8) }
            let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"
            let backup = settings.path + ".bak-corsairctrl-" + f.string(from: Date())
            try fm.copyItem(atPath: settings.path, toPath: backup)
        } catch {
            return "Could not prepare the settings file: \(error.localizedDescription)"
        }
        // Python keeps the file's key order; Foundation's JSON writer would reshuffle it.
        let py = """
        import json, sys
        path, cmd, mode = sys.argv[1:4]
        with open(path) as f:
            s = json.load(f)
        hooks = s.setdefault("hooks", {})
        events = {"SessionStart": None, "UserPromptSubmit": None, "PreToolUse": "*", "PostToolUse": "*",
                  "Notification": None, "Stop": None, "SessionEnd": None}
        for ev, matcher in events.items():
            groups = [g for g in hooks.get(ev, [])
                      if not any("corsair-hook.sh" in h.get("command", "") for h in g.get("hooks", []))]
            if mode == "install":
                g = {"hooks": [{"type": "command", "command": cmd, "timeout": 5}]}
                if matcher:
                    g["matcher"] = matcher
                groups.append(g)
            if groups:
                hooks[ev] = groups
            else:
                hooks.pop(ev, None)
        if not hooks:
            s.pop("hooks")
        with open(path, "w") as f:
            json.dump(s, f, indent=2)
            f.write("\\n")
        """
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        p.arguments = ["-c", py, settings.path, command, mode]
        let err = Pipe()
        p.standardError = err
        p.standardOutput = Pipe()
        do { try p.run() } catch { return "Could not run python3: \(error.localizedDescription)" }
        p.waitUntilExit()
        refresh()
        if p.terminationStatus != 0 {
            let msg = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            return "Settings were not changed: \(msg.split(separator: "\n").last.map(String.init) ?? "unknown error")"
        }
        return nil
    }
}
