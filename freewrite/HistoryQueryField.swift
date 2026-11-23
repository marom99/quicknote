import SwiftUI
import AppKit

struct HistoryQueryField: NSViewRepresentable {
    @Binding var query: String
    var focusRequest: UUID?
    var moveSelection: (Int) -> Void
    var submit: () -> Void
    var cancel: () -> Void

    func makeNSView(context: Context) -> QueryTextField {
        let field = QueryTextField()
        field.delegate = context.coordinator
        field.font = .systemFont(ofSize: 12)
        field.placeholderString = "Search"
        field.isEditable = true
        field.isBezeled = false
        field.drawsBackground = false
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setAccessibilityLabel("Search Notes")
        field.setAccessibilityIdentifier("historySearchField")
        return field
    }

    func updateNSView(_ field: QueryTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != query {
            field.stringValue = query
        }
        field.focusRequest = focusRequest
        field.applyFocusRequest()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class QueryTextField: NSTextField {
        var focusRequest: UUID?
        private var appliedFocusRequest: UUID?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            applyFocusRequest()
        }

        func applyFocusRequest() {
            guard let request = focusRequest, request != appliedFocusRequest, window != nil else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.focusRequest == request, self.appliedFocusRequest != request,
                      let window = self.window, window.makeFirstResponder(self) else { return }
                self.appliedFocusRequest = request
                self.currentEditor()?.selectAll(nil)
            }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: HistoryQueryField

        init(parent: HistoryQueryField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.query = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard !textView.hasMarkedText() else { return false }
            switch selector {
            case #selector(NSResponder.moveUp(_:)): parent.moveSelection(-1)
            case #selector(NSResponder.moveDown(_:)): parent.moveSelection(1)
            case #selector(NSResponder.insertNewline(_:)): parent.submit()
            case #selector(NSResponder.cancelOperation(_:)): parent.cancel()
            default: return false
            }
            return true
        }
    }
}
