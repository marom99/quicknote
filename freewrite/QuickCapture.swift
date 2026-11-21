import AppKit
import Carbon
import SwiftUI

struct CaptureHotKey: Equatable {
    let keyCode: UInt32
    let modifiers: NSEvent.ModifierFlags

    static let standard = CaptureHotKey(keyCode: UInt32(kVK_ANSI_N), modifiers: [.control, .option, .command])

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
        + (keyCode == UInt32(kVK_ANSI_N) ? "N" : "")
    }
}

final class GlobalHotKey {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void

    init(shortcut: CaptureHotKey = .standard, action: @escaping () -> Void) {
        self.action = action
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            Unmanaged<GlobalHotKey>.fromOpaque(context).takeUnretainedValue().action()
            return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard status == noErr else {
            NSLog("Quick capture event handler registration failed: %d", status)
            return
        }
        let registration = RegisterEventHotKey(shortcut.keyCode, shortcut.carbonModifiers,
            EventHotKeyID(signature: 0x46574350, id: 1), GetApplicationEventTarget(), 0, &hotKey)
        if registration != noErr {
            NSLog("Quick capture hotkey registration failed: %d", registration)
        }
    }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }
}

@MainActor
final class QuickCaptureCenter {
    static let shared = QuickCaptureCenter()

    struct Editor {
        let isAvailable: () -> Bool
        let isKey: () -> Bool
        let show: () -> Void
        let capture: () -> Void
    }

    private var editors: [UUID: Editor] = [:]
    private let activate: @MainActor () -> Void
    private let fallback: @MainActor () -> Void
    var openWindow: (() -> Void)?
    private(set) var hasPendingCapture = false

    init(activate: @escaping @MainActor () -> Void = { NSApp.activate(ignoringOtherApps: true) },
         fallback: @escaping @MainActor () -> Void = { NSApp.sendAction(Selector(("newWindow:")), to: nil, from: nil) }) {
        self.activate = activate
        self.fallback = fallback
    }

    func register(id: UUID, editor: Editor) {
        editors[id] = editor
        if hasPendingCapture && editor.isAvailable() {
            hasPendingCapture = false
            editor.show()
            editor.capture()
        }
    }

    func unregister(id: UUID) { editors[id] = nil }

    func trigger() { showWindow(capture: true) }

    func showWindow(capture: Bool = false) {
        activate()
        let available = editors.values.filter { $0.isAvailable() }
        if let editor = available.first(where: { $0.isKey() }) ?? available.first {
            editor.show()
            if capture { editor.capture() }
        } else {
            hasPendingCapture = hasPendingCapture || capture
            if let openWindow { openWindow() } else { fallback() }
        }
    }
}

struct QuickCaptureWindowAccessor: NSViewRepresentable {
    let capture: () -> Void

    final class HostView: NSView {
        let id = UUID()
        var capture: () -> Void = {}

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            QuickCaptureCenter.shared.unregister(id: id)
            guard let window else { return }
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, let window, self.window === window else { return }
                QuickCaptureCenter.shared.register(id: self.id, editor: .init(
                    isAvailable: { [weak window] in
                        guard let window else { return false }
                        return NSApp.windows.contains { $0 === window }
                    },
                    isKey: { [weak window] in window?.isKeyWindow == true },
                    show: { [weak window] in
                        window?.deminiaturize(nil)
                        window?.makeKeyAndOrderFront(nil)
                    },
                    capture: { [weak self] in self?.capture() }
                ))
            }
        }
    }

    func makeNSView(context: Context) -> HostView {
        let view = HostView()
        view.capture = capture
        return view
    }

    func updateNSView(_ view: HostView, context: Context) { view.capture = capture }

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
