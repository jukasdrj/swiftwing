import Foundation
import SwiftUI
import UIKit

/// Represents an item in the processing queue
/// Used for live UI feedback during image capture and processing
struct ProcessingItem: Identifiable, Equatable {
    let id: UUID
    let thumbnailData: Data  // Pre-processed 60x90px thumbnail for performance
    let captureDate: Date
    var state: ProcessingState
    var progressMessage: String?  // Real-time progress text from SSE (e.g., "Looking...", "Reading...")
    var errorMessage: String?     // Error message for failed scans (US-407)
    var originalImageData: Data?  // Original full-size image for retry (US-407)
    var tempFileURL: URL?  // Temporary JPEG file URL for cleanup (US-406)
    var jobId: String?     // Talaria job ID for server cleanup (US-406)
    var preScannedISBN: String? = nil  // Vision-detected ISBN from barcode scanner (TODO 4.4)
    var segmentedPreview: Data?  // Segmented image preview with bounding boxes (Task 5)
    var detectedBookCount: Int?  // Number of books detected in segmented preview (Task 5)
    var currentBookIndex: Int?   // Current book being processed in multi-book scan (Task 5)

    init(imageData: Data, state: ProcessingState = .uploading, progressMessage: String? = nil) {
        self.id = UUID()
        self.thumbnailData = Self.generateThumbnail(from: imageData)
        self.captureDate = Date()
        self.state = state
        self.progressMessage = progressMessage
        self.errorMessage = nil
        self.originalImageData = imageData  // Store for retry (US-407)
        self.tempFileURL = nil
        self.jobId = nil
    }

    /// Generates optimized 60x90px thumbnail from full image data
    /// Performance optimization for ProcessingQueueView
    private static func generateThumbnail(from imageData: Data) -> Data {
        guard let image = UIImage(data: imageData) else {
            return imageData // Fallback to original data if processing fails
        }

        // Calculate size maintaining aspect ratio (60x90px target)
        let targetSize = CGSize(width: 60, height: 90)
        let size = image.size
        let aspectRatio = size.width / size.height
        let thumbnailAspectRatio = targetSize.width / targetSize.height

        let newSize: CGSize
        if aspectRatio > thumbnailAspectRatio {
            // Wider than target - fit height
            newSize = CGSize(width: targetSize.height * aspectRatio, height: targetSize.height)
        } else {
            // Taller than target - fit width
            newSize = CGSize(width: targetSize.width, height: targetSize.width / aspectRatio)
        }

        // Render thumbnail
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let thumbnail = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }

        // Compress to JPEG with lower quality (thumbnails don't need high quality)
        return thumbnail.jpegData(compressionQuality: 0.6) ?? imageData
    }

    enum ProcessingState: Equatable {
        case preprocessing  // Purple border - preprocessing (CIFilter pipeline)
        case uploading      // Yellow border - uploading image to Talaria
        case analyzing      // Blue border - AI is analyzing the book spine
        case done           // Green border - successfully identified
        case error          // Red border - processing failed
        case offline        // Gray border - queued for upload when network returns (US-409)

        var borderColor: Color {
            switch self {
            case .preprocessing:
                return .purple
            case .uploading:
                return .yellow
            case .analyzing:
                return .blue
            case .done:
                return .green
            case .error:
                return .red
            case .offline:
                return .gray
            }
        }
    }
}
