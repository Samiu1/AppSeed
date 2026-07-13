import AppKit

/// Visual constants for the HUD. One flat dark surface, one clay accent,
/// oversized corner radius — a two-second input card, not a content surface.
/// No gradients, no vibrancy, no neumorphic depth.
enum HUDStyle {
    static let surface = NSColor(srgbRed: 0.110, green: 0.102, blue: 0.090, alpha: 1)      // warm charcoal
    static let fieldBackground = NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.07)
    static let accent = NSColor(srgbRed: 0.788, green: 0.482, blue: 0.294, alpha: 1)       // clay
    static let text = NSColor(srgbRed: 0.941, green: 0.922, blue: 0.890, alpha: 1)
    static let secondaryText = NSColor(srgbRed: 0.941, green: 0.922, blue: 0.890, alpha: 0.52)
    static let errorText = NSColor(srgbRed: 0.902, green: 0.494, blue: 0.412, alpha: 1)

    static let panelSize = NSSize(width: 480, height: 236)
    static let cornerRadius: CGFloat = 18
    static let padding: CGFloat = 28
}

/// The floating input card's window. Borderless + non-activating so it
/// appears above other apps — including over fullscreen Spaces — takes
/// keyboard focus for its fields, and never forces a Space switch or steals
/// app activation.
final class HUDPanel: NSPanel {
    init() {
        let screenFrame = NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = HUDStyle.panelSize
        // Centered, nudged slightly above the midline like Spotlight.
        let origin = NSPoint(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.midY - size.height / 2 + screenFrame.height * 0.08
        )
        super.init(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        animationBehavior = .utilityWindow
        // Dark field editor (caret/selection) to match the surface.
        appearance = NSAppearance(named: .darkAqua)
    }

    // Borderless windows refuse key status by default; the HUD needs it for
    // its text fields.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Top-down coordinate container for straightforward manual layout.
final class HUDContentView: NSView {
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = HUDStyle.surface.cgColor
        layer?.cornerRadius = HUDStyle.cornerRadius
        layer?.cornerCurve = .continuous
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("HUDContentView is created in code only")
    }
}

enum HUDControls {
    static func makeEyebrow(_ text: String, y: CGFloat, width: CGFloat) -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.attributedStringValue = NSAttributedString(
            string: text.uppercased(),
            attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: HUDStyle.accent,
                .kern: 2.4,
            ]
        )
        label.frame = NSRect(x: HUDStyle.padding, y: y, width: width, height: 14)
        return label
    }

    static func makeFieldLabel(_ text: String, y: CGFloat, width: CGFloat) -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.attributedStringValue = NSAttributedString(
            string: text.uppercased(),
            attributes: [
                .font: NSFont.systemFont(ofSize: 10, weight: .medium),
                .foregroundColor: HUDStyle.secondaryText,
                .kern: 1.6,
            ]
        )
        label.frame = NSRect(x: HUDStyle.padding, y: y, width: width, height: 13)
        return label
    }

    static func makeField(placeholder: String, y: CGFloat, width: CGFloat) -> (container: NSView, field: NSTextField) {
        let container = NSView(frame: NSRect(x: HUDStyle.padding, y: y, width: width, height: 40))
        container.wantsLayer = true
        container.layer?.backgroundColor = HUDStyle.fieldBackground.cgColor
        container.layer?.cornerRadius = 10
        container.layer?.cornerCurve = .continuous

        let field = NSTextField(frame: NSRect(x: 12, y: 10, width: width - 24, height: 20))
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 14)
        field.textColor = HUDStyle.text
        field.placeholderAttributedString = NSAttributedString(
            string: placeholder,
            attributes: [
                .font: NSFont.systemFont(ofSize: 14),
                .foregroundColor: HUDStyle.secondaryText,
            ]
        )
        field.cell?.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        container.addSubview(field)
        return (container, field)
    }

    static func makeStatusLabel(y: CGFloat, width: CGFloat) -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 12)
        label.textColor = HUDStyle.secondaryText
        label.lineBreakMode = .byTruncatingTail
        label.frame = NSRect(x: HUDStyle.padding, y: y, width: width, height: 16)
        return label
    }
}
