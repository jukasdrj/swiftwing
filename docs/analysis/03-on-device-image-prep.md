# Pass 3 — On-device image prep

Date: 2026-09-24. Read only.

Files: `swiftwing/Services/ImagePreprocessor.swift`, `swiftwing/Features/Camera/CameraViewModel.swift` (`preprocessAndPrepareUpload`), `swiftwing/Features/Camera/CameraManager.swift` (`capturePhoto` dimension cap).

Do not change yet.

## 1. What starts it, and who owns it

After `capturePhoto()` returns `Data`, `CameraViewModel.preprocessAndPrepareUpload` owns the step. It calls `ImagePreprocessor` (`actor`):

1. `preprocess(_:)` — contrast, brightness, denoise, and a rotation check.
2. `processImageForUpload(_:)` — resize and a second JPEG encode, then a temp file.

The comment on `processImageForUpload` says the caller must preprocess first. Calling preprocess again would run the filters twice. The view model does not.

This step does not find spines or faces. It changes pixels and writes a file.

## 2. Inputs and outputs

Input is the capture `Data`. Capture already asked the photo output for dimensions near 1024×768.

`preprocess` returns `PreprocessingResult`:

- `processedData: Data` — JPEG at quality 0.85 from `CIContext`, or the original bytes if `UIImage` cannot decode them
- `wasRotated: Bool` — true only when `height / width > 2.0`, then a 90° counterclockwise turn
- `brightnessAdjustment: Float` — about −0.2...0.2 from a 64×64 luminance sample, or 0 when the sample sits between 100 and 180
- `processingTimeMs: Int`

Then `resizeAndCompress` (default longest edge 1920, JPEG 0.85, EXIF orientation honored) writes `temporaryDirectory/<uuid>.jpg`. The view model reads that file back into `Data` and uploads the bytes. A detached task deletes the file after 30 minutes. `SwiftwingApp.cleanupOrphanedTempPhotos` deletes temp JPEGs older than one hour.

A shelf photo is wider than it is tall, or only moderately tall. Its aspect ratio does not clear 2.0, so the "vertical bookshelf" rotation does not run. The heuristic matches a very narrow crop, not a shelf.

## 3. Failures

Handled:

- Undecodable input: `preprocess` returns the original bytes and reports 0 ms. No throw.
- A missing CIFilter logs and leaves the image unchanged for that stage.
- `resizeAndCompress` throws `ImageProcessingError.invalidImageData` or `.compressionFailed`. The view model’s processing catch shows the error overlay.
- JPEG render failure falls back to `UIImage.jpegData`. If that is also nil, `preprocess` keeps the original bytes (`?? imageData`).

Logged or dropped:

- Nothing records that the rotation heuristic skipped a shelf.
- The 0.5 s budget is a log warning in the view model. It does not fail the scan.
- There is no test that the pipeline stays under 500 ms, and no test of the filters.

## 4. What is tested

No test targets `ImagePreprocessor` or `preprocessAndPrepareUpload`. Timing and rotation can only be seen on a device, with a real shelf photo and a deliberately tall crop.

## 5. Structural risk

The upload bytes are a second JPEG (quality 0.85) of a first JPEG (quality 0.85) of a capture that was already limited near 1024×768. The resize ceiling is 1920, so it does not shrink that capture. The rotation pass, which is the only geometry change, does not apply to a shelf. The server receives a recompressed photo, not a straightened shelf.

## Do not change yet

Leave the filter order, the aspect threshold, and the temp-file lifetime until pass 4 and pass 9 have been read beside this note.
