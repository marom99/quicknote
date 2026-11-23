# Quick Note - Technical Documentation for AI Agents

> **⚠️ IMPORTANT FOR AI AGENTS**: This file (`AGENTS.md`) and `CLAUDE.md` are clones and must be kept in sync.
>
> Update both files when changes are **substantial** and meaningfully affect future agent understanding (for example: architecture, data flow, storage/permissions, threading behavior, user-facing workflows, or major bug fixes).
>
> For minor tweaks (small UI polish, copy edits, tiny refactors), updates are optional. Do **not** churn these docs on every small code change.
>
> If one file is updated, mirror the same change in the other file immediately.

## Product Vision & User Experience

### What is Quick Note?

Quick Note is a distraction-free writing environment for macOS. It also plays existing video journals.

### User Experience Philosophy

**Core Principles:**
1. **No Backspace (Optional)**: Users can disable the backspace key to encourage forward-thinking writing without self-editing
2. **Timed Sessions**: Built-in timer (default 15 minutes) creates focused writing sprints
3. **Auto-Everything**: Auto-save, auto-new-entry, auto-timestamp - the app manages logistics so users can focus on writing
4. **Local-First**: All data stays on the user's machine in plain markdown files they can access directly
5. **Minimal UI**: Most UI elements hide during timed sessions, leaving only the text

### Use Cases

**Primary Use Case - Stream of Consciousness Writing:**
- Users open the app and start writing immediately (no "New Document" dialog)
- The app creates a new entry automatically at the start of each day
- Writing is saved continuously with no manual save action
- Timer creates urgency and prevents over-editing
- Backspace disable forces forward momentum in thinking

**Secondary Use Case - Revisit Video Journals:**
- Play existing video notes from the same History as text notes.
- Copy a saved transcript when one is available.

**Tertiary Use Case - AI-Assisted Reflection:**
- "Chat" button sends writing to ChatGPT or Claude
- Prompts designed to help users reflect on and understand their writing
- AI provides feedback, questions, or analysis of stream-of-consciousness text

**Hidden Power Feature - Long-Form Writing:**
- Despite minimalist interface, supports full markdown
- Fixed 16px Lato body text for comfort during long sessions
- Dark mode for night writing

## Overview

Quick Note is a native macOS writing application built with SwiftUI. It writes text entries and plays existing video entries. All data is stored locally; the default journal lives in `~/Documents/Quick Note/`, and writers can add additional named destinations pointing at other folders.

## Architecture

### Technology Stack
- **Framework**: SwiftUI (macOS)
- **Minimum macOS Version**: 14.0
- **Language**: Swift 5.0
- **Build System**: Xcode
- **Media**: AVKit for playback and AVFoundation for thumbnails

### Project Structure

```
freewrite/
├── freewrite.xcodeproj/          # Xcode project file
├── freewrite/
│   ├── freewriteApp.swift        # App entry point
│   ├── ContentView.swift         # Main view (1400+ lines)
│   ├── QuickCapture.swift        # Carbon hotkey + menu-bar capture routing
│   ├── DestinationStore.swift    # Named destinations + save modes
│   ├── DestinationWriteTarget.swift # Rolling/existing resolve helpers
│   ├── VideoPlayerView.swift     # Video playback interface
│   └── freewrite.entitlements    # App permissions
├── CLAUDE.md                     # This file
└── AGENTS.md                     # Duplicate of this file
```

## Data Model

### Entry Types

```swift
enum EntryType {
    case text
    case video
}

struct HumanEntry: Identifiable {
    let id: UUID
    let date: String              // Display format: "MMM d" (e.g., "Feb 20")
    let filename: String          // Format: [UUID]-[YYYY-MM-DD-HH-mm-ss].md
    var previewText: String       // History title: first non-blank line (HistoryRowFormatting.title) or video transcript preview
    var entryType: EntryType      // .text or .video
    var videoFilename: String?    // Format: [UUID]-[YYYY-MM-DD-HH-mm-ss].mov
    var timestamp: Date?          // History row time: filename timestamp (canonical) or file modification date
    var searchableBody: String    // History search body: note content or video transcript
}
```

### File Storage

**Default location**: `~/Documents/Quick Note/` (always available as the first named destination)

**Legacy Freewrite migration**: on first resolve, an existing `~/Documents/Freewrite/` is moved to `~/Documents/Quick Note/` when no `Quick Note` folder exists yet (if the move fails, the legacy folder stays in use). A persisted default destination still named `Freewrite` is renamed to `Quick Note`; user-chosen names are kept.

