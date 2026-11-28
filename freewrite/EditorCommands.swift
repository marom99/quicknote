import SwiftUI

struct EditorCommandActions {
    var newEntry: () -> Void
    var openHistory: () -> Void
    var searchNotes: () -> Void
    var openDestinationSettings: () -> Void
    var markdownSourceShown = false
    var toggleMarkdownSource: (() -> Void)?
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

enum EditorCommand {
    case newEntry
    case openHistory
    case searchNotes
    case openDestinationSettings

    var shortcut: KeyboardShortcut {
        switch self {
        case .newEntry: KeyboardShortcut("n", modifiers: .command)
        case .openHistory: KeyboardShortcut("h", modifiers: [.command, .shift])
        case .searchNotes: KeyboardShortcut("p", modifiers: .command)
        case .openDestinationSettings: KeyboardShortcut(",", modifiers: .command)
        }
    }

    func perform(with actions: EditorCommandActions?) {
        guard let actions else { return }
        switch self {
        case .newEntry: actions.newEntry()
        case .openHistory: actions.openHistory()
        case .searchNotes: actions.searchNotes()
        case .openDestinationSettings: actions.openDestinationSettings()
        }
    }
}

struct EditorCommands: Commands {
    @FocusedValue(\.editorCommandActions) private var actions

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            commandButton("New Note", .newEntry)
        }

        CommandGroup(after: .sidebar) {
            commandButton("History", .openHistory)
            commandButton("Search Notes", .searchNotes)
            Button(actions?.markdownSourceShown == true ? "Show Rendered Markdown" : "Show Markdown Source") {
                actions?.toggleMarkdownSource?()
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])
            .disabled(actions?.toggleMarkdownSource == nil)
        }

        CommandGroup(replacing: .appSettings) {
            commandButton("Destination Settings…", .openDestinationSettings)
        }
    }

    private func commandButton(_ title: LocalizedStringKey, _ command: EditorCommand) -> some View {
        Button(title) {
            command.perform(with: actions)
        }
        .keyboardShortcut(command.shortcut)
        .disabled(actions == nil)
    }
}
