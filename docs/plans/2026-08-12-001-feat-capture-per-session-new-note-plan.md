---
title: Capture-per-Session New Note - Plan
type: feat
date: 2026-08-12
topic: capture-per-session-new-note
artifact_contract: ce-unified-plan/v1
artifact_readiness: requirements-only
product_contract_source: ce-brainstorm
---

# Capture-per-Session New Note - Plan

## Goal Capsule

- **Objective:** Reshape quicknote's default **New note** behavior so each capture is a discrete `.md` file — saved only when the user writes something, finalized when they close the app or window, with a fresh empty editor ready for the next capture.
- **Product authority:** [README.md](../../README.md) positions quicknote as fast capture vs long freewriting; [PRODUCT.md](../../PRODUCT.md) principles (auto-everything, start instantly, local-first) still apply.
- **Scope boundary:** Replaces/evolves **New note** only. **Rolling** and **Existing** destination modes are unchanged.
- **Open blockers:** None.

---

## Product Contract

### Summary

Evolve **New note** from a persistent daily journal (UUID-timestamp entries, auto-save on every keystroke, empty entries saved immediately) into a **capture-per-session** model: open → write one thought → close → file lands in the folder (if non-empty) → editor resets for the next capture.

### Problem Frame

Current **New note** behavior inherits Freewrite's journaling model: continuous autosave, today's empty entry persists across launches, and filenames are opaque `[UUID]-[timestamp].md`. For quick capture, this creates clutter (empty files), breaks Finder readability (UUID names), and keeps the user in "one ongoing document" mental model instead of "one thought, one file."

### Key Decisions

- **Replace/evolve New note** (session-settled: user chose option 1) — this is quicknote's default journal behavior, not a separate save mode.
- **One `.md` file per capture** — each capture cycle produces at most one file.
- **Filename format choice** — per destination in Destination settings:
  - **Date:** date & time locked when capture starts (e.g. `2026-08-12-10-30-00.md`)
  - **Title:** first paragraph sanitized at finalize (draft hidden file during session)
- **Empty captures are not saved** — whitespace-only content creates no file.
- **Autosave while typing** (session-settled: implementation default) — same in-progress file updates as the user types; close finalizes and resets the editor.
- **Close trigger** (session-settled: implementation default) — finalize on app quit and on window close.
- **Title filename rules** (session-settled: implementation default) — first paragraph (text before first blank line), strip `/\:*?"<>|` and control characters, max 80 characters, collision suffix `-2`, `-3`, etc.; fall back to Date basename if paragraph is empty at finalize.

### Requirements

**Capture lifecycle**

- R1. Opening quicknote presents an empty editor — no pre-created file on disk.
- R2. The first non-empty keystroke begins a capture and allocates a target filename (Date: final name immediately; Title: hidden draft until finalize).
- R3. Closing quicknote or the main window finalizes the active capture: if content is non-empty, the `.md` file is kept (Title: renamed from draft); if empty, no file remains.
- R4. After finalize, the editor is empty and ready for a new capture without requiring manual action.
- R5. **New Entry** finalizes the current capture (if any) and starts a fresh empty editor.

**Filename format**

- R6. In Destination settings for **New note** destinations, the user chooses **Date** or **Title** filename format.
- R7. **Date** format uses `yyyy-MM-dd-HH-mm-ss` as the basename.
- R8. **Title** format uses the sanitized first paragraph as the basename at finalize.

**Persistence & History**

- R9. Saved captures appear in History for that destination; hidden draft files are excluded from History.
- R10. Filename format preference persists per destination (`newNoteFilenameFormat` on `SaveDestination`).
- R11. Legacy canonical `[UUID]-[timestamp].md` entries remain visible in History.

### Key Flows

- **F1. Quick capture** — Open → type → close → file saved → reopen → empty editor.
- **F2. Empty close** — Open → don't type → close → no file created.
- **F3. Configure filename format** — Destination settings → New note → Date or Title.

### Acceptance Examples

- **AE1.** User types "Meeting notes about launch" with Title format, closes app → `Meeting notes about launch.md` appears in folder and History.
- **AE2.** User opens app, types nothing, closes → no new file in folder.
- **AE3.** User captures twice in one day with Date format → two distinct timestamped files.

### Success Criteria

- A user can capture a quick thought, close the app, and find a readable `.md` file in Finder without empty-file clutter.
- Reopening always feels like a fresh scratchpad.
- Behavior stays invisible — no save button, no "New Document" dialog.

### Scope Boundaries

**In scope**

- New note capture lifecycle, Date/Title naming, Destination settings UI, History listing (excluding drafts)

**Out of scope (v1)**

- Rolling / Existing mode changes
- Video capture in this mode
- Subfolders in filenames