**Named save destinations**:
- Writers pick additional journal folders via the bottom-left destination menu (`Add destination…`).
- Each destination has a display name (defaults to the folder name) and an optional security-scoped bookmark for user-picked paths.
- The default Quick Note folder uses no bookmark; user-picked folders persist bookmark `Data` in UserDefaults (`saveDestinations`, `activeDestinationId`).
- **Per-destination save modes** (persisted on each `SaveDestination`; legacy decoded destinations default to **New note**):
  - **New note**: capture-per-session. Launch and destination reload show an unbound empty canvas; the first non-whitespace edit starts a capture. Each destination chooses a `newNoteFilenameFormat` of **Date** (`yyyy-MM-dd-HH-mm-ss.md`) or **Title** (first paragraph when the capture closes).
  - **Rolling**: period (daily / weekly / monthly) + `filenameFormat` DateFormatter pattern (basename only, no subfolders) → e.g. `yyyy-MM-dd.md`. Period uses an ISO-week-aware anchor for weekly; bind on launch / switch / New Note; New Note appends `\n---\nyyyy-MM-dd HH:mm\n` and moves the caret to the end so the next session starts below the separator.
  - **Existing**: bind to a chosen root-level `.md` (`existingNoteFilename`); create-on-pick; soft-fail (empty editor) if missing later.
- Switching destinations reloads History and scopes autosave to that folder only; video assets live under each destination's `Videos/` subdirectory.
- Adding a destination creates it inactive, then uses the normal destination-switch path. This ordering is required so an active capture finalizes in its original folder before the new destination becomes active.
- **History listing**: all modes list root-level `.md` files, with non-canonical rows using a stable UUID derived from the file path. New note excludes hidden `.quicknote-capture-*.md` title drafts until they are finalized. Each row shows the note's first non-blank line as its title (empty notes read "Untitled") and the day plus time (`HistoryRowFormatting`). A search field under the History header filters rows as you type (`HistorySearch`): every whitespace-separated term must appear in the title or body (video: transcript), ignoring case and diacritics; the open note matches against its unsaved editor text. Esc or the clear button resets it; opening History or switching destinations starts with an empty query.
- **Destination settings** rail opens from the destination menu (`Destination settings…`); mutually exclusive with History; edits the active destination only; changes apply immediately and re-resolve the write target. Out of v1: video into rolling, subfolders in format, folder rebind.
- `DestinationStore` owns persistence, bookmark resolve/start/stop, and active path resolution; pure helpers live in `DestinationWriteTarget.swift`; `ContentView` wires the chip/menu UI, settings rail, resolve/bind, and journal reload on switch.
- Missing or unreadable destinations soft-fail: the name stays in the menu, History is empty, no crash.

**New note capture lifecycle**:
- A capture starts only when the blank, unbound canvas receives non-whitespace text. Date captures autosave directly to their final timestamp filename; Title captures autosave to a hidden `.quicknote-capture-[UUID].md` draft.
- Selecting a saved History entry binds the editor to that file. Subsequent edits, including clearing all text, must save that selected file and must not start a new capture.
- A live capture finalizes before selecting History, switching or adding destinations, applying destination settings, creating a New Note, closing the window, or terminating the app.
- Empty live captures are deleted. A nonempty Title capture is renamed from its hidden draft to a sanitized first-paragraph filename (80 characters maximum), with a timestamp fallback and `-2`, `-3`, etc. collision suffixes.
- Journal loading recovers orphaned title drafts (for example after Force Quit) into normal History files using the same title rules and deletes whitespace-only orphans. A process-wide, destination-path-scoped registry protects live drafts in every window until finalization, discard, or view teardown; unreadable drafts remain on disk for a later retry.
- Finalization must run while the capture's destination is still active because autosave, draft cleanup, and title renaming all resolve against the active destination directory.

**Location** (active destination root):

**Text Entries**:
- Format: Markdown (.md)
- Naming depends on destination mode. New note uses `yyyy-MM-dd-HH-mm-ss.md` or a sanitized first-paragraph title; Rolling uses its DateFormatter pattern; Existing uses the selected filename. Legacy canonical `[UUID]-[timestamp].md` files remain readable.
- Content: Plain UTF-8 text
- Examples: `2026-02-20-08-01-04.md`, `Ideas for the launch.md`

**Video Entries**:
- Format: QuickTime Movie (.mov)
- Naming: `[UUID]-[YYYY-MM-DD-HH-mm-ss].mov`
- Metadata: Corresponding `.md` file with "Video Entry" text in the active destination root
- Storage layout: `[active-destination]/Videos/[UUID]-[YYYY-MM-DD-HH-mm-ss]/`
- Directory contents:
  - `[UUID]-[YYYY-MM-DD-HH-mm-ss].mov`
  - `thumbnail.jpg`
  - `transcript.md` (optional; speech transcript for that recording)
