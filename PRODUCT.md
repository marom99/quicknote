# Product

<!-- impeccable:product-schema 1 -->

## Platform

macos

## Users

Distraction-free writers and journalers who want to capture thoughts exactly when they happen, without ceremony. They journal by free writing, revisit past entries, and sometimes play back earlier video thoughts. Their context: often late at night or in a quiet moment, in flow, wanting the tool to get out of the way so the thinking stays theirs.

## Product Purpose

Freewrite is a distraction-free macOS writing environment built around stream-of-consciousness writing. It removes the friction between thought and capture: no save button, no "New Document" dialog, no formatting decisions — you open it and type. Everything is auto-saved locally as plain markdown files the user owns. Success looks like a user entering flow immediately and capturing more, more honestly, than they would in a heavier tool.

## Positioning

The quietest local-first freewrite surface on macOS: open the app and you are already writing today's entry, in plain files you own, with no ceremony. Neighboring notes apps ask you to manage documents, folders, or formatting first; Freewrite's mechanism is auto-everything and a near-invisible interface so the writing stays the only thing on screen.

## Operating Context

- Native macOS desktop app (SwiftUI / AppKit window chrome), typically used in a single focused window during a quiet writing session.
- Entries live under `~/Documents/Freewrite/` as plain `.md` files; video assets (when present) live under `~/Documents/Freewrite/Videos/`.
- Core loop: open → write into today's empty entry → auto-save on every change → optionally open History to revisit or delete → optionally play an existing video entry.
- Theme (light/dark) is user-switchable and persisted; writing font is currently fixed (Lato at 14px) for the session chrome/product surface as shipped.
- Site / distribution: [freewrite.io](https://www.freewrite.io/); development via Xcode (`freewrite.xcodeproj`).

## Capabilities and Constraints

**Present (confirmed):**
- Text entries with continuous auto-save to local markdown.
- Automatic daily empty entry / welcome entry on first launch.
- History sidebar (200px) with entry preview, date, delete, and Finder reveal of the Freewrite folder.
- Native window title reflecting the current entry; solid title bar matched to paper/night with a muted bottom border.
- Bottom nav: New Entry, theme toggle, History.
- Light and dark appearance, persisted in UserDefaults.
- Playback of existing video entries (AVKit), including transcript copy when a `transcript.md` is present.

**Not current product surface (do not design as if shipped):**
- In-app font size / font family switching.
- Backspace lock, focus timer, and AI chat (ChatGPT/Claude) chrome.
- In-app video recording entry from the main writing chrome (recording implementation may still exist in the codebase; it is not a confirmed user-facing capability of the current nav).

**Technical constraints:**
- Local-first; no backend.
- App sandbox with camera/mic/speech entitlements historically used for video journaling; treat recording as undecided for UX until re-exposed.
- Minimum macOS version: 14.0.

## Brand Commitments

- **Name:** Freewrite.
- **Voice:** A friend, not a tool or a therapist — warm, direct, slightly casual, never clinical, never corporate.
- **Personality:** Fast, light, frictionless. Calm, minimal, human. The interface is quiet and nearly invisible so the writing is the only thing on screen.
- **Anti-references (binding):**
  - Not a cluttered Notion-style tool — no dense panels, nested databases, or feature-soup chrome.
  - Not generic Notes.app — no stock "card list of memos" blandness; every detail should feel considered, not default.
  - Not a slick dark developer tool — warm and human, not terminal-native.

## Evidence on Hand

- Marketing / download site: [https://www.freewrite.io/](https://www.freewrite.io/)
- Open-source repository with README demo GIF (`https://i.imgur.com/2ucbtff.gif`)
- Local sample / default content: `freewrite/default.md`
- Bundled typeface: Lato (`freewrite/fonts/`)
- Design system record: `DESIGN.md` and `.impeccable/design.json` ("The Quiet Page")
- No customer testimonials, benchmarks, pricing claims, or press quotes are on hand — future work must not invent them.

## Product Principles

- **Get out of the way.** The interface's job is to disappear; the text (or video playback) is the point.
- **Practice what you preach.** The app should feel as frictionless as the writing it enables — no dialogs, no setup, auto-everything.
- **Start instantly.** Open the app and you are already writing today's entry; no blank "new document" gate.
- **Human over clinical.** Tone and detail should read as a friend's helping hand — comfort, validation, warmth — not a sterile product.
- **Local-first ownership.** Every thought lives in a plain file the user can open; transparency and control over cleverness.

## Accessibility & Inclusion

- Full dark and light modes, user-switchable and persisted.
- Soft ink on paper/night (not pure black-on-white body text) for long-session comfort; 1.5× line height on the writing surface.
- History and primary actions remain visible by default; do not gate core content behind hover-only reveals.
- No confirmed Dynamic Type / system text-size support in the current fixed 14px editor; treat broader type scaling as undecided unless reintroduced.
