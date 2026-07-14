import AppKit

/// The window's content view: hosts the web view plus overlay chrome, and
/// reports mouse movement so the floating toolbar can appear/auto-hide.
final class EngineContentView: NSView {
    var onMouseMoved: (() -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseMoved(with event: NSEvent) {
        onMouseMoved?()
        super.mouseMoved(with: event)
    }
}

/// A small floating back / forward / reload pill. The buttons are nil-target:
/// their actions resolve through the responder chain to the same
/// BrowserWindowController methods the menu items use (single code path).
final class FloatingToolbar: NSVisualEffectView {
    static let size = NSSize(width: 124, height: 36)

    let backButton: NSButton
    let forwardButton: NSButton
    private(set) var isHovered = false

    init() {
        backButton = Self.makeButton(symbol: "chevron.left", label: "Back",
                                     action: #selector(BrowserWindowController.navigateBack(_:)))
        forwardButton = Self.makeButton(symbol: "chevron.right", label: "Forward",
                                        action: #selector(BrowserWindowController.navigateForward(_:)))
        let reloadButton = Self.makeButton(symbol: "arrow.clockwise", label: "Reload",
                                           action: #selector(BrowserWindowController.reloadPage(_:)))
        super.init(frame: NSRect(origin: .zero, size: Self.size))

        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.cornerCurve = .continuous
        alphaValue = 0

        let buttons = [backButton, forwardButton, reloadButton]
        let buttonWidth = Self.size.width / CGFloat(buttons.count)
        for (index, button) in buttons.enumerated() {
            button.frame = NSRect(x: CGFloat(index) * buttonWidth, y: 0,
                                  width: buttonWidth, height: Self.size.height)
            addSubview(button)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("code-only view") }

    private static func makeButton(symbol: String, label: String, action: Selector) -> NSButton {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: label) ?? NSImage()
        let button = NSButton(image: image, target: nil, action: action)
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.imagePosition = .imageOnly
        button.toolTip = label
        return button
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }
}

/// A faint grabber glyph at the right edge of the (invisible) title strip.
/// Brightens and shows an open-hand cursor on hover, hinting that the strip
/// drags the window.
final class DragHintView: NSView {
    private let glyph = NSImageView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        glyph.image = NSImage(systemSymbolName: "circle.grid.3x3.fill",
                              accessibilityDescription: "Drag to move window")
        glyph.contentTintColor = .tertiaryLabelColor
        glyph.alphaValue = 0.25
        glyph.frame = bounds.insetBy(dx: 7, dy: 7)
        glyph.autoresizingMask = [.width, .height]
        addSubview(glyph)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("code-only view") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .cursorUpdate, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func cursorUpdate(with event: NSEvent) { NSCursor.openHand.set() }
    override func mouseEntered(with event: NSEvent) { glyph.animator().alphaValue = 0.6 }
    override func mouseExited(with event: NSEvent) { glyph.animator().alphaValue = 0.25 }
}
