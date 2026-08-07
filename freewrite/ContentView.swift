// Swift 5.0
//
//  ContentView.swift
//  freewrite
//
//  Created by thorfinn on 2/14/25.
//

import SwiftUI
import AppKit

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

struct ContentView: View {
    @State private var entries: [HumanEntry] = []
    @State private var text: String = ""  // Remove initial welcome text since we'll handle it in createNewEntry
    
    private let selectedFont: String = "Lato-Regular"
    private let fontSize: CGFloat = 14
    @State private var bottomNavOpacity: Double = 1.0
    @State private var isHoveringBottomNav = false
    @State private var selectedEntryIndex: Int = 0
    @State private var scrollOffset: CGFloat = 0
    @State private var selectedEntryId: UUID? = nil
    @State private var hoveredEntryId: UUID? = nil
    @State private var showingSidebar = false  // Add this state variable
    @State private var hoveredTrashId: UUID? = nil
    @State private var placeholderText: String = ""  // Add this line
    @State private var isHoveringNewEntry = false
    @State private var isHoveringClock = false
    @State private var isHoveringHistory = false
    @State private var isHoveringHistoryText = false
    @State private var isHoveringHistoryPath = false
    @State private var isHoveringHistoryArrow = false
    @State private var isHoveringCopyTranscript = false
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
    
    // Add cached documents directory
    private let documentsDirectory: URL = {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Freewrite")
        
        // Create Freewrite directory if it doesn't exist
        if !FileManager.default.fileExists(atPath: directory.path) {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                print("Successfully created Freewrite directory")
            } catch {
                print("Error creating directory: \(error)")
            }
        }
        
