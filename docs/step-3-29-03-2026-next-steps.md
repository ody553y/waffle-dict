# Step 3 — Next Steps for Codex
**Date:** 29/03/2026

## Update Before These Next Steps

Since this document was first written, the project has moved forward beyond the original Step 3 scope. I completed the work that wired the main dictation flow together, including the menu bar recording/transcription states, paste and clipboard behavior, shared dictation control, the floating dictation panel, the global hotkey scaffolding, and the first pass of model management in settings. That model work included a bundled model manifest, install-state detection, selected-model resolution, download plumbing, and the supporting Swift tests.

While pushing those changes, GitHub rejected the branch because generated local build artifacts under `.build/` had accidentally been committed, including a file over GitHub's 100 MB limit. I fixed that by removing tracked generated files from Git, adding `.gitignore` entries for `.build/`, local Xcode user data, and other machine-specific files, rerunning the Swift and Python verification steps, and recommitting only the real source changes. The cleaned commit was then pushed successfully.

I intentionally left the follow-up Parakeet spike files and newer planning docs out of that cleanup commit so they could be handled separately and not get mixed into the hotkey/model-management work.

## Current State Summary

We're at the **end of Phase 0 / beginning of Phase 1**. The foundation is solid:

- **Spike 3 (IPC):** Complete — Swift spawns Python worker, polls `/health`, sends transcription requests over local HTTP.
- **Swift app:** Menu bar UI with worker status, start/stop recording, settings shell. Compiles cleanly.
- **Python worker:** HTTP server with `/health` and `/transcriptions/file` endpoints, FasterWhisperBackend with lazy model loading.
- **Audio capture:** Records 16kHz mono WAV to crash-safe scratch directory.
- **Permissions:** Accessibility and Microphone checks implemented.
- **Tests:** 3 Swift tests (WorkerClient), 3 Python tests (server endpoints). All pass.
- **MVP design doc:** Written and scoped — record → transcribe → clipboard → paste.

**What's NOT wired up yet:** The end-to-end flow. Recording stops but doesn't trigger transcription. Transcription results don't flow to clipboard. No paste helper exists.

---

## Codex Task Sequence

Each task below is a self-contained unit of work. Tasks are ordered by dependency — later tasks build on earlier ones. Each should be committed separately.

### Task 1: Build the Paste Helper
**Target:** `Sources/ScreamerCore/PasteHelper.swift`

Create a new `PasteHelper` in ScreamerCore that:
- Writes a given string to `NSPasteboard.general`
- Checks Accessibility permission via `PermissionsService`
- If granted, synthesises `Cmd+V` via `CGEvent` to paste into the active app
- Returns a structured result enum: `.pastedAndCopied`, `.copiedOnly`, `.copyFailed`
- Must be testable with injected side effects (protocol for pasteboard + event posting)

**Tests:** `Tests/ScreamerCoreTests/PasteHelperTests.swift`
- Accessibility granted → paste succeeds
- Accessibility missing → clipboard-only
- Clipboard write failure → `.copyFailed`
- Paste event failure after successful copy → `.copiedOnly`

**Acceptance:** `swift build` passes. Tests compile (run requires Xcode).

---

### Task 2: Wire the End-to-End MVP Flow in MenuBarView
**Target:** `Sources/ScreamerApp/MenuBarView.swift`

Update MenuBarView to coordinate the full dictation flow:

1. Add state enum: `idle`, `recording`, `transcribing`, `success(String)`, `error(String)`
2. On "Stop Recording":
   - Call `AudioCaptureService.stopRecording()` to get the WAV file URL
   - Transition to `.transcribing` state
   - Call `WorkerClient.transcribeFile()` with a fixed model ID (e.g. `"small"`)
   - On success: invoke `PasteHelper`, transition to `.success(transcript)`
   - On failure: transition to `.error(message)`, keep the scratch file
3. Show transcript text or error message in the popover
4. Show appropriate UI for each state (recording indicator, spinner, result text)

**Dependencies:** Task 1 (PasteHelper)

**Acceptance:** The full record → transcribe → clipboard → paste flow works when the app is built and run manually with `faster-whisper` installed.

---

### Task 3: Handle Microphone Permission in the Recording Flow
**Target:** `Sources/ScreamerApp/MenuBarView.swift`, `Sources/ScreamerCore/AudioCaptureService.swift`

Currently the recording start doesn't check microphone permission status. Wire it up:

