// Swift 5.0
//
//  ContentView.swift
//  freewrite
//
//  Created by thorfinn on 2/14/25.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum EntryType {
    case text
    case video
}

struct HumanEntry: Identifiable {
    let id: UUID
    let date: String
    let filename: String
    var previewText: String
    var entryType: EntryType
    var videoFilename: String?

    static func createNew() -> HumanEntry {
        let id = UUID()
        let now = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        let dateString = dateFormatter.string(from: now)

        // For display
        dateFormatter.dateFormat = "MMM d"
        let displayDate = dateFormatter.string(from: now)

        return HumanEntry(
            id: id,
            date: displayDate,
            filename: "[\(id)]-[\(dateString)].md",
            previewText: "",
            entryType: .text,
            videoFilename: nil
        )
    }
}

struct HeartEmoji: Identifiable {
    let id = UUID()
    var position: CGPoint
    var offset: CGFloat = 0
}

struct EditorScrollMetrics: Equatable {
    var contentHeight: CGFloat = 1
    var viewportHeight: CGFloat = 1
    var offsetY: CGFloat = 0

    var maxOffset: CGFloat {
        max(contentHeight - viewportHeight, 0)
    }

    var canScroll: Bool {
        maxOffset > 1
    }

    var offsetFraction: CGFloat {
        guard canScroll else { return 0 }
        return min(max(offsetY / maxOffset, 0), 1)
    }
}

struct EditorScrollRequest: Equatable {
    let id = UUID()
    let fraction: CGFloat
}

struct FreewriteTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var scrollRequest: EditorScrollRequest?

    let editorID: UUID?
    let selectedFont: String
    let fontSize: CGFloat
    let lineSpacing: CGFloat
    let colorScheme: ColorScheme
    let editorInset: CGFloat
    let editorNativeTextPadding: CGFloat
    let bottomContentMargin: CGFloat
    let onScrollMetricsChange: (EditorScrollMetrics) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onScrollMetricsChange: onScrollMetricsChange)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.contentInsets = NSEdgeInsets(
            top: 0,
            left: 0,
            bottom: max(bottomContentMargin - editorInset, 0),
            right: 0
        )
        scrollView.contentView.postsBoundsChangedNotifications = true

        let textView = NSTextView(frame: .zero)
        textView.drawsBackground = false
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.lineFragmentPadding = editorNativeTextPadding
        textView.textContainerInset = NSSize(
            width: max(editorInset - editorNativeTextPadding, 0),
            height: editorInset
        )
        textView.delegate = context.coordinator

        scrollView.documentView = textView
        context.coordinator.scrollView = scrollView
        context.coordinator.textView = textView
        context.coordinator.configureTextView(
            textView,
            text: text,
            editorID: editorID,
            selectedFont: selectedFont,
            fontSize: fontSize,
            lineSpacing: lineSpacing,
            colorScheme: colorScheme
        )
        context.coordinator.startObservingBoundsChanges()
        context.coordinator.publishScrollMetrics()

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        scrollView.contentInsets = NSEdgeInsets(
            top: 0,
            left: 0,
            bottom: max(bottomContentMargin - editorInset, 0),
            right: 0
        )

        if let textView = context.coordinator.textView {
            textView.textContainer?.lineFragmentPadding = editorNativeTextPadding
            textView.textContainerInset = NSSize(
                width: max(editorInset - editorNativeTextPadding, 0),
                height: editorInset
            )
            context.coordinator.configureTextView(
                textView,
                text: text,
                editorID: editorID,
                selectedFont: selectedFont,
                fontSize: fontSize,
                lineSpacing: lineSpacing,
                colorScheme: colorScheme
            )
        }

        if let request = scrollRequest, request != context.coordinator.lastAppliedScrollRequest {
            context.coordinator.scrollTo(fraction: request.fraction)
            context.coordinator.lastAppliedScrollRequest = request
        }

        context.coordinator.publishScrollMetrics()
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        coordinator.stopObservingBoundsChanges()
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding private var text: String
        private let onScrollMetricsChange: (EditorScrollMetrics) -> Void
        private var boundsObserver: NSObjectProtocol?
        private var isUpdatingText = false

        weak var scrollView: NSScrollView?
        weak var textView: NSTextView?
        var lastAppliedScrollRequest: EditorScrollRequest?
        var lastConfiguredEditorID: UUID?

        init(text: Binding<String>, onScrollMetricsChange: @escaping (EditorScrollMetrics) -> Void) {
            _text = text
            self.onScrollMetricsChange = onScrollMetricsChange
        }

        func configureTextView(
            _ textView: NSTextView,
            text: String,
            editorID: UUID?,
            selectedFont: String,
            fontSize: CGFloat,
            lineSpacing: CGFloat,
            colorScheme: ColorScheme
        ) {
            let editorChanged = lastConfiguredEditorID != editorID
            let font = NSFont(name: selectedFont, size: fontSize) ?? .systemFont(ofSize: fontSize)
            let textColor = colorScheme == .light
                ? NSColor(red: 0.20, green: 0.20, blue: 0.20, alpha: 1.0)
                : NSColor(red: 0.9, green: 0.9, blue: 0.9, alpha: 1.0)
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineSpacing = max(lineSpacing, 0)

            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: textColor,
                .paragraphStyle: paragraphStyle,
            ]

            textView.typingAttributes = attributes
            textView.defaultParagraphStyle = paragraphStyle
            textView.insertionPointColor = textColor

            let shouldReplaceText = editorChanged || textView.string != text
            guard shouldReplaceText else {
                textView.textColor = textColor
                textView.font = font
                return
            }

            let selectedRanges = clampedSelectedRanges(textView.selectedRanges, maxLength: (text as NSString).length)
            isUpdatingText = true
            textView.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: attributes))
            textView.undoManager?.removeAllActions()
            textView.selectedRanges = selectedRanges
            isUpdatingText = false
            lastConfiguredEditorID = editorID
        }

        func startObservingBoundsChanges() {
            guard boundsObserver == nil, let contentView = scrollView?.contentView else { return }
            boundsObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: contentView,
                queue: .main
            ) { [weak self] _ in
                self?.publishScrollMetrics()
            }
        }

        func stopObservingBoundsChanges() {
            if let boundsObserver {
                NotificationCenter.default.removeObserver(boundsObserver)
            }
            boundsObserver = nil
        }

        func textDidChange(_ notification: Notification) {
            guard !isUpdatingText, let textView else { return }
            text = textView.string
            publishScrollMetrics()
        }

        func scrollTo(fraction: CGFloat) {
            guard let scrollView else { return }
            let metrics = currentMetrics()
            guard metrics.canScroll else { return }
            let y = min(max(fraction, 0), 1) * metrics.maxOffset
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: y))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            publishScrollMetrics()
        }

        func publishScrollMetrics() {
            guard let textView, let textContainer = textView.textContainer else { return }
            textView.layoutManager?.ensureLayout(for: textContainer)
            let metrics = currentMetrics()
            DispatchQueue.main.async { [onScrollMetricsChange] in
                onScrollMetricsChange(metrics)
            }
        }

        private func clampedSelectedRanges(_ ranges: [NSValue], maxLength: Int) -> [NSValue] {
            ranges.map { value in
                let range = value.rangeValue
                let location = min(range.location, maxLength)
                let length = min(range.length, max(maxLength - location, 0))
                return NSValue(range: NSRange(location: location, length: length))
            }
        }

        private func currentMetrics() -> EditorScrollMetrics {
            guard let scrollView, let textView else {
                return EditorScrollMetrics()
            }

            let viewportHeight = max(scrollView.contentView.bounds.height, 1)
            let textContainer = textView.textContainer
            let usedRect = textContainer.flatMap { textView.layoutManager?.usedRect(for: $0) } ?? .zero
            let contentHeight = max(
                usedRect.height + (textView.textContainerInset.height * 2) + scrollView.contentInsets.bottom,
                viewportHeight
            )
            let offsetY = min(max(scrollView.contentView.bounds.origin.y, 0), max(contentHeight - viewportHeight, 0))

            return EditorScrollMetrics(
                contentHeight: contentHeight,
                viewportHeight: viewportHeight,
                offsetY: offsetY
            )
        }
    }
}

struct NativeEditorEdgeScroller: NSViewRepresentable {
    let metrics: EditorScrollMetrics
    let colorScheme: ColorScheme
    let onScrollFractionChange: (CGFloat) -> Void

    final class Coordinator: NSObject {
        let onScrollFractionChange: (CGFloat) -> Void

        init(onScrollFractionChange: @escaping (CGFloat) -> Void) {
            self.onScrollFractionChange = onScrollFractionChange
        }

