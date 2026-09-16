import AppKit

/// A monotonic deadline keeps the countdown accurate after sleep or delayed UI updates.
struct PomodoroSession {
    static let duration = 20 * 60
    private(set) var deadline: ContinuousClock.Instant?

    var isActive: Bool { deadline != nil }

    mutating func start(now: ContinuousClock.Instant = .now) {
        deadline = now.advanced(by: .seconds(Self.duration))
    }

    mutating func reset() { deadline = nil }

    func remainingSeconds(now: ContinuousClock.Instant = .now) -> Int {
        guard let deadline else { return Self.duration }
        let components = now.duration(to: deadline).components
        let seconds = Double(components.seconds) + Double(components.attoseconds) / 1e18
        return max(0, min(Self.duration, Int(ceil(seconds))))
    }

    static func label(for seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

/// An AppKit overlay; the wallpaper's Metal pipeline does not render the timer.
final class PomodoroOverlay: NSView {
    private let countdown = NSTextField(labelWithString: "20:00")
    var onInterrupt: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        autoresizingMask = [.width, .height]

        let title = NSTextField(labelWithString: "FOCUS")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        countdown.font = .monospacedDigitSystemFont(ofSize: 88, weight: .light)
        countdown.setAccessibilityLabel("Time remaining")
        let hint = NSTextField(labelWithString: "Double-click anywhere to end · Esc to exit")
        hint.font = .systemFont(ofSize: 13)

        let stack = NSStackView(views: [title, countdown, hint])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        for label in [title, countdown, hint] {
            label.textColor = .white
            label.alignment = .center
            label.shadow = NSShadow()
            label.shadow?.shadowColor = NSColor.black.withAlphaComponent(0.8)
            label.shadow?.shadowBlurRadius = 8
            label.shadow?.shadowOffset = NSSize(width: 0, height: -1)
        }
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { bounds.contains(point) ? self : nil }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { onInterrupt?() }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onInterrupt?() } else { super.keyDown(with: event) }
    }

    func update(seconds: Int) {
        let text = PomodoroSession.label(for: seconds)
        if countdown.stringValue != text { countdown.stringValue = text }
    }
}