- Example directory: `~/Documents/Quick Note/Videos/[6910BBDE-75FC-415C-ABB9-C76644B037B2]-[2026-02-20-08-01-04]/`

## Key Components

### ContentView.swift

The main view containing all UI and business logic.

#### State Variables (Selection)

```swift
@State private var entries: [HumanEntry] = []           // All loaded entries
@State private var text: String = ""                    // Current text editor content
@State private var selectedEntryId: UUID? = nil         // Currently selected entry
@State private var currentVideoURL: URL? = nil          // Video playback URL
@State private var showingSidebar = false               // History sidebar visibility
@State private var colorScheme: ColorScheme = .light    // Light/dark theme
@State private var timerIsRunning = false               // Timer state
@State private var timeRemaining: Int = 900             // Timer (seconds)
@State private var backspaceDisabled = false            // Backspace lock
```

#### Core Functions

**Entry Management**:
- `loadExistingEntries()` - Loads Markdown entries and resolves associated video files
- `createNewEntry()` - Creates new text entry
- `saveEntry(entry:)` - Saves text to .md file
- `loadEntry(entry:)` - Loads text or video for display
- `deleteEntry(entry:)` - Moves the note and associated video assets to macOS Trash via `HistoryTrash`, retaining original/resulting URLs. An eight-second “Moved to Trash” banner restores files and the History row with Undo; switching destinations clears the affordance. Undo reselects/reloads a note that was selected before deletion, including an Existing target. Deleting the last selected entry leaves a blank, unbound canvas in every mode without creating a replacement file. If typing recreates the target before Undo, its user content is never overwritten. Restored Title drafts are finalized directly to unique visible title filenames rather than left hidden.

**Important**: When modifying the `entries` array from async contexts, wrap in `DispatchQueue.main.async` to prevent collection mutation crashes.

### VideoPlayerView.swift

Simple AVKit-based video player for playback.

```swift
struct VideoPlayerView: View {
    let videoURL: URL
    @State private var player: AVPlayer?
}
```

## UI Layout

### Main Interface

```
┌─────────────────────────────────────────────────────────┐
│                                                         │
│                    Text Editor Area                     │
│              (or Video Player if video)                 │
│                                                         │
├─────────────────────────────────────────────────────────┤
│  Bottom Nav Bar:                                        │
│  [Destination]                                          │
│     [New Note] • [Theme] • [History]                    │
└─────────────────────────────────────────────────────────┘
```

### Sidebar (History)

```
┌──────────────┐
│   History    │
├──────────────┤
│ 📹 Video...  │ ← Video entry with thumbnail
│ Feb 20       │
├──────────────┤
│ Ideas for... │ ← First line as title (tail-truncated)
│ Feb 19, 9:41 AM │ ← Day plus time
├──────────────┤
│ Another ...  │
│ Feb 18       │
└──────────────┘
```

## Navigation Bar Items

### Left Side
- **Destination**: Shows the active save destination and opens its menu.
- **Copy Transcript**: Appears alongside the destination when viewing a video with a transcript.

### Right Side (Utilities)
- **Timer**: Shows time remaining, click to start/stop, double-click to reset
- **Chat**: Opens AI chat menu (ChatGPT/Claude integration)
- **Backspace Toggle**: Enable/disable backspace key
- **Fullscreen**: Toggle fullscreen mode
- **New Note**: Finalizes the active New note capture and returns to a blank canvas; Rolling / Existing append a timestamped session separator. A successful nonempty finalization or separator write shows “Saved to <destination name>” above the bottom nav for about two seconds, then fades. Empty canvases and failed writes show no confirmation. The label uses the nav’s muted 13px styling without extra chrome; write/rename success propagates to the confirmation decision.
- **Theme Toggle**: 🌙/☀️ for dark/light mode
- **History**: 🕐 Shows/hides sidebar

### Keyboard Shortcuts

- **Cmd+N**: New Note, using `createNewEntry()` just like the bottom-nav button (not a new window).
- **Cmd+Shift+H**: Opens History via `openHistorySidebar()`, preserving the unsaved destination-settings confirmation; does not close History if already open.
- **Cmd+,**: Opens the active destination settings rail via `openDestinationSettings()`; does not reset unsaved edits if already open.
- `EditorCommands` is attached to the app scene with `.commands`; it replaces `.newItem` and `.appSettings` to avoid duplicate shortcuts. `ContentView` publishes `EditorCommandActions` with `.focusedSceneValue`, so commands target only the focused window and are disabled without one.

