import AppKit

/// A monotonic deadline keeps the countdown accurate after sleep or delayed UI updates.
struct PomodoroSession {
    static let duration = 20 * 60
    static let breakDuration = 30
    private(set) var deadline: ContinuousClock.Instant?
    private(set) var isOnBreak = false

    var isActive: Bool { deadline != nil }

    mutating func start(now: ContinuousClock.Instant = .now) {
        isOnBreak = false
        deadline = now.advanced(by: .seconds(Self.duration))
    }

    mutating func startBreak(now: ContinuousClock.Instant = .now) {
        isOnBreak = true
        deadline = now.advanced(by: .seconds(Self.breakDuration))
    }

    mutating func reset() {
        deadline = nil
        isOnBreak = false
    }

    func remainingSeconds(now: ContinuousClock.Instant = .now) -> Int {
        guard let deadline else { return Self.duration }
        let components = now.duration(to: deadline).components
        let seconds = Double(components.seconds) + Double(components.attoseconds) / 1e18
        return max(0, min(isOnBreak ? Self.breakDuration : Self.duration, Int(ceil(seconds))))
    }

    static func label(for seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

/// An AppKit overlay; the wallpaper's Metal pipeline does not render the timer.
final class PomodoroOverlay: NSView {
    private let title = NSTextField(labelWithString: "TAKE A BREAK")
    private let countdown = NSTextField(labelWithString: "00:30")
    private let hint = NSTextField(labelWithString: "Double-click anywhere or press Esc to skip this break")
    var onInterrupt: (() -> Void)?

    init(frame: NSRect, isDarkMode: Bool) {
        super.init(frame: frame)
        autoresizingMask = [.width, .height]

        title.font = .systemFont(ofSize: 13, weight: .semibold)
        countdown.font = .monospacedDigitSystemFont(ofSize: 88, weight: .light)
        countdown.setAccessibilityLabel("Time remaining")
        hint.font = .systemFont(ofSize: 13)

        let stack = NSStackView(views: [title, countdown, hint])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        for label in [title, countdown, hint] {
            label.alignment = .center
        }
        updateAppearance(isDarkMode: isDarkMode)
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

    func updateAppearance(isDarkMode: Bool) {
        for label in [title, countdown, hint] {
            label.textColor = isDarkMode ? .white : .black
            guard isDarkMode else {
                label.shadow = nil
                continue
            }
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.8)
            shadow.shadowBlurRadius = 8
            shadow.shadowOffset = NSSize(width: 0, height: -1)
            label.shadow = shadow
        }
    }

    func update(seconds: Int) {
        let text = PomodoroSession.label(for: seconds)
        if countdown.stringValue != text { countdown.stringValue = text }
    }
}
