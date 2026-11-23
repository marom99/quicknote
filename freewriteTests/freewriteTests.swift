//
//  freewriteTests.swift
//  freewriteTests
//
//  Created by thorfinn on 2/14/25.
//

import Testing
import AppKit
@testable import freewrite

private final class EditorFocusTestWindow: NSWindow {
    var keyForTesting = true
    override var isKeyWindow: Bool { keyForTesting }
}

private final class EditorFocusTestField: NSTextField, NSTextViewDelegate {}

private final class TestWindowCloseDelegate: NSObject, NSWindowDelegate {
    var allowsClose = true
    func windowShouldClose(_ sender: NSWindow) -> Bool { allowsClose }
}

private final class CloseTrackingWindow: NSWindow {
    private(set) var closeCount = 0
    override func close() { closeCount += 1 }
}

struct freewriteTests {

    @Test @MainActor func editorWindowCloseRequiresBothApprovalAndASuccessfulSave() {
        let window = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let existingDelegate = TestWindowCloseDelegate()
        let closeDelegate = EditorWindowCloseDelegate()
        closeDelegate.forwardedDelegate = existingDelegate
        var saveAttempts = 0
        var canSave = false
        closeDelegate.prepareToClose = { _ in
            saveAttempts += 1
            return canSave
        }
        existingDelegate.allowsClose = false
        #expect(!closeDelegate.windowShouldClose(window))
        #expect(saveAttempts == 0)

        existingDelegate.allowsClose = true
        #expect(!closeDelegate.windowShouldClose(window))
        #expect(saveAttempts == 1)

        canSave = true
        #expect(closeDelegate.windowShouldClose(window))
        #expect(saveAttempts == 2)
    }

    @Test @MainActor func editorWindowCloseWaitsForExplicitDiscardWhenSaveFails() {
        let window = CloseTrackingWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let delegate = EditorWindowCloseDelegate()
        var discardChanges: (() -> Void)?
        delegate.prepareToClose = { continuation in
            discardChanges = continuation
            return false
        }

        #expect(!delegate.windowShouldClose(window))
        #expect(window.closeCount == 0)

        discardChanges?()
        #expect(window.closeCount == 1)
    }

    @Test func appKeepsItsBundleIdentityWithoutRecordingUsageDescriptions() {
        let appBundle = Bundle.main
        #expect(appBundle.bundleIdentifier == "app.humansongs.freewrite")
        for key in ["NSCameraUsageDescription", "NSMicrophoneUsageDescription", "NSSpeechRecognitionUsageDescription"] {
            #expect(appBundle.object(forInfoDictionaryKey: key) == nil, "Unexpected recording privacy key: \(key)")
        }
    }

    @Test @MainActor func automaticEditorFocusRespectsOtherRespondersAndRails() async {
        let window = EditorFocusTestWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let editor = FreewriteEditorTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        let field = NSTextField(frame: NSRect(x: 0, y: 210, width: 200, height: 24))
        window.contentView?.addSubview(editor)
        window.contentView?.addSubview(field)
        window.makeFirstResponder(nil)

        editor.focusIfAvailable()
        #expect(window.firstResponder === editor)

        window.makeFirstResponder(field)
        let fieldResponder = window.firstResponder
        editor.focusIfAvailable()
        #expect(window.firstResponder === fieldResponder)

        window.makeFirstResponder(nil)
        editor.allowsAutomaticFocus = false
        editor.focusIfAvailable()
        #expect(window.firstResponder !== editor)

        let button = NSButton(frame: NSRect(x: 210, y: 0, width: 80, height: 24))
        window.contentView?.addSubview(button)
        window.makeFirstResponder(button)
        editor.allowsAutomaticFocus = true
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        #expect(window.firstResponder === editor)

        editor.allowsAutomaticFocus = false
        window.makeFirstResponder(field)
        let railFieldResponder = window.firstResponder
        editor.allowsAutomaticFocus = true
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        #expect(window.firstResponder === railFieldResponder)

        window.makeFirstResponder(nil)
        editor.allowsAutomaticFocus = true
        window.keyForTesting = false
        editor.focusIfAvailable()
        #expect(window.firstResponder !== editor)
    }

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    }

    @Test @MainActor func staleFieldEditorDoesNotBlockRailRemovalFocus() async {
        let window = EditorFocusTestWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 300),
                                           styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let editor = FreewriteEditorTextView(frame: .zero)
        let owner = EditorFocusTestField(frame: .zero)
        let fieldEditor = NSTextView(frame: .zero)
        fieldEditor.isFieldEditor = true
        fieldEditor.delegate = owner
        let rail = RailRemovalObserver.RemovalView()
        window.contentView?.addSubview(editor)
        window.contentView?.addSubview(owner)
        window.contentView?.addSubview(fieldEditor)
        window.contentView?.addSubview(rail)
        window.makeFirstResponder(fieldEditor)

        editor.focusIfAvailable()
        #expect(window.firstResponder === fieldEditor)

        editor.allowsAutomaticFocus = false
        editor.allowsAutomaticFocus = true
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        #expect(window.firstResponder === fieldEditor)

        owner.isHidden = true
        editor.focusIfAvailable()
        #expect(window.firstResponder === editor)

        owner.isHidden = false
        owner.removeFromSuperview()
        window.contentView?.addSubview(fieldEditor)
        fieldEditor.delegate = owner
        window.makeFirstResponder(fieldEditor)
        #expect(fieldEditor.window === window)
        rail.onRemoval = { editor.requestAutomaticFocus() }
        rail.removeFromSuperview()
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                DispatchQueue.main.async { continuation.resume() }
            }
        }
        #expect(window.firstResponder === editor)
    }

}