## Video Playback Flow

1. User clicks video entry in sidebar
2. `loadEntry(entry:)` checks `entry.entryType`
3. If `.video`:
   - Sets `currentVideoURL` to video file path
   - Clears `text`
4. Main view checks `if let videoURL = currentVideoURL`
5. Shows `VideoPlayerView(videoURL:)` instead of TextEditor
6. Video auto-plays with the stored mute and volume settings; a saved transcript can be copied from the bottom nav

## Quick capture (global hotkey + menu bar)

- ⌃⌥⌘N uses Carbon hotkey registration (no Accessibility permission); the menu-bar pencil also offers Quick Capture, Show Window, and Quit.
- Main-actor `QuickCaptureCenter` activates and restores the key registered editor (or another editor). With all windows closed it opens WindowGroup `main` through the menu label's SwiftUI openWindow action; the new editor consumes one pending capture request after appearing.
- Quick capture reuses `createNewEntry()` and existing destination/autosave behavior, closes History and clean settings, preserves dirty settings, and focuses the native text editor.
- `QuickCapture.swift` and its tests belong to file-system-synchronized Xcode groups; no manual project file entries are needed.
- Before capture, native editor input is suspended and first responder resigned; capture runs before raising the window. Input resumes only after the SwiftUI editor update applies the new capture text, preventing immediate typing from copying stale native text into the new note.

## Entry Loading Logic

On app launch or destination reload:

1. `loadExistingEntries()` reads root-level `.md` files from the active destination, excluding hidden capture drafts.
2. Canonical legacy filenames retain their embedded UUID and timestamp; other filenames receive a stable UUID derived from their full path and use file modification time for sorting/display.
3. Video metadata resolves assets from the current per-entry directory and legacy video layouts.
4. Entries sort newest first.
5. Rolling / Existing bind the editor to their resolved write target.
6. New note clears selection and presents a fresh, unbound canvas. It does not create a file until the user types non-whitespace content.

Markdown that cannot be decoded as UTF-8 appears in History by filename. Failing to read a note shows an alert and does not bind the editor to it. If a configured Rolling / Existing note fails to open and no other note is selected, the canvas shows a message instead of accepting edits that cannot be saved.

## Auto-Save Behavior

Text is auto-saved on every change. Routing depends on editor state:

```swift
.onChange(of: text) { _ in
    // 1. Save the live New note capture when one exists.
    // 2. Otherwise save the selected History / Rolling / Existing entry.
    // 3. Only an unbound, nonempty New note canvas starts a new capture.
}
```

The selected-entry check must precede starting a capture so historical edits—including clearing a note—persist to the selected file rather than creating a duplicate.

`NoteSaveState` tracks the last loaded/saved editor content by file URL. All `saveEntry` paths (including termination) write only when that content changed locally; otherwise they read the disk content back into the editor. Loaded legacy newline normalization is recorded as the baseline, not treated as a user edit. Failed reads/writes leave the baseline unchanged, and a changed edit can create a missing file but cannot replace an unreadable file. Simultaneous local and external edits still use the local edit when the file is readable; this is not conflict merging. Opening or leaving a History note without editing does not change its modification time. Non-canonical History rows display that time.

An unbound Rolling / Existing canvas resolves and creates its configured target on the next non-whitespace edit, then binds and saves that edit without reloading the editor. Deleting the last selected History entry clears the canvas without recreating the file or appending a separator; typing again recreates the current period's file / configured Existing note. Empty edits do not recreate deleted files. Missing Existing notes on launch remain unbound until typing or picking a note.

If the unbound target already contains text (for example, restored from Trash), its contents are preserved and the canvas text is appended on a new line; the merged text becomes the editor contents. A read failure leaves the canvas unbound and does not overwrite the target.

## Permissions

Required entitlements in `freewrite.entitlements`:

```xml
<key>com.apple.security.app-sandbox</key>
<true/>
<key>com.apple.security.files.user-selected.read-write</key>
<true/>
<key>com.apple.security.files.bookmarks.app-scope</key>
<true/>
```

Quick Note does not request access to the camera, microphone, or speech recognition. Playing existing videos and copying stored transcripts only reads files.

## Technical Nuances & Implementation Details

### Threading Model

The app uses a **hybrid threading approach**:

1. **Main Thread**: All UI updates and `@State` mutations
2. **Global Queue**: File I/O operations (reading/writing markdown files)

**Critical Threading Issue**:
SwiftUI's `ForEach` creates an enumerator over the `entries` array. If you modify this array (insert, remove, replace) while the enumerator is active, you get `NSGenericException: Collection was mutated while being enumerated`.

