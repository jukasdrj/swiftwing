import Foundation
import SwiftUI
import UIKit

/// Represents an item in the processing queue
/// Used for live UI feedback during image capture and processing
struct ProcessingItem: Identifiable, Equatable {
    let id: UUID
    let thumbnailData: Data  // Pre-processed 40x60px thumbnail for performance
    let captureDate: Date
    var state: ProcessingState
    var progressMessage: String?  // Real-time progress text from SSE (e.g., "Looking...", "Reading...")

    init(imageData: Data, state: ProcessingState = .uploading, progressMessage: String? = nil) {
        self.id = UUID()
        self.thumbnailData = Self.generateThumbnail(from: imageData)
        self.captureDate = Date()
        self.state = state
        self.progressMessage = progressMessage
    }

    /// Generates optimized 40x60px thumbnail from full image data
    /// Performance optimization for ProcessingQueueView
    private static func generateThumbnail(from imageData: Data) -> Data {
        guard let image = UIImage(data: imageData) else {
            return imageData // Fallback to original data if processing fails
        }

        // Calculate size maintaining aspect ratio (40x60px target)
        let targetSize = CGSize(width: 40, height: 60)
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
        case uploading   // Yellow border - uploading image to Talaria
        case analyzing   // Blue border - AI is analyzing the book spine
        case done        // Green border - successfully identified
        case error       // Red border - processing failed

        var borderColor: Color {
            switch self {
            case .uploading:
                return .yellow
            case .analyzing:
                return .blue
            case .done:
                return .green
            case .error:
                return .red
            }
        }
    }
}
