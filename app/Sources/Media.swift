import Cocoa

/// Media Ctrl on the Mac. Follows the approach of the Media Ctrl Mac helper
/// (cyd-media-ctrl/mac-helper): ask Spotify and Apple Music what is playing through
/// AppleScript, and control them the same way. With neither playing, the transport
/// buttons fall back to the system media keys, which reach whichever app played last.
///
/// Every AppleScript call runs `osascript` on a background queue. The main thread must
/// stay free for the touch driver's 50 ms Accessibility queries.
final class Media {
    private struct Player { let name: String; let bundle: String; let key: String }
    private let players = [Player(name: "Spotify", bundle: "com.spotify.client", key: "S"),
                           Player(name: "Music", bundle: "com.apple.Music", key: "M")]
    private let work = DispatchQueue(label: "com.woodwerd.corsairctrl.media", qos: .utility)
    private var busy = false
    private var lastApp: String?
    private var lastSummary = ""
    private(set) var state: [String: Any] = ["state": "keys"]
    var onChange: () -> Void = {}
    var onNote: (String) -> Void = { _ in }

    func start() {
        poll()
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.poll() }
    }

    // MARK: AppleScript

    private static func osa(_ script: String, timeout: Double = 6) -> (ok: Bool, out: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", script]
        let out = Pipe(), err = Pipe()
        p.standardOutput = out; p.standardError = err
        do { try p.run() } catch { return (false, "\(error.localizedDescription)") }
        // A first call can sit behind macOS's permission prompt, so reads wait a good while
        // for an answer. Nothing else is held up: this is a background queue.
        let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        killer.cancel()
        let ok = p.terminationStatus == 0
        return (ok, String(decoding: ok ? data : errData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// One script covering the players that are running, plus the system volume.
    /// Only running apps are named, so nothing here ever launches a player.
    private static func readScript(_ running: [Player]) -> String {
        var s = "set out to \"\"\n"
        for p in running {
            let fields = p.name == "Spotify"
                ? "set t to current track\nset out to out & \"\(p.key)|\" & ps & tab & (name of t) & tab & (artist of t) & tab & ((duration of t) / 1000) & tab & player position & tab & shuffling & tab & repeating & linefeed"
                : "set nm to \"\"\nset ar to \"\"\nset du to 0\ntry\nset t to current track\nset nm to name of t\nset ar to artist of t\nset du to duration of t\nend try\nset out to out & \"\(p.key)|\" & ps & tab & nm & tab & ar & tab & du & tab & player position & tab & shuffle enabled & tab & (song repeat as text) & linefeed"
            s += """
            if application "\(p.name)" is running then
            try
            tell application "\(p.name)"
            set ps to player state as text
            if ps is "stopped" then
            set out to out & "\(p.key)|stopped" & linefeed
            else
            \(fields)
            end if
            end tell
            on error number n
            set out to out & "\(p.key)|error" & tab & n & linefeed
            end try
            end if

            """
        }
        s += "set v to get volume settings\nset out to out & \"V|\" & (output volume of v as text) & tab & (output muted of v as text)\nreturn out"
        return s
    }

    /// AppleScript reals follow the user's locale (decimal comma) and may use E-notation.
    private static func num(_ s: String) -> Double {
        Double(s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    private func runningPlayers() -> [Player] {
        let ids = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier })
        return players.filter { ids.contains($0.bundle) }
    }

    // MARK: Reading

    private func poll() {
        guard !busy else { return }
        busy = true
        let running = runningPlayers()
        let script = Media.readScript(running)
        let last = lastApp
        work.async { [weak self] in
            let (ok, out) = Media.osa(script, timeout: 45)
            let sampled = Date().timeIntervalSince1970
            DispatchQueue.main.async {
                guard let self else { return }
                self.busy = false
                self.apply(ok ? out : "", running: running, last: last, at: sampled)
            }
        }
    }

    private func apply(_ out: String, running: [Player], last: String?, at: Double) {
        var tracks: [[String: Any]] = []
        var denied: [String] = []
        var volume: Any = NSNull()
        var muted = false
        for line in out.components(separatedBy: "\n") {
            guard line.count > 2 else { continue }
            let key = String(line.prefix(1))
            let f = String(line.dropFirst(2)).components(separatedBy: "\t")
            if key == "V" {
                if let v = Int(f[0].trimmingCharacters(in: .whitespaces)) { volume = v }
                muted = f.count > 1 && f[1].trimmingCharacters(in: .whitespaces) == "true"
                continue
            }
            guard let p = players.first(where: { $0.key == key }) else { continue }
            if f[0] == "error" { if f.count > 1, f[1].contains("1743") { denied.append(p.name) }; continue }
            guard f[0] != "stopped", f.count >= 7 else { continue }
            let playing = ["playing", "fast forwarding", "rewinding"].contains(f[0])
            let rp = f[6].trimmingCharacters(in: .whitespaces)
            tracks.append([
                "state": playing ? "playing" : "paused", "app": p.name, "title": f[1], "artist": f[2],
                "duration": Media.num(f[3]), "position": Media.num(f[4]), "at": at,
                "shuffle": f[5].trimmingCharacters(in: .whitespaces) == "true",
                "repeat": ["true", "one", "all"].contains(rp),
                "can": ["seek": true, "shuffle": true, "repeat": true, "like": p.name == "Music"],
            ])
        }
        // The one that is playing wins; otherwise stay with the last one shown.
        var pick = tracks.first { $0["state"] as? String == "playing" }
        if pick == nil, let last { pick = tracks.first { $0["app"] as? String == last } }
        if pick == nil { pick = tracks.first }

        var next: [String: Any]
        if var p = pick {
            lastApp = p["app"] as? String
            p["volume"] = volume; p["muted"] = muted
            next = p
        } else {
            next = ["state": "keys", "volume": volume, "muted": muted]
            if let app = denied.first {
                next["note"] = "Allow Corsair Ctrl to control \(app) under Privacy & Security > Automation to see what is playing."
            } else if running.isEmpty {
                next["note"] = "Spotify and Music are not open. The buttons work as media keys for whatever played last."
            } else {
                next["note"] = "Nothing is loaded in \(running.map { $0.name }.joined(separator: " or ")). The buttons work as media keys."
            }
        }
        // Tell the page only when something it shows has changed. The page advances the
        // progress bar itself, so a position that is where it should be is not a change.
        let keyOf: ([String: Any]) -> String = { d in
            ["state", "app", "title", "artist", "duration", "shuffle", "repeat", "volume", "muted", "note"]
                .map { "\(d[$0] ?? "")" }.joined(separator: "\u{1f}")
        }
        var changed = keyOf(next) != keyOf(state)
        if !changed, let np = next["position"] as? Double, let op = state["position"] as? Double,
           let nat = next["at"] as? Double, let oat = state["at"] as? Double {
            let expected = op + ((state["state"] as? String) == "playing" ? nat - oat : 0)
            changed = abs(np - expected) > 1.5
        }
        guard changed else { return }
        state = next
        let summary = "\(next["state"] as? String ?? "") \(next["app"] as? String ?? "")" + (denied.isEmpty ? "" : " (no permission: \(denied.joined(separator: ", ")))")
        if summary != lastSummary { lastSummary = summary; onNote("Media: \(summary.trimmingCharacters(in: .whitespaces))") }
        onChange()
    }

    // MARK: Control

    /// The system media keys, as a keyboard would send them. Needs Accessibility.
    private func mediaKey(_ key: Int) {
        for down in [true, false] {
            let flags = NSEvent.ModifierFlags(rawValue: down ? 0xa00 : 0xb00)
            let data1 = (key << 16) | ((down ? 0xa : 0xb) << 8)
            NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: flags, timestamp: 0,
                               windowNumber: 0, context: nil, subtype: 8, data1: data1, data2: -1)?
                .cgEvent?.post(tap: .cghidEventTap)
        }
    }

    private func script(_ text: String) {
        work.async { [weak self] in
            let (ok, out) = Media.osa(text)
            DispatchQueue.main.async {
                if !ok { self?.onNote("Media command failed: \(out.split(separator: "\n").last.map(String.init) ?? "unknown")") }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { self?.poll() }
            }
        }
    }

    func command(_ cmd: String, value: Double?) {
        switch cmd {
        case "volume":
            guard let value else { return }
            script("set volume output volume \(max(0, min(100, Int(value))))")
            return
        case "mute":
            script("set volume output muted (not (output muted of (get volume settings)))")
            return
        default: break
        }
        // A player we can script, if one is on screen; otherwise the media keys.
        let scripted = state["app"] as? String
        guard let app = scripted, runningPlayers().contains(where: { $0.name == app }) else {
            switch cmd {
            case "toggle": mediaKey(16)   // NX_KEYTYPE_PLAY
            case "next": mediaKey(17)     // NX_KEYTYPE_NEXT
            case "prev": mediaKey(18)     // NX_KEYTYPE_PREVIOUS
            default: return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.poll() }
            return
        }
        let tell = "tell application \"\(app)\" to "
        switch cmd {
        case "toggle": script(tell + "playpause")
        case "next": script(tell + "next track")
        case "prev": script(tell + "previous track")
        case "back15", "fwd15":
            let d = cmd == "fwd15" ? 15 : -15
            script("tell application \"\(app)\"\nset p to (player position) + (\(d))\nif p < 0 then set p to 0\nset player position to p\nend tell")
        case "shuffle":
            let prop = app == "Spotify" ? "shuffling" : "shuffle enabled"
            script(tell + "set \(prop) to not \(prop)")
        case "repeat":
            if app == "Spotify" { script(tell + "set repeating to not repeating") }
            else { script("tell application \"Music\"\nif song repeat is off then\nset song repeat to all\nelse if song repeat is all then\nset song repeat to one\nelse\nset song repeat to off\nend if\nend tell") }
        case "like":
            if app == "Music" { script("tell application \"Music\"\ntry\nset favorited of current track to true\non error\nset loved of current track to true\nend try\nend tell") }
        default: break
        }
    }
}