1. Before starting recording, check `AVCaptureDevice.authorizationStatus(for: .audio)`
2. If `.notDetermined`, request permission and only proceed on grant
3. If `.denied` or `.restricted`, show a clear blocked message in the UI with a link to System Settings
4. Do not attempt to start recording when permission is missing

**Acceptance:** First-time recording triggers the system permission dialog. Denied state shows a clear message.

---

### Task 4: Accessibility Permission Prompt on First Paste
**Target:** `Sources/ScreamerCore/PasteHelper.swift`, `Sources/ScreamerApp/MenuBarView.swift`

When the first transcription completes and Accessibility is not granted:

1. PasteHelper returns `.copiedOnly`
2. MenuBarView shows a one-time prompt explaining why Accessibility is needed
3. Include a button/link to open System Settings → Privacy & Security → Accessibility
4. After dismissal, don't show again (store in UserDefaults)
5. Future transcriptions silently fall back to clipboard-only until permission is granted

**Dependencies:** Task 2

**Acceptance:** First paste without Accessibility shows the prompt. Subsequent pastes silently copy to clipboard.

---

### Task 5: Worker File Transcription Endpoint — Robustness
**Target:** `worker/screamer_worker/server.py`, `worker/tests/test_server.py`

Harden the `/transcriptions/file` endpoint:

1. Return proper error JSON when the audio file doesn't exist (404)
2. Return proper error JSON when the model fails to load (503)
3. Return proper error JSON for malformed request bodies (400)
4. Add a `Content-Length` limit to reject absurdly large request bodies
5. Log transcription duration to stdout

**Tests:** Add Python tests for each error case.

**Acceptance:** All Python tests pass. Error responses are structured JSON with `error` and `detail` fields.

---

### Task 6: Worker Health — Report Model Readiness
**Target:** `worker/screamer_worker/server.py`, `worker/screamer_worker/models.py`

Extend `/health` to report whether a model is loaded and ready:

1. Add `model_loaded: bool` and `model_id: str | null` to the health response
2. Swift side: update `WorkerHealth` struct to decode these new fields
3. MenuBarView: show "Model loading..." state when worker is healthy but model isn't ready

**Tests:** Update Swift and Python health tests.

**Acceptance:** Health endpoint reports model status. Swift decodes it correctly. Tests pass.

---

### Task 7: Transcription Result Display Polish
**Target:** `Sources/ScreamerApp/MenuBarView.swift`

Improve the post-transcription UI:

1. Show the transcript text in the popover (scrollable, selectable, max ~200 chars with "show more")
2. Add a "Copy Again" button to re-copy to clipboard
3. Show how the result was delivered: "Pasted into app" vs "Copied to clipboard"
4. Auto-clear the result after 30 seconds or on next recording start

**Dependencies:** Task 2

**Acceptance:** User can see what was transcribed and how it was delivered.

---

## Priority Order

| Priority | Task | Effort | Blocker? |
|----------|------|--------|----------|
| P0 | Task 1 — Paste Helper | Small | Yes — needed for flow |
| P0 | Task 2 — Wire E2E Flow | Medium | Yes — the MVP |
| P1 | Task 3 — Mic Permission | Small | Yes — first-run UX |
| P1 | Task 4 — Accessibility Prompt | Small | Improves first-run UX |
| P1 | Task 5 — Worker Robustness | Small | Error handling |
| P2 | Task 6 — Health Model Status | Small | Nice to have |
| P2 | Task 7 — Result Display | Small | Polish |

---

## After These Tasks

Once all 7 tasks are done, we'll have a **working Phase 1 MVP**: record from menu bar → transcribe locally → copy/paste result. The next step document will cover:

- Global hotkey registration (Phase 1 stretch / Phase 2)
- Floating dictation panel
- GRDB transcript history
- Model catalog and downloads
- Spike 1 (Parakeet) and Spike 4 (pyannote) follow-up

---

## Notes for Codex

- **Swift version:** 6.0+ (strict concurrency). All new types must be `Sendable` where needed.
- **Test framework:** Swift Testing (`import Testing`, `@Test`, `#expect`), NOT XCTest.
- **`swift test` requires Xcode.app** — but `swift build` works with CLI Tools. Ensure tests compile.
- **Python tests:** `PYTHONPATH=worker python3 -m unittest discover -s worker/tests`
- **No external Swift packages yet.** Don't add any unless explicitly required.
- **Worker runs on `127.0.0.1:8765`.** Don't change this.
- **Fixed model ID for MVP:** Use `"small"` (faster-whisper small model). No model picker yet.
- **Keep it thin.** No history, no model management, no diarization in this step.