**Solution Pattern**:
```swift
// When in a DispatchQueue callback:
DispatchQueue.main.async {
    self.entries.insert(newEntry, at: 0)  // Safe
}

// When in loadExistingEntries:
let loadedEntries = mdFiles.compactMap { ... }  // Work on local copy
entries = loadedEntries  // Assign once to @State
// Now safe to check entries.contains, entries.first, etc.
```

### File System Architecture

**Why UUID + Timestamp Naming?**

The filename format `[UUID]-[YYYY-MM-DD-HH-mm-ss].md` serves multiple purposes:

1. **UUID**: Ensures global uniqueness even if multiple devices sync to same folder
2. **Timestamp**: Human-readable sorting in Finder without opening files
3. **Brackets**: Makes regex extraction reliable: `\\[(.*?)\\]` and `\\[(\\d{4}-\\d{2}-\\d{2}-\\d{2}-\\d{2}-\\d{2})\\]`

**File Loading Algorithm**:

```swift
// 1. Get all files
let fileURLs = try fileManager.contentsOfDirectory(at: documentsDirectory, ...)
let mdFiles = fileURLs.filter { $0.pathExtension == "md" }

// 2. Parse each .md file
let entriesWithDates = mdFiles.compactMap { fileURL -> (entry, date, content)? in
    // Extract UUID from filename using regex
    let uuidMatch = filename.range(of: "\\[(.*?)\\]", options: .regularExpression)
    let uuid = UUID(uuidString: String(filename[uuidMatch].dropFirst().dropLast()))

    // Extract timestamp
    let dateMatch = filename.range(of: "\\[(\\d{4}-\\d{2}-\\d{2}-\\d{2}-\\d{2}-\\d{2})\\]", ...)
    let dateString = String(filename[dateMatch].dropFirst().dropLast())

    // Parse date for sorting
    dateFormatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
    let fileDate = dateFormatter.date(from: dateString)

    // Check for corresponding video
    let videoFilename = filename.replacingOccurrences(of: ".md", with: ".mov")
    let hasVideo = hasVideoAsset(for: videoFilename) // checks current + legacy locations

    // Read content for preview
    let content = try String(contentsOf: fileURL, encoding: .utf8)
    let preview = content.replacingOccurrences(of: "\n", with: " ")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
    let truncated = preview.isEmpty ? "" : String(preview.prefix(30)) + "..."

    return (entry: HumanEntry(...), date: fileDate, content: content)
}

// 3. Sort by actual date (not display date)
entries = entriesWithDates
    .sorted { $0.date > $1.date }  // Newest first
    .map { $0.entry }
```

**Why separate .md and .mov files instead of embedding?**

- User can open .md files in any text editor
- Video files can be played in QuickTime independently
- Easier to backup/sync text separately from large video files
- Transparent file format for user ownership
- Per-entry video directories keep each recording's media + thumbnail together

### Auto-Save State Machine

The app implements **continuous auto-save** with debouncing:

```swift
.onChange(of: text) { _ in
    if let currentId = selectedEntryId,
       let currentEntry = entries.first(where: { $0.id == currentId }) {
        saveEntry(entry: currentEntry)
    }
}
```

**State Transitions**:
1. User types character → `text` state updates
2. `.onChange` fires immediately
3. `saveEntry()` writes to disk synchronously (fast on SSD)
4. No loading spinner needed (happens in <10ms)

**Edge Case**: What if user switches entries before save completes?

```swift
Button(action: {
    if selectedEntryId != entry.id {
        // Save current entry BEFORE switching
        if let currentId = selectedEntryId,
           let currentEntry = entries.first(where: { $0.id == currentId }) {
            saveEntry(entry: currentEntry)
        }

        selectedEntryId = entry.id
        loadEntry(entry: entry)
    }
})
```

This ensures no data loss on rapid entry switching.

### Timer Implementation Details

The timer is **not a countdown** - it's a visual focus tool:

```swift
@State private var timeRemaining: Int = 900  // 15 minutes default
@State private var timerIsRunning = false

let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

.onReceive(timer) { _ in
    if timerIsRunning && timeRemaining > 0 {
        timeRemaining -= 1
    } else if timeRemaining == 0 {
        timerIsRunning = false
        // Show bottom nav again when timer expires
        bottomNavOpacity = 1.0
    }
}
```

**UI Behavior During Timer**:
- When timer starts: Bottom nav fades out after 1 second
- While running: Nav only appears on hover
- When timer ends: Nav fades back in

This creates **immersion** - the UI disappears, leaving only text and timer.

**Timer Adjustment**:
- Scroll wheel over timer: Adjust in 5-minute increments
- Click: Start/pause
- Double-click: Reset to 15 minutes

