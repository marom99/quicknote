//
//  freewriteApp.swift
//  freewrite
//
//  Created by thorfinn on 2/14/25.
//

import SwiftUI
import AppKit

/// Keeps native traffic lights + title, but forces a solid title bar that
/// always matches the note background (macOS likes to reset this on focus).
enum WindowChrome {
    private final class WindowState {
        var title: String = "Untitled"
        var isDark: Bool = false
    }

    private static var observations: [NSObjectProtocol] = []
    private static var states = NSMapTable<NSWindow, WindowState>(
        keyOptions: .weakMemory,
        valueOptions: .strongMemory
    )
    private static var started = false

    private static func state(for window: NSWindow) -> WindowState {
        if let existing = states.object(forKey: window) {
            return existing
        }
        let newState = WindowState()
        states.setObject(newState, forKey: window)
        return newState
    }

    static func startObserving() {
        guard !started else { return }
        started = true

        let names: [Notification.Name] = [
            NSWindow.didBecomeKeyNotification,
            NSWindow.didBecomeMainNotification,
            NSWindow.didExposeNotification,
            NSApplication.didBecomeActiveNotification,
            NSApplication.didChangeScreenParametersNotification,
        ]

        for name in names {
            let token = NotificationCenter.default.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { notification in
                if let window = notification.object as? NSWindow {
                    apply(to: window)
                } else {
                    applyToAllWindows()
                }
            }
            observations.append(token)
        }
    }

    /// Called from SwiftUI when the entry title or theme changes for a specific window.
    static func update(for window: NSWindow, title: String, isDark: Bool) {
        guard shouldStyle(window) else { return }
        let state = state(for: window)
        let themeChanged = state.isDark != isDark
        state.title = title
        state.isDark = isDark

        window.title = title
        if themeChanged {
            apply(to: window)
        }
    }

    static func applyToAllWindows() {
        for window in NSApplication.shared.windows where shouldStyle(window) {
            apply(to: window)
        }
    }

    static func apply(to window: NSWindow) {
        guard shouldStyle(window) else { return }
        let state = state(for: window)

        window.title = state.title
        window.styleMask.insert([.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView])
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = true
        window.isOpaque = true
        window.appearance = NSAppearance(named: state.isDark ? .darkAqua : .aqua)
        window.backgroundColor = state.isDark ? .black : .white

        if #available(macOS 11.0, *) {
            window.titlebarSeparatorStyle = .none
        }

        // macOS re-injects a material fill into the title bar when key status changes.
        // Clear it so the solid window / content color shows through.
        clearTitlebarMaterials(in: window)

        // Re-apply after the run loop so we win races against AppKit's own redraw.
        DispatchQueue.main.async {
            guard shouldStyle(window) else { return }
            window.titlebarAppearsTransparent = true
            window.backgroundColor = state.isDark ? .black : .white
            if #available(macOS 11.0, *) {
                window.titlebarSeparatorStyle = .none
            }
            clearTitlebarMaterials(in: window)
        }
    }

    private static func shouldStyle(_ window: NSWindow) -> Bool {
        // Style ordinary app windows; skip menus / status items if any.
        window.contentView != nil && !window.className.contains("NSStatusBar")
    }

    private static func clearTitlebarMaterials(in window: NSWindow) {
        guard let closeButton = window.standardWindowButton(.closeButton) else { return }

        // closeButton → titlebar view → titlebar container
        var view: NSView? = closeButton.superview
        while let current = view {
            neutralizeTitlebarMaterials(in: current)
            if current.className.contains("TitlebarContainer") {
                break
            }
            view = current.superview
        }
    }

    private static func neutralizeTitlebarMaterials(in root: NSView) {
        if let effectView = root as? NSVisualEffectView {
            // Hidden effect views stop AppKit from painting the gray material strip.
            effectView.isHidden = true
            effectView.alphaValue = 0
        }

        root.wantsLayer = true
        if root.className.contains("Titlebar") {
            root.layer?.backgroundColor = NSColor.clear.cgColor
        }

        for subview in root.subviews {
            neutralizeTitlebarMaterials(in: subview)
        }
    }
}

/// Pushes the current entry title + theme into WindowChrome and hooks window access.
struct WindowTitleAccessor: NSViewRepresentable {
    let title: String
    let isDark: Bool

    func makeNSView(context: Context) -> NSView {
        WindowChrome.startObserving()
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                WindowChrome.update(for: window, title: title, isDark: isDark)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                WindowChrome.update(for: window, title: title, isDark: isDark)
            }
        }
    }
}

@main
struct freewriteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage("colorScheme") private var colorSchemeString: String = "light"
    
    init() {
        // Register Lato font
        if let fontURL = Bundle.main.url(forResource: "Lato-Regular", withExtension: "ttf") {
            CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, nil)
        }
    }
     
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(colorSchemeString == "dark" ? .dark : .light)
        }
        // Native macOS title bar (traffic lights + centered window title)
        // Default is a comfortable note size; min allows Age-like compact windows.
        .defaultSize(width: 360, height: 540)
        .windowResizability(.contentMinSize)
    }
}

// Add AppDelegate to handle window configuration
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        WindowChrome.startObserving()

        if let window = NSApplication.shared.windows.first {
            // Ensure window starts in windowed mode
            if window.styleMask.contains(.fullScreen) {
                window.toggleFullScreen(nil)
            }
            
            // Center the window on the screen
            window.center()
            WindowChrome.apply(to: window)
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        WindowChrome.applyToAllWindows()
    }
}
