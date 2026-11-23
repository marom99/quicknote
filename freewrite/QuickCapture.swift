import AppKit
import Carbon
import SwiftUI

struct CaptureHotKey: Codable, Equatable {
    private static let supportedModifiers: NSEvent.ModifierFlags = [.control, .option, .shift, .command]
    private static let requiredModifiers: NSEvent.ModifierFlags = [.control, .option, .command]

    let keyCode: UInt32
    let modifierBits: UInt
    let keyLabel: String

    init(keyCode: UInt32, modifiers: NSEvent.ModifierFlags, keyLabel: String) {
        self.keyCode = keyCode
        self.modifierBits = modifiers.intersection(Self.supportedModifiers).rawValue
        self.keyLabel = keyLabel
    }

    init?(event: NSEvent) {
        self.init(event: event, modifiers: event.modifierFlags)
    }

    init?(keyOnly event: NSEvent, modifiers: NSEvent.ModifierFlags) {
        guard event.modifierFlags.intersection(Self.supportedModifiers).isEmpty,
              let characters = event.characters(byApplyingModifiers: []) ?? event.charactersIgnoringModifiers,
              !characters.isEmpty, characters.unicodeScalars.allSatisfy(CharacterSet.alphanumerics.contains) else {
            return nil
        }
        self.init(event: event, modifiers: modifiers)
    }

    private init?(event: NSEvent, modifiers: NSEvent.ModifierFlags) {
        guard !modifiers.intersection(Self.requiredModifiers).isEmpty else { return nil }
        guard let label = Self.keyLabel(for: event) else { return nil }
        self.init(keyCode: UInt32(event.keyCode), modifiers: modifiers, keyLabel: label)
    }

    private static func keyLabel(for event: NSEvent) -> String? {
        let label: String
        switch Int(event.keyCode) {
        case kVK_Space: label = "Space"
        case kVK_Return: label = "↩"
        case kVK_Tab: label = "⇥"
        case kVK_Delete: label = "⌫"
        case kVK_ForwardDelete: label = "⌦"
        case kVK_UpArrow: label = "↑"
        case kVK_DownArrow: label = "↓"
        case kVK_LeftArrow: label = "←"
        case kVK_RightArrow: label = "→"
        default:
            guard let characters = event.characters(byApplyingModifiers: []) ?? event.charactersIgnoringModifiers,
                  !characters.isEmpty,
                  characters.unicodeScalars.allSatisfy({
                      !CharacterSet.controlCharacters.contains($0) && $0.properties.generalCategory != .privateUse
                  }) else { return nil }
            label = characters.uppercased()
        }
        return label
    }

    static let standard = CaptureHotKey(keyCode: UInt32(kVK_ANSI_N),
                                        modifiers: [.control, .option, .command], keyLabel: "N")

    fileprivate var modifiers: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifierBits) }

    func matches(_ other: Self) -> Bool { keyCode == other.keyCode && modifierBits == other.modifierBits }

    var carbonModifiers: UInt32 {
        var result: UInt32 = 0
        if modifiers.contains(.control) { result |= UInt32(controlKey) }
        if modifiers.contains(.option) { result |= UInt32(optionKey) }
        if modifiers.contains(.shift) { result |= UInt32(shiftKey) }
        if modifiers.contains(.command) { result |= UInt32(cmdKey) }
        return result
    }

    var displayString: String {
        (modifiers.contains(.control) ? "⌃" : "")
        + (modifiers.contains(.option) ? "⌥" : "")
        + (modifiers.contains(.shift) ? "⇧" : "")
        + (modifiers.contains(.command) ? "⌘" : "")
        + keyLabel
    }
}

private final class GlobalHotKey {
    private static let signature: OSType = 0x46574350
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var handlerStatus: OSStatus = noErr
    private var installedShortcut: CaptureHotKey?
    private var installedID: UInt32 = 0
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        handlerStatus = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            let owner = Unmanaged<GlobalHotKey>.fromOpaque(context).takeUnretainedValue()
            var id = EventHotKeyID()
            let status = GetEventParameter(event, UInt32(kEventParamDirectObject), UInt32(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard status == noErr, id.signature == GlobalHotKey.signature,
                  id.id == owner.installedID else { return OSStatus(eventNotHandledErr) }
            owner.action()
            return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    func register(_ shortcut: CaptureHotKey) -> OSStatus {
        guard handlerStatus == noErr else { return handlerStatus }
        if installedShortcut?.matches(shortcut) == true { return noErr }

        let id = installedID &+ 1
        var replacement: EventHotKeyRef?
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.carbonModifiers,
            EventHotKeyID(signature: Self.signature, id: id), GetApplicationEventTarget(),
            OptionBits(kEventHotKeyExclusive), &replacement)
        guard status == noErr else { return status }

        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = replacement
        installedID = id
        installedShortcut = shortcut
        return noErr
    }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }
}