```swift
NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
    if isHoveringTimer {
        let scrollBuffer = event.deltaY * 0.25
        if abs(scrollBuffer) >= 0.1 {
            let currentMinutes = timeRemaining / 60
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, ...)
            let direction = -scrollBuffer > 0 ? 5 : -5
            let newMinutes = currentMinutes + direction
            let roundedMinutes = (newMinutes / 5) * 5
            timeRemaining = roundedMinutes * 60
        }
    }
    return event
}
```

### Backspace Disable Mechanism

**Implementation**:
```swift
@State private var backspaceDisabled = false

NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
    if backspaceDisabled && (event.keyCode == 51 || event.keyCode == 117) {
        return nil  // Swallow the event
    }
    return event
}
```

**macOS Key Codes**:
- 51: Delete/Backspace key
- 117: Forward delete (fn+delete)

**Why this matters**: Forces users to write without editing, embracing imperfection and maintaining flow state.

### Video Thumbnail Generation Nuances

```swift
func generateVideoThumbnail(from url: URL) -> NSImage? {
    let asset = AVAsset(url: url)
    let imageGenerator = AVAssetImageGenerator(asset: asset)
    imageGenerator.appliesPreferredTrackTransform = true  // CRITICAL

    let cgImage = try imageGenerator.copyCGImage(at: CMTime(seconds: 0, preferredTimescale: 1), ...)
    return NSImage(cgImage: cgImage, size: NSSize(...))
}
```

**`appliesPreferredTrackTransform = true`**:

Videos recorded on front-facing camera are often rotated 90°. The video file contains a transform matrix that says "rotate this video when playing." Without `appliesPreferredTrackTransform`, the thumbnail would be sideways.

**Performance Note**: Sidebar rows load `thumbnail.jpg` from the per-entry directory. If a saved entry has no thumbnail, the app generates one from the existing movie and tries to persist it for future loads.

### Text Editor Header Behavior

Every entry starts with `\n\n` (two newlines):

```swift
TextEditor(text: Binding(
    get: { text },
    set: { newValue in
        if !newValue.hasPrefix("\n\n") {
            text = "\n\n" + newValue.trimmingCharacters(in: .newlines)
        } else {
            text = newValue
        }
    }
))
```

**Why?** Creates visual breathing room at top of page. All entries look like they start mid-page, not cramped at the top edge.

### Entry Creation Logic

**Complex Decision Tree**:

```swift
if entries.isEmpty {
    // First time user → create welcome entry
    createNewEntry()
} else if !hasEmptyEntryToday && !hasOnlyWelcomeEntry {
    // No empty entry for today → create new entry
    createNewEntry()
} else {
    // Select most recent empty entry from today
    if let todayEntry = entries.first(where: { isFromTodayAndEmpty }) {
        selectedEntryId = todayEntry.id
        loadEntry(entry: todayEntry)
    } else if hasOnlyWelcomeEntry {
        // Only have welcome entry → select it
        selectedEntryId = entries[0].id
        loadEntry(entry: entries[0])
    }
}
```

**Date Comparison Complexity**:

Display dates are "MMM d" (e.g., "Feb 20") without year. To check "is this from today?":

```swift
let dateFormatter = DateFormatter()
dateFormatter.dateFormat = "MMM d"
if let entryDate = dateFormatter.date(from: entry.date) {
    // entryDate is now "Feb 20" in year 1 (default year)
    // Need to add current year to compare
    var components = calendar.dateComponents([.year, .month, .day], from: entryDate)
    components.year = calendar.component(.year, from: Date())

    if let entryDateWithYear = calendar.date(from: components) {
        let entryDayStart = calendar.startOfDay(for: entryDateWithYear)
        let todayStart = calendar.startOfDay(for: Date())
        return calendar.isDate(entryDayStart, inSameDayAs: todayStart)
    }
}
```

This handles edge cases like February 29th on non-leap years.

### Font System

The body uses Lato Regular at a fixed 16px with a system font fallback. `FreewriteTextEditor.bodyFontSize` also sets the placeholder size and the line-spacing calculation.

### Line Spacing Calculation

```swift
var lineHeight: CGFloat {
    let fontSize = FreewriteTextEditor.bodyFontSize
    let font = NSFont(name: selectedFont, size: fontSize) ?? .systemFont(ofSize: fontSize)
    let defaultLineHeight = getLineHeight(font: font)
    return (fontSize * 1.5) - defaultLineHeight
}

func getLineHeight(font: NSFont) -> CGFloat {
    return font.ascender - font.descender + font.leading
}
```

