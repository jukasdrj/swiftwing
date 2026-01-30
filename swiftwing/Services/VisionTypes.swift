//
//  VisionTypes.swift
//  swiftwing
//
//  Created by Claude Code on 2026-01-30.
//

import Foundation
import CoreGraphics
import AVFoundation

// MARK: - Vision Result Types

/// Represents the result of Vision framework processing on a captured image.
/// This is the primary output type from VisionService analysis.
public enum VisionResult: Sendable {
    /// Text was detected in the image with regions and confidence scores
    case textRegions([TextRegion])

    /// A barcode (ISBN) was detected in the image
    case barcode(BarcodeResult)

    /// No meaningful content was detected in the image
    case noContent
}

// MARK: - Text Region

/// Represents a detected text region in an image with its bounding box and confidence.
/// Used for OCR results from Vision framework text recognition.
public struct TextRegion: Sendable {
    /// The bounding box of the text region in normalized coordinates (0.0 to 1.0)
    /// Origin is bottom-left in Vision framework coordinate system
    public let boundingBox: CGRect

    /// The recognized text content within this region
    public let text: String

    /// Confidence score of the text recognition (0.0 to 1.0)
    /// Higher values indicate more confident recognition
    public let confidence: Float

    public init(boundingBox: CGRect, text: String, confidence: Float) {
        self.boundingBox = boundingBox
        self.text = text
        self.confidence = confidence
    }
}

// MARK: - Barcode Result

/// Represents a detected ISBN barcode with validation status.
/// ISBN-10 and ISBN-13 formats are supported.
public struct BarcodeResult: Sendable {
    /// The ISBN string extracted from the barcode
    /// May be ISBN-10 or ISBN-13 format
    public let isbn: String

    /// The bounding box of the barcode in normalized coordinates (0.0 to 1.0)
    /// Origin is bottom-left in Vision framework coordinate system
    public let boundingBox: CGRect

    /// Whether the ISBN passes checksum validation
    /// True indicates a structurally valid ISBN
    public let isValidISBN: Bool

    public init(isbn: String, boundingBox: CGRect, isValidISBN: Bool) {
        self.isbn = isbn
        self.boundingBox = boundingBox
        self.isValidISBN = isValidISBN
    }
}

// MARK: - Capture Guidance

/// Real-time guidance for the user during camera capture.
/// Helps users position the camera optimally for book spine detection.
public enum CaptureGuidance: Sendable {
    /// A book spine has been detected - ready to capture
    case spineDetected

    /// The camera is too far from the book spine
    case moveCloser

    /// The camera is moving - user should stabilize
    case holdSteady

    /// No book or spine detected in the frame
    case noBookDetected
}
