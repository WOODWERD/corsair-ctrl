import Cocoa

/// Keeps the Dock off the Corsair.
///
/// A Dock that hides itself keeps an invisible window over the whole of the display it
/// lives on, above the panel. The touch driver only clicks without activating when the
/// first visible window under the finger is the panel, so with the Dock there every tap
/// is rejected. The Corsair sits below the main screen, and the Dock moves to whichever
/// display the cursor rests against the bottom of, so it can land there at any time.
///
/// Everything here runs on its own queue: the window list and launchctl must not hold
/// the main thread, which the touch driver needs free.
final class DockGuard {
    enum State: String {
        case clear = ""          // the Dock is not on the Corsair
        case restarting          // it is, and the Dock is being restarted
        case held                // it is, and a restart in the last ten minutes did not hold
        case down                // the restart left no Dock running
    }

    /// Called on the main thread when the state changes.
    var onChange: ((State) -> Void)?

    private let queue = DispatchQueue(label: "com.woodwerd.corsairctrl.dockguard")
    private var state = State.clear
    private var sightings = 0
    private var restartedAt = 0.0
    private var pretend = 0

    /// `display` is the Corsair in window-server coordinates (origin top left of the main screen).
    func check(display: CGRect) {
        queue.async { self.run(display) }
    }

    /// For testing the restart by hand: the next two checks behave as if the Dock were there.
    func pretendOnce() { queue.async { self.pretend = 2 } }

    private func run(_ display: CGRect) {
        var covered = Self.dockCovers(display)
        if pretend > 0 { pretend -= 1; covered = true }
        guard covered else {
            sightings = 0
            if state == .down && Self.dockPID() == nil { return }
            if state != .clear { Log.write("[dock] the Dock is off the Corsair") }
            set(.clear)
            return
        }
        // Mission Control and the like put Dock windows over every display for a moment.
        // Act only on a second sighting in a row.
        sightings += 1
        guard sightings >= 2 else { return }
        let now = Date().timeIntervalSince1970
        guard now - restartedAt > 600 else {
            if state != .held { Log.write("[dock] the Dock is on the Corsair again within ten minutes of a restart; left as it is") }
            set(.held)
            return
        }
        restartedAt = now
        sightings = 0
        Log.write("[dock] the Dock is on the Corsair, so taps are rejected; restarting the Dock")
        set(.restarting)
        let pid = restart()
        guard let pid else {
            Log.write("[dock] the Dock did not start again; apps will not change Spaces until it does")
            set(.down)
            return
        }
        Thread.sleep(forTimeInterval: 3)
        if Self.dockCovers(display) {
            Log.write("[dock] the Dock is running again (pid \(pid)) but still on the Corsair")
            set(.held)
        } else {
            Log.write("[dock] the Dock is running again (pid \(pid)) and off the Corsair")
            set(.clear)
        }
    }

    private func set(_ new: State) {
        guard new != state else { return }
        state = new
        DispatchQueue.main.async { self.onChange?(new) }
    }

    /// Restarts the Dock through launchd and returns the new process id, or nil if none
    /// appeared. `killall Dock` is not enough: the Dock exits cleanly on that signal and
    /// launchd then leaves it stopped, which takes Spaces and the app switcher with it.
    private func restart() -> pid_t? {
        let old = Self.dockPID()
        let job = "gui/\(getuid())/com.apple.Dock.agent"
        Self.launchctl(["kickstart", "-k", job])
        if let pid = Self.awaitDock(not: old) { return pid }
        Self.launchctl(["kickstart", job])
        return Self.awaitDock(not: old)
    }

    private static func awaitDock(not old: pid_t?) -> pid_t? {
        for _ in 0..<24 {
            Thread.sleep(forTimeInterval: 0.25)
            if let pid = dockPID(), pid != old { return pid }
        }
        return nil
    }

    private static func launchctl(_ arguments: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = arguments
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run(); p.waitUntilExit() } catch { Log.write("[dock] launchctl could not run: \(error.localizedDescription)") }
    }

    private static func dockPID() -> pid_t? {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier
    }

    /// True when the first visible window at a point on the Corsair is the Dock's own
    /// display-sized window. The point is inside the panel whether it is folded or not.
    private static func dockCovers(_ display: CGRect) -> Bool {
        guard let dock = dockPID(),
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                       kCGNullWindowID) as? [[String: Any]] else { return false }
        let point = CGPoint(x: display.minX + 200, y: display.midY)
        for window in windows {
            guard let alpha = window[kCGWindowAlpha as String] as? Double, alpha > 0,
                  let raw = window[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: raw), rect.contains(point) else { continue }
            let owner = window[kCGWindowOwnerPID as String] as? Int32 ?? 0
            let level = window[kCGWindowLayer as String] as? Int32 ?? 0
            return owner == dock && level == CGWindowLevelForKey(.dockWindow)
                && rect.width >= display.width && rect.height >= display.height
        }
        return false
    }
}
