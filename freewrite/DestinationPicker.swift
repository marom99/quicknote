import SwiftUI
import AppKit

struct DestinationPickerItem: Identifiable, Equatable {
    let id: UUID
    let name: String
}

/// Pure destination filtering for the picker: an empty query keeps every destination,
/// otherwise every whitespace-separated term must appear in the destination's name.
enum DestinationPickerFilter {
    static func filter(_ items: [DestinationPickerItem], query: String) -> [DestinationPickerItem] {
        HistorySearch.filter(items, query: query, title: { $0.name }, body: { _ in "" })
    }
}

/// Keyboard highlight for the picker's visible rows. The highlight is stored by identity so it
/// survives a re-filter, and it clamps at both ends instead of wrapping.
struct DestinationPickerSelection: Equatable {
    private(set) var highlightedID: UUID?

    mutating func highlightFirst(in items: [DestinationPickerItem]) {
        highlightedID = items.first?.id
    }

    mutating func highlight(_ id: UUID?) {
        highlightedID = id
    }

    mutating func move(by offset: Int, in items: [DestinationPickerItem]) {
        guard !items.isEmpty else {
            highlightedID = nil
            return
        }
        guard let current = items.firstIndex(where: { $0.id == highlightedID }) else {
            highlightedID = (offset < 0 ? items.last : items.first)?.id
            return
        }
        let next = min(max(current + offset, 0), items.count - 1)
        highlightedID = items[next].id
    }

    func highlighted(in items: [DestinationPickerItem]) -> DestinationPickerItem? {
        items.first { $0.id == highlightedID }
    }
}

struct DestinationPickerPopover: View {
    let destinations: [DestinationPickerItem]
    let activeID: UUID?
    let onChoose: (UUID) -> Void
    let onAdd: () -> Void
    let onSettings: () -> Void
    let onDismiss: () -> Void

    @State private var query = ""
    @State private var selection = DestinationPickerSelection()
    @State private var focusRequest = UUID()
    @State private var isHoveringAction = false

    private static let rowFontSize: CGFloat = 13
    private static let glyphFontSize: CGFloat = 11
    private static let rowHeight: CGFloat = 28
    private static let listMaxHeight: CGFloat = 264

    private var filtered: [DestinationPickerItem] {
        DestinationPickerFilter.filter(destinations, query: query)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: Self.glyphFontSize))
                    .foregroundStyle(.secondary)
                DestinationSearchField(
                    query: $query,
                    focusRequest: focusRequest,
                    moveSelection: { selection.move(by: $0, in: filtered) },
                    submit: chooseHighlighted,
                    cancel: onDismiss
                )
                .frame(height: 18)
            }
            .padding(.horizontal, 10)
            .padding(.top, 9)
            .padding(.bottom, 7)

            destinationRows

            Divider()

            VStack(spacing: 0) {
                actionRow("Add destination…", glyph: "plus", action: onAdd)
                actionRow("Destination settings…", glyph: "gearshape", action: onSettings)
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 5)
        }
        .frame(width: 244)
        .padding(.bottom, 1)
        .onAppear { selection.highlightFirst(in: filtered) }
        .onChange(of: query) { _ in
            selection.highlightFirst(in: filtered)
        }
        .onExitCommand(perform: onDismiss)
    }

    @ViewBuilder
    private var destinationRows: some View {
        if filtered.isEmpty {
            Text("No destinations match “\(query.trimmingCharacters(in: .whitespacesAndNewlines))”")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 13)
                .padding(.vertical, 10)
        } else {
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(filtered) { destination in
                            destinationRow(destination)
                                .id(destination.id)
                        }
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                }
                .frame(maxHeight: Self.listMaxHeight)
                .onChange(of: selection.highlightedID) { id in
                    guard let id else { return }
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }

    private func destinationRow(_ destination: DestinationPickerItem) -> some View {
        let isActive = destination.id == activeID
        let isHighlighted = destination.id == selection.highlightedID
        return Button {
            onChoose(destination.id)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: isActive ? "folder.fill" : "folder")
                    .font(.system(size: Self.glyphFontSize))
                    .foregroundStyle(.secondary)
                    .frame(width: 14, alignment: .center)
                Text(destination.name)
                    .font(.system(size: Self.rowFontSize, weight: isActive ? .medium : .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 6)
                if isActive {
                    Image(systemName: "checkmark")
                        .font(.system(size: Self.glyphFontSize, weight: .semibold))
                        .foregroundStyle(.primary)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: Self.rowHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(rowBackground(isActive: isActive, isHighlighted: isHighlighted))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                selection.highlight(destination.id)
            } else if selection.highlightedID == destination.id {
                selection.highlightFirst(in: filtered)
            }
        }
        .accessibilityIdentifier("destinationPickerRow")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private func actionRow(_ title: String, glyph: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: glyph)
                    .font(.system(size: Self.glyphFontSize))
                    .foregroundStyle(.secondary)
                    .frame(width: 14, alignment: .center)
                Text(title)
                    .font(.system(size: Self.rowFontSize))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .frame(height: Self.rowHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.primary.opacity(isHoveringAction ? 0.06 : 0))
            )
        }
        .buttonStyle(.plain)
        .onHover { isHoveringAction = $0 }
    }

    private func rowBackground(isActive: Bool, isHighlighted: Bool) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color.primary.opacity(isHighlighted ? 0.09 : (isActive ? 0.04 : 0)))
    }

    private func chooseHighlighted() {
        guard let destination = selection.highlighted(in: filtered) else { return }
        onChoose(destination.id)
    }
}

/// Search field for the picker. It owns first responder on open and routes the keys a
/// result list needs (Up, Down, Return, Esc) to the popover instead of the field editor.
struct DestinationSearchField: NSViewRepresentable {
    @Binding var query: String
    var focusRequest: UUID?
    var moveSelection: (Int) -> Void
    var submit: () -> Void
    var cancel: () -> Void

    func makeNSView(context: Context) -> PickerTextField {
        let field = PickerTextField()
        field.delegate = context.coordinator
        field.font = .systemFont(ofSize: 12)
        field.placeholderString = "Search destinations"
        field.isEditable = true
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setAccessibilityLabel("Search destinations")
        field.setAccessibilityIdentifier("destinationPickerSearchField")
        return field
    }

    func updateNSView(_ field: PickerTextField, context: Context) {
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

    final class PickerTextField: NSTextField {
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
        var parent: DestinationSearchField

        init(parent: DestinationSearchField) {
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
