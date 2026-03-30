# Local-First macOS Dictation & Transcription App Plan

## Summary
- Build a direct-download macOS app that combines two workflows in one product: system-wide push-to-talk dictation and drag-drop file transcription, with all core transcription running locally.
- Match the strongest patterns from the researched apps and screenshots: sidebar preferences, downloadable model catalog, global shortcut control, history/retry/copy flows, drag-drop file import, transcript editing, speaker-aware transcripts, and optional AI summaries/chat over transcript text.
- Chosen approach: native `SwiftUI/AppKit` shell plus a bundled local inference worker. Rejected alternatives:
  - `Tauri/Electron`: easier web UI, weaker macOS integration for hotkeys, permissions, paste, menu bar, and audio device behavior.
  - `Pure Swift/CoreML only`: cleaner packaging, but too risky for Parakeet, diarization, and fast model iteration.
- Critical constraint: NVIDIA's published Parakeet v3 support currently points to NeMo on Linux/NVIDIA hardware, so the plan starts with a hard feasibility gate for Apple Silicon while still treating Parakeet as a launch requirement.

> **[Review]:** The chosen stack is sensible. Two architectural decisions that are not yet specified here but must be resolved before any code is written — the Swift↔Python IPC mechanism and the Python bundling approach — are documented in the new **Architecture Decisions** section below. Resolve those before Phase 1 begins.

---

## Architecture Decisions
> **[Review — new section, must be resolved before Phase 1]**

### Swift ↔ Python IPC
The plan says "SwiftUI/AppKit shell plus bundled local worker" but does not specify how the two processes communicate. Choose one approach and commit to it:

- **Local HTTP (recommended):** Python worker runs a lightweight HTTP server (e.g. FastAPI on a loopback port). Swift speaks to it via `URLSession`. Simple to debug, easy to version with a `/health` endpoint, works naturally with streaming via SSE or chunked responses for live preview. Downside: port management.
- **XPC Service:** macOS-native IPC, sandboxable, process lifecycle managed by launchd. More complex to set up with a Python worker; requires a thin Swift XPC shim that spawns Python.
- **stdin/stdout pipes:** Simple, no port management, but awkward for concurrent requests and streaming.

**Decision needed:** Go with local HTTP unless there is a strong reason otherwise. The worker should bind to `127.0.0.1` only, pick a fixed or configured port, and expose a `/health` endpoint that Swift polls on startup.

### Python Runtime Bundling
The plan does not specify how Python is packaged inside the `.app` bundle. This affects code signing, notarization, binary size, and the crash-recovery story. Options:

- **Embedded Python framework (recommended):** Bundle a standalone CPython framework (e.g. via `python-build-standalone` or a pre-built relocatable Python) inside `YourApp.app/Contents/Frameworks/`. All dependencies installed relative to it. Avoids relying on the user's system Python. Works with notarization if all binaries are signed.
- **Conda/Miniforge embedded:** Heavier (~200 MB baseline) but handles native dependencies (numpy, torch) more reliably on ARM.
- **Rely on system Python / uv-managed venv at first launch:** Simpler to build but fragile — system Python version varies, and first-launch install creates a poor UX.

**Decision needed:** Use `python-build-standalone` with a pinned CPython version (3.11 recommended for torch/pyannote compatibility as of early 2026). Ship all dependencies pre-installed in the bundle. No network installs at runtime.

---

## Key Changes
- App surfaces
  - Ship a menu bar app with a floating dictation panel plus a full settings/workspace window.
  - Organize the main window around `General`, `Models`, `Transcribe Files`, `History`, `Keyboard Controls`, and `AI Analysis`.
  > **[Review]:** Menu bar icon states and the floating panel behavior are underspecified. See the new **UI Behavior Details** section below.
