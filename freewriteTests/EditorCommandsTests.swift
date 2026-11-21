import SwiftUI
import Testing
@testable import freewrite

struct EditorCommandsTests {
    @Test(arguments: [
        (EditorCommand.newEntry, KeyboardShortcut("n", modifiers: .command)),
        (.openHistory, KeyboardShortcut("h", modifiers: [.command, .shift])),
        (.openDestinationSettings, KeyboardShortcut(",", modifiers: .command))
    ])
    func commandUsesExpectedShortcutAndHandler(command: EditorCommand, shortcut: KeyboardShortcut) {
        var calls: [EditorCommand] = []
        let actions = EditorCommandActions(
            newEntry: { calls.append(.newEntry) },
            openHistory: { calls.append(.openHistory) },
            openDestinationSettings: { calls.append(.openDestinationSettings) }
        )

        #expect(command.shortcut == shortcut)
        command.perform(with: actions)
        #expect(calls == [command])
        command.perform(with: nil)
        #expect(calls == [command])
    }
}