        @objc func scrollerChanged(_ sender: NSScroller) {
            onScrollFractionChange(CGFloat(sender.doubleValue))
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onScrollFractionChange: onScrollFractionChange)
    }

    func makeNSView(context: Context) -> NSScroller {
        let scroller = NSScroller()
        scroller.scrollerStyle = .legacy
        scroller.controlSize = .regular
        scroller.target = context.coordinator
        scroller.action = #selector(Coordinator.scrollerChanged(_:))
        scroller.isEnabled = metrics.canScroll
        scroller.isHidden = !metrics.canScroll
        updateScroller(scroller)
        return scroller
    }

    func updateNSView(_ scroller: NSScroller, context: Context) {
        scroller.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
        scroller.isEnabled = metrics.canScroll
        scroller.isHidden = !metrics.canScroll
        updateScroller(scroller)
    }

    private func updateScroller(_ scroller: NSScroller) {
        let knobProportion = metrics.canScroll
            ? min(max(metrics.viewportHeight / metrics.contentHeight, 0), 1)
            : 1
        scroller.knobProportion = knobProportion
        scroller.doubleValue = Double(metrics.offsetFraction)
    }
}

struct ContentView: View {
    @StateObject private var destinationStore = DestinationStore()
    @State private var entries: [HumanEntry] = []
    @State private var text: String = ""  // Remove initial welcome text since we'll handle it in createNewEntry
    
    private let selectedFont: String = "Lato-Regular"
    private let fontSize: CGFloat = 14
    @State private var bottomNavOpacity: Double = 1.0
    @State private var isHoveringBottomNav = false
    @State private var selectedEntryIndex: Int = 0
    @State private var scrollOffset: CGFloat = 0
    @State private var editorScrollMetrics = EditorScrollMetrics()
    @State private var editorScrollRequest: EditorScrollRequest?
    @State private var selectedEntryId: UUID? = nil
    @State private var isLoadingEntry = false
    @State private var hoveredEntryId: UUID? = nil
    @State private var showingSidebar = false  // Add this state variable
    @State private var showingDestinationSettings = false
    @State private var hoveredTrashId: UUID? = nil
    @State private var placeholderText: String = ""  // Add this line
    @State private var isHoveringNewEntry = false
    @State private var isHoveringClock = false
    @State private var isHoveringHistory = false
    @State private var isHoveringHistoryText = false
    @State private var isHoveringHistoryPath = false
    @State private var isHoveringHistoryArrow = false
    @State private var isHoveringCopyTranscript = false
    @State private var isHoveringDestinationChip = false
    @State private var settingsDisplayName: String = ""
    @State private var settingsFilenameFormat: String = RollingPeriod.daily.defaultFilenameFormat
    @State private var settingsNewNoteFilenameFormat: NewNoteFilenameFormat = .date
    @State private var inProgressCaptureFilename: String? = nil
    @State private var captureStartedAt: Date? = nil
    @State private var colorScheme: ColorScheme = .light // Add state for color scheme
    @State private var isHoveringThemeToggle = false // Add state for theme toggle hover
    @State private var didCopyTranscript: Bool = false
    @State private var selectedVideoHasTranscript = false
    @State private var currentVideoURL: URL? = nil // Add state for current video being viewed
    let entryHeight: CGFloat = 40
    private let editorInset: CGFloat = 18
    // NSTextView line-fragment padding (horizontal only; top inset is 0).
    private let editorNativeTextPadding: CGFloat = 5
    // Bottom nav: 12pt above/below ~16pt controls ≈ 40pt tall.
    private let bottomNavVerticalPadding: CGFloat = 12
    private let bottomNavHeight: CGFloat = 40
    // Gap between the last editor line and the nav's top border.
    private let bottomNavContentGap: CGFloat = 8
    
    let placeholderOptions = [
        "Begin writing",
        "Pick a thought and go",
        "Start typing",
        "What's on your mind",
        "Just start",
        "Type your first thought",
        "Start with one sentence",
        "Just say it"
    ]
    
