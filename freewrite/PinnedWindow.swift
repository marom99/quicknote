import AppKit
import SwiftUI

/// Keeps the editor window floating above other apps' windows and present on every Space.
///
/// Only the window's level and collection behavior change: it stays an ordinary key
/// window, so editing, menus, sheets and shortcuts behave as they always have.
enum PinnedWindow {
    /// Key left behind by the earlier pin toggle; cleared so no stored value can imply a choice.
    static let legacyDefaultsKey = "windowPinned"

    private static let floatingLevel: NSWindow.Level = .floating
    private static let floatingBehavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

    private static var editorWindows = NSHashTable<NSWindow>.weakObjects()
    private static var observations: [NSObjectProtocol] = []

    /// Floats one editor window. Idempotent, so every SwiftUI update can call it.
    static func apply(to window: NSWindow) {
        // Menus, status items and panels (Quick Capture) keep their own behavior.
        guard window.contentView != nil, !(window is NSPanel) else { return }
        clearLegacyDefaults()
        startObserving()

        editorWindows.add(window)
        window.level = floatingLevel
        window.hidesOnDeactivate = false

        // A full-screen window's collection behavior belongs to AppKit until it exits.
        guard !window.styleMask.contains(.fullScreen) else { return }
        var behavior = window.collectionBehavior.subtracting(.moveToActiveSpace)
        behavior.formUnion(floatingBehavior)
        if behavior != window.collectionBehavior {
            window.collectionBehavior = behavior
        }
    }

    /// Re-applies the floating treatment after AppKit rebuilds the window (full screen, Minimize, screen change).
    private static func reapply(_ window: NSWindow) {
        guard editorWindows.contains(window) else { return }
        window.level = floatingLevel
        guard !window.styleMask.contains(.fullScreen) else { return }
        var behavior = window.collectionBehavior.subtracting(.moveToActiveSpace)
        behavior.formUnion(floatingBehavior)
        if behavior != window.collectionBehavior {
            window.collectionBehavior = behavior
        }
    }

    private static func clearLegacyDefaults() {
        UserDefaults.standard.removeObject(forKey: legacyDefaultsKey)
    }

    private static func startObserving() {
        guard observations.isEmpty else { return }
        let names: [Notification.Name] = [
            NSWindow.didExitFullScreenNotification,
            NSWindow.didDeminiaturizeNotification,
            NSApplication.didChangeScreenParametersNotification,
        ]
        for name in names {
            let token = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { notification in
                if let window = notification.object as? NSWindow {
                    reapply(window)
                } else {
                    for window in editorWindows.allObjects {
                        reapply(window)
                    }
                }
            }
            observations.append(token)
        }
    }
}

/// Pushes the floating window treatment into the window that hosts the editor.
struct PinnedWindowAccessor: NSViewRepresentable {
    final class HostView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            PinnedWindow.apply(to: window)
        }
    }

    func makeNSView(context: Context) -> HostView {
        HostView()
    }

    func updateNSView(_ nsView: HostView, context: Context) {
        guard let window = nsView.window else { return }
        PinnedWindow.apply(to: window)
    }
}
