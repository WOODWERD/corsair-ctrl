import Cocoa
import WebKit

/// The panel window. The touch driver (ajvwhite/MacXeneonEdgeTouchDriver) only clicks
/// without activating the target app when the window under the finger reads to
/// Accessibility as a floating dialog whose focus cannot be set. Report exactly that,
/// and answer every hit test with the window itself so the driver never sees WebKit's
/// out-of-process elements (their owner pid differs and it rejects the tap).
final class EdgePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
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

/// A small bounded log at ~/Library/Logs/CorsairCtrl/app.log. Never holds prompt text.
enum Log {
    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/CorsairCtrl/app.log")
    private static let stamp: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss"; return f
    }()
    static func write(_ line: String) {
        let text = "\(stamp.string(from: Date())) \(line)\n"
        print(text, terminator: "")
        let fm = FileManager.default
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? Int, size > 1_000_000 {
            try? fm.removeItem(at: url)
        }
        guard let data = text.data(using: .utf8) else { return }
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(data); try? h.close() }
        else { try? data.write(to: url) }
    }
}
