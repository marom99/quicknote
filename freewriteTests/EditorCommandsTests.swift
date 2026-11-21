import SwiftUI
import Testing
@testable import freewrite

struct EditorCommandsTests {
    @Test func focusedActionsRouteToTheirMatchingHandler() {
        var calls: [String] = []
        var values = FocusedValues()
        values.editorCommandActions = EditorCommandActions(
            newEntry: { calls.append("newEntry") },
            openHistory: { calls.append("history") },
            openDestinationSettings: { calls.append("settings") }
        )

        values.editorCommandActions?.newEntry()
        #expect(calls == ["newEntry"])
        values.editorCommandActions?.openHistory()
        #expect(calls == ["newEntry", "history"])
        values.editorCommandActions?.openDestinationSettings()
        #expect(calls == ["newEntry", "history", "settings"])
    }

    @Test func missingFocusedActionsAreSafeAndCanBeCleared() {
        var values = FocusedValues()
        #expect(values.editorCommandActions == nil)

        var callCount = 0
        values.editorCommandActions = EditorCommandActions(
            newEntry: { callCount += 1 },
            openHistory: { callCount += 1 },
            openDestinationSettings: { callCount += 1 }
        )
        values.editorCommandActions = nil

        values.editorCommandActions?.newEntry()
        values.editorCommandActions?.openHistory()
        values.editorCommandActions?.openDestinationSettings()
        #expect(values.editorCommandActions == nil)
        #expect(callCount == 0)
    }
}
