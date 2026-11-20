import Cocoa

/// Sends the Wispr Flow keys, the same chords as CYD Flow Ctrl (push to talk = Ctrl+Opt+T).
/// Needs the Accessibility permission. Keys go to whichever app is in front; the panel
/// itself never takes focus.
final class Keys {
    private let src = CGEventSource(stateID: .hidSystemState)
    private let kT: CGKeyCode = 17, kCtrl: CGKeyCode = 59, kOpt: CGKeyCode = 58
    private let kRet: CGKeyCode = 36, kEsc: CGKeyCode = 53, kSpace: CGKeyCode = 49
    private(set) var holding = false
    private var watchdog: DispatchWorkItem?

    private func key(_ k: CGKeyCode, _ down: Bool, _ flags: CGEventFlags) {
        guard let e = CGEvent(keyboardEventSource: src, virtualKey: k, keyDown: down) else { return }
        e.flags = flags
        e.post(tap: .cghidEventTap)
    }
    private func chordDown() {
        key(kCtrl, true, .maskControl)
        key(kOpt, true, [.maskControl, .maskAlternate])
        usleep(12_000)
        key(kT, true, [.maskControl, .maskAlternate])
    }
    private func chordUp() {
        key(kT, false, [.maskControl, .maskAlternate])
        key(kOpt, false, .maskControl)
        key(kCtrl, false, [])
    }
    private func tapChord() { chordDown(); usleep(60_000); chordUp() }
    private func tap(_ k: CGKeyCode, _ flags: CGEventFlags = []) { key(k, true, flags); key(k, false, flags) }

    /// Returns false for an unknown name.
    @discardableResult
    func perform(_ name: String) -> Bool {
        switch name {
        case "pttDown":
            guard !holding else { return true }
            holding = true
            chordDown()
            // If the finger-up never arrives (page reload, lost touch), let go after two minutes.
            let w = DispatchWorkItem { [weak self] in self?.release() }
            watchdog = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 120, execute: w)
        case "pttUp": release()
        case "handsFree": tapChord(); usleep(120_000); tapChord()
        case "stop": tapChord()
        case "send": tap(kRet)
        case "sendNow": tap(kRet, .maskCommand)
        case "discard": tap(kEsc)
        case "newChat": tap(kSpace, .maskAlternate)
        default: return false
        }
        return true
    }

    func release() {
        watchdog?.cancel(); watchdog = nil
        guard holding else { return }
        holding = false
        chordUp()
    }
}