        return directory
    }()

    private let videosDirectory: URL = {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Freewrite")
            .appendingPathComponent("Videos")

        if !FileManager.default.fileExists(atPath: directory.path) {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                print("Successfully created Freewrite/Videos directory")
            } catch {
                print("Error creating videos directory: \(error)")
            }
        }

        return directory
    }()

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
    
    // Modify getDocumentsDirectory to use cached value
    private func getDocumentsDirectory() -> URL {
        return documentsDirectory
    }

    private func getVideosDirectory() -> URL {
        return videosDirectory
    }

    private func getVideoEntryDirectory(for videoFilename: String) -> URL {
        let baseName = (videoFilename as NSString).deletingPathExtension
        return getVideosDirectory().appendingPathComponent(baseName, isDirectory: true)
    }

    private func getManagedVideoURL(for filename: String) -> URL {
        getVideoEntryDirectory(for: filename).appendingPathComponent(filename)
    }

    private func getVideoThumbnailURL(for filename: String) -> URL {
        getVideoEntryDirectory(for: filename).appendingPathComponent("thumbnail.jpg")
    }

    private func getVideoTranscriptURL(for filename: String) -> URL {
        getVideoEntryDirectory(for: filename).appendingPathComponent("transcript.md")
    }

    @discardableResult
    private func ensureVideoEntryDirectoryExists(for videoFilename: String) throws -> URL {
        let directory = getVideoEntryDirectory(for: videoFilename)
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    private func getVideoURL(for filename: String) -> URL {
        // Current production layout: Videos/[entry-base]/[entry-filename].mov
        let managedVideoURL = getManagedVideoURL(for: filename)
        if fileManager.fileExists(atPath: managedVideoURL.path) {
            return managedVideoURL
        }

        // Backward compatibility: older builds stored videos flat under Videos/
        let flatVideosURL = getVideosDirectory().appendingPathComponent(filename)
        if fileManager.fileExists(atPath: flatVideosURL.path) {
            return flatVideosURL
        }

        // Backward compatibility: oldest builds stored videos in root Freewrite folder
        let rootVideosURL = getDocumentsDirectory().appendingPathComponent(filename)
        if fileManager.fileExists(atPath: rootVideosURL.path) {
            return rootVideosURL
        }

        // Default to managed path for newly created entries.
        return managedVideoURL
    }

    private func hasVideoAsset(for filename: String) -> Bool {
        let managedVideoURL = getManagedVideoURL(for: filename)
        if fileManager.fileExists(atPath: managedVideoURL.path) {
            return true
        }

        let flatVideosURL = getVideosDirectory().appendingPathComponent(filename)
        if fileManager.fileExists(atPath: flatVideosURL.path) {
            return true
        }

        let rootVideosURL = getDocumentsDirectory().appendingPathComponent(filename)
        return fileManager.fileExists(atPath: rootVideosURL.path)
    }

    private let historyDebugEnabled = true

    private func historyDebug(_ message: String) {
        guard historyDebugEnabled else { return }
        print("[HistoryDebug] \(message)")
    }

    private func debugEntrySummary(_ entry: HumanEntry) -> String {
        let shortID = String(entry.id.uuidString.prefix(8))
        let type = entry.entryType == .video ? "video" : "text"
        let videoFilename = resolvedVideoFilename(for: entry) ?? "-"
        return "id=\(shortID) type=\(type) file=\(entry.filename) video=\(videoFilename)"
    }

    private func logEntriesOrder(_ reason: String, limit: Int = 20) {
        guard historyDebugEnabled else { return }
        historyDebug("ORDER SNAPSHOT (\(reason)) total=\(entries.count) selected=\(selectedEntryId?.uuidString ?? "nil")")
        for (index, entry) in entries.prefix(limit).enumerated() {
            historyDebug("#\(index + 1) \(debugEntrySummary(entry))")
        }
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

        let thumbnailURL = getVideoThumbnailURL(for: videoFilename)
        if fileManager.fileExists(atPath: thumbnailURL.path),
           let image = NSImage(contentsOf: thumbnailURL) {
            thumbnailMemoryCache.setObject(image, forKey: cacheKey)
            return image
        }

        // Backward compatibility: generate once for old video entries, then persist.
        let videoURL = getVideoURL(for: videoFilename)
        guard fileManager.fileExists(atPath: videoURL.path),
              let generated = generateVideoThumbnail(from: videoURL) else {
            historyDebug("THUMBNAIL MISS video=\(videoFilename) thumbnailPath=\(thumbnailURL.path) videoPath=\(videoURL.path)")
            return nil
        }
        persistThumbnail(generated, for: videoFilename)
        thumbnailMemoryCache.setObject(generated, forKey: cacheKey)
        historyDebug("THUMBNAIL GENERATED video=\(videoFilename) thumbnailPath=\(thumbnailURL.path)")
        return generated
    }

    private func deleteVideoAssets(for videoFilename: String) {
        thumbnailMemoryCache.removeObject(forKey: videoFilename as NSString)

        let managedDirectory = getVideoEntryDirectory(for: videoFilename)
        let managedVideoURL = managedDirectory.appendingPathComponent(videoFilename)
        let managedThumbnailURL = managedDirectory.appendingPathComponent("thumbnail.jpg")
        let managedTranscriptURL = managedDirectory.appendingPathComponent("transcript.md")
        let flatVideosURL = getVideosDirectory().appendingPathComponent(videoFilename)
        let rootVideosURL = getDocumentsDirectory().appendingPathComponent(videoFilename)

        let candidateURLs = [managedVideoURL, managedThumbnailURL, managedTranscriptURL, flatVideosURL, rootVideosURL]
        for url in candidateURLs where fileManager.fileExists(atPath: url.path) {
            do {
                try fileManager.removeItem(at: url)
            } catch {
                print("Error deleting video asset \(url.lastPathComponent): \(error)")
            }
        }

        if fileManager.fileExists(atPath: managedDirectory.path) {
            do {
                try fileManager.removeItem(at: managedDirectory)
            } catch {
                print("Error deleting video entry directory: \(error)")
            }
        }
    }

    private func loadTranscriptText(for videoFilename: String) -> String? {
        let transcriptURL = getVideoTranscriptURL(for: videoFilename)
        guard fileManager.fileExists(atPath: transcriptURL.path),
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
    
    // Add function to save text
    private func saveText() {
        let documentsDirectory = getDocumentsDirectory()
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
        let documentsDirectory = getDocumentsDirectory()
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
    
    // Add function to load existing entries
    private func loadExistingEntries() {
        let documentsDirectory = getDocumentsDirectory()
        print("Looking for entries in: \(documentsDirectory.path)")
        print("Looking for videos in: \(getVideosDirectory().path)")
        
        do {
            let fileURLs = try fileManager.contentsOfDirectory(at: documentsDirectory, includingPropertiesForKeys: nil)
            let mdFiles = fileURLs.filter { $0.pathExtension == "md" }

            print("Found \(mdFiles.count) .md files")

            // Process each file
            let entriesWithDates = mdFiles.compactMap { fileURL -> (entry: HumanEntry, date: Date, content: String)? in
                let filename = fileURL.lastPathComponent
                print("Processing: \(filename)")

                // Only accept canonical entry filenames: [UUID]-[yyyy-MM-dd-HH-mm-ss].md
                guard let parsed = parseCanonicalEntryFilename(filename) else {
                    print("Skipping non-canonical entry filename: \(filename)")
                    return nil
                }
                let uuid = parsed.uuid
                let fileDate = parsed.timestamp

                // Check if there's a corresponding video file
                let videoFilename = filename.replacingOccurrences(of: ".md", with: ".mov")
                let hasVideo = hasVideoAsset(for: videoFilename)

                // Read file contents for preview
                do {
                    let content = try String(contentsOf: fileURL, encoding: .utf8)
                    let preview = content
                        .replacingOccurrences(of: "\n", with: " ")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let truncated = preview.isEmpty ? "" : (preview.count > 30 ? String(preview.prefix(30)) + "..." : preview)

                    // Format display date
                    let dateFormatter = DateFormatter()
                    dateFormatter.dateFormat = "MMM d"
                    let displayDate = dateFormatter.string(from: fileDate)

                    return (
                        entry: HumanEntry(
                            id: uuid,
                            date: displayDate,
                            filename: filename,
                            previewText: hasVideo ? videoPreviewText(for: videoFilename) : truncated,
                            entryType: hasVideo ? .video : .text,
                            videoFilename: hasVideo ? videoFilename : nil
                        ),
                        date: fileDate,
                        content: content  // Store the full content to check for welcome message
                    )
                } catch {
                    print("Error reading file: \(error)")
                    return nil
                }
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

            // Check if we need to create a new entry
            let calendar = Calendar.current
            let today = Date()
            let hasEntryToday = loadedEntries.contains { isEntryFromToday($0, calendar: calendar, today: today) }
            let hasEmptyTextEntryToday = loadedEntries.contains {
                isEntryFromToday($0, calendar: calendar, today: today) &&
                $0.entryType == .text &&
                $0.previewText.isEmpty
            }

            // Check if we have only one entry and it's the welcome message
            let hasOnlyWelcomeEntry = loadedEntries.count == 1 && entriesWithDates.first?.content.contains("Welcome to Freewrite.") == true

            // Now assign to the state variable
            entries = loadedEntries
            logEntriesOrder("loadExistingEntries")

            // Never open directly into video on startup; create a fresh text entry instead.
            if let latestEntry = entries.first, latestEntry.entryType == .video {
                print("Latest entry is video, creating new text entry for startup")
                createNewEntry()
                return
            }

            if entries.isEmpty {
                // First time user - create entry with welcome message
                print("First time user, creating welcome entry")
                createNewEntry()
            } else if !hasEntryToday && !hasOnlyWelcomeEntry {
                // No entries at all for today - create a new text entry
                print("No entry for today, creating new entry")
                createNewEntry()
            } else {
                // Prefer an empty text entry from today for writing continuity; otherwise pick latest entry.
                if hasEmptyTextEntryToday,
                   let todayEntry = entries.first(where: {
                       isEntryFromToday($0, calendar: calendar, today: today) &&
                       $0.entryType == .text &&
                       $0.previewText.isEmpty
                   }) {
                    selectedEntryId = todayEntry.id
                    loadEntry(entry: todayEntry)
                } else if hasOnlyWelcomeEntry {
                    // If we only have the welcome entry, select it
                    selectedEntryId = entries[0].id
                    loadEntry(entry: entries[0])
                } else if let latestEntry = entries.first {
                    selectedEntryId = latestEntry.id
                    loadEntry(entry: latestEntry)
                }
            }
            
        } catch {
            print("Error loading directory contents: \(error)")
            print("Creating default entry after error")
            createNewEntry()
        }
    }
    
    var lineHeight: CGFloat {
        let font = NSFont(name: selectedFont, size: fontSize) ?? .systemFont(ofSize: fontSize)
        let defaultLineHeight = getLineHeight(font: font)
        return (fontSize * 1.5) - defaultLineHeight
    }

    private var currentEntryTitle: String {
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
        let buttonBackground = colorScheme == .light ? Color.white : Color.black
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
                } else {
                    // Show text editor for text entries
                    TextEditor(text: $text)
                        .background(Color(colorScheme == .light ? .white : .black))
                        .font(.custom(selectedFont, size: fontSize))
                        .foregroundColor(colorScheme == .light ? Color(red: 0.20, green: 0.20, blue: 0.20) : Color(red: 0.9, green: 0.9, blue: 0.9))
                        .scrollContentBackground(.hidden)
                        .scrollIndicators(.never)
                        .lineSpacing(lineHeight)
                        // Placeholder shares the editor's coordinate space so it sits on the first line.
                        .overlay(alignment: .topLeading) {
                            if text.isEmpty {
                                Text(placeholderText)
                                    .font(.custom(selectedFont, size: fontSize))
                                    .foregroundColor(colorScheme == .light ? .gray.opacity(0.5) : .gray.opacity(0.6))
                                    // Align with NSTextView's native horizontal line-fragment padding.
                                    .padding(.leading, editorNativeTextPadding)
                                    .allowsHitTesting(false)
                            }
                        }
                        // Fixed 18pt page inset to the glyph origin: subtract the editor's
                        // native 5pt horizontal padding so text sits 18pt from the window edge.
                        // Bottom clearance is a scroll content margin with an 8pt gap above the nav border.
                        .padding(.top, editorInset)
                        .padding(.horizontal, editorInset - editorNativeTextPadding)
                        .contentMargins(.bottom, bottomNavHeight + bottomNavContentGap, for: .scrollContent)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .id("\(selectedFont)-\(fontSize)-\(colorScheme)")
                        .colorScheme(colorScheme)
                        .onAppear {
                            placeholderText = placeholderOptions.randomElement() ?? "Begin writing"
                        }
                }

                // Bottom nav
                VStack {
                    Spacer()
                    HStack {
                        if isViewingVideoEntry {
                            HStack(spacing: 8) {
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
                            .onHover { hovering in
                                isHoveringBottomNav = hovering
                            }
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
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showingSidebar.toggle()
                                }
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

            // Right sidebar
            if showingSidebar {
                Divider()
                
                VStack(spacing: 0) {
                    // Header
                    Button(action: {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: getDocumentsDirectory().path)
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
                                Text(getDocumentsDirectory().path)
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
                                Button(action: {
                                    if selectedEntryId != entry.id {
                                        historyDebug("ROW TAP \(debugEntrySummary(entry))")
                                        // Save current entry before switching
                                        if let currentId = selectedEntryId,
                                           let currentEntry = entries.first(where: { $0.id == currentId }),
                                           currentEntry.entryType == .text {
                                            saveEntry(entry: currentEntry)
                                        }

                                        // Re-resolve from source of truth after any state mutations.
                                        guard let targetEntry = entries.first(where: { $0.id == entry.id }) else {
                                            historyDebug("ROW TAP target missing id=\(entry.id.uuidString)")
                                            return
                                        }
                                        selectedEntryId = targetEntry.id
                                        historyDebug("ROW TAP resolved target \(debugEntrySummary(targetEntry))")
                                        loadEntry(entry: targetEntry)
                                    }
                                }) {
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
                                                
                                                // Trash icon that appears on hover
                                                if hoveredEntryId == entry.id {
                                                    Button(action: {
                                                        deleteEntry(entry: entry)
                                                    }) {
                                                        Image(systemName: "trash")
                                                            .font(.system(size: 11))
                                                            .foregroundColor(hoveredTrashId == entry.id ? .red : .gray)
                                                    }
                                                    .buttonStyle(.plain)
                                                    .onHover { hovering in
                                                        withAnimation(.easeInOut(duration: 0.2)) {
                                                            hoveredTrashId = hovering ? entry.id : nil
                                                        }
                                                        if hovering {
                                                            NSCursor.pointingHand.push()
                                                        } else {
                                                            NSCursor.pop()
                                                        }
                                                    }
                                                }
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
                                }
                                .buttonStyle(PlainButtonStyle())
                                .contentShape(Rectangle())
                                .onHover { hovering in
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        hoveredEntryId = hovering ? entry.id : nil
                                    }
                                }
                                .onAppear {
                                    NSCursor.pop()  // Reset cursor when button appears
                                }
                                .help("Click to select this entry")  // Add tooltip
                                
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
            }
        }
        // Keep the editor usable at compact sizes: sidebar is fixed 200pt wide,
        // and top inset + bottom nav need leftover vertical room to write.
        .frame(minWidth: showingSidebar ? 480 : 280, minHeight: 200)
        .animation(.easeInOut(duration: 0.2), value: showingSidebar)
        .preferredColorScheme(colorScheme)
        .background(WindowTitleAccessor(title: currentEntryTitle, isDark: colorScheme == .dark))
        .onAppear {
            showingSidebar = false  // Hide sidebar by default
            loadExistingEntries()
        }
        .onChange(of: text) { _ in
            // Save current entry when text changes
            if let currentId = selectedEntryId,
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

        let documentsDirectory = getDocumentsDirectory()
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
    
    private func saveEntry(entry: HumanEntry) {
        guard entry.entryType == .text else {
            return
        }

        let documentsDirectory = getDocumentsDirectory()
        let fileURL = documentsDirectory.appendingPathComponent(entry.filename)
        
        do {
            try text.write(to: fileURL, atomically: true, encoding: .utf8)
            print("Successfully saved entry: \(entry.filename)")
            updatePreviewText(for: entry)  // Update preview after saving
        } catch {
            print("Error saving entry: \(error)")
        }
    }
    
    private func loadEntry(entry: HumanEntry) {
        if let videoFilename = resolvedVideoFilename(for: entry) {
            // Load video entry
            let videoURL = getVideoURL(for: videoFilename)
            let thumbnailURL = getVideoThumbnailURL(for: videoFilename)
            let transcriptURL = getVideoTranscriptURL(for: videoFilename)
            historyDebug("LOAD VIDEO \(debugEntrySummary(entry)) resolvedVideoPath=\(videoURL.path) videoExists=\(fileManager.fileExists(atPath: videoURL.path)) thumbnailPath=\(thumbnailURL.path) thumbnailExists=\(fileManager.fileExists(atPath: thumbnailURL.path))")
            text = ""
            didCopyTranscript = false
            selectedVideoHasTranscript = fileManager.fileExists(atPath: transcriptURL.path)
            if fileManager.fileExists(atPath: videoURL.path) {
                currentVideoURL = videoURL
                print("Successfully loaded video entry: \(videoFilename)")
            } else {
                print("Video file missing for entry: \(videoFilename)")
            }
        } else {
            // Load text entry
            historyDebug("LOAD TEXT \(debugEntrySummary(entry))")
            currentVideoURL = nil
            selectedVideoHasTranscript = false
            didCopyTranscript = false
            let documentsDirectory = getDocumentsDirectory()
            let fileURL = documentsDirectory.appendingPathComponent(entry.filename)

            do {
                if fileManager.fileExists(atPath: fileURL.path) {
                    let rawText = try String(contentsOf: fileURL, encoding: .utf8)
                    // Strip legacy leading newlines from older entries
                    text = String(rawText.drop(while: { $0 == "\n" }))
                    print("Successfully loaded entry: \(entry.filename)")
                }
            } catch {
                print("Error loading entry: \(error)")
            }
        }
    }
    
    private func createNewEntry() {
        let newEntry = HumanEntry.createNew()
        entries.insert(newEntry, at: 0) // Add to the beginning
        selectedEntryId = newEntry.id
        currentVideoURL = nil
        selectedVideoHasTranscript = false
        didCopyTranscript = false
        historyDebug("NEW ENTRY created \(debugEntrySummary(newEntry))")
        logEntriesOrder("createNewEntry")

        text = ""
        // Randomize placeholder text for new entry
        placeholderText = placeholderOptions.randomElement() ?? "Begin writing"
        // Save the empty entry
        saveEntry(entry: newEntry)
    }
    
    private func deleteEntry(entry: HumanEntry) {
        // Delete the file from the filesystem
        let documentsDirectory = getDocumentsDirectory()
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
                historyDebug("DELETE ENTRY removed \(debugEntrySummary(entry))")
                logEntriesOrder("deleteEntry")

                // If the deleted entry was selected, select the first entry or create a new one
                if selectedEntryId == entry.id {
                    if let firstEntry = entries.first {
                        selectedEntryId = firstEntry.id
                        loadEntry(entry: firstEntry)
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
