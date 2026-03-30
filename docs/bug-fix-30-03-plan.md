# Waffle Visibility + Settings Usability + Model Catalog Resilience Plan

## Summary
Implement a menu-bar-first UX with optional Dock/App Switcher presence, add a Dock-facing "global menu/control center" window, fix Settings clipping by making it resizable + fully scrollable, and harden model catalog loading so the Models tab remains usable even when remote TLS fails and bundled manifest signature verification fails.

## Implementation Changes

### 1) App Visibility Mode (Menu-First with Optional Dock/App Switcher)
- Add a persisted setting: `showInDockAndAppSwitcher` (default `false`).
- Add an app-level activation-policy controller:
  - `false` => `.accessory` (menu-bar-first, hidden from Cmd+Tab).
  - `true` => `.regular` (visible in Dock + Cmd+Tab).
- Apply activation policy at launch and whenever toggle changes (no restart required).
- Add toggle in **Settings > General** under a new "App Visibility" section.
- Ensure app can always reopen a primary window via `applicationShouldHandleReopen` when Dock mode is enabled.

### 2) Dock Click Behavior: Global Menu/Control Center Window
- Add a dedicated Dock-facing window scene (new "Control Center" window), using current implemented functionality only.
- Primary behavior when Dock icon is clicked (and no visible windows): open Control Center.
- Control Center contents (no new backend features):
  - Worker/model status summary.
  - Quick actions: Start/Stop Recording, Open Settings, Open History, Open Review, Import File.
  - Recent transcript list (read-only summary + open-in-history action).
  - Optional top controls for currently selected transcription model if already available in app state.
- Keep existing `MenuBarExtra` flow unchanged.

### 3) Settings Window Fixes (No Clipping, Full Scrollability)
- Replace fixed-size settings frame with resizable window constraints:
  - Use sensible min/default size (for example, min ~700x520, default ~900x620).
- Ensure every tab can scroll vertically when content exceeds viewport.
- Prevent text clipping by removing fixed-height assumptions in tab content.
- Keep existing tab structure and controls; this is a usability/layout fix, not a settings IA redesign.

### 4) Models Tab: Robust Catalog Loading + Diagnostics
- Current root issue: remote fetch fails (TLS), and bundled manifest signature verification can fail, causing empty catalog.
- Bundled manifest policy:
  - Trust bundled fallback when signature verification fails, with explicit diagnostic state.
  - Continue strict verification for remote/cached manifests.
- Add load diagnostics surfaced to UI:
  - source used (`remote`, `cache`, `bundled-verified`, `bundled-unverified`),
  - latest error context (remote/cached/bundled parsing/verifier failures).
- Models tab UX:
  - If catalog empty, show a diagnostic empty state (not silent blank list),
  - include Retry actions and source/error details,
  - include warning badge when using unverified bundled fallback.

## API / Interface Changes
- Extend model-catalog load result surface to carry diagnostic metadata (source + verification state + recoverable errors).
- Extend app state store for models with diagnostic fields consumed by Models UI.
- Add app visibility setting key and activation-policy coordinator methods.
- Add new Control Center window view + scene identifier.

## Test Plan

### Automated
- Model catalog tests:
  - bundled signed manifest with invalid signature falls back to usable bundled entries + unverified diagnostic state,
  - remote/cached invalid signatures remain rejected.
- Model store tests:
  - diagnostics propagate correctly for remote TLS failure + bundled fallback,
  - catalog source transitions are correct after refresh.
- App/UI-level tests:
  - settings visibility toggle updates activation policy state,
  - control center open/reopen behavior entry points (reopen handler path).
- Regression tests:
  - existing transcript/model/history/review flows still pass current suite.

### Manual acceptance
- Launch app with default mode:
  - menu bar present, no Dock/Cmd+Tab presence.
- Enable "Show in Dock and App Switcher":
  - app appears in Dock and Cmd+Tab immediately.
- Click Dock icon:
  - Control Center opens and quick actions work.
- Open Settings:
  - window is resizable, content scrolls in all tabs, no clipped text.
- Open Models tab under remote TLS failure:
  - list is not silently blank; diagnostic state is visible,
  - bundled fallback models are visible with warning badge when unverified.

## Assumptions / Defaults
- Default behavior remains menu-bar-first (`showInDockAndAppSwitcher = false`).
- Dock-enabled click target is the new Control Center window.
- Scope is limited to currently implemented functionality only.
- Remote TLS issue itself is not fixed in this plan; UX and fallback behavior are fixed so app remains usable.
