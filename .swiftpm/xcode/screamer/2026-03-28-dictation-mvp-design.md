# Dictation MVP Design

## Scope
Implement the smallest usable end-to-end dictation flow for the existing macOS menu bar app:

- Start recording from the menu bar UI
- Stop recording and save audio to the existing scratch directory
- Submit the saved audio file to the local worker for transcription
- Copy the resulting transcript to the clipboard
- Paste into the active app when Accessibility permission is available
- Fall back cleanly to clipboard-only behavior when Accessibility permission is missing

Out of scope for this slice:

- Global hotkeys
- Floating dictation panel
- Model catalog and downloads
- Transcript history
- Diarization
- LM Studio analysis
- Retry queues, crash recovery UI, or worker restart orchestration

## Architecture
This slice stays inside the current structure rather than adding new top-level subsystems.

- `MenuBarView` becomes the coordinator for the MVP user flow and visible state
- `AudioCaptureService` remains responsible for microphone permission requests, recording start, recording stop, and scratch-file lifecycle
- `WorkerClient` remains responsible for local HTTP communication with the Python worker
- A new small pasteboard/paste helper in `ScreamerCore` owns clipboard writes and optional simulated `Cmd+V`

The intent is to keep all system interaction behind service boundaries and keep the menu bar view focused on state transitions.

## User Flow
The menu bar UI should expose one primary action and one visible result area.

### Recording
- Initial state shows `Start Recording`
- If microphone permission is `.notDetermined`, the app requests permission on first start attempt
- If microphone permission is denied, recording does not start and the UI shows a clear blocked state
- When recording starts, the primary button changes to `Stop Recording`

### Transcription
- Stopping recording finalizes the WAV file and immediately starts transcription
- The UI shows a transcribing state while the worker request is in flight
- The MVP uses a fixed model id already registered in the worker path; no model picker is added in this slice

### Result Delivery
- On successful transcription, the transcript is always written to the clipboard
- If Accessibility permission is granted, the app then synthesizes `Cmd+V` to paste into the active app
- If Accessibility permission is not granted, the app prompts once and leaves the transcript on the clipboard
- The menu bar UI shows the latest transcript text or a compact success message so the user can confirm the result

### Failure Handling
- Worker offline or request failure shows an error state in the menu bar UI
- Transcription failure does not delete the scratch audio automatically
- Paste failure after a successful clipboard write still counts as partial success and the UI must say that the text was copied

## Components
### MenuBarView
Responsibilities:

- Hold the MVP UI state: idle, recording, transcribing, success, error
- Trigger recording start/stop
- Call the worker client after recording stops
- Display transcript text and user-facing status

This view should not contain low-level pasteboard or event-posting logic.

### AudioCaptureService
Responsibilities:

- Request microphone permission when needed
- Start and stop recording using the existing scratch-file behavior
- Return the final audio file URL

No new device-priority or silence-detection work is included in this slice.

### Paste Helper
Responsibilities:

- Write transcript text to `NSPasteboard`
- Check Accessibility permission status
- Attempt synthetic paste only when permission is granted
- Return a structured outcome so UI code can distinguish:
  - copied and pasted
  - copied only
  - copy failed

This should live in `ScreamerCore` so it can be tested independently of SwiftUI.

### WorkerClient
Responsibilities:

- Submit the recorded file to `/transcriptions/file`
- Decode the transcription payload

If worker contract changes are required for the MVP, keep them minimal and covered by tests.

## Data Flow
1. User clicks `Start Recording`
2. App checks or requests microphone permission
3. `AudioCaptureService` starts recording to a scratch WAV file
4. User clicks `Stop Recording`
5. `AudioCaptureService` stops recording and returns the file URL
6. `WorkerClient` posts the file transcription request
7. App receives transcript text
8. Paste helper writes to clipboard
9. Paste helper attempts `Cmd+V` if Accessibility is granted
10. UI updates to success or partial-success state

## Error Handling
- Microphone denied: show a clear message and do not start recording
- Missing Accessibility permission: copy transcript, prompt once, report clipboard-only fallback
- Worker unavailable: show transcription failure and keep the recorded file
- Invalid worker response: show transcription failure and keep the recorded file
- Paste event failure: report clipboard-only fallback if the clipboard write succeeded

## Testing
Use TDD for new behavior.

### Swift Tests
- Add unit tests for the new paste helper using injected side effects for clipboard writes and key-event posting
- Verify outcomes for:
  - Accessibility granted and paste succeeds
  - Accessibility missing
  - Clipboard write failure
  - Paste failure after successful clipboard write

### Existing WorkerClient Tests
- Extend only if the worker request/response contract changes for this MVP

### Python Tests
- Add or extend worker tests only if endpoint behavior changes materially

### Verification
- Build the project in Xcode
- Refresh Swift diagnostics for edited files
- Manually validate:
  - microphone request flow
  - successful clipboard copy
  - Accessibility fallback
  - successful auto-paste when permission is granted

## Constraints
- Keep the MVP architecture thin; avoid introducing model management or history abstractions in this slice
- Preserve loopback-only worker communication
- Do not require a system-wide hotkey for MVP completion
- Do not claim paste success unless the clipboard write succeeded first

## Acceptance Criteria
- A user can record speech from the menu bar UI and receive a transcript through the existing local worker path
- The transcript is copied to the clipboard on every successful transcription
- The transcript is pasted automatically when Accessibility permission is present
- The app falls back to clipboard-only mode with explicit user feedback when Accessibility permission is missing
- Errors are visible in the menu bar UI instead of failing silently
