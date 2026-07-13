import AppKit

/// A custom subclass of NSWindow for the About modal that closes on Escape key press.
final class AboutWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) {
        self.close()
    }
}

/// Controller for the custom About panel.
final class AboutWindowController: NSWindowController {
    static let shared = AboutWindowController()

    private convenience init() {
        let size = NSSize(width: 320, height: 260)
        let window = AboutWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = ""
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = HUDStyle.surface
        
        self.init(window: window)
        buildContent()
    }

    func show() {
        // Bring app to front and show the About window centered.
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    private func buildContent() {
        guard let content = window?.contentView else { return }

        let stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.alignment = .centerX
        stackView.spacing = 10
        stackView.edgeInsets = NSEdgeInsets(top: 36, left: 24, bottom: 24, right: 24)
        stackView.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: content.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])

        // 1. App Icon
        let iconImageView = NSImageView()
        iconImageView.image = NSApp.applicationIconImage
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            iconImageView.widthAnchor.constraint(equalToConstant: 64),
            iconImageView.heightAnchor.constraint(equalToConstant: 64)
        ])
        stackView.addArrangedSubview(iconImageView)

        // 2. Bold Name "AppSeed"
        let nameLabel = NSTextField(labelWithString: "AppSeed")
        nameLabel.font = .systemFont(ofSize: 18, weight: .bold)
        nameLabel.textColor = HUDStyle.text
        nameLabel.alignment = .center
        stackView.addArrangedSubview(nameLabel)

        // 3. Current Version and Build Number
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        let versionLabel = NSTextField(labelWithString: "Version \(version) (Build \(build))")
        versionLabel.font = .systemFont(ofSize: 11)
        versionLabel.textColor = HUDStyle.secondaryText
        versionLabel.alignment = .center
        stackView.addArrangedSubview(versionLabel)

        // 4. Description Text
        let descLabel = NSTextField(labelWithString: "Turn any website into a lightweight Mac app.")
        descLabel.font = .systemFont(ofSize: 12)
        descLabel.textColor = HUDStyle.text
        descLabel.alignment = .center
        descLabel.lineBreakMode = .byWordWrapping
        descLabel.cell?.wraps = true
        descLabel.preferredMaxLayoutWidth = 272
        stackView.addArrangedSubview(descLabel)

        // 5. Copyright Text
        let copyrightLabel = NSTextField(labelWithString: "© 2026 Samiul Islam")
        copyrightLabel.font = .systemFont(ofSize: 10)
        copyrightLabel.textColor = HUDStyle.secondaryText
        copyrightLabel.alignment = .center
        stackView.addArrangedSubview(copyrightLabel)
    }
}
