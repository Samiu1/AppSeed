import AppKit

/// Owns the transient HUD lifecycle: created on invoke, fully torn down on
/// dismissal — the panel exists only while in use. Esc closes, Enter submits,
/// clicking outside (resign key) closes.
final class HUDController: NSObject, NSWindowDelegate, NSTextFieldDelegate {
    private var panel: HUDPanel?
    private var urlField: NSTextField?
    private var nameField: NSTextField?
    private var statusLabel: NSTextField?

    private var userEditedName = false
    private var isBuilding = false
    private var titleFetchTask: Task<Void, Never>?

    private static let defaultHint = "↩ create app   ·   esc dismiss"

    func toggle() {
        panel == nil ? show() : close()
    }

    func show() {
        if panel != nil { close() }
        buildPanel()
        prefillFromClipboard()
        panel?.makeKeyAndOrderFront(nil)
        if let urlField { panel?.makeFirstResponder(urlField) }
    }

    func close() {
        titleFetchTask?.cancel()
        titleFetchTask = nil
        userEditedName = false
        isBuilding = false
        guard let panel else { return }
        panel.delegate = nil
        panel.orderOut(nil)
        // Full teardown, not hide — preserves the "exists only when invoked" model.
        self.panel = nil
        urlField = nil
        nameField = nil
        statusLabel = nil
    }

    // MARK: - Panel construction

    private func buildPanel() {
        let panel = HUDPanel()
        let content = HUDContentView(frame: NSRect(origin: .zero, size: HUDStyle.panelSize))
        let fieldWidth = HUDStyle.panelSize.width - HUDStyle.padding * 2

        content.addSubview(HUDControls.makeEyebrow("AppSeed", y: 24, width: fieldWidth))
        content.addSubview(HUDControls.makeFieldLabel("URL", y: 56, width: fieldWidth))
        let (urlContainer, urlField) = HUDControls.makeField(
            placeholder: "linear.app", y: 74, width: fieldWidth)
        content.addSubview(urlContainer)

        content.addSubview(HUDControls.makeFieldLabel("App name", y: 128, width: fieldWidth))
        let (nameContainer, nameField) = HUDControls.makeField(
            placeholder: "Linear", y: 146, width: fieldWidth)
        content.addSubview(nameContainer)

        let statusLabel = HUDControls.makeStatusLabel(y: 196, width: fieldWidth)
        statusLabel.stringValue = Self.defaultHint
        content.addSubview(statusLabel)

        urlField.delegate = self
        nameField.delegate = self
        panel.contentView = content
        panel.delegate = self

        self.panel = panel
        self.urlField = urlField
        self.nameField = nameField
        self.statusLabel = statusLabel
    }

    /// Clipboard is read ONCE on invoke, read-only, and never leaves this
    /// process. Do not extend this into history, polling, or any telemetry.
    private func prefillFromClipboard() {
        guard let clipboard = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            InputNormalizer.looksLikeURL(clipboard)
        else { return }
        urlField?.stringValue = clipboard
        suggestName(for: clipboard)
    }

    /// Instant fallback from the registrable domain, upgraded by the page
    /// <title> when the fetch lands — unless the user typed a name themselves.
    private func suggestName(for urlString: String) {
        guard let url = try? InputNormalizer.normalizeURL(urlString) else { return }
        if !userEditedName {
            nameField?.stringValue = DomainUtils.suggestedAppName(forHost: url.host ?? "")
        }
        titleFetchTask?.cancel()
        titleFetchTask = Task { [weak self] in
            guard let title = await TitleFetcher.fetchTitle(from: url), !Task.isCancelled else { return }
            DispatchQueue.main.async {
                guard let self, !self.userEditedName, !self.isBuilding else { return }
                self.nameField?.stringValue = title
            }
        }
    }

