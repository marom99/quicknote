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

struct freewriteTests {

    @Test @MainActor func automaticEditorFocusRespectsOtherRespondersAndRails() {
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

        editor.allowsAutomaticFocus = true
        window.keyForTesting = false
        editor.focusIfAvailable()
        #expect(window.firstResponder !== editor)
    }

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    }

}