**Formula**: Target line height is 1.5× font size. Subtract natural line height to get spacing to add.

At 16px, the target line height is 24px.

This creates **generous vertical rhythm** for readability during long writing sessions.

### Chat Integration

**Prompts**:
```swift
let aiChatPrompt = "You are a writing coach. Help me understand what I wrote below and ask me questions about it:\n\n"
let claudePrompt = "You are a thoughtful writing partner. Read what I wrote and help me explore the ideas further:\n\n"
```

**URL Encoding**:
```swift
let fullText = aiChatPrompt + "\n\n" + trimmedText
if let encodedText = fullText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
   let url = URL(string: "https://chat.openai.com/?prompt=" + encodedText) {
    NSWorkspace.shared.open(url)
}
```

**Length Handling**:
- URLs >6000 chars fail in some browsers
- If too long, shows "Copy Prompt" button instead
- Copies to clipboard for manual paste

### Theme System

```swift
@State private var colorScheme: ColorScheme = .light

// Apply to entire window
.preferredColorScheme(colorScheme)

// Persisted to UserDefaults
UserDefaults.standard.set(colorScheme == .light ? "light" : "dark", forKey: "colorScheme")
```

**Colors**:
- Light mode text: `Color(red: 0.20, green: 0.20, blue: 0.20)` (dark gray, not black, easier on eyes)
- Dark mode text: `Color(red: 0.9, green: 0.9, blue: 0.9)` (off-white, not pure white)

## Common Pitfalls

### Collection Mutation Crashes

**Problem**: Modifying `entries` array while SwiftUI is enumerating it.

**Solution**:
```swift
// BAD
entries.insert(newEntry, at: 0)

// GOOD (from async context)
DispatchQueue.main.async {
    self.entries.insert(newEntry, at: 0)
}
```

### File Path Issues

Always use absolute paths:
```swift
let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("Quick Note")
let fileURL = documentsDirectory.appendingPathComponent(filename)
```

## Build Configuration

**Scheme**: freewrite
**Product**: `Quick Note.app` (`PRODUCT_NAME = "Quick Note"`, which sets the menu bar and About name; `PRODUCT_MODULE_NAME = freewrite` keeps `@testable import freewrite`; bundle id stays `app.humansongs.freewrite` so the sandbox container and preferences carry over)
**Configuration**: Debug or Release
**Build Command**:
```bash
xcodebuild -project freewrite.xcodeproj -scheme freewrite -configuration Debug build
```

**Clean Build**:
```bash
xcodebuild -project freewrite.xcodeproj -scheme freewrite -configuration Debug clean build
```

## Testing Existing Video Playback

1. Open a journal containing an existing video entry and show History.
2. Verify the video row displays a thumbnail, including when the entry has no cached thumbnail.
3. Select the row to verify playback. If `transcript.md` is present, use **Copy Transcript** and check the clipboard.

## Video Thumbnail Generation

```swift
func generateVideoThumbnail(from url: URL) -> NSImage? {
    let asset = AVAsset(url: url)
    let imageGenerator = AVAssetImageGenerator(asset: asset)
    imageGenerator.appliesPreferredTrackTransform = true

    let cgImage = try imageGenerator.copyCGImage(at: CMTime(seconds: 0, preferredTimescale: 1), actualTime: nil)
    return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
}
```

The sidebar loads the cached thumbnail, or generates and stores one if it is missing.

## Feature Flags / Settings

Stored in `UserDefaults`:
- `colorScheme`: "light" or "dark"

Other settings are session-only (not persisted):
- Timer duration, backspace state

## Future Development Notes

### Adding New Entry Types

1. Add case to `EntryType` enum
2. Update `HumanEntry` with relevant properties
3. Modify `loadExistingEntries()` to detect new file type
4. Update `loadEntry()` to handle new type
5. Add UI in main view for new entry type
6. Update `deleteEntry()` to clean up new file types

### Adding New Navigation Items

Add to bottom nav in ContentView.swift around line 500-950:

```swift
Text("•")
    .foregroundColor(.gray)

Button(action: {
    // Your action
}) {
    Image(systemName: "icon.name") // or Text("Label")
        .foregroundColor(isHovering ? textHoverColor : textColor)
}
.buttonStyle(.plain)
.onHover { hovering in
    isHovering = hovering
    isHoveringBottomNav = hovering
    if hovering {
        NSCursor.pointingHand.push()
    } else {
        NSCursor.pop()
    }
}
```

## Debugging

Enable console output in Xcode to see:
- File loading: "Processing: [filename]"
- Video playback: "Successfully loaded video entry: [filename]"

