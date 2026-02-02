//
//  VisionService.swift
//  swiftwing
//
//  Created by Claude Code on 2026-01-30.
//

import Vision
import CoreVideo
import ImageIO
import Foundation

// MARK: - VisionService

/// Service for processing image frames with Vision framework.
/// Performs text recognition and barcode detection on video frames.
///
/// **Design Note:** VisionService is a plain class (not an actor, not @MainActor).
/// It is queue-agnostic and designed to be called synchronously from the AVFoundation
/// delegate queue. Results are published via an AsyncStream that the ViewModel consumes on @MainActor.
final class VisionService {
    // MARK: - Private Properties

    private let textRequest = VNRecognizeTextRequest()
    private let barcodeRequest = VNDetectBarcodesRequest()
    private let rectangleRequest = VNDetectRectanglesRequest()
    private var lastProcessedTime: CFAbsoluteTime = 0
    private var processingInterval: CFAbsoluteTime = 0.15 // Default: 150ms (~6.7 fps)

    // MARK: - Initialization

    init() {
        // Configure text recognition request
        textRequest.recognitionLevel = .fast // Real-time performance
        textRequest.recognitionLanguages = ["en-US"] // English for book spines
        textRequest.usesLanguageCorrection = false // Avoid delays

        // Configure barcode request
        // Note: ISBN-13 barcodes use EAN-13 symbology
        barcodeRequest.symbologies = [.ean13]

        // Configure rectangle detection request
        rectangleRequest.minimumAspectRatio = 0.1   // Book spines are tall and narrow
        rectangleRequest.maximumAspectRatio = 0.9   // Exclude near-square shapes
        rectangleRequest.minimumSize = 0.05         // At least 5% of frame
        rectangleRequest.maximumObservations = 3    // Limit UI clutter
        rectangleRequest.minimumConfidence = 0.75   // Reduce false positives
    }

    // MARK: - Frame Processing

    /// Process a video frame with Vision framework requests.
    /// This method is synchronous and should be called from the AVFoundation delegate queue.
    ///
    /// - Parameters:
    ///   - pixelBuffer: The pixel buffer from the video frame
    ///   - orientation: The image orientation (from camera connection)
    /// - Returns: A VisionResult containing detected text regions, barcodes, or no content
    func processFrame(
        _ pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation
    ) -> VisionResult {
        // Check if enough time has elapsed since last processing
        guard shouldProcessFrame() else {
            return VisionResult.noContent
        }

        do {
            // Create handler for this frame
            let handler = VNImageRequestHandler(
                cvPixelBuffer: pixelBuffer,
                orientation: orientation,
                options: [:]
            )

            // Perform all requests on the same frame
            try handler.perform([textRequest, barcodeRequest, rectangleRequest])

            // Extract text observations
            var textRegions: [TextRegion] = []
            if let textObservations = textRequest.results {
                for observation in textObservations {
                    guard observation.confidence > 0.5 else { continue }

                    if let topCandidate = observation.topCandidates(1).first {
                        let region = TextRegion(
                            boundingBox: observation.boundingBox,
                            text: topCandidate.string,
                            confidence: observation.confidence
                        )
                        textRegions.append(region)
                    }
                }
            }

            // Extract barcode observations
            if let barcodeObservations = barcodeRequest.results {
                for observation in barcodeObservations {
                    if let isbn = observation.payloadStringValue {
                        let isValid = validateISBN13(isbn)
                        let barcodeResult = BarcodeResult(
                            isbn: isbn,
                            boundingBox: observation.boundingBox,
                            isValidISBN: isValid
                        )
                        return VisionResult.barcode(barcodeResult)
                    }
                }
            }

            // Extract rectangle observations (potential book spines)
            var detectedObjects: [DetectedObject] = []
            if let rectangleObservations = rectangleRequest.results {
                for observation in rectangleObservations {
                    guard observation.confidence > 0.75 else { continue }
                    let object = DetectedObject(
                        boundingBox: observation.boundingBox,
                        confidence: observation.confidence,
                        observationUUID: observation.uuid
                    )
                    detectedObjects.append(object)
                }
            }

            // Return appropriate result with priority: barcode > objects > text > noContent
            // Note: Barcode is already returned above
            if !detectedObjects.isEmpty {
                return VisionResult.objects(detectedObjects)
            } else if !textRegions.isEmpty {
                return VisionResult.textRegions(textRegions)
            } else {
                return VisionResult.noContent
            }
        } catch {
            // Vision processing failed, return no content
            return VisionResult.noContent
        }
    }