    // Add file manager and save timer
    private let fileManager = FileManager.default
    private let saveTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    private let thumbnailMemoryCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 512
        return cache
    }()
    
    // Initialize with saved theme preference if available
    init() {
        // Load saved color scheme preference
        let savedScheme = UserDefaults.standard.string(forKey: "colorScheme") ?? "light"
        _colorScheme = State(initialValue: savedScheme == "dark" ? .dark : .light)
    }
    
    // Active journal root; nil when the destination cannot be accessed (soft-fail).
    private func getDocumentsDirectory() -> URL? {
        destinationStore.resolvedDocumentsURL()
    }

    private func getVideosDirectory() -> URL? {
        destinationStore.resolvedVideosURL()
    }

    private var activeDestinationHistoryLabel: String {
        if let path = destinationStore.activeDocumentsPath {
            return path
        }
        let name = destinationStore.activeDestination?.displayName ?? "Journal"
        return "\(name) (unavailable)"
    }

    private func getVideoEntryDirectory(for videoFilename: String) -> URL? {
        guard let videosDirectory = getVideosDirectory() else { return nil }
        let baseName = (videoFilename as NSString).deletingPathExtension
        return videosDirectory.appendingPathComponent(baseName, isDirectory: true)
    }

    private func getManagedVideoURL(for filename: String) -> URL? {
        guard let directory = getVideoEntryDirectory(for: filename) else { return nil }
        return directory.appendingPathComponent(filename)
    }

    private func getVideoThumbnailURL(for filename: String) -> URL? {
        guard let directory = getVideoEntryDirectory(for: filename) else { return nil }
        return directory.appendingPathComponent("thumbnail.jpg")
    }

    private func getVideoTranscriptURL(for filename: String) -> URL? {
        guard let directory = getVideoEntryDirectory(for: filename) else { return nil }
        return directory.appendingPathComponent("transcript.md")
    }

    @discardableResult
    private func ensureVideoEntryDirectoryExists(for videoFilename: String) throws -> URL {
        guard let directory = getVideoEntryDirectory(for: videoFilename) else {
            throw CocoaError(.fileNoSuchFile)
        }
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    private func getVideoURL(for filename: String) -> URL? {
        // Current production layout: Videos/[entry-base]/[entry-filename].mov
        if let managedVideoURL = getManagedVideoURL(for: filename),
           fileManager.fileExists(atPath: managedVideoURL.path) {
            return managedVideoURL
        }

        // Backward compatibility: older builds stored videos flat under Videos/
        if let videosDirectory = getVideosDirectory() {
            let flatVideosURL = videosDirectory.appendingPathComponent(filename)
            if fileManager.fileExists(atPath: flatVideosURL.path) {
                return flatVideosURL
            }
        }

        // Backward compatibility: oldest builds stored videos in root Freewrite folder
        if let documentsDirectory = getDocumentsDirectory() {
            let rootVideosURL = documentsDirectory.appendingPathComponent(filename)
            if fileManager.fileExists(atPath: rootVideosURL.path) {
                return rootVideosURL
            }
        }

        // Default to managed path for newly created entries.
        return getManagedVideoURL(for: filename)
    }

    private func hasVideoAsset(for filename: String) -> Bool {
        if let managedVideoURL = getManagedVideoURL(for: filename),
           fileManager.fileExists(atPath: managedVideoURL.path) {
            return true
        }

        if let videosDirectory = getVideosDirectory() {
            let flatVideosURL = videosDirectory.appendingPathComponent(filename)
            if fileManager.fileExists(atPath: flatVideosURL.path) {
                return true
            }
        }

        if let documentsDirectory = getDocumentsDirectory() {
            let rootVideosURL = documentsDirectory.appendingPathComponent(filename)
            if fileManager.fileExists(atPath: rootVideosURL.path) {
                return true
            }
        }

        return false
    }

    private func resolvedVideoFilename(for entry: HumanEntry) -> String? {
        guard entry.entryType == .video else {
            return nil
        }
        if let videoFilename = entry.videoFilename, !videoFilename.isEmpty {
            return videoFilename
        }
        return entry.filename.replacingOccurrences(of: ".md", with: ".mov")
    }

    private func persistThumbnail(_ image: NSImage, for videoFilename: String) {
        do {
            let directory = try ensureVideoEntryDirectoryExists(for: videoFilename)
            let thumbnailURL = directory.appendingPathComponent("thumbnail.jpg")
            guard let tiff = image.tiffRepresentation,
                  let bitmapRep = NSBitmapImageRep(data: tiff),
                  let imageData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.82]) else {
                print("Could not convert thumbnail image to JPEG data")
                return
            }
            try imageData.write(to: thumbnailURL, options: .atomic)
        } catch {
            print("Error saving thumbnail: \(error)")
        }
    }

    private func loadThumbnailImage(for videoFilename: String) -> NSImage? {
        let cacheKey = videoFilename as NSString
        if let cachedImage = thumbnailMemoryCache.object(forKey: cacheKey) {
            return cachedImage
        }

        guard let thumbnailURL = getVideoThumbnailURL(for: videoFilename) else {
            return nil
        }
        if fileManager.fileExists(atPath: thumbnailURL.path),
           let image = NSImage(contentsOf: thumbnailURL) {
            thumbnailMemoryCache.setObject(image, forKey: cacheKey)
            return image
        }

        // Backward compatibility: generate once for old video entries, then persist.
        guard let videoURL = getVideoURL(for: videoFilename),
              fileManager.fileExists(atPath: videoURL.path),
              let generated = generateVideoThumbnail(from: videoURL) else {
            return nil
        }
        persistThumbnail(generated, for: videoFilename)
        thumbnailMemoryCache.setObject(generated, forKey: cacheKey)
        return generated
    }

    private func deleteVideoAssets(for videoFilename: String) {
        thumbnailMemoryCache.removeObject(forKey: videoFilename as NSString)

        var candidateURLs: [URL] = []
        var managedDirectory: URL?
        if let directory = getVideoEntryDirectory(for: videoFilename) {
            managedDirectory = directory
            candidateURLs.append(directory.appendingPathComponent(videoFilename))
            candidateURLs.append(directory.appendingPathComponent("thumbnail.jpg"))
            candidateURLs.append(directory.appendingPathComponent("transcript.md"))
        }
        if let videosDirectory = getVideosDirectory() {
            candidateURLs.append(videosDirectory.appendingPathComponent(videoFilename))
        }
        if let documentsDirectory = getDocumentsDirectory() {
            candidateURLs.append(documentsDirectory.appendingPathComponent(videoFilename))
        }

        for url in candidateURLs where fileManager.fileExists(atPath: url.path) {
            do {
                try fileManager.removeItem(at: url)
            } catch {
                print("Error deleting video asset \(url.lastPathComponent): \(error)")
            }
        }

        if let managedDirectory,
           fileManager.fileExists(atPath: managedDirectory.path) {
            do {
                try fileManager.removeItem(at: managedDirectory)
            } catch {
                print("Error deleting video entry directory: \(error)")
            }
        }
    }

    private func loadTranscriptText(for videoFilename: String) -> String? {
        guard let transcriptURL = getVideoTranscriptURL(for: videoFilename),
              fileManager.fileExists(atPath: transcriptURL.path),
              let content = try? String(contentsOf: transcriptURL, encoding: .utf8) else {
            return nil
        }
        let cleaned = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    private func previewTextFromTranscript(_ transcript: String?) -> String {
        guard let transcript else {
            return "Video Entry"
        }

        let normalized = transcript
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else {
            return "Video Entry"
        }

        var preview = String(normalized.prefix(10))

        while let last = preview.last, (!last.isLetter && !last.isNumber) {
            preview.removeLast()
        }

        if preview.isEmpty {
            return "Video Entry"
        }

        return preview + "..."
    }

    private func videoPreviewText(for videoFilename: String) -> String {
        previewTextFromTranscript(loadTranscriptText(for: videoFilename))
    }

    private func copyTranscriptForSelectedVideoEntry() {
        guard let selectedEntryId,
              let selectedEntry = entries.first(where: { $0.id == selectedEntryId }),
              let videoFilename = resolvedVideoFilename(for: selectedEntry),
              let transcript = loadTranscriptText(for: videoFilename) else {
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(transcript, forType: .string)
        didCopyTranscript = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            didCopyTranscript = false
        }
    }
    
    private func parseCanonicalEntryFilename(_ filename: String) -> (uuid: UUID, timestamp: Date)? {
        guard filename.hasPrefix("["),
              filename.hasSuffix("].md"),
              let divider = filename.range(of: "]-[") else {
            return nil
        }

        let uuidStart = filename.index(after: filename.startIndex)
        let uuidString = String(filename[uuidStart..<divider.lowerBound])
        guard let uuid = UUID(uuidString: uuidString) else {
            return nil
        }

        let timestampStart = divider.upperBound
        let timestampEnd = filename.index(filename.endIndex, offsetBy: -4) // before ".md"
        let timestampString = String(filename[timestampStart..<timestampEnd])
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        guard let timestamp = formatter.date(from: timestampString) else {
            return nil
        }

        return (uuid: uuid, timestamp: timestamp)
    }
    
    private func isEntryNewer(_ lhs: HumanEntry, than rhs: HumanEntry) -> Bool {
        let lhsTimestamp = parseCanonicalEntryFilename(lhs.filename)?.timestamp ?? .distantPast
        let rhsTimestamp = parseCanonicalEntryFilename(rhs.filename)?.timestamp ?? .distantPast
        if lhsTimestamp == rhsTimestamp {
            return lhs.filename > rhs.filename
        }
        return lhsTimestamp > rhsTimestamp
    }
    
    private func isEntryFromToday(_ entry: HumanEntry, calendar: Calendar = .current, today: Date = Date()) -> Bool {
        guard let timestamp = parseCanonicalEntryFilename(entry.filename)?.timestamp else {
            return false
        }
        return calendar.isDate(timestamp, inSameDayAs: today)
    }

    private var activeSaveMode: DestinationSaveMode {
        destinationStore.activeDestination?.saveMode ?? .newNote
    }

    private var listsAllRootMarkdown: Bool {
        activeSaveMode == .rolling || activeSaveMode == .existing || activeSaveMode == .newNote
    }

    private var isCapturePerSessionMode: Bool {
        activeSaveMode == .newNote
    }

    private func normalizedCaptureContent(_ content: String) -> String {
        content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func beginFreshCaptureSession(clearText: Bool) {
        inProgressCaptureFilename = nil
        captureStartedAt = nil
        selectedEntryId = nil
        currentVideoURL = nil
        selectedVideoHasTranscript = false
        didCopyTranscript = false
        if clearText {
            isLoadingEntry = true
            text = ""
            isLoadingEntry = false
        }
        placeholderText = placeholderOptions.randomElement() ?? "Begin writing"
    }

    private func deleteCaptureFileIfExists(_ filename: String) {
        guard let documentsDirectory = getDocumentsDirectory() else { return }
        let fileURL = documentsDirectory.appendingPathComponent(filename)
        if fileManager.fileExists(atPath: fileURL.path) {
            try? fileManager.removeItem(at: fileURL)
        }
    }

    private func removeEntry(withFilename filename: String) {
        if let index = entries.firstIndex(where: { $0.filename == filename }) {
            entries.remove(at: index)
        }
        if selectedEntryId != nil,
           entries.first(where: { $0.id == selectedEntryId }) == nil {
            selectedEntryId = nil
        }
    }

    private func moveCaptureFile(from sourceFilename: String, to destinationFilename: String, in documentsDirectory: URL) {
        let sourceURL = documentsDirectory.appendingPathComponent(sourceFilename)
        let destinationURL = documentsDirectory.appendingPathComponent(destinationFilename)
        guard sourceFilename != destinationFilename else { return }
        guard fileManager.fileExists(atPath: sourceURL.path) else { return }

        if fileManager.fileExists(atPath: destinationURL.path) {
            try? fileManager.removeItem(at: destinationURL)
        }

        do {
            try fileManager.moveItem(at: sourceURL, to: destinationURL)
        } catch {
            print("Error renaming capture file: \(error)")
        }
    }

    private func updateEntryFilename(from sourceFilename: String, to destinationFilename: String) {
        guard let index = entries.firstIndex(where: { $0.filename == sourceFilename }) else { return }
        let existing = entries[index]
        let newPath = getDocumentsDirectory()?
            .appendingPathComponent(destinationFilename)
            .standardizedFileURL.path ?? destinationFilename
        let newId = DestinationWriteTarget.stableUUID(fromPath: newPath)
        entries[index] = HumanEntry(
            id: newId,
            date: existing.date,
            filename: destinationFilename,
            previewText: existing.previewText,
            entryType: existing.entryType,
            videoFilename: existing.videoFilename
        )
        if selectedEntryId == existing.id {
            selectedEntryId = newId
        }
        if inProgressCaptureFilename == sourceFilename {
            inProgressCaptureFilename = destinationFilename
        }
    }

    private func startCaptureSession() {
        guard isCapturePerSessionMode,
              inProgressCaptureFilename == nil,
              let documentsDirectory = getDocumentsDirectory() else {
            return
        }

        let format = destinationStore.activeDestination?.newNoteFilenameFormat ?? .date
        let now = Date()
        captureStartedAt = now
        let captureId = UUID()

        let filename: String
        switch format {
        case .date:
            filename = DestinationWriteTarget.uniqueMarkdownFilename(
                preferredBasename: DestinationWriteTarget.dateCaptureBasename(now: now),
                documentsURL: documentsDirectory
            )
        case .title:
            filename = DestinationWriteTarget.captureDraftFilename(captureId: captureId)
        }

        inProgressCaptureFilename = filename
        let pathKey = documentsDirectory.appendingPathComponent(filename).standardizedFileURL.path
        let entry = HumanEntry(
            id: DestinationWriteTarget.stableUUID(fromPath: pathKey),
            date: DestinationWriteTarget.displayDateString(from: now),
            filename: filename,
            previewText: "",
            entryType: .text,
            videoFilename: nil
        )
        entries.insert(entry, at: 0)
        selectedEntryId = entry.id
        saveEntry(entry: entry)
    }

    private func handleCaptureTextChange() {
        guard isCapturePerSessionMode, !isLoadingEntry else { return }

        let trimmed = normalizedCaptureContent(text)

        if trimmed.isEmpty {
            if let filename = inProgressCaptureFilename {
                deleteCaptureFileIfExists(filename)
                removeEntry(withFilename: filename)
                inProgressCaptureFilename = nil
                captureStartedAt = nil
            }
            return
        }

        if inProgressCaptureFilename == nil {
            startCaptureSession()
        }

        guard let filename = inProgressCaptureFilename,
              let entry = entries.first(where: { $0.filename == filename }) else {
            return
        }
        saveEntry(entry: entry)
    }

    private func finalizeCaptureSession() {
        guard isCapturePerSessionMode else {
            if let currentId = selectedEntryId,
               let currentEntry = entries.first(where: { $0.id == currentId }),
               currentEntry.entryType == .text {
                saveEntry(entry: currentEntry, updatePreview: false)
            }
            return
        }

        guard let draftFilename = inProgressCaptureFilename else { return }
        guard let documentsDirectory = getDocumentsDirectory() else { return }

        let trimmed = normalizedCaptureContent(text)
        if trimmed.isEmpty {
            deleteCaptureFileIfExists(draftFilename)
            removeEntry(withFilename: draftFilename)
            beginFreshCaptureSession(clearText: true)
            return
        }

        if let entry = entries.first(where: { $0.filename == draftFilename }) {
            saveEntry(entry: entry, updatePreview: true)
        }

        let format = destinationStore.activeDestination?.newNoteFilenameFormat ?? .date
        if format == .title {
            let fallbackBasename: String
            if let started = captureStartedAt {
                fallbackBasename = DestinationWriteTarget.dateCaptureBasename(now: started)
            } else {
                fallbackBasename = DestinationWriteTarget.dateCaptureBasename()
            }

            let preferredBasename = DestinationWriteTarget.sanitizedTitleBasename(from: text) ?? fallbackBasename
            let finalFilename = DestinationWriteTarget.uniqueMarkdownFilename(
                preferredBasename: preferredBasename,
                documentsURL: documentsDirectory,
                excluding: draftFilename
            )

            if finalFilename != draftFilename {
                moveCaptureFile(from: draftFilename, to: finalFilename, in: documentsDirectory)
                updateEntryFilename(from: draftFilename, to: finalFilename)
            }
        }

        inProgressCaptureFilename = nil
        captureStartedAt = nil
        selectedEntryId = nil
        isLoadingEntry = true
        text = ""
        isLoadingEntry = false
        placeholderText = placeholderOptions.randomElement() ?? "Begin writing"
    }

    private func entryDisplayDate(from date: Date) -> String {
        DestinationWriteTarget.displayDateString(from: date)
    }

    private func modificationDate(for fileURL: URL) -> Date {
        if let attrs = try? fileManager.attributesOfItem(atPath: fileURL.path),
           let mod = attrs[.modificationDate] as? Date {
            return mod
        }
        return Date()
    }

    private func humanEntry(
        from fileURL: URL,
        allowNonCanonical: Bool
    ) -> (entry: HumanEntry, date: Date, content: String)? {
        let filename = fileURL.lastPathComponent
        let parsed = parseCanonicalEntryFilename(filename)

        if !allowNonCanonical {
            guard let parsed else {
                print("Skipping non-canonical entry filename: \(filename)")
                return nil
            }
        }

        let uuid: UUID
        let fileDate: Date
        if let parsed {
            uuid = parsed.uuid
            fileDate = parsed.timestamp
        } else {
            uuid = DestinationWriteTarget.stableUUID(fromPath: fileURL.standardizedFileURL.path)
            fileDate = modificationDate(for: fileURL)
        }

        let videoFilename = filename.replacingOccurrences(of: ".md", with: ".mov")
        let hasVideo = hasVideoAsset(for: videoFilename)

        do {
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            let preview = content
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let truncated = preview.isEmpty ? "" : (preview.count > 30 ? String(preview.prefix(30)) + "..." : preview)

            return (
                entry: HumanEntry(
                    id: uuid,
                    date: entryDisplayDate(from: fileDate),
                    filename: filename,
                    previewText: hasVideo ? videoPreviewText(for: videoFilename) : truncated,
                    entryType: hasVideo ? .video : .text,
                    videoFilename: hasVideo ? videoFilename : nil
                ),
                date: fileDate,
                content: content
            )
        } catch {
            print("Error reading file: \(error)")
            return nil
        }
    }

    /// Builds a HumanEntry for a resolved write target, creating a shell if not yet listed.
    private func entryForResolvedTarget(_ target: DestinationWriteTarget.ResolvedTarget) -> HumanEntry {
        if let existing = entries.first(where: { $0.filename == target.filename }) {
            return existing
        }
        return HumanEntry(
            id: target.entryId,
            date: target.displayDate,
            filename: target.filename,
            previewText: "",
            entryType: .text,
            videoFilename: nil
        )
    }

    private func bindToResolvedWriteTarget(appendSeparator: Bool = false) -> Bool {
        guard let destination = destinationStore.activeDestination,
              destination.saveMode == .rolling || destination.saveMode == .existing,
              let documentsDirectory = destinationStore.resolvedDocumentsURL() else {
            return false
        }

        // Soft-fail existing when no note is configured: empty editor, no crash.
        if destination.saveMode == .existing,
           destination.existingNoteFilename == nil ||
            DestinationWriteTarget.validatedBasename(destination.existingNoteFilename ?? "") == nil {
            selectedEntryId = nil
            currentVideoURL = nil
            selectedVideoHasTranscript = false
            didCopyTranscript = false
            text = ""
            placeholderText = "Choose a note in Destination settings"
            return true
        }

        let createIfMissing = destination.saveMode == .rolling

        guard let target = DestinationWriteTarget.resolve(
            for: destination,
            documentsURL: documentsDirectory,
            createIfMissing: createIfMissing
        ) else {
            selectedEntryId = nil
            currentVideoURL = nil
            selectedVideoHasTranscript = false
            didCopyTranscript = false
            text = ""
            return true
        }

        // Missing path: stay unbound so typing cannot silently recreate the file
        // (Existing soft-fail, or Rolling create failure). Settings keep the path.
        guard target.fileExists else {
            selectedEntryId = nil
            currentVideoURL = nil
            selectedVideoHasTranscript = false
            didCopyTranscript = false
            text = ""
            isLoadingEntry = false
            if destination.saveMode == .existing {
                placeholderText = "Configured note is missing"
            } else {
                placeholderText = placeholderOptions.randomElement() ?? "Begin writing"
            }
            return true
        }

        let entry = entryForResolvedTarget(target)
        if !entries.contains(where: { $0.id == entry.id }) {
            entries.insert(entry, at: 0)
        }

        isLoadingEntry = true
        loadEntry(entry: entry)

        if appendSeparator {
            text += DestinationWriteTarget.sessionSeparator()
            selectedEntryId = entry.id
            isLoadingEntry = false
            saveEntry(entry: entry)
        } else {
            selectedEntryId = entry.id
            isLoadingEntry = false
            if entry.entryType == .text {
                updatePreviewText(for: entry)
            }
        }

        placeholderText = placeholderOptions.randomElement() ?? "Begin writing"
        return true
    }

    private func openHistorySidebar() {
        withAnimation(.easeInOut(duration: 0.2)) {
            if showingSidebar {
                showingSidebar = false
            } else {
                showingDestinationSettings = false
                showingSidebar = true
            }
        }
    }

    private func openDestinationSettings() {
        syncSettingsDraftFromActiveDestination()
        withAnimation(.easeInOut(duration: 0.2)) {
            showingSidebar = false
            showingDestinationSettings = true
        }
    }

    private func syncSettingsDraftFromActiveDestination() {
        guard let destination = destinationStore.activeDestination else { return }
        settingsDisplayName = destination.displayName
        settingsFilenameFormat = destination.filenameFormat
        settingsNewNoteFilenameFormat = destination.newNoteFilenameFormat
    }

    private func applyActiveDestinationSettingsChange(
        displayName: String? = nil,
        saveMode: DestinationSaveMode? = nil,
        rollingPeriod: RollingPeriod? = nil,
        filenameFormat: String? = nil,
        newNoteFilenameFormat: NewNoteFilenameFormat? = nil,
        existingNoteFilename: String?? = nil
    ) {
        guard let destination = destinationStore.activeDestination else { return }

        if isCapturePerSessionMode, inProgressCaptureFilename != nil {
            finalizeCaptureSession()
        } else if let currentId = selectedEntryId,
           let currentEntry = entries.first(where: { $0.id == currentId }),
           currentEntry.entryType == .text {
            saveEntry(entry: currentEntry, updatePreview: false)
        }

        destinationStore.updateDestination(
            id: destination.id,
            displayName: displayName,
            saveMode: saveMode,
            rollingPeriod: rollingPeriod,
            filenameFormat: filenameFormat,
            newNoteFilenameFormat: newNoteFilenameFormat,
            existingNoteFilename: existingNoteFilename
        )

        if let updated = destinationStore.activeDestination {
            settingsDisplayName = updated.displayName
            settingsFilenameFormat = updated.filenameFormat
            settingsNewNoteFilenameFormat = updated.newNoteFilenameFormat
        }

        // Immediate apply: same re-resolve path used on destination switch.
        DispatchQueue.main.async {
            self.reloadJournalForActiveDestination()
        }
    }
    
    // Add function to save text
    private func saveText() {
        guard let documentsDirectory = getDocumentsDirectory() else { return }
        let fileURL = documentsDirectory.appendingPathComponent("entry.md")
        
        print("Attempting to save file to: \(fileURL.path)")
        
        do {
            try text.write(to: fileURL, atomically: true, encoding: .utf8)
            print("Successfully saved file")
        } catch {
            print("Error saving file: \(error)")
            print("Error details: \(error.localizedDescription)")
        }
    }
    
    // Add function to load text
    private func loadText() {
        guard let documentsDirectory = getDocumentsDirectory() else { return }
        let fileURL = documentsDirectory.appendingPathComponent("entry.md")
        
        print("Attempting to load file from: \(fileURL.path)")
        
        do {
            if fileManager.fileExists(atPath: fileURL.path) {
                text = try String(contentsOf: fileURL, encoding: .utf8)
                print("Successfully loaded file")
            } else {
                print("File does not exist yet")
            }
        } catch {
            print("Error loading file: \(error)")
            print("Error details: \(error.localizedDescription)")
        }
    }
    
    private func selectEntry(_ entry: HumanEntry) {
        guard selectedEntryId != entry.id else { return }

        if isCapturePerSessionMode, inProgressCaptureFilename != nil {
            finalizeCaptureSession()
        } else if let currentId = selectedEntryId,
           let currentEntry = entries.first(where: { $0.id == currentId }),
           currentEntry.entryType == .text {
            saveEntry(entry: currentEntry, updatePreview: false)
        }

        guard let targetEntry = entries.first(where: { $0.id == entry.id }) else {
            return
        }

        isLoadingEntry = true
        loadEntry(entry: targetEntry)
        selectedEntryId = targetEntry.id
        isLoadingEntry = false

        if targetEntry.entryType == .text {
            DispatchQueue.main.async {
                self.updatePreviewText(for: targetEntry)
            }
        }
    }

    private func reloadJournalForActiveDestination() {
        if isCapturePerSessionMode, inProgressCaptureFilename != nil {
            finalizeCaptureSession()
        }
        selectedEntryId = nil
        currentVideoURL = nil
        selectedVideoHasTranscript = false
        didCopyTranscript = false
        thumbnailMemoryCache.removeAllObjects()
        inProgressCaptureFilename = nil
        captureStartedAt = nil
        text = ""
        loadExistingEntries()
    }

    private func switchToDestination(id: UUID) {
        guard id != destinationStore.activeDestinationId else { return }

        if isCapturePerSessionMode, inProgressCaptureFilename != nil {
            finalizeCaptureSession()
        } else if let currentId = selectedEntryId,
           let currentEntry = entries.first(where: { $0.id == currentId }),
           currentEntry.entryType == .text {
            saveEntry(entry: currentEntry)
        }

        destinationStore.activateDestination(id: id)
        // Defer journal reload so ForEach(entries) isn't mid-update when History is open.
        DispatchQueue.main.async {
            self.reloadJournalForActiveDestination()
        }
    }

    private func revealActiveDestinationInFinder() {
        guard let url = destinationStore.resolvedDocumentsURL() else { return }
        // Use the security-scoped URL directly. Path-based selectFile can crash/fail
        // for user-picked destinations outside the app container.
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func addDestinationFromFolderPicker() {
        // AppKit restores NSOSPLastRootDirectory when the panel opens. That
        // bookmark often isn't a valid security-scoped bookmark and surfaces as
        // NSCocoaErrorDomain 256 — "The file couldn’t be opened."
        UserDefaults.standard.removeObject(forKey: "NSOSPLastRootDirectory")

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose Folder"
        panel.message = "Choose a folder for this journal destination."
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser

        let response = panel.runModal()
        guard response == .OK, let url = panel.url else { return }

        do {
            _ = try destinationStore.addDestination(from: url, activate: true)
            reloadJournalForActiveDestination()
        } catch {
            print("Error adding destination: \(error)")
        }
    }

    private var activeDestinationDisplayName: String {
        destinationStore.activeDestination?.displayName ?? "Freewrite"
    }

    // Add function to load existing entries
    private func loadExistingEntries() {
        guard let documentsDirectory = destinationStore.resolvedDocumentsURL() else {
            print("Active destination is unavailable; showing empty History")
            entries = []
            selectedEntryId = nil
            currentVideoURL = nil
            selectedVideoHasTranscript = false
            didCopyTranscript = false
            text = ""
            return
        }
        print("Looking for entries in: \(documentsDirectory.path)")
        if let videosDirectory = getVideosDirectory() {
            print("Looking for videos in: \(videosDirectory.path)")
        }
        
        do {
            let fileURLs = try fileManager.contentsOfDirectory(at: documentsDirectory, includingPropertiesForKeys: nil)
            let mdFiles = fileURLs.filter {
                $0.pathExtension == "md"
                    && !DestinationWriteTarget.isCaptureDraftFilename($0.lastPathComponent)
            }

            print("Found \(mdFiles.count) .md files")

            let allowNonCanonical = listsAllRootMarkdown

            // Process each file (canonical-only for New note; all root .md for Rolling/Existing)
            let entriesWithDates = mdFiles.compactMap { fileURL -> (entry: HumanEntry, date: Date, content: String)? in
                print("Processing: \(fileURL.lastPathComponent)")
                return humanEntry(from: fileURL, allowNonCanonical: allowNonCanonical)
            }
            
            // Sort and extract entries - store in temporary variable
            let loadedEntries = entriesWithDates
                .sorted {
                    if $0.date == $1.date {
                        return $0.entry.filename > $1.entry.filename
                    }
                    return $0.date > $1.date
                }
                .map { $0.entry }

            print("Successfully loaded and sorted \(loadedEntries.count) entries")

            // Now assign to the state variable
            entries = loadedEntries

            // Rolling / Existing: bind to resolved write target (skip new-note launch rules).
            if activeSaveMode == .rolling || activeSaveMode == .existing {
                _ = bindToResolvedWriteTarget(appendSeparator: false)
                return
            }

            // New note: load history, start with a fresh empty capture session.
            beginFreshCaptureSession(clearText: true)
            
        } catch {
            print("Error loading directory contents: \(error)")
            print("Creating default entry after error")
            if activeSaveMode == .rolling || activeSaveMode == .existing {
                _ = bindToResolvedWriteTarget(appendSeparator: false)
            } else {
                beginFreshCaptureSession(clearText: true)
            }
        }
    }
    
    var lineHeight: CGFloat {
        let font = NSFont(name: selectedFont, size: fontSize) ?? .systemFont(ofSize: fontSize)
        let defaultLineHeight = getLineHeight(font: font)
        return (fontSize * 1.5) - defaultLineHeight
    }

    private func captureTitleBarDate(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "MMM d, HH:mm"
        return formatter.string(from: date)
    }

    private func titleBarDateFromCaptureFilename(_ filename: String) -> String? {
        var basename = filename
        if basename.lowercased().hasSuffix(".md") {
            basename = String(basename.dropLast(3))
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"

        if let date = formatter.date(from: basename) {
            return captureTitleBarDate(from: date)
        }

        if let suffixRange = basename.range(of: #"-\d+$"#, options: .regularExpression) {
            let withoutSuffix = String(basename[..<suffixRange.lowerBound])
            if let date = formatter.date(from: withoutSuffix) {
                return captureTitleBarDate(from: date)
            }
        }

        return nil
    }

    private var currentEntryTitle: String {
        if isCapturePerSessionMode,
           destinationStore.activeDestination?.newNoteFilenameFormat == .date {
            if let started = captureStartedAt, inProgressCaptureFilename != nil {
                return captureTitleBarDate(from: started)
            }

            if let selectedEntryId,
               let entry = entries.first(where: { $0.id == selectedEntryId }) {
                if entry.entryType == .video {
                    return entry.previewText.isEmpty ? "Video Entry" : entry.previewText
                }
                if let fromFilename = titleBarDateFromCaptureFilename(entry.filename) {
                    return fromFilename
                }
                return entry.date
            }

            return "Untitled"
        }

        guard let selectedEntryId,
              let entry = entries.first(where: { $0.id == selectedEntryId }) else {
            return "Untitled"
        }

        if entry.entryType == .video {
            return entry.previewText.isEmpty ? "Video Entry" : entry.previewText
        }

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedText.isEmpty {
            return "Untitled"
        }

        let firstLine = trimmedText.components(separatedBy: .newlines).first ?? trimmedText
        let words = firstLine
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
        if words.isEmpty {
            return "Untitled"
        }
        let title = words.prefix(4).joined(separator: " ")
        return words.count > 4 ? "\(title)..." : title
    }

    
    var body: some View {
        let textColor = colorScheme == .light ? Color.gray : Color.gray.opacity(0.8)
        let textHoverColor = colorScheme == .light ? Color.black : Color.white
        let isViewingVideoEntry = currentVideoURL != nil
        
        HStack(spacing: 0) {
            // Main content
            ZStack {
                Color(colorScheme == .light ? .white : .black)
                    .ignoresSafeArea()

                // Show video player if a video entry is selected
                if let videoURL = currentVideoURL {
                    VideoPlayerView(
                        videoURL: videoURL,
                        isPlaybackSuspended: false
                    )
                        .id(videoURL.path)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .ignoresSafeArea(edges: .top)
                        // Avoid animating AVKit/AppKit representables when History opens.
                        .transaction { $0.animation = nil }
                } else {
                    // Show text editor for text entries
                    FreewriteTextEditor(
                        text: $text,
                        scrollRequest: $editorScrollRequest,
                        editorID: selectedEntryId,
                        selectedFont: selectedFont,
                        fontSize: fontSize,
                        lineSpacing: lineHeight,
                        colorScheme: colorScheme,
                        editorInset: editorInset,
                        editorNativeTextPadding: editorNativeTextPadding,
                        bottomContentMargin: bottomNavHeight + bottomNavContentGap,
                        onScrollMetricsChange: { metrics in
                            if editorScrollMetrics != metrics {
                                editorScrollMetrics = metrics
                            }
                        }
                    )
                    .background(Color(colorScheme == .light ? .white : .black))
                        // Placeholder shares the editor's coordinate space so it sits on the first line.
                        .overlay(alignment: .topLeading) {
                            if text.isEmpty {
                                Text(placeholderText)
                                    .font(.custom(selectedFont, size: fontSize))
                                    .foregroundColor(colorScheme == .light ? .gray.opacity(0.5) : .gray.opacity(0.6))
                                    // Align with NSTextView's native horizontal line-fragment padding.
                                    .padding(.top, editorInset)
                                    .padding(.leading, editorInset)
                                    .allowsHitTesting(false)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .id("\(selectedFont)-\(fontSize)-\(colorScheme)")
                        .colorScheme(colorScheme)
                        .transaction { $0.animation = nil }
                        .onAppear {
                            placeholderText = placeholderOptions.randomElement() ?? "Begin writing"
                        }

                    NativeEditorEdgeScroller(
                        metrics: editorScrollMetrics,
                        colorScheme: colorScheme,
                        onScrollFractionChange: { fraction in
                            editorScrollRequest = EditorScrollRequest(fraction: fraction)
                        }
                    )
                    .padding(.bottom, bottomNavHeight)
                    .frame(width: 15)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    .transaction { $0.animation = nil }
                }

                // Bottom nav
                VStack {
                    Spacer()
                    HStack {
                        HStack(spacing: 8) {
                            destinationChip(textColor: textColor, textHoverColor: textHoverColor)

                            if isViewingVideoEntry {
                                if selectedVideoHasTranscript {
                                    Button(action: {
                                        copyTranscriptForSelectedVideoEntry()
                                    }) {
                                        Text(didCopyTranscript ? "Copied Transcript" : "Copy Transcript")
                                            .font(.system(size: 13))
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundColor(isHoveringCopyTranscript ? textHoverColor : textColor)
                                    .onHover { hovering in
                                        isHoveringCopyTranscript = hovering
                                        isHoveringBottomNav = hovering
                                        if hovering {
                                            NSCursor.pointingHand.push()
                                        } else {
                                            NSCursor.pop()
                                        }
                                    }
                                }
                            }
                        }
                        .onHover { hovering in
                            isHoveringBottomNav = hovering
                        }

                        Spacer()
                        
                        // Utility buttons (moved to right)
                        HStack(spacing: 8) {
                            Button(action: {
                                createNewEntry()
                            }) {
                                Text("New Entry")
                                    .font(.system(size: 13))
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(isHoveringNewEntry ? textHoverColor : textColor)
                            .onHover { hovering in
                                isHoveringNewEntry = hovering
                                isHoveringBottomNav = hovering
                                if hovering {
                                    NSCursor.pointingHand.push()
                                } else {
                                    NSCursor.pop()
                                }
                            }
                            
                            Text("•")
                                .foregroundColor(.gray)
                            
                            // Theme toggle button
                            Button(action: {
                                colorScheme = colorScheme == .light ? .dark : .light
                                // Save preference
                                UserDefaults.standard.set(colorScheme == .light ? "light" : "dark", forKey: "colorScheme")
                            }) {
                                Image(systemName: colorScheme == .light ? "moon.fill" : "sun.max.fill")
                                    .foregroundColor(isHoveringThemeToggle ? textHoverColor : textColor)
                            }
                            .buttonStyle(.plain)
                            .onHover { hovering in
                                isHoveringThemeToggle = hovering
                                isHoveringBottomNav = hovering
                                if hovering {
                                    NSCursor.pointingHand.push()
                                } else {
                                    NSCursor.pop()
                                }
                            }

                            Text("•")
                                .foregroundColor(.gray)

                            // Version history button
                            Button(action: {
                                openHistorySidebar()
                            }) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .foregroundColor(isHoveringClock ? textHoverColor : textColor)
                            }
                            .buttonStyle(.plain)
                            .onHover { hovering in
                                isHoveringClock = hovering
                                isHoveringBottomNav = hovering
                                if hovering {
                                    NSCursor.pointingHand.push()
                                } else {
                                    NSCursor.pop()
                                }
                            }
                        }
                        .onHover { hovering in
                            isHoveringBottomNav = hovering
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, bottomNavVerticalPadding - 1)
                    .padding(.bottom, bottomNavVerticalPadding)
                    .background(Color(colorScheme == .light ? .white : .black))
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(Color.gray.opacity(colorScheme == .light ? 0.2 : 0.35))
                            .frame(height: 1)
                    }
                    .opacity(bottomNavOpacity)
                        .onHover { hovering in
                            isHoveringBottomNav = hovering
                            if hovering {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    bottomNavOpacity = 1.0
                                }
                            }
                        }
                }
            }

            // Right side rails: History and Destination settings (mutually exclusive)
            if showingSidebar {
                Divider()
                
                VStack(spacing: 0) {
                    // Header
                    Button(action: {
                        revealActiveDestinationInFinder()
                    }) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 4) {
                                    Text("History")
                                        .font(.system(size: 13))
                                        .foregroundColor(isHoveringHistory ? textHoverColor : textColor)
                                    Image(systemName: "arrow.up.right")
                                        .font(.system(size: 10))
                                        .foregroundColor(isHoveringHistory ? textHoverColor : textColor)
                                }
                                Text(activeDestinationHistoryLabel)
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .onHover { hovering in
                        isHoveringHistory = hovering
                    }
                    
                    Divider()
                    
                    // Entries List
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(entries) { entry in
                                HStack(alignment: .top) {
                                    // Show video thumbnail for video entries
                                    if let videoFilename = resolvedVideoFilename(for: entry) {
                                        if let thumbnail = loadThumbnailImage(for: videoFilename) {
                                            Image(nsImage: thumbnail)
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                                .frame(width: 40, height: 40)
                                                .cornerRadius(4)
                                                .overlay(
                                                    Image(systemName: "play.circle.fill")
                                                        .foregroundColor(.white)
                                                        .font(.system(size: 16))
                                                )
                                        } else {
                                            // Fallback if thumbnail generation fails
                                            ZStack {
                                                Rectangle()
                                                    .fill(Color.gray.opacity(0.3))
                                                    .frame(width: 40, height: 40)
                                                    .cornerRadius(4)
                                                Image(systemName: "video.fill")
                                                    .foregroundColor(.gray)
                                                    .font(.system(size: 16))
                                            }
                                        }
                                    }

                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(entry.previewText)
                                                .font(.system(size: 13))
                                                .lineLimit(1)
                                                .foregroundColor(.primary)

                                            Spacer()
                                        }

                                        Text(entry.date)
                                            .font(.system(size: 12))
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(backgroundColor(for: entry))
                                )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectEntry(entry)
                                }
                                .overlay(alignment: .trailing) {
                                    if hoveredEntryId == entry.id {
                                        Button(action: {
                                            deleteEntry(entry: entry)
                                        }) {
                                            Image(systemName: "trash")
                                                .font(.system(size: 11))
                                                .foregroundColor(hoveredTrashId == entry.id ? .red : .gray)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                        }
                                        .buttonStyle(.plain)
                                        .onHover { hovering in
                                            hoveredTrashId = hovering ? entry.id : nil
                                            if hovering {
                                                NSCursor.pointingHand.push()
                                            } else {
                                                NSCursor.pop()
                                            }
                                        }
                                        .padding(.trailing, 8)
                                    }
                                }
                                .onHover { hovering in
                                    hoveredEntryId = hovering ? entry.id : nil
                                }
                                .help("Click to select this entry")

                                if entry.id != entries.last?.id {
                                    Divider()
                                }
                            }
                        }
                    }
                    .scrollIndicators(.never)
                }
                .frame(width: 200)
                .background(Color(colorScheme == .light ? .white : NSColor.black))
                .transition(.move(edge: .trailing))
            }

            if showingDestinationSettings {
                Divider()
                destinationSettingsRail(textColor: textColor)
                    .frame(width: 260)
                    .background(Color(colorScheme == .light ? .white : NSColor.black))
                    .transition(.move(edge: .trailing))
            }
        }
        // Keep the editor usable at compact sizes: sidebar is fixed 200pt wide,
        // and top inset + bottom nav need leftover vertical room to write.
        .frame(
            minWidth: (showingSidebar || showingDestinationSettings) ? 480 : 280,
            minHeight: 200
        )
        // Animate only sidebar insertion; AppKit editor is excluded via .transaction above.
        .animation(.easeInOut(duration: 0.2), value: showingSidebar)
        .animation(.easeInOut(duration: 0.2), value: showingDestinationSettings)
        .preferredColorScheme(colorScheme)
        .background(WindowTitleAccessor(title: currentEntryTitle, isDark: colorScheme == .dark))
        .onAppear {
            showingSidebar = false  // Hide sidebar by default
            showingDestinationSettings = false
            destinationStore.activateDestination(id: destinationStore.activeDestinationId)
            loadExistingEntries()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            finalizeCaptureSession()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { notification in
            guard let window = notification.object as? NSWindow,
                  window.isKeyWindow || NSApplication.shared.keyWindow == window else {
                return
            }
            finalizeCaptureSession()
        }
        .onChange(of: text) { _ in
            guard !isLoadingEntry else { return }
            if isCapturePerSessionMode {
                if inProgressCaptureFilename != nil || normalizedCaptureContent(text).isEmpty == false {
                    handleCaptureTextChange()
                } else if let currentId = selectedEntryId,
                          let currentEntry = entries.first(where: { $0.id == currentId }),
                          currentEntry.entryType == .text {
                    saveEntry(entry: currentEntry)
                }
            } else if let currentId = selectedEntryId,
               let currentEntry = entries.first(where: { $0.id == currentId }),
               currentEntry.entryType == .text {
                saveEntry(entry: currentEntry)
            }
        }
    }
    
    private func backgroundColor(for entry: HumanEntry) -> Color {
        if entry.id == selectedEntryId {
            return Color.gray.opacity(0.1)  // More subtle selection highlight
        } else if entry.id == hoveredEntryId {
            return Color.gray.opacity(0.05)  // Even more subtle hover state
        } else {
            return Color.clear
        }
    }
    
    private func updatePreviewText(for entry: HumanEntry) {
        if entry.entryType == .video {
            if let index = entries.firstIndex(where: { $0.id == entry.id }),
               let videoFilename = resolvedVideoFilename(for: entry) {
                entries[index].previewText = videoPreviewText(for: videoFilename)
            }
            return
        }

        guard let documentsDirectory = getDocumentsDirectory() else { return }
        let fileURL = documentsDirectory.appendingPathComponent(entry.filename)
        
        do {
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            let preview = content
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let truncated = preview.isEmpty ? "" : (preview.count > 30 ? String(preview.prefix(30)) + "..." : preview)
            
            // Find and update the entry in the entries array
            if let index = entries.firstIndex(where: { $0.id == entry.id }) {
                entries[index].previewText = truncated
            }
        } catch {
            print("Error updating preview text: \(error)")
        }
    }
    
    private func saveEntry(entry: HumanEntry, updatePreview: Bool = true) {
        guard entry.entryType == .text else {
            return
        }

        guard let documentsDirectory = destinationStore.resolvedDocumentsURL() else {
            print("Skipping save — active destination unavailable")
            return
        }
        let fileURL = documentsDirectory.appendingPathComponent(entry.filename)
        
        do {
            try text.write(to: fileURL, atomically: true, encoding: .utf8)
            print("Successfully saved entry: \(entry.filename)")
            if updatePreview {
                updatePreviewText(for: entry)
            }
        } catch {
            print("Error saving entry: \(error)")
        }
    }
    
    private func loadEntry(entry: HumanEntry) {
        if let videoFilename = resolvedVideoFilename(for: entry) {
            // Load video entry
            let videoURL = getVideoURL(for: videoFilename)
            let transcriptURL = getVideoTranscriptURL(for: videoFilename)
            text = ""
            didCopyTranscript = false
            selectedVideoHasTranscript = transcriptURL.map { fileManager.fileExists(atPath: $0.path) } ?? false
            if let videoURL, fileManager.fileExists(atPath: videoURL.path) {
                currentVideoURL = videoURL
                print("Successfully loaded video entry: \(videoFilename)")
            } else {
                print("Video file missing for entry: \(videoFilename)")
            }
        } else {
            // Load text entry
            currentVideoURL = nil
            selectedVideoHasTranscript = false
            didCopyTranscript = false
            guard let documentsDirectory = getDocumentsDirectory() else {
                text = ""
                return
            }
            let fileURL = documentsDirectory.appendingPathComponent(entry.filename)

            do {
                if fileManager.fileExists(atPath: fileURL.path) {
                    let rawText = try String(contentsOf: fileURL, encoding: .utf8)
                    // Strip legacy leading newlines from older entries
                    text = String(rawText.drop(while: { $0 == "\n" }))
                    print("Successfully loaded entry: \(entry.filename)")
                } else {
                    // Soft-fail missing file (e.g. Existing note removed from disk).
                    text = ""
                    print("Entry file missing: \(entry.filename)")
                }
            } catch {
                print("Error loading entry: \(error)")
                text = ""
            }
        }
    }
    
    private func createNewEntry() {
        // Rolling / Existing: re-bind to current period/target and append a session separator.
        if activeSaveMode == .rolling || activeSaveMode == .existing {
            if let currentId = selectedEntryId,
               let currentEntry = entries.first(where: { $0.id == currentId }),
               currentEntry.entryType == .text {
                saveEntry(entry: currentEntry, updatePreview: false)
            }
            _ = bindToResolvedWriteTarget(appendSeparator: true)
            return
        }

        finalizeCaptureSession()
        beginFreshCaptureSession(clearText: true)
    }

    @ViewBuilder
    private func destinationChip(textColor: Color, textHoverColor: Color) -> some View {
        Menu {
            ForEach(destinationStore.destinations) { destination in
                Button {
                    switchToDestination(id: destination.id)
                } label: {
                    HStack {
                        Text(destination.displayName)
                        Spacer()
                        if destination.id == destinationStore.activeDestinationId {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
            Divider()
            Button("Destination settings…") {
                openDestinationSettings()
            }
            Button("Add destination…") {
                // Dismiss the SwiftUI Menu before presenting NSOpenPanel.
                // Presenting the panel synchronously from a Menu action can race
                // AppKit's open-panel restore and show "The file couldn’t be opened."
                DispatchQueue.main.async {
                    addDestinationFromFolderPicker()
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "folder")
                    .font(.system(size: 12))
                Text(activeDestinationDisplayName)
                    .font(.system(size: 13))
                    .lineLimit(1)
            }
            .foregroundColor(isHoveringDestinationChip ? textHoverColor : textColor)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .onHover { hovering in
            isHoveringDestinationChip = hovering
            isHoveringBottomNav = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }

    @ViewBuilder
    private func destinationSettingsRail(textColor: Color) -> some View {
        let destination = destinationStore.activeDestination
        let pathLabel = destinationStore.activeDocumentsPath
            ?? (destinationStore.activeAccessFailed ? "Unavailable" : "—")
        let currentMode = destination?.saveMode ?? .newNote
        let currentPeriod = destination?.rollingPeriod ?? .daily
        let existingName = destination?.existingNoteFilename

        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Destination settings")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(textColor)
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showingDestinationSettings = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Name")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        TextField("Display name", text: $settingsDisplayName)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit {
                                applyActiveDestinationSettingsChange(displayName: settingsDisplayName)
                            }
                        Button("Apply name") {
                            applyActiveDestinationSettingsChange(displayName: settingsDisplayName)
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundColor(textColor)

                        Text("Folder")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                        Text(pathLabel)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(3)
                            .textSelection(.enabled)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Save write as?")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)

                        ForEach(DestinationSaveMode.allCases, id: \.self) { mode in
                            Button {
                                applyActiveDestinationSettingsChange(saveMode: mode)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: currentMode == mode ? "circle.inset.filled" : "circle")
                                        .font(.system(size: 12))
                                        .foregroundColor(textColor)
                                    Text(mode.displayName)
                                        .font(.system(size: 13))
                                        .foregroundColor(textColor)
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if currentMode == .newNote {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Filename format")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)

                            ForEach(NewNoteFilenameFormat.allCases, id: \.self) { format in
                                Button {
                                    applyActiveDestinationSettingsChange(newNoteFilenameFormat: format)
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: settingsNewNoteFilenameFormat == format ? "circle.inset.filled" : "circle")
                                            .font(.system(size: 12))
                                            .foregroundColor(textColor)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(format.displayName)
                                                .font(.system(size: 13))
                                                .foregroundColor(textColor)
                                            Text(format == .date
                                                 ? "Date and time when capture starts"
                                                 : "First paragraph when capture closes")
                                                .font(.system(size: 10))
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if currentMode == .rolling {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Period")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            HStack(spacing: 6) {
                                ForEach(RollingPeriod.allCases, id: \.self) { period in
                                    Button {
                                        applyActiveDestinationSettingsChange(rollingPeriod: period)
                                        settingsFilenameFormat = period.defaultFilenameFormat
                                    } label: {
                                        Text(period.displayName)
                                            .font(.system(size: 12))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(
                                                currentPeriod == period
                                                    ? Color.gray.opacity(0.15)
                                                    : Color.clear
                                            )
                                            .cornerRadius(4)
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundColor(textColor)
                                }
                            }

                            Text("Filename format")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            TextField("yyyy-MM-dd", text: $settingsFilenameFormat)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12, design: .monospaced))
                            Button("Apply format") {
                                guard DestinationWriteTarget.formattedBasename(
                                    format: settingsFilenameFormat,
                                    period: currentPeriod
                                ) != nil else { return }
                                applyActiveDestinationSettingsChange(filenameFormat: settingsFilenameFormat)
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 12))
                            .foregroundColor(textColor)

                            Text("Tokens: yyyy MM dd ww — quote literals, e.g. yyyy-'W'ww")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                            if let preview = DestinationWriteTarget.formattedBasename(
                                format: settingsFilenameFormat,
                                period: currentPeriod
                            ) {
                                Text("Today → \(preview).md")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            } else {
                                Text("Invalid format (no path separators; basename only)")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    if currentMode == .existing {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Note")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Text(existingName ?? "None selected")
                                .font(.system(size: 12))
                                .foregroundColor(existingName == nil ? .secondary : textColor)
                                .lineLimit(2)

                            Button("Choose note…") {
                                DispatchQueue.main.async {
                                    pickExistingNoteForActiveDestination()
                                }
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 13))
                            .foregroundColor(textColor)
                        }
                    }
                }
                .padding(16)
            }
            .scrollIndicators(.never)
        }
    }

    private func pickExistingNoteForActiveDestination() {
        guard let documentsURL = destinationStore.resolvedDocumentsURL() else { return }

        UserDefaults.standard.removeObject(forKey: "NSOSPLastRootDirectory")

        // Save panel allows pick-or-create a .md basename under the destination root.
        let panel = NSSavePanel()
        panel.canCreateDirectories = false
        panel.directoryURL = documentsURL
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.allowsOtherFileTypes = true
        panel.nameFieldStringValue = destinationStore.activeDestination?.existingNoteFilename
            ?? "journal.md"
        panel.title = "Choose or create a note"
        panel.message = "Select or name a markdown file in this destination folder."
        panel.prompt = "Use Note"

        let response = panel.runModal()
        guard response == .OK, let url = panel.url else { return }

        let standardizedRoot = documentsURL.standardizedFileURL.path
        let standardizedPick = url.standardizedFileURL.path
        guard standardizedPick.hasPrefix(standardizedRoot + "/") || standardizedPick == standardizedRoot else {
            print("Existing note must stay inside the destination folder")
            return
        }

        let relative = String(standardizedPick.dropFirst(standardizedRoot.count + 1))
        guard DestinationWriteTarget.validatedBasename(relative) != nil,
              !relative.contains("/") else {
            print("Existing note must be a root-level basename (no subfolders)")
            return
        }

        let filename = DestinationWriteTarget.markdownFilename(
            fromBasename: DestinationWriteTarget.validatedBasename(relative) ?? relative
        )
        let finalURL = documentsURL.appendingPathComponent(filename)

        // Create-on-pick if missing.
        if !fileManager.fileExists(atPath: finalURL.path) {
            try? "".write(to: finalURL, atomically: true, encoding: .utf8)
        }

        applyActiveDestinationSettingsChange(existingNoteFilename: .some(filename))
    }

    private func deleteEntry(entry: HumanEntry) {
        // Delete the file from the filesystem
        guard let documentsDirectory = getDocumentsDirectory() else { return }
        let fileURL = documentsDirectory.appendingPathComponent(entry.filename)

        do {
            try fileManager.removeItem(at: fileURL)
            print("Successfully deleted file: \(entry.filename)")

            // If this is a video entry, also delete the video file
            if let videoFilename = resolvedVideoFilename(for: entry) {
                deleteVideoAssets(for: videoFilename)
                print("Successfully deleted video assets: \(videoFilename)")
            }

            // Remove the entry from the entries array
            if let index = entries.firstIndex(where: { $0.id == entry.id }) {
                entries.remove(at: index)

                // If the deleted entry was selected, select the first entry or create a new one
                if selectedEntryId == entry.id {
                    if let firstEntry = entries.first {
                        selectedEntryId = firstEntry.id
                        loadEntry(entry: firstEntry)
                    } else if isCapturePerSessionMode {
                        beginFreshCaptureSession(clearText: true)
                    } else {
                        createNewEntry()
                    }
                }
            }
        } catch {
            print("Error deleting file: \(error)")
        }
    }
}

// Helper function to calculate line height
func getLineHeight(font: NSFont) -> CGFloat {
    return font.ascender - font.descender + font.leading
}

// Add helper extension to find NSTextView
extension NSView {
    func findTextView() -> NSView? {
        if self is NSTextView {
            return self
        }
        for subview in subviews {
            if let textView = subview.findTextView() {
                return textView
            }
        }
        return nil
    }
}

// Add helper extension for finding subviews of a specific type
extension NSView {
    func findSubview<T: NSView>(ofType type: T.Type) -> T? {
        if let typedSelf = self as? T {
            return typedSelf
        }
        for subview in subviews {
            if let found = subview.findSubview(ofType: type) {
                return found
            }
        }
        return nil
    }
}

#Preview {
    ContentView()
}