Check `~/Documents/Quick Note/` in Finder to verify files are being created.

## Code Organization

- **Lines 1-130**: Imports, models, state variables
- **Lines 130-430**: Computed properties and helpers
- **Lines 430-1200**: Main view body and UI
- **Lines 1200-1400**: Helper functions (save, load, delete, etc.)

## Native Text Editor and Scrolling

`FreewriteTextEditor` is an `NSViewRepresentable` that owns the editor's `NSScrollView` and `NSTextView`; it replaces the former SwiftUI `TextEditor`. Its coordinator is the bridge between AppKit and the entry state:

1. `NSTextViewDelegate.textDidChange` writes user edits to the bound `text`; the view-level `onChange` then performs the normal auto-save.
2. `updateNSView` applies typography, colors, insets, and incoming text. When the incoming text differs (for example, after switching entries), it replaces the text storage while `isUpdatingText` suppresses the delegate callback, clamps the existing selection, and clears the undo manager. Clearing undo is required so an Undo action from one entry cannot modify another entry.
3. The coordinator observes the scroll view's bounds and derives `EditorScrollMetrics` from the text layout. It publishes those metrics asynchronously to avoid mutating SwiftUI state during AppKit layout.

The scroll view's built-in vertical scroller remains hidden. `NativeEditorEdgeScroller` renders the separate native `NSScroller` at the editor edge, maps its knob position to a fractional `EditorScrollRequest`, and the editor coordinator applies that request to the scroll view. Keep both directions of this metrics/request pipeline intact when changing editor layout or scrolling behavior.

## Key SwiftUI Patterns Used

- `@State` for local view state
- `.onChange(of:)` for auto-save
- `.onAppear` for initialization
- `ForEach(entries)` with `Identifiable` for list rendering
- Conditional views: `if currentVideoURL != nil { VideoPlayerView } else { FreewriteTextEditor }`

## Summary

Quick Note is a local-first macOS writing app that also plays existing video entries. The main complexity is in:

1. Proper file management and UUID-based naming
2. Thread-safe array mutations for entries
3. Compatibility with legacy video layouts and conditional rendering between text and video content

When making changes, always:
- When changing History or media code, test with an existing video entry
- Check for collection mutation crashes
- Verify files are created in correct location
- Ensure privacy permissions are properly configured

## Design Context

Design direction is captured in `PRODUCT.md`, `DESIGN.md`, and `.impeccable.md`. The visual system ("The Quiet Page") is **strictly monochrome, ink-only** — identity lives in typography and whitespace, never in accent color.

### Users
Distraction-free writers and journalers who want to capture thoughts the moment they happen, without ceremony. They free-write and revisit entries later, including existing video notes. The tool should stay out of the way so the thinking stays theirs.

### Brand Personality
Fast, light, frictionless. Calm, minimal, human. The voice is a friend, not a tool or a therapist — warm, direct, slightly casual, never clinical, never corporate. The interface is quiet and nearly invisible so the writing is the only thing on screen.

### Aesthetic Direction
Minimal and calm by default — the UI's job is to disappear during timed writing sessions, leaving only the text (or video). No dense panels, no feature-soup chrome, nothing that reads as default/stock.
- Theme: both light and dark, user-switchable and persisted; neither is the "default default."
- Anti-references: not a cluttered Notion-style tool; not generic Notes.app; not a slick dark developer tool.
- Native SwiftUI/macOS app — design must feel at home on the platform, not like a ported web UI.

### Design Principles
- **Get out of the way.** The interface's job is to disappear. Most UI hides during timed sessions; the text (or video) is the whole point.
- **Practice what you preach.** The app itself should feel as frictionless as the writing it enables — no dialogs, no setup, auto-everything.
- **Start instantly.** Open the app and you're already writing today's entry; no blank "new document" gate.
- **Human over clinical.** Tone and detail should read as a friend's helping hand — comfort, validation, warmth — not a sterile product.
- **Local-first ownership.** Every thought lives in a plain file the user can open; transparency and control over cleverness.

### Visual Guardrails (from DESIGN.md)
- **The One Ink Rule.** No accent or brand color, ever — strictly black / white / gray / their transparencies.
- **The Flat-By-Default Rule.** Flat surfaces; one whisper shadow (`rgba(0,0,0,0.10)` @ 4px) reserved for floating popovers only.
- **The One Voice Rule.** System chrome always speaks in the native system sans; the writer's words may use Lato / Arial / System / Serif / random.
- Body ink: `#333333` (light) / `#E6E6E6` (dark). Selection/hover fills: gray at 10% / 5%. Editor fills the window with a fixed 18px inset on all four sides, 1.5× line height.