    // MARK: - Field events

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        if field === nameField {
            userEditedName = !field.stringValue.isEmpty
        }
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField, field === urlField else { return }
        if !field.stringValue.isEmpty, nameField?.stringValue.isEmpty != false || !userEditedName {
            suggestName(for: field.stringValue)
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.cancelOperation(_:)):
            if !isBuilding { close() }
            return true
        case #selector(NSResponder.insertNewline(_:)):
            submit()
            return true
        default:
            return false
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        // Click-outside dismissal — but never mid-build (the collision alert
        // and completion feedback need the panel alive).
        if !isBuilding { close() }
    }

    // MARK: - Submission

    private func submit() {
        guard !isBuilding, let urlField, let nameField else { return }
        let request: FactoryRequest
        do {
            let url = try InputNormalizer.normalizeURL(urlField.stringValue)
            let fallbackName = DomainUtils.suggestedAppName(forHost: url.host ?? "")
            let rawName = nameField.stringValue.isEmpty ? fallbackName : nameField.stringValue
            request = FactoryRequest(
                url: url,
                appName: try InputNormalizer.sanitizeAppName(rawName),
                destinationDirectory: AppFactory.defaultInstallDirectory
            )
        } catch {
            showStatus(error.localizedDescription, isError: true)
            return
        }

        isBuilding = true
        setFieldsEnabled(false)
        showStatus("Preparing…")

        Task.detached { [weak self] in
            let factory = AppFactory(
                progress: { message in self?.showStatus(message) },
                resolveCollision: { collision in await Self.askCollisionDecision(collision) }
            )
            do {
                let installed = try await factory.build(request)
                self?.showStatus("Launching \(request.appName)…")
                Self.launch(installed)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                    self?.close()
                }
            } catch let error as FactoryError where error.isCancellation {
                DispatchQueue.main.async {
                    self?.isBuilding = false
                    self?.setFieldsEnabled(true)
                    self?.showStatus(Self.defaultHint)
                }
            } catch {
                // Failure surfaces inline in the HUD — never a silent dismissal.
                DispatchQueue.main.async {
                    self?.isBuilding = false
                    self?.setFieldsEnabled(true)
                    self?.showStatus(error.localizedDescription, isError: true)
                }
            }
        }
    }

    private static func launch(_ appURL: URL) {
        DispatchQueue.main.async {
            NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
        }
    }

    private static func askCollisionDecision(_ collision: Collision) async -> CollisionDecision {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
                let alert = NSAlert()
                alert.messageText = "\(collision.appName).app already exists"
                if collision.existingIsAppSeedClone {
                    alert.informativeText = "An app with this name is already installed. Overwriting keeps its login session — the app's identity is derived from the site, not the copy."
                    alert.addButton(withTitle: "Overwrite")
                    alert.addButton(withTitle: "Keep Both")
                    alert.addButton(withTitle: "Cancel")
                    switch alert.runModal() {
                    case .alertFirstButtonReturn: continuation.resume(returning: .overwrite)
                    case .alertSecondButtonReturn: continuation.resume(returning: .autoRename)
                    default: continuation.resume(returning: .cancel)
                    }
                } else {
                    // The existing app is NOT one of ours (e.g. the official
                    // LinkedIn.app) — overwriting it is never offered.
                    alert.informativeText = "The existing \(collision.appName).app wasn't created by AppSeed, so it won't be replaced. Keep Both installs this one as \"\(collision.appName) 2.app\"."
                    alert.addButton(withTitle: "Keep Both")
                    alert.addButton(withTitle: "Cancel")
                    switch alert.runModal() {
                    case .alertFirstButtonReturn: continuation.resume(returning: .autoRename)
                    default: continuation.resume(returning: .cancel)
                    }
                }
            }
        }
    }

    // MARK: - Status

    private func showStatus(_ message: String, isError: Bool = false) {
        DispatchQueue.main.async { [weak self] in
            guard let statusLabel = self?.statusLabel else { return }
            statusLabel.stringValue = message
            statusLabel.textColor = isError ? HUDStyle.errorText : HUDStyle.secondaryText
        }
    }

    private func setFieldsEnabled(_ enabled: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.urlField?.isEnabled = enabled
            self?.nameField?.isEnabled = enabled
        }
    }
}

private extension FactoryError {
    var isCancellation: Bool {
        if case .cancelled = self { return true }
        return false
    }
}
