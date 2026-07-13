import AppKit

/// A small progress window for "Update All Apps": shows which app is being
/// rebuilt, a determinate bar, and a final summary. One shared instance,
/// reused across runs (mirrors SettingsWindowController).
final class UpdateProgressWindowController: NSWindowController {
    static let shared = UpdateProgressWindowController()

    private var statusLabel: NSTextField!
    private var progressBar: NSProgressIndicator!
    private var doneButton: NSButton!
    private var isRunning = false
    private var onFinish: (() -> Void)?

    private convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 160),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = "Update Apps"
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = HUDStyle.surface
        self.init(window: window)
        buildContent()
    }

    /// Runs the batch update. A no-op re-entrancy guard keeps a second click
    /// from starting an overlapping run; it just refocuses the window instead.
    /// `completion` runs on the main actor once the batch finishes (e.g. so the
    /// caller can refresh a list).
    func run(completion: (() -> Void)? = nil) {
        present()
        guard !isRunning else { return }
        onFinish = completion
        isRunning = true

        doneButton.isHidden = true
        progressBar.isHidden = false
        progressBar.doubleValue = 0
        statusLabel.stringValue = "Preparing…"

        Task { [weak self] in
            let outcomes = await AppUpdater.updateAll { completed, total, name in
                self?.updateProgress(completed: completed, total: total, name: name)
            }
            await MainActor.run { self?.finish(with: outcomes) }
        }
    }

    // MARK: - Progress / completion

    private func updateProgress(completed: Int, total: Int, name: String) {
        progressBar.maxValue = Double(max(total, 1))
        progressBar.doubleValue = Double(completed)
        if completed < total {
            statusLabel.stringValue = "Updating \(name)…  (\(completed + 1) of \(total))"
        } else {
            statusLabel.stringValue = "Finishing up…"
        }
    }

    private func finish(with outcomes: [AppUpdateOutcome]) {
        isRunning = false
        progressBar.isHidden = true

        let succeeded = outcomes.filter { $0.succeeded }.count
        let failed = outcomes.filter { !$0.succeeded }

        if outcomes.isEmpty {
            statusLabel.stringValue = "There are no apps to update yet."
        } else if failed.isEmpty {
            let plural = succeeded == 1 ? "app" : "apps"
            statusLabel.stringValue =
                "Updated \(succeeded) \(plural) to the latest version.\nYour logins were kept."
        } else {
            let lines = failed.map { "• \($0.name): \($0.detail ?? "couldn't update")" }
                .joined(separator: "\n")
            statusLabel.stringValue =
                "Updated \(succeeded) of \(outcomes.count).\nCouldn't update:\n\(lines)"
        }
        doneButton.isHidden = false
        onFinish?()
        onFinish = nil
    }

    // MARK: - Window

    private func present() {
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    @objc private func done() {
        window?.close()
    }

    private func buildContent() {
        guard let content = window?.contentView else { return }

        statusLabel = NSTextField(labelWithString: "")
        statusLabel.font = .systemFont(ofSize: 13)
        statusLabel.textColor = HUDStyle.text
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.maximumNumberOfLines = 4
        statusLabel.cell?.wraps = true
        statusLabel.frame = NSRect(x: 24, y: 66, width: 392, height: 72)

        progressBar = NSProgressIndicator(frame: NSRect(x: 24, y: 52, width: 392, height: 16))
        progressBar.isIndeterminate = false
        progressBar.style = .bar
        progressBar.minValue = 0

        doneButton = NSButton(frame: NSRect(x: 320, y: 14, width: 96, height: 30))
        doneButton.title = "Done"
        doneButton.bezelStyle = .rounded
        doneButton.keyEquivalent = "\r"
        doneButton.target = self
        doneButton.action = #selector(done)
        doneButton.isHidden = true

        [statusLabel, progressBar, doneButton].forEach(content.addSubview)
    }
}