@MainActor
final class CaptureShortcutSettings: ObservableObject {
    static let shared = CaptureShortcutSettings()
    static let defaultsKey = "quickCaptureShortcut"

    @Published private(set) var shortcut: CaptureHotKey
    @Published private(set) var isAvailable = false
    private var isRecording = false
    private let defaults: UserDefaults

    private lazy var hotKey = GlobalHotKey { [weak self] in
        MainActor.assumeIsolated {
            guard self?.isRecording == false else { return }
            QuickCaptureCenter.shared.trigger()
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        shortcut = defaults.data(forKey: Self.defaultsKey)
            .flatMap { try? JSONDecoder().decode(CaptureHotKey.self, from: $0) } ?? .standard
    }

    func start() {
        let status = hotKey.register(shortcut)
        isAvailable = status == noErr
        if !isAvailable { NSLog("Quick capture shortcut registration failed: %d", status) }
    }

    private func setShortcut(_ candidate: CaptureHotKey) -> Bool {
        let status = hotKey.register(candidate)
        guard status == noErr else {
            NSLog("Quick capture shortcut registration failed: %d", status)
            return false
        }
        shortcut = candidate
        isAvailable = true
        defaults.set(try? JSONEncoder().encode(candidate), forKey: Self.defaultsKey)
        return true
    }

    func record() {
        guard !isRecording else { return }
        isRecording = true
        defer { isRecording = false }

        let alert = NSAlert()
        alert.messageText = "Capture Shortcut"
        alert.informativeText = "Press a key with Control, Option, or Command. If the combination doesn’t respond, use Choose Keys to check whether it’s available."
        let close = alert.addButton(withTitle: "Done")
        close.keyEquivalent = "\r"
        alert.addButton(withTitle: "Use Default")
        alert.addButton(withTitle: "Choose Keys…")

        let status = NSTextField(wrappingLabelWithString: "")
        status.frame = NSRect(x: 0, y: 0, width: 260, height: 48)
        alert.accessoryView = status

        func showCurrent() {
            status.stringValue = isAvailable ? "Current shortcut: \(shortcut.displayString)"
                : "\(shortcut.displayString) is unavailable. Choose a different shortcut, or use the menu bar."
        }
        showCurrent()

        func apply(_ candidate: CaptureHotKey) {
            if setShortcut(candidate) {
                showCurrent()
            } else {
                status.stringValue = "\(candidate.displayString) is unavailable. Try another shortcut."
            }
        }

        let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.window === alert.window else { return event }
            if event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty {
                if Int(event.keyCode) == kVK_Escape {
                    NSApp.stopModal()
                    return nil
                }
                if Int(event.keyCode) == kVK_Return || Int(event.keyCode) == kVK_Tab { return event }
            }
            guard !event.isARepeat else { return nil }
            guard let candidate = CaptureHotKey(event: event) else {
                status.stringValue = "Choose a key with Control, Option, or Command."
                return nil
            }
            apply(candidate)
            return nil
        }
        defer { if let monitor { NSEvent.removeMonitor(monitor) } }
        NSApp.activate()
        while true {
            switch alert.runModal() {
            case .alertSecondButtonReturn:
                apply(.standard)
            case .alertThirdButtonReturn:
                alert.window.orderOut(nil)
                if let candidate = chooseKeys() { apply(candidate) }
            default:
                alert.window.orderOut(nil)
                return
            }
        }
    }

    private func chooseKeys() -> CaptureHotKey? {
        let alert = NSAlert()
        alert.messageText = "Choose Shortcut Keys"
        alert.informativeText = "Select the modifiers, then press the letter or number by itself."
        alert.addButton(withTitle: "Apply")
        alert.addButton(withTitle: "Cancel").keyEquivalent = "\u{1b}"

        let choices: [(String, NSEvent.ModifierFlags)] = [
            ("Control", .control), ("Option", .option), ("Shift", .shift), ("Command", .command),
        ]
        let buttons = choices.map { title, flag in
            let button = NSButton(checkboxWithTitle: title, target: nil, action: nil)
            button.state = shortcut.modifiers.contains(flag) ? .on : .off
            return button
        }
        let modifiers = NSStackView(views: buttons)
        var keyCode = shortcut.keyCode
        var keyLabel = shortcut.keyLabel
        let key = NSTextField(labelWithString: "Key: \(keyLabel)")
        let status = NSTextField(labelWithString: "")
        let rows = NSStackView(views: [modifiers, key, status])
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.frame.size = rows.fittingSize
        alert.accessoryView = rows

        let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.window === alert.window,
                  let candidate = CaptureHotKey(keyOnly: event, modifiers: .control) else {
                return event
            }
            keyCode = candidate.keyCode
            keyLabel = candidate.keyLabel
            key.stringValue = "Key: \(keyLabel)"
            return nil
        }
        defer {
            if let monitor { NSEvent.removeMonitor(monitor) }
            alert.window.orderOut(nil)
        }
        while alert.runModal() == .alertFirstButtonReturn {
            var flags: NSEvent.ModifierFlags = []
            for ((_, flag), button) in zip(choices, buttons) where button.state == .on {
                flags.insert(flag)
            }
            if !flags.intersection([.control, .option, .command]).isEmpty {
                return CaptureHotKey(keyCode: keyCode, modifiers: flags, keyLabel: keyLabel)
            }
            status.stringValue = "Select Control, Option, or Command."
        }
        return nil
    }
}

