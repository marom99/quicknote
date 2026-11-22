enum NoteSaveConfirmation {
    static func message(didSave: Bool, destinationName: String) -> String? {
        guard didSave else { return nil }
        return "Saved to \(destinationName)"
    }
}
