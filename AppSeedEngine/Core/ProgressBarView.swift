import AppKit

/// A thin Safari-style loading bar: fills left-to-right with the accent
/// color while a page loads, then completes and fades out.
final class ProgressBarView: NSView {
    static let barHeight: CGFloat = 2

    private let fill = NSView()

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        alphaValue = 0
        fill.wantsLayer = true
        fill.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        addSubview(fill)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("code-only view") }

    /// value in 0...1 — sets the filled width, animated.
    func setProgress(_ value: Double) {
        let clamped = max(0, min(1, value))
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            fill.animator().frame = NSRect(
                x: 0, y: 0,
                width: bounds.width * CGFloat(clamped),
                height: bounds.height
            )
        }
    }

    /// Show immediately with a sliver of progress so slow pages give
    /// instant feedback.
    func beginLoading() {
        fill.frame = NSRect(x: 0, y: 0, width: bounds.width * 0.05, height: bounds.height)
        alphaValue = 1
    }

    /// Run to full, pause briefly, then fade away.
    func finishLoading() {
        setProgress(1.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                self?.animator().alphaValue = 0
            }
        }
    }
}