struct CaptureShortcutMenu: View {
    @ObservedObject private var settings = CaptureShortcutSettings.shared

    var body: some View {
        Button("Quick Capture") { QuickCaptureCenter.shared.trigger() }
        if !settings.isAvailable {
            Text("Shortcut \(settings.shortcut.displayString) unavailable")
        }
        Button("Capture Shortcut…") { DispatchQueue.main.async { settings.record() } }
        Button("Show Window") { QuickCaptureCenter.shared.showWindow() }
        Divider()
        Button("Quit") { NSApp.terminate(nil) }
    }
}

extension Notification.Name {
    static let quickCaptureDidSave = Notification.Name("quickCaptureDidSave")
}

@MainActor
final class QuickCaptureCenter {
    static let shared = QuickCaptureCenter()

    struct Editor {
        let isAvailable: () -> Bool
        let isKey: () -> Bool
        let show: () -> Void
        let canAcceptCapture: (URL) -> Bool
    }

    private var editors: [UUID: Editor] = [:]
    private let activate: @MainActor () -> Void
    private let fallback: @MainActor () -> Void
    var openWindow: (() -> Void)?

    private lazy var panel: CapturePanelController = {
        let panel = CapturePanelController()
        panel.canWrite = { [weak self] url in
            self?.editors.values.allSatisfy { !$0.isAvailable() || $0.canAcceptCapture(url) } ?? true
        }
        panel.didSave = { url in
            NotificationCenter.default.post(name: .quickCaptureDidSave, object: url)
        }
        return panel
    }()

    init(activate: @escaping @MainActor () -> Void = { NSApp.activate() },
         fallback: @escaping @MainActor () -> Void = { NSApp.sendAction(Selector(("newWindow:")), to: nil, from: nil) }) {
        self.activate = activate
        self.fallback = fallback
    }

    func register(id: UUID, editor: Editor) { editors[id] = editor }

    func unregister(id: UUID) { editors[id] = nil }

    func trigger() { panel.show(destination: DestinationStore().activeDestination) }

    func showWindow() {
        activate()
        let available = editors.values.filter { $0.isAvailable() }
        if let editor = available.first(where: { $0.isKey() }) ?? available.first {
            editor.show()
        } else if let openWindow {
            openWindow()
        } else {
            fallback()
        }
    }
}

struct QuickCaptureWindowAccessor: NSViewRepresentable {
    let canAcceptCapture: (URL) -> Bool

    final class HostView: NSView {
        let id = UUID()
        var canAcceptCapture: (URL) -> Bool = { _ in true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            QuickCaptureCenter.shared.unregister(id: id)
            guard let window else { return }
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, let window, self.window === window else { return }
                QuickCaptureCenter.shared.register(id: self.id, editor: .init(
                    isAvailable: { [weak window] in
                        guard let window else { return false }
                        return window.isVisible || window.isMiniaturized
                    },
                    isKey: { [weak window] in window?.isKeyWindow == true },
                    show: { [weak window] in
                        window?.deminiaturize(nil)
                        window?.makeKeyAndOrderFront(nil)
                    },
                    canAcceptCapture: { [weak self] url in self?.canAcceptCapture(url) ?? true }
                ))
            }
        }
    }

    func makeNSView(context: Context) -> HostView {
        let view = HostView()
        view.canAcceptCapture = canAcceptCapture
        return view
    }

    func updateNSView(_ view: HostView, context: Context) { view.canAcceptCapture = canAcceptCapture }

    static func dismantleNSView(_ view: HostView, coordinator: ()) {
        QuickCaptureCenter.shared.unregister(id: view.id)
    }
}

struct QuickCaptureMenuLabel: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: "square.and.pencil")
            .onAppear {
                QuickCaptureCenter.shared.openWindow = { openWindow(id: "main") }
            }
    }
}