    // MARK: - Frame Throttling

    /// Set the processing rate based on activity state.
    /// Adjusts throttling interval dynamically to save battery during idle periods.
    ///
    /// - Parameter active: True if actively scanning (10 fps), false if idle (1 fps)
    func setProcessingRate(active: Bool) {
        if active {
            processingInterval = 0.1 // 10 fps during active scanning
        } else {
            processingInterval = 1.0 // 1 fps when idle
        }
    }

    /// Determine whether enough time has elapsed to process another frame.
    /// Used to limit processing frequency and save battery.
    ///
    /// - Returns: True if the frame should be processed, false if it should be skipped
    func shouldProcessFrame() -> Bool {
        let now = CFAbsoluteTimeGetCurrent()
        let elapsed = now - lastProcessedTime

        if elapsed >= processingInterval {
            lastProcessedTime = now
            return true
        }
        return false
    }

    // MARK: - Capture Guidance

    /// Generate guidance for the user based on Vision results.
    /// Helps the user position the camera optimally for book spine detection.
    ///
    /// **Enhanced Heuristics (US-511):**
    /// - Barcode → always ready (ISBN is definitive)
    /// - Multiple high-confidence text regions → spine detected
    /// - Medium confidence → move closer (camera too far)
    /// - Low confidence → hold steady (motion blur)
    /// - No content → no book detected
    ///
    /// - Parameter result: The VisionResult to analyze
    /// - Returns: CaptureGuidance indicating what action the user should take
    func generateGuidance(from result: VisionResult) -> CaptureGuidance {
        switch result {
        case .barcode:
            // ISBN detected - ready to capture (definitive signal)
            return CaptureGuidance.spineDetected

        case .objects(_):
            // Dead code: generateGuidance is not called by CameraViewModel
            // This case exists only to satisfy exhaustive switch compilation
            return CaptureGuidance.holdSteady

        case .textRegions(let regions):
            guard !regions.isEmpty else {
                return CaptureGuidance.noBookDetected
            }

            // Calculate average confidence
            let avgConfidence = regions.map { $0.confidence }.reduce(0, +) / Float(regions.count)

            // High confidence (>0.75) with multiple regions → spine detected
            if avgConfidence > 0.75 && regions.count >= 2 {
                return CaptureGuidance.spineDetected
            }

            // Medium confidence (0.5-0.75) → move closer
            if avgConfidence > 0.5 {
                return CaptureGuidance.moveCloser
            }

            // Low confidence (<0.5) → hold steady (motion blur likely)
            return CaptureGuidance.holdSteady

        case .noContent:
            return CaptureGuidance.noBookDetected
        }
    }
}

// MARK: - Private Extension: ISBN Validation

private extension VisionService {
    /// Validate an ISBN-13 barcode using checksum verification.
    /// Performs format validation and modulo-10 checksum calculation.
    ///
    /// - Parameter code: The ISBN string to validate (may contain hyphens or spaces)
    /// - Returns: True if the code is a valid ISBN-13, false otherwise
    func validateISBN13(_ code: String) -> Bool {
        // Strip non-numeric characters
        let digits = code.filter { $0.isNumber }

        // Verify exactly 13 digits
        guard digits.count == 13 else { return false }

        // Verify starts with 978 or 979 (book ISBN prefix)
        guard digits.hasPrefix("978") || digits.hasPrefix("979") else { return false }

        // Calculate checksum: alternating weights of 1 and 3, sum mod 10 == 0
        let sum = digits.enumerated().reduce(0) { sum, pair in
            let digit = Int(String(pair.element))!
            let weight = pair.offset % 2 == 0 ? 1 : 3
            return sum + (digit * weight)
        }

        return sum % 10 == 0
    }
}
