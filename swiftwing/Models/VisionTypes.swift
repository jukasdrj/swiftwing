import CoreGraphics
import Foundation
import Vision

// MARK: - Vision Result Types

/// Result from frame processing
enum VisionResult: Sendable {
    case textRegions([TextRegion])
    case barcode(BarcodeResult)
    case objects([DetectedObject])
    case noContent
}

/// Detected text region
struct TextRegion: Identifiable, Sendable {
    let id = UUID()
    let boundingBox: CGRect
    let text: String
    let confidence: Float
}

/// Detected barcode (ISBN)
struct BarcodeResult: Identifiable, Sendable {
    let id = UUID()
    let isbn: String
    let boundingBox: CGRect
    let isValidISBN: Bool
}

/// Detected generic object (potential book spine)
struct DetectedObject: Identifiable, Sendable {
    let id = UUID()
    let boundingBox: CGRect
    let confidence: Float
    let observationUUID: UUID
}

/// Structure for recognized paragraphs in document mode
struct Paragraph: Identifiable, Sendable {
    let id = UUID()
    let text: String
    let confidence: Float
    let boundingBox: CGRect
}

/// Structure for full document observation
struct DocumentObservation: Sendable {
    let fullText: String
    let paragraphs: [Paragraph]
    let detectedISBNs: [String]
}

// MARK: - Capture Guidance

/// User guidance based on vision analysis
enum CaptureGuidance: String, CaseIterable, Sendable {
    case noBookDetected = "Point at a book spine"
    case spineDetected = "Hold steady"
    case moveCloser = "Move closer"
    case holdSteady = "Scanning..."
}
