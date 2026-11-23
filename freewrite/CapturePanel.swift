import AppKit

@MainActor
private final class CapturePanel: NSPanel {
    var onEscape: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) { onEscape?() }
}

@MainActor
final class CapturePanelController: NSObject, NSTextViewDelegate {
    private let store = CaptureDraftStore.local
    private let editor = NSTextView()
    private let destinationLabel = NSTextField(labelWithString: "")
    private let message = NSTextField(wrappingLabelWithString: "")
    private let hint = NSTextField(labelWithString: "Esc to finish")
    private lazy var done = NSButton(title: "Done", target: self, action: #selector(finish))
    private lazy var keepDraft = NSButton(title: "Keep Draft", target: self, action: #selector(hideKeepingDraft))
    private lazy var discardDraft = NSButton(title: "Discard…", target: self, action: #selector(confirmDiscard))
    private var draft: CaptureDraft?

    var canWrite: (URL) -> Bool = { _ in true }
    var didSave: (URL) -> Void = { _ in }

    private lazy var panel: NSPanel = {
        let panel = CapturePanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 290),
                                 styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Quick Capture"
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.onEscape = { [weak self] in self?.escape() }

        destinationLabel.lineBreakMode = .byTruncatingTail
        destinationLabel.textColor = .secondaryLabelColor
        destinationLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)

        editor.isRichText = false
        editor.importsGraphics = false
        editor.allowsUndo = true
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.font = NSFont(name: "Lato-Regular", size: 16) ?? .systemFont(ofSize: 16)
        editor.textContainerInset = NSSize(width: 10, height: 10)
        editor.textContainer?.widthTracksTextView = true
        editor.autoresizingMask = [.width]
        editor.isVerticallyResizable = true
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.delegate = self
        editor.setAccessibilityLabel("Capture text")
        editor.setAccessibilityIdentifier("quickCaptureEditor")

        let scroll = NSScrollView()
        scroll.borderType = .lineBorder
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = editor

        message.textColor = .secondaryLabelColor
        message.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        message.setAccessibilityIdentifier("quickCaptureStatus")

        hint.textColor = .secondaryLabelColor
        hint.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let footer = NSStackView(views: [hint, spacer, discardDraft, keepDraft, done])
        footer.alignment = .centerY

        let stack = NSStackView(views: [destinationLabel, scroll, message, footer])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(stack)
        panel.contentView = content
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 14),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
            destinationLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            message.widthAnchor.constraint(equalTo: stack.widthAnchor),
            footer.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        panel.initialFirstResponder = editor
        return panel
    }()

    func show(destination: @autoclosure () -> SaveDestination?) {
        if !panel.isVisible {
            do {
                if draft == nil {
                    draft = try store.load() ?? destination().map { CaptureDraft(destination: $0) }
                }
                guard let draft else { return }
                editor.string = draft.text
                editor.undoManager?.removeAllActions()
                editor.isEditable = draft.pendingWrite == nil
                destinationLabel.stringValue = "To: \(draft.destination.displayName)"
                setStatus(draft.isBlank ? nil : "Recovered draft")
            } catch {
                editor.string = ""
                editor.isEditable = false
                destinationLabel.stringValue = ""
                setStatus("The local draft couldn’t be opened. It hasn’t been replaced.")
            }
            done.title = "Done"
            offerKeepDraft(false)
            discardDraft.isHidden = true
            panel.appearance = NSAppearance(named: UserDefaults.standard.string(forKey: "colorScheme") == "dark"
                                               ? .darkAqua : .aqua)
            if let frame = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })?.visibleFrame
                ?? NSScreen.main?.visibleFrame {
                panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2,
                                             y: frame.midY - panel.frame.height / 2))
            }
            let end = NSRange(location: (editor.string as NSString).length, length: 0)
            editor.setSelectedRange(end)
            editor.scrollRangeToVisible(end)
        }
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(editor)
    }

    func textDidChange(_ notification: Notification) {
        guard var draft, draft.pendingWrite == nil, !editor.hasMarkedText() else { return }
        draft.text = editor.string
        self.draft = draft
        do {
            try store.preserve(draft)
            if done.title == "Done" { setStatus(nil) }
        } catch {
            setStatus("Couldn’t keep a local copy. Leave this panel open until you can save.")
            offerKeepDraft(false)
        }
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard commandSelector == #selector(NSResponder.cancelOperation(_:)) else { return false }
        escape()
        return true
    }

    private func escape() {
        if keepDraft.isHidden { finish() } else { hideKeepingDraft() }
    }

    @objc private func finish() {
        guard var draft else {
            panel.orderOut(nil)
            return
        }
        editor.unmarkText()
        if draft.pendingWrite == nil { draft.text = editor.string }
        do {
            let url = try store.save(&draft, canWrite: canWrite)
            self.draft = nil
            if let url { didSave(url) }
            panel.orderOut(nil)
        } catch {
            self.draft = draft
            editor.isEditable = draft.pendingWrite == nil
            NSLog("Quick capture save failed: %@", error.localizedDescription)
            let reason = (error as? CaptureDraftStore.SaveError)?.localizedDescription ?? "Couldn’t save to the destination."
            if (try? store.preserve(draft)) != nil {
                setStatus("\(reason) Your draft is kept on this Mac.")
                offerKeepDraft(true)
            } else {
                setStatus("\(reason) Keep this panel open or copy your text.")
                offerKeepDraft(false)
            }
            done.title = "Retry"
            discardDraft.isHidden = draft.isBlank
            panel.makeFirstResponder(editor)
        }
    }

    @objc private func hideKeepingDraft() {
        editor.unmarkText()
        guard let draft else { return }
        do {
            try store.preserve(draft)
            panel.orderOut(nil)
        } catch {
            setStatus("Couldn’t keep a local copy. Leave this panel open or copy your text.")
            offerKeepDraft(false)
        }
    }

    private func offerKeepDraft(_ isSafe: Bool) {
        keepDraft.isHidden = !isSafe
        hint.stringValue = isSafe ? "Esc to keep draft" : "Esc to finish"
    }

    @objc private func confirmDiscard() {
        let alert = NSAlert()
        alert.messageText = "Discard this capture draft?"
        alert.informativeText = "The text in the capture panel will be cleared."
        alert.addButton(withTitle: "Keep Draft").keyEquivalent = "\r"
        alert.addButton(withTitle: "Discard Draft").hasDestructiveAction = true
        alert.beginSheetModal(for: panel) { [weak self] response in
            guard let self, response == .alertSecondButtonReturn else { return }
            do {
                try self.store.discard()
                self.draft = nil
                self.panel.orderOut(nil)
            } catch {
                self.setStatus("Couldn’t remove the local draft. It hasn’t been cleared.")
            }
        }
    }

    private func setStatus(_ text: String?) {
        message.stringValue = text ?? ""
        message.isHidden = text == nil
    }
}
