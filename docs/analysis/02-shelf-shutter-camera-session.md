# Pass 2 — Shelf shutter and camera session

Date: 2026-09-24. Read only.

Files: `swiftwing/Features/Camera/CameraView.swift`, `swiftwing/Features/Camera/CameraViewModel.swift` (`setupCamera`, `captureImage`, `handleFocusTap`), `swiftwing/Features/Camera/CameraManager.swift`, `swiftwing/Features/Camera/CameraOverlayView.swift`, `swiftwing/Features/Camera/CameraPreviewView.swift`, `swiftwingUITests/CameraUITests.swift`.

Do not change yet.

## 1. What starts it, and who owns it

`CameraView` appears inside the Camera tab. Its `.task` assigns `modelContext` and calls `CameraViewModel.setupCamera()`. The view model owns the flow. `CameraManager` (`@MainActor`, `@Observable`) owns the `AVCaptureSession`.

`setupCamera()` calls `setupSession()` on the main actor, then `startSession()`, which dispatches `startRunning()` onto a global queue and returns without waiting. The shutter button calls `captureImage()`. That increments `activeCaptureCount` (cap 5), flashes the screen, and fires `processCapture` without awaiting it. `processCapture` calls `cameraManager.capturePhoto()`.

The shutter is disabled when `isRateLimited` or `isInterrupted`. It stays enabled at the 5-capture cap. `captureImage()` logs and returns in that case.

Zoom is a slider in `CameraOverlayView` and a pinch gesture in `CameraPreviewView`. Both call `CameraManager.setZoom`, clamped to 1.0...4.0. The numeric readout is separate, in `statusOverlays`. The slider hides while a scan-complete banner or a segmented preview is showing. AE/AF lock is `toggleExposureFocusLock()`. A focus tap calls `setFocusPoint` and clears the lock only after the device accepts the new mode.

## 2. Inputs and outputs

| Step | Input | Output |
|---|---|---|
| `setupSession()` | back wide camera, preset `.high` | `AVCaptureSession`, `AVCapturePhotoOutput`, `resolution` |
| Photo settings | `maxPhotoDimensions` nearest to 1024×768, quality `.balanced` | one `Data` from `fileDataRepresentation()` |
| `captureImage()` | shutter tap | `UUID` item id, unawaited `processCapture` task |
| `setZoom` | `CGFloat` | `currentZoomFactor` in 1.0...4.0, or no change |
| Lock | current `isExposureFocusLocked` | `.locked` or continuous auto focus and exposure |

`videoOutput` is never added to the session. Rotation setup still asks it for a connection, which is nil.

`isInterrupted` becomes true only for `.audioDeviceInUseByAnotherClient` and `.videoDeviceInUseByAnotherClient`. Other interruption reasons leave the shutter enabled. A media-services reset restarts the session.

## 3. Failures

Handled:

- No camera, rejected input, or rejected output throws `CameraError`. `setupCamera` stores `errorMessage` and the overlay shows "Camera Error".
- `capturePhoto` resumes the continuation with the delegate error, or `photoOutputNotConfigured` when `fileDataRepresentation()` is nil. `processCapture` shows the processing-error overlay.
- Zoom and focus failures are logged. The flag is left unchanged when `lockForConfiguration` throws.
- `videoDevice == nil` makes `setZoom` and `toggleExposureFocusLock` return immediately.

Logged or dropped:

- `startSession` does not report failure. `startRunning()` has no completion.
- Hitting the 5-capture cap logs a warning and drops the tap.
- The first-run coach (`hasSeenCameraGuidance`) can cover the shutter. `UI_TESTING` presets that flag unless `FORCE_CAMERA_GUIDANCE` is set.

## 4. What is tested

`CameraUITests` checks that the shutter, zoom slider, and AE/AF lock render and that first-run guidance appears or stays hidden. The simulator has no camera, so `setupSession()` throws `.noCameraAvailable` before `videoDevice` is set. Zoom and the lock cannot move hardware. A device is required for a real shelf frame, a zoom change, and a lock that survives a second shot.

## 5. Structural risk

`startSession()` returns before `startRunning()` finishes, and `isLoading` is cleared immediately. The shutter is tappable against a session that is not running yet. `capturePhoto` then fails in the delegate, and the user sees a processing error for a tap that was simply early.

## Do not change yet

Leave the session start, the 5-capture cap, and the simulator no-op controls as they are until a later pass decides to fix them.
