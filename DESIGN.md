---
name: Freewrite
description: A distraction-free, local-first writing and video journaling app for macOS.
colors:
  ink: "#333333"
  ink-soft: "#E6E6E6"
  ink-muted: "#808080"
  paper: "#FFFFFF"
  night: "#000000"
  row-selected: "rgba(128,128,128,0.10)"
  row-hover: "rgba(128,128,128,0.05)"
  placeholder: "rgba(128,128,128,0.50)"
  border-muted-light: "rgba(128,128,128,0.20)"
  border-muted-dark: "rgba(128,128,128,0.35)"
typography:
  body:
    fontFamily: "Lato, Lato-Regular, -apple-system, sans-serif"
    fontSize: "14px"
    fontWeight: 400
    lineHeight: 1.5
    inset: "18px"
  label:
    fontFamily: "-apple-system, BlinkMacSystemFont, sans-serif"
    fontSize: "13px"
    fontWeight: 400
  label-small:
    fontFamily: "-apple-system, BlinkMacSystemFont, sans-serif"
    fontSize: "12px"
    fontWeight: 400
rounded:
  sm: "4px"
  md: "8px"
spacing:
  xs: "4px"
  sm: "8px"
  md: "16px"
  editor-inset: "18px"
  nav-vertical: "12px"
  nav-content-gap: "8px"
  sidebar-width: "200px"
components:
  nav-button:
    textColor: "{colors.ink-muted}"
    typography: "{typography.label}"
    rounded: "{rounded.md}"
    padding: "12px"
  nav-button-hover:
    textColor: "{colors.ink}"
    typography: "{typography.label}"
    rounded: "{rounded.md}"
    padding: "12px"
  sidebar-row:
    textColor: "{colors.ink}"
    rounded: "{rounded.sm}"
    height: "40px"
    padding: "8px 16px"
  sidebar-row-selected:
    backgroundColor: "{colors.row-selected}"
    textColor: "{colors.ink}"
    rounded: "{rounded.sm}"
    height: "40px"
    padding: "8px 16px"
  sidebar-row-hover:
    backgroundColor: "{colors.row-hover}"
    textColor: "{colors.ink}"
    rounded: "{rounded.sm}"
    height: "40px"
    padding: "8px 16px"
  editor:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.ink}"
    typography: "{typography.body}"
    inset: "18px"
  title-bar:
    backgroundColor: "{colors.paper}"
    height: "28px"
  bottom-nav-bar:
    backgroundColor: "{colors.paper}"
    height: "40px"
    padding: "12px"
---

# Design System: Freewrite

## Overview

**Creative North Star: "The Quiet Page"**

Freewrite's visual system is built to vanish. The product is a distraction-free writing environment — the point is that nothing on screen competes with the words (or the video) being captured. The interface reads as a nearly empty page: white in light mode, black in dark mode, with typography and whitespace carrying all the identity. There is no accent color; there is no decorative chrome; there is no competing structure. Calm, minimal, and human — the design whispers so the writing can speak.

Density is deliberately low. The editor fills the window behind a fixed 18px page inset, so the page feels open at any window size; scroll content keeps an 8px gap above the floating navigation so the last line never touches its border. The bottom navigation itself is a quiet, always-visible strip of gray text that darkens on hover, with 12px padding above and below the controls. The native title bar mirrors the same paper/night fill and carries a matching 1px muted rule at its bottom edge. Surfaces are flat at rest; the only depth is a whisper of shadow on popovers, and it appears only when a menu must float above the page.

This system explicitly rejects the cluttered Notion-style tool (dense panels, nested databases, feature-soup chrome) and the generic Notes.app (stock memo-list blandness). It equally rejects the slick dark developer tool. It is a friend's quiet desk, not a control room.

**Key Characteristics:**
- Ink-only. No color beyond black/white/gray; identity lives in typography and whitespace.
- Flat by default; depth reserved for floating menus only.
- Human-calm microcopy and a sparse, unpressured layout.
- Native macOS restraint — it should feel at home on the platform, never like a ported web UI.
- The interface's highest goal is to disappear during writing.

