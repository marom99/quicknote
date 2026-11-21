import SwiftUI

struct EditorCommandActions {
    var newEntry: () -> Void
    var openHistory: () -> Void
    var openDestinationSettings: () -> Void
}

private struct EditorCommandActionsKey: FocusedValueKey {
    typealias Value = EditorCommandActions
}

extension FocusedValues {
    var editorCommandActions: EditorCommandActions? {
        get { self[EditorCommandActionsKey.self] }
        set { self[EditorCommandActionsKey.self] = newValue }
    }
}

struct EditorCommands: Commands {
    @FocusedValue(\.editorCommandActions) private var actions

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Entry") {
                actions?.newEntry()
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(actions == nil)
        }

        CommandGroup(after: .sidebar) {
            Button("History") {
                actions?.openHistory()
            }
            .keyboardShortcut("h", modifiers: [.command, .shift])
            .disabled(actions == nil)
        }

        CommandGroup(replacing: .appSettings) {
            Button("Destination Settings…") {
                actions?.openDestinationSettings()
            }
            .keyboardShortcut(",", modifiers: .command)
            .disabled(actions == nil)
        }
    }
}