- Core runtime
  - Add `AudioCaptureService` for microphone discovery, priority ordering, push-to-talk/toggle recording, silence detection, and crash-safe recording recovery.
  > **[Review]:** "Priority ordering" should mean a user-configurable ordered preference list of audio input devices. Crash-safe recording should write audio to a temp file in `~/Library/Application Support/<App>/Scratch/` continuously so an incomplete recording can be recovered on relaunch. Temp files should be named with a UUID and timestamp and cleaned up only after the transcript is confirmed saved.
  - Add a `TranscriptionBackend` interface with `WhisperBackend` and `ParakeetBackend` adapters exposing `prepareModel`, `startLiveSession`, `finishLiveSession`, `transcribeFile`, `cancelJob`, `supportsTranslation`, and `supportsRealtimePreview`.
  > **[Review]:** The Whisper implementation is unspecified. Use `faster-whisper` (Python, CTranslate2 backend) as the `WhisperBackend` implementation. It runs well on Apple Silicon via the MPS or CPU backend, is significantly faster than the original `openai/whisper`, and supports streaming partial results. Do not use `whisper.cpp` — it would require a separate C++ build pipeline that conflicts with the Python-first worker decision.
  - Add `ModelCatalogService` backed by a signed JSON manifest with model id, provider, size, languages, realtime capability, download URL, checksum, runtime requirements, and install state.
  > **[Review]:** "Signed manifest" is underspecified. Use a manifest hosted at a stable URL (e.g. a GitHub release asset or a CDN path controlled by the developer). Sign the manifest with an Ed25519 key; ship the public key embedded in the app binary. Swift verifies the signature before trusting any download URLs. Concurrent download limit should be 1 at a time to avoid saturating the user's connection and to keep disk accounting simple. In-progress downloads should survive app quit via resume data (`URLSessionDownloadTask` resumeData) stored in `UserDefaults` or a scratch file.
  - Add `TranscriptStore` with local-first types: `TranscriptDocument`, `Utterance`, `SpeakerSpan`, `MediaAsset`, `AnalysisArtifact`, and `ExportFormat`.
  > **[Review]:** Storage backend is unspecified. Use SQLite via [GRDB.swift](https://github.com/groue/GRDB.swift) — it is well-maintained, Swift-native, supports full-text search (FTS5) natively which is needed for the history search feature, and handles migrations cleanly. Do not use CoreData — it adds complexity without benefit here. Store media assets as files on disk (in `~/Library/Application Support/<App>/Media/`) with only the path recorded in the database.
  - Add `LLMAnalysisProvider` with `LMStudioProvider` as the only v1 analysis backend, using LM Studio's local REST API for model listing, loading, and chat.
  > **[Review]:** LM Studio's local API is OpenAI-compatible (it targets `http://localhost:1234/v1`). The user configures the host:port in the app if they changed LM Studio's default. LM Studio does not require authentication by default, but the field should exist in settings for future use. When LM Studio is not running or not installed, the app should show a one-time setup card with a direct link to `lmstudio.ai` and instructions, not a generic error.
  - Add `DiarizationService` using pyannote `community-1` as the default local/open pipeline for multi-speaker labeling.
  > **[Review — significant issue]:** `pyannote/speaker-diarization-3.1` (and related pipelines) require the user to accept HuggingFace terms of service and provide an HF access token before the model can be downloaded. This is a mandatory UX step that is completely absent from the current plan. The app must: (1) prompt the user for their HF token the first time diarization is enabled, (2) store it securely in the macOS Keychain (not UserDefaults), (3) use it only for the HF model download, and (4) show a setup guide with a link to `hf.co/settings/tokens` if the token is missing or invalid. The model name `community-1` does not match a known pyannote model — use `pyannote/speaker-diarization-3.1`.

- User-visible behavior
  - Global hotkey flow: hold or toggle, record, preview/transcribe, then paste into the active app or copy to clipboard; `Escape` cancels.
  > **[Review — permissions blocker]:** Pasting into the active app requires `CGEventPost`, which requires the macOS Accessibility permission (`AXIsProcessTrusted()`). This is a first-launch blocker. The app must: (1) check for Accessibility permission on first hotkey use, (2) if absent, show a modal directing the user to System Settings → Privacy & Security → Accessibility, (3) fall back gracefully to clipboard-only mode until permission is granted. This flow must be implemented in Phase 1, not deferred.
  - File flow: drag/drop or record audio/video, choose model, optionally enable diarization and translation, optionally run LM Studio prompts, then export or save to history.
  - Model flow: browse built-in models, filter by fast/accurate/local/language, download/remove in-app, and set defaults per workflow.
  - History flow: searchable local archive with retry, retranscribe, copy, play audio, delete, and reopen prior AI outputs.
  > **[Review]:** Full-text search over history should use FTS5 via GRDB (see `TranscriptStore` note above). Search should cover transcript text, speaker labels, and file names.

- Delivery phases
  - `Phase 0`: feasibility spikes and benchmarks
  > **[Review]:** Phase 0 currently has no definition of done. See the new **Phase 0 Exit Criteria** section below.
  - `Phase 1`: Whisper-based dictation MVP
  - `Phase 2`: in-app model management plus Parakeet integration
  - `Phase 3`: file transcription workspace with editing/export
  - `Phase 4`: LM Studio summaries, Q&A, translation, and prompt presets
  - `Phase 5`: onboarding, updater, recovery, performance, docs, ship readiness
  > **[Review]:** Code signing and notarization are not mentioned anywhere in the phases. Add notarization setup to Phase 5. The bundled Python worker complicates this — every `.dylib` and binary inside the bundle must be individually signed with a Developer ID certificate before `xcrun notarytool` will accept the submission. Plan for this to take a full day of effort.

---

## Phase 0 Exit Criteria
> **[Review — new section]**

Phase 0 is a set of time-boxed spikes. Each spike has a pass/fail criterion. Do not begin Phase 1 until all spikes have a recorded result.

### Spike 1: Parakeet on Apple Silicon
- **Goal:** Determine whether `nvidia/parakeet-tdt-0.6b-v3` can run on Apple Silicon at acceptable speed.
- **Method:** Load the model via NeMo or a ONNX export in a Python script on an M-series Mac. Transcribe a 60-second audio clip.
- **Pass criteria:** Real-time factor (RTF) ≤ 0.3 (i.e., 60s audio transcribed in ≤ 18s) on M1 or better.
- **Fail criteria:** RTF > 0.5, crashes, or model refuses to load without CUDA.
- **If fail:** Parakeet ships as "coming soon" or is cut from v1. Whisper large-v3 becomes the accuracy-tier model. Document the finding and update the plan before Phase 2.

### Spike 2: faster-whisper on Apple Silicon
- **Goal:** Confirm `faster-whisper` with `int8` quantization runs acceptably for live dictation latency.
- **Pass criteria:** RTF ≤ 0.15 on `whisper-small` or `whisper-medium` on M1. End-to-end latency from audio stop to text paste ≤ 2s for a 10s utterance.

### Spike 3: Swift ↔ Python IPC round-trip
- **Goal:** Confirm the chosen IPC mechanism works with the bundled Python runtime.
- **Pass criteria:** A Swift app can spawn the Python worker, wait for `/health` to respond, send an audio file, and receive a transcript string — all within a fresh `.app` bundle without any system Python dependency.

### Spike 4: pyannote diarization with HF token flow
- **Goal:** Confirm pyannote loads and runs correctly with a user-supplied HF token.
- **Pass criteria:** A 2-speaker test clip produces correctly labeled speaker segments. HF token is accepted and the model downloads without manual intervention beyond pasting the token.

---

## UI Behavior Details
> **[Review — new section]**

### Menu Bar Icon States
The menu bar icon must reflect the current app state clearly. Implement these states:

| State | Icon treatment |
|---|---|
| Idle | Static microphone icon |
| Recording (hold/toggle) | Animated pulse or filled indicator |
| Processing / transcribing | Spinner or animated dots |
| Model downloading | Progress indicator (percentage in icon or tooltip) |
| Error / permission missing | Badge or exclamation overlay |

### Floating Dictation Panel
- Appears centered near the bottom of the screen (above the Dock) when recording starts.
- Always on top (`NSWindowLevel.floating`).
- Shows a live waveform visualization during recording and a progress indicator during transcription.
- `Escape` dismisses it and cancels the current recording/transcription.
- Does not steal focus from the active app — it must be `NSPanel` with `canBecomeKey = false` so the frontmost app retains focus for the subsequent paste action.
- Follows the primary display (the one with the menu bar) by default; do not attempt multi-display tracking in v1.

---

## Required Permissions Flow
> **[Review — new section]**

The app requires three permissions. Each must have an explicit request flow, not a silent failure.

| Permission | When required | Fallback if denied |
|---|---|---|
| Microphone (`AVCaptureDevice`) | First recording attempt | Show setup card; all recording features disabled |
| Accessibility (`AXIsProcessTrusted`) | First paste-into-app attempt | Fall back to clipboard-only mode; show one-time prompt explaining why |
| HuggingFace token (Keychain) | First diarization use | Show setup card with link to `hf.co/settings/tokens`; diarization disabled until supplied |

Request permissions lazily (on first use), not at launch. Store the HF token in the macOS Keychain using `kSecClassGenericPassword`, not in `UserDefaults` or a config file.

---

## Public Interfaces / Types
- `TranscriptionBackend`
  - `prepareModel(modelId)`
  - `startLiveSession(config)`
  - `finishLiveSession(sessionId)`
  - `transcribeFile(fileUrl, options)`
  - `cancelJob(jobId)`
- `ModelCatalogEntry`
  - `id`, `family`, `source`, `languages`, `sizeMB`, `installURL`, `checksum`, `runtime`, `supportsLive`, `supportsTranslation`, `supportsDiarization`
- `TranscriptDocument`
  - `id`, `sourceType`, `mediaPath`, `backend`, `language`, `createdAt`, `segments`, `speakers`, `analysisRuns`, `exportState`
- `LLMAnalysisProvider`
  - `listModels()`, `ensureLoaded(modelId)`, `runPrompt(transcript, promptPreset, options)`

> **[Review]:** The following interfaces are described in prose above but are missing formal definitions. Add them:

- `AudioCaptureService`
  - `listInputDevices() -> [AudioDevice]`
  - `setDevicePriority([AudioDevice])`
  - `startRecording(config: RecordingConfig) -> RecordingSession`
  - `stopRecording(sessionId) -> URL` (returns temp file URL)
  - `cancelRecording(sessionId)`
  - `recoverOrphanedRecordings() -> [URL]`

- `DiarizationService`
  - `isAvailable() -> Bool` (false if HF token missing or pyannote not installed)
  - `diarize(audioURL: URL, options: DiarizationOptions) -> [SpeakerSegment]`
  - `setHFToken(_ token: String)` (stores to Keychain)

- `ExportFormat` (enum)
  - `.plainText` — unformatted transcript
  - `.srt` — SubRip subtitles with timestamps
  - `.vtt` — WebVTT
  - `.json` — full structured transcript including speaker spans and metadata
  - `.markdown` — speaker-labeled transcript in Markdown

---

## Test Plan
- Dictation
  - Download the default Whisper model, hold the hotkey in TextEdit, release, and confirm inserted text.
  - Verify hold vs toggle, `Escape` cancel, microphone priority changes, and clipboard-only mode.
  - Verify that denying Accessibility permission shows the setup card and falls back to clipboard mode.
- File transcription
  - Import `mp3`, `wav`, `m4a`, `mp4`, and `mov`; transcribe; reopen from history; export successfully.
  - Retry the same file with another model and preserve both runs.
  - Export in all five `ExportFormat` variants and verify format correctness.
- Models
  - Download, cancel, resume, remove, and validate checksum/disk accounting for each model.
  - Surface actionable errors for low disk, missing runtime dependencies, or unsupported hardware.
  - Verify that a tampered manifest (bad signature) is rejected before any download begins.
- Speakers and AI
  - Confirm 1-speaker audio does not fragment into fake speakers.
  - Confirm 2-4 speaker audio produces labeled segments that remain editable after save/reopen.
  - Confirm LM Studio unavailable/unloaded/auth failures show setup guidance instead of silent failure.
  - Confirm summaries, translations, and Q&A are versioned per transcript run.
  - Confirm diarization is disabled (with explanation) when HF token is absent.
  - Confirm a valid HF token is accepted, stored in Keychain, and not written to disk in plaintext.
- Reliability
  - Recover unfinished recordings after crash/relaunch.
  - Preserve history and model installs across app upgrades.
  - Validate offline operation for already-installed local models.
  - Verify the app launches and all installed-model features work with no network connection.
- IPC / worker
  - Verify the Python worker starts within 5s of app launch on a cold start.
  - Verify the Swift layer retries and shows an error if the worker fails to start within 10s.
  - Verify the worker restarts automatically if it crashes mid-session.

---

## Assumptions And Defaults
- Launch target: `macOS first`.
- Distribution: `direct download`, not Mac App Store.
- Scope: both `system-wide dictation` and `file transcription` are in v1.
- Stack: `SwiftUI/AppKit` frontend plus a bundled local worker, likely Python first for model interoperability.
- Whisper is the reliability baseline; Parakeet is required for launch, but release remains gated on a successful Apple Silicon feasibility spike because NVIDIA's published runtime support is Linux/NVIDIA-oriented today.
- LM Studio is the only planned v1 analysis backend.
- Privacy default is local-first: audio, transcripts, history, and model files stay on-device unless the user explicitly connects LM Studio or another future external service.
- `faster-whisper` (CTranslate2) is the `WhisperBackend` implementation. `openai/whisper` and `whisper.cpp` are explicitly excluded.
- Python runtime is bundled using `python-build-standalone` (CPython 3.11). No network installs at runtime. No reliance on system Python.
- IPC between Swift and the Python worker is local HTTP on loopback (`127.0.0.1`), with the worker exposing a `/health` endpoint.
- Storage is SQLite via GRDB.swift with FTS5 for full-text search.
- The HF token for pyannote is stored in the macOS Keychain, never on disk in plaintext.
- Notarization with a Developer ID certificate is required before any public release build. Plan for this in Phase 5.
- Auto-update uses Sparkle 2. Add Sparkle as a dependency in Phase 1 even if the update UI ships in Phase 5, to avoid retrofitting the feed URL later.
---

## Dev Notes

### 2026-03-28 — Codex scaffolding + Claude review

**What Codex built (Phase 0 / Spike 3 scaffolding):**

- `Package.swift` — Swift 6.0, macOS 14+ target, `WaffleCore` library + `WaffleCoreTests` test target.
- `Sources/WaffleCore/WorkerClient.swift` — Swift HTTP client for the Python worker. `WorkerConfiguration` defaults to `127.0.0.1:8765`, exposes `baseURL` and `healthURL`. `WorkerClient.fetchHealth()` calls `GET /health` and decodes `WorkerHealth`. Conforms to Swift 6 `Sendable` constraints.
- `worker/waffle_worker/server.py` — `ThreadingHTTPServer`-based Python worker, serves `GET /health` and returns `{"service":"waffle-worker","status":"ok","version":"0.1.0"}`. Binds to loopback only.
- `worker/waffle_worker/models.py` — Data classes: `HealthResponse`, `RecordingConfig`, `LiveSessionConfig`, `FileTranscriptionRequest`.
- `worker/waffle_worker/backends/base.py` — `TranscriptionBackend` Protocol with all methods from the plan: `prepare_model`, `start_live_session`, `finish_live_session`, `transcribe_file`, `cancel_job`. `BackendCapabilities` dataclass with `supports_translation` and `supports_realtime_preview`.
- `worker/tests/test_server.py` — Two Python unit tests covering `/health` (200 + correct payload) and unknown routes (404 + `error: not_found`). Both pass.

**Bug fixed by Claude (second pass):**

- `Tests/WaffleCoreTests/WorkerClientTests.swift` was still using `import XCTest` / `XCTestCase` — the migration documented below had not been applied. Migrated to **Swift Testing** (`import Testing`, `@Suite struct`, `@Test func`, `#expect(...)`, `await #expect(throws:)`). The `MockURLProtocol` / `URLSession.makeMockingSession` mock infrastructure is unchanged. `swift build` now succeeds with CLI Tools only.

**Known environment constraint:**

- `swift test` requires Xcode.app to *execute* the test bundle (the runner depends on `XCTest.framework` from Xcode even when the tests themselves use Swift Testing). With CLI Tools only, `swift build` succeeds and all test symbols compile correctly, but the runner cannot launch. Install Xcode.app to run `swift test`.
- Python tests run without any extra setup: `python3 -m unittest discover -s worker/tests`.

**Toolchain in use:**
- Swift 6.2.4 (Apple Swift, Command Line Tools), target `arm64-apple-macosx14.0`
- macOS 26.2 SDK (Tahoe beta)
- Python 3.11 (system)

### 2026-03-28 — Claude Code session 2

**FasterWhisperBackend (Python):**

- `worker/waffle_worker/backends/faster_whisper.py` — Concrete `TranscriptionBackend` implementation backed by `faster-whisper`. Lazy-loads models on first `transcribe_file` call. Uses `device="cpu"`, `compute_type="int8"` per plan. Gracefully raises `RuntimeError` when the `faster-whisper` pip package is not installed.

**WorkerProcess (Swift):**

- `Sources/WaffleCore/WorkerProcess.swift` — Spawns the Python worker as a `Process`, passes `--host`/`--port` args, polls `/health` every 200ms until ready or timeout (default 10s). Resolves `worker/` path from the app bundle (`Contents/Resources/worker`) or falls back to the dev-layout sibling directory.

**CLI args for worker:**

- `worker/waffle_worker/__main__.py` — Now accepts `--host` and `--port` via `argparse` (required by `WorkerProcess`). Auto-registers `FasterWhisperBackend` if the import succeeds.

**Spike 2 benchmark script:**

- `worker/benchmarks/spike2_faster_whisper.py` — Standalone script that loads a `faster-whisper` model, transcribes a clip (or auto-generated 10s silence), and reports RTF + pass/fail against plan criteria (RTF ≤ 0.15, latency ≤ 2s for ≤ 10s clip). Run with: `python3 worker/benchmarks/spike2_faster_whisper.py --audio clip.wav --model small`.

**macOS App Target (`WaffleApp`):**

- `Package.swift` — Added `executableTarget("WaffleApp")` depending on `WaffleCore`.
- `Sources/WaffleApp/WaffleApp.swift` — `@main` SwiftUI app with `MenuBarExtra` (mic icon, `.window` style) + `Settings` scene.
- `Sources/WaffleApp/AppDelegate.swift` — Spawns the Python worker via `WorkerProcess` on launch, terminates on quit.
- `Sources/WaffleApp/MenuBarView.swift` — Menu bar popover showing worker status (green/yellow/red dot), start/stop recording button, settings + quit. Polls `/health` on appear.
- `Sources/WaffleApp/SettingsView.swift` — Tabbed settings: General (paste/clipboard toggles), Models (placeholder), Keyboard (placeholder).

**AudioCaptureService:**

- `Sources/WaffleCore/AudioCaptureService.swift` — Manages mic recording lifecycle. Lists input devices via `AVCaptureDevice.DiscoverySession`. Records 16kHz mono WAV to `~/Library/Application Support/Waffle/Scratch/` with UUID+timestamp filenames for crash recovery. Provides `startRecording()`, `stopRecording()`, `cancelRecording()`, `recoverOrphanedRecordings()`, and `cleanupScratchFile()`.

**PermissionsService:**

- `Sources/WaffleCore/PermissionsService.swift` — Checks Accessibility (`AXIsProcessTrusted`) and Microphone (`AVCaptureDevice.authorizationStatus`) permissions. `promptAccessibility()` triggers the system dialog pointing to Privacy & Security. Works around Swift 6 strict concurrency for the `kAXTrustedCheckOptionPrompt` global.

**Status:**

- `swift build` passes — all targets (WaffleCore, WaffleApp, WaffleCoreTests) compile cleanly.
- All 3 Python tests pass (`PYTHONPATH=worker python3 -m unittest discover -s worker/tests`).
- Spike 2 benchmark requires `pip install faster-whisper` to run.

---

- Research references used for this plan:
  - [Spokenly App Store](https://apps.apple.com/us/app/spokenly-audio-to-text-ai-app/id6740315592)
  - [Spokenly Docs](https://spokenly.app/docs)
  - [Whisper Transcription App Store](https://apps.apple.com/us/app/whisper-transcription/id1668083311)
  - [OpenAI Whisper](https://github.com/openai/whisper)
  - [NVIDIA Parakeet TDT 0.6B v3](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3)
  - [LM Studio REST API](https://lmstudio.ai/docs/developer/rest)
  - [pyannote.audio](https://github.com/pyannote/pyannote-audio)
  - [faster-whisper](https://github.com/SYSTRAN/faster-whisper)
  - [GRDB.swift](https://github.com/groue/GRDB.swift)
  - [python-build-standalone](https://github.com/indygreg/python-build-standalone)
  - [Sparkle updater](https://sparkle-project.org)