## Colors

A strict monochrome ramp. Identity is carried by ink and paper, never by hue. Two themes mirror each other: light (paper + soft off-black ink) and dark (night + soft off-white ink).

### Primary
- **Soft Off-Black** (#333333): The primary ink for body text in light mode. A softened near-black chosen for comfortable long-session reading — easier on the eyes than pure black.

### Neutral
- **Paper White** (#FFFFFF): The light-mode surface and editor background. Pure and untextured; the page the user writes on.
- **Night** (#000000): The dark-mode surface. True black that lets the writing and video recede into a quiet frame.
- **Soft Off-White** (#E6E6E6): Body text in dark mode. An eased white for comfortable reading against night.
- **Muted Gray** (#808080): Resting state for navigation labels, dates, and secondary information. Darkens to ink on hover.
- **Placeholder Gray** (#808080 at 50%): The empty-editor hint ("Begin writing"), deliberately faint so it never competes with real words.
- **Row Selected** (#808080 at 10%): The selected entry's background in the history sidebar.
- **Row Hover** (#808080 at 5%): The hover background for sidebar rows — nearly imperceptible, always calm.
- **Border Muted** (gray at 20% light / 35% dark): The 1px rules separating title bar and bottom nav from the page. Same opacity in both places so the frame feels balanced.

### Named Rules
**The One Ink Rule.** There is exactly one ink family. Any color that isn't black, white, gray, or a transparency of those is forbidden. Rarity of any accent is moot — there simply is none.

## Typography

**Body Font:** Lato (fallback: system sans)
**Label Font:** System (Apple SF)

**Character:** A calm, humanist pairing. Lato at a generous 1.5× line height creates easy vertical rhythm for long writing sessions; the compact system sans keeps the navigation quiet and unobtrusive. A fixed 18px page inset keeps the text off the window edges.

### Hierarchy
- **Body** (regular, 14px default, 1.5× line height): The core surface — the user's writing. Full window width, inset 18px; the bottom edge adds reserved clearance for the floating navigation.
- **Label** (regular, 13px): Navigation controls, sidebar entry previews, action buttons.
- **Label Small** (regular, 12px): Entry dates, secondary sidebar metadata, popover sublabels.
- **Display/Headline**: Intentionally absent. A writing tool has no hero headings; the writing is the only "display."

### Named Rules
**The One Voice Rule.** Every font is an option the *writer* chooses for their own words (Lato, Arial, System, Serif, or random). The system chrome itself always speaks in the native system sans — the tool's voice stays distinct from the writer's.

## Layout

The editor is full-bleed within the window content area, with a fixed **18px inset** on all sides (adjusted for NSTextView's native 5px horizontal line-fragment padding so glyphs sit exactly 18pt from the window edge). Scroll content reserves **48px** of bottom margin (40px nav height + 8px content gap) so the last line never touches the nav border.

The **bottom navigation** is a 40px-tall strip with 12px vertical padding, pinned to the window bottom. The **history sidebar** is a fixed **200px** column separated from the editor by a native `Divider`. Minimum window size is **280×200** (editor only) or **480×200** when the sidebar is open.

Density stays low: no cards, no nested panels, no column measure cap — the page breathes at any window width.

## Elevation & Depth

Flat by default. The system conveys hierarchy through ink weight and tonal layering (selection fills, divider lines), not through shadows. Depth appears in exactly one place: floating menus (popovers), which need to read as sitting above the page.

### Shadow Vocabulary
- **Menu Float** (`rgba(0,0,0,0.10)` at 4px, 2px offset): The single shadow in the system, reserved for popovers and dropdowns. Ambient, whisper-level, never structural.

### Named Rules
**The Flat-By-Default Rule.** Surfaces are flat at rest. Shadows appear only to lift a floating menu off the page — never as card decoration, never on the writing surface itself.

## Shapes

Corners are restrained. Sidebar rows and video thumbnails use a gentle **4px radius**; navigation hover targets allow **8px** rounding. Borders are **1px** rules only — used on the title bar bottom edge and the bottom nav top edge, never as card outlines or editor frames. Dividers between sidebar sections are native macOS hairlines.

## Components

### Buttons (Navigation & Actions)
- **Shape:** Invisible until hover — plain text, no border, no background.
- **Resting:** Muted Gray text (12–13px). Clickable affordance shown only by the pointer cursor.
- **Hover:** Darkens to the ink (Soft Off-Black in light mode, Soft Off-White in dark mode); pointer becomes the pointing hand.
- **Primary:** N/A. There are no filled action buttons; the app's whole posture is to avoid visual weight.
- **Separators:** Items in the bottom nav are divided by a single muted gray dot (`•`) — not pipes or rules, keeping the strip airy.

### History Sidebar Rows
- **Shape:** Gently curved (4px radius), full-width.
- **Background:** Clear at rest; Row Hover (gray/5%) on hover; Row Selected (gray/10%) when active.
- **Content:** Entry preview (13px) + date (12px) stacked; video entries show a 40px rounded thumbnail with a play overlay.
- **Hover Actions:** Trash icon fades in on hover, right-aligned; turns red on hover.
- **Shadow:** None.

### Editor
- **Style:** Borderless and backgroundless text, transparent scrollbars, full-bleed page with a fixed 18px inset; the bottom inset includes reserved clearance for the always-visible floating navigation.
- **Focus:** None — it is always focused by design; there is no frame or glow to signal editing.
- **Placeholder:** Faint Placeholder Gray hint in the empty state, removed the instant the writer types.

### Inputs / Fields
- **Style:** None present — the app avoids form-like inputs entirely in its core loop.

### Title Bar
- **Style:** Native macOS title bar (traffic lights + centered entry title) with a solid paper/night fill matching the editor. Separated from the page by a 1px muted bottom border — same gray opacity as the bottom nav (20% light / 35% dark). System separator hidden; border is a custom AppKit layer pinned to the titlebar container bottom.

### Navigation (Bottom Bar)
- **Style:** A flat strip (40px, with 12px vertical padding) at the bottom of the window, separated from the page by a 1px muted top border; content-matched background (white/black), with an 8px editor content gap above the border.
- **State:** Always visible at full opacity while writing. Focus-timer auto-hide is not part of the current product surface.
- **Treatment:** Gray text labels and icons separated by muted dots; each darkens on hover.

### Video Player
- **Style:** Standard AVKit controls. The player surface fills the content area with no chrome, so the recording is the whole experience.

## Do's and Don'ts

### Do:
- **Do** keep the writing surface utterly bare — no borders, frames, shadows, or background tint on the editor.
- **Do** use the soft ink values (#333333 light / #E6E6E6 dark) for body text over the muted gray; never read near-ink against a tinted background.
- **Do** reserve the single Menu Float shadow for popovers only.
- **Do** keep selection and hover states whisper-subtle (gray at 10% / 5%).
- **Do** protect the fixed 18px page inset and 1.5× line height for long-session comfort.
- **Do** keep the bottom nav always visible at full opacity while writing — focus-timer chrome is not part of the current surface.
- **Do** keep title bar and bottom nav borders visually paired — same 1px muted rule, same opacity values.

### Don't:
- **Don't** introduce any accent or brand color — this is strictly monochrome (ink-only).
- **Don't** build a cluttered Notion-style tool — no dense panels, nested database chrome, or feature-soup navigation.
- **Don't** ship generic Notes.app blandness — every detail must feel considered, not default.
- **Don't** go dark "developer-tool" — no terminal green/amber, no neon, no glassmorphism.
- **Don't** add card shadows, gradient text, side-stripe colored borders, or oversized radii (≥16px) anywhere.
- **Don't** gate content visibility behind a hover or reveal state — what matters must be visible by default.
