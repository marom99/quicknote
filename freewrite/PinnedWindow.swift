import AppKit
import SwiftUI

/// Keeps the editor window floating above other apps and present on every Space.
///
/// Only the window's level and collection behavior change: it stays an ordinary
/// key window, so editing, menus, sheets and shortcuts behave as they always have.
/// A click on the floating window activates the app and lands in the editor.
enum PinnedWindow {
    static let defaultsKey = "windowPinned"

    private static let pinnedLevel: NSWindow.Level = .floating
    private static let pinnedBehavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

    /// Window state from before the first pin, restored when pinning is turned off.
    private final class Baseline {
        let level: NSWindow.Level
        let collectionBehavior: NSWindow.CollectionBehavior
        let hidesOnDeactivate: Bool

        init(_ window: NSWindow) {
            level = window.level
            collectionBehavior = window.collectionBehavior
            hidesOnDeactivate = window.hidesOnDeactivate
        }
    }

    private static var baselines = NSMapTable<NSWindow, Baseline>(keyOptions: .weakMemory, valueOptions: .strongMemory)
    private static var pinnedWindows = NSHashTable<NSWindow>.weakObjects()
    private static var observations: [NSObjectProtocol] = []

    static func isPinned(_ window: NSWindow) -> Bool {
        pinnedWindows.contains(window)
    }

    /// Applies (or removes once) the pinned treatment for one editor window.
    static func apply(to window: NSWindow, pinned: Bool) {
        // Menus, status items and panels (Quick Capture) keep their own behavior.
        guard window.contentView != nil, !(window is NSPanel) else { return }
        startObserving()
        if pinned {
            if baselines.object(forKey: window) == nil {
                baselines.setObject(Baseline(window), forKey: window)
            }
            pinnedWindows.add(window)
            applyPinned(window)
        } else if pinnedWindows.contains(window) {
            restore(window)
        }
    }

    /// Re-applies the pinned level after AppKit rebuilds the window (full screen, Minimize, screen change).
    private static func applyPinned(_ window: NSWindow) {
        window.level = pinnedLevel
        window.hidesOnDeactivate = false
        guard !window.styleMask.contains(.fullScreen) else { return }
        var behavior = window.collectionBehavior.subtracting(.moveToActiveSpace)
        behavior.formUnion(pinnedBehavior)
        if behavior != window.collectionBehavior {
            window.collectionBehavior = behavior
        }
    }

    private static func restore(_ window: NSWindow) {
        defer { pinnedWindows.remove(window) }
        guard let baseline = baselines.object(forKey: window) else { return }
        baselines.setObject(nil, forKey: window)
        window.level = baseline.level
        window.hidesOnDeactivate = baseline.hidesOnDeactivate
        // A full-screen window's collection behavior belongs to AppKit until it exits.
        guard !window.styleMask.contains(.fullScreen) else { return }
        window.collectionBehavior = baseline.collectionBehavior
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
                    guard pinnedWindows.contains(window) else { return }
                    applyPinned(window)
                } else {
                    for window in pinnedWindows.allObjects {
                        applyPinned(window)
                    }
                }
            }
            observations.append(token)
        }
    }
}

/// Pushes the pinned preference into the window that hosts the editor.
struct PinnedWindowAccessor: NSViewRepresentable {
    let pinned: Bool

    final class HostView: NSView {
        var pinned = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
        }

        func apply() {
            guard let window else { return }
            PinnedWindow.apply(to: window, pinned: pinned)
        }
    }

    func makeNSView(context: Context) -> HostView {
        let view = HostView()
        view.pinned = pinned
        return view
    }

    func updateNSView(_ nsView: HostView, context: Context) {
        nsView.pinned = pinned
        nsView.apply()
    }
}
