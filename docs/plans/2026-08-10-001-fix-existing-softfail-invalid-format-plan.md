---
title: Fix Existing soft-fail recreate and invalid rolling format apply
type: fix
date: 2026-08-10
topic: destination-save-mode-softfail
artifact_contract: ce-unified-plan/v1
artifact_readiness: implementation-ready
product_contract_source: ce-brainstorm
execution: code
---

# Fix Existing soft-fail recreate and invalid rolling format apply

## Goal Capsule

- **Objective:** Preserve unbound soft-fail when an Existing note path is missing, and refuse to persist invalid Rolling filename formats so the editor never loses a valid autosave target from a bad Apply.
- **Product authority:** Grilled destination-folder settings contract (Q25 soft-fail empty editor; no silent file rewrite; Rolling format basename validation).
- **Open blockers:** None.
- **Product Contract preservation:** Destination save modes stay; only failure handling is tightened.

---

## Product Contract

### Summary

Two correctness bugs in destination write binding / settings apply.

### Key Decisions

- **Missing Existing note stays unbound** (session-settled: user-approved grilled Q25; bug report valid): no `selectedEntryId` and no phantom entry that would make the first keystroke recreate the file. Rejected: selected synthetic entry with empty text.
- **Apply format requires a successful basename preview** (session-settled: user-approved; bug report valid): guard Apply (and equivalent apply paths) so invalid nonempty patterns cannot be persisted. Rejected: persist then soft-clear selection on reload.

### Requirements

- R1. When Existing mode's configured `.md` is missing on disk, bind leaves the editor empty with **no selected entry id**, so autosave does not create the file.
- R2. Apply format only calls `updateDestination` for filename format when `formattedBasename` succeeds.
- R3. Unit coverage for resolve/soft-fail stays pure-helper where possible; ContentView soft-fail selection is verified by focused logic if extractable, else manual acceptance notes.

### Scope Boundaries

**In scope:** `bindToResolvedWriteTarget` soft-fail selection; Apply format guard; tests for format validation if missing.

**Out of scope:** Re-pick UI for dead Existing paths; format auto-sanitize; rolling mid-edit live apply.

---

## Planning Contract

### Key Technical Decisions

- KTD1. Treat `!target.fileExists` after resolve (Existing: no create; Rolling: create failed) as the same unbound soft-fail as unconfigured Existing — clear selection and do not insert a selectable target entry solely for that missing path.
- KTD2. Gate Apply format with `DestinationWriteTarget.formattedBasename` for the draft format + current period (user suggestion).

### Implementation Units

#### U1. Soft-fail unbound bind

**Files:** `freewrite/ContentView.swift`

**Approach:** After resolve, if `!target.fileExists`, clear editor state with `selectedEntryId = nil` and return without selecting. Keep configured path in settings unchanged.

**Test scenarios:**

- Existing configured note deleted externally → open destination → typing does not create the file; `selectedEntryId` remains nil.
- Rolling create succeeds → still binds and may create period file (unchanged happy path).

#### U2. Guard invalid format apply

**Files:** `freewrite/ContentView.swift`

**Approach:** Guard button action before `applyActiveDestinationSettingsChange(filenameFormat:)`.

**Test scenarios:**

- Preview shows invalid → Apply leaves stored `filenameFormat` and current selection intact.
- Valid format still applies and reloads.

### Verification

- `xcodebuild … -only-testing:freewriteTests test` (existing write-target / store tests).
- Manual: missing existing note; invalid apply guard.

### Dependencies / Sequencing

U1 and U2 independent; either order.
