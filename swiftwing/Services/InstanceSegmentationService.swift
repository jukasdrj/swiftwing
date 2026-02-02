import Vision
import CoreImage
import SwiftUI

/// Actor-isolated service for segmenting bookshelf photos into individual book spines
/// Uses iOS 26 GenerateForegroundInstanceMaskRequest for instance segmentation
/// Falls back to Hough Line Transform (vertical edge detection) if instance segmentation fails
actor InstanceSegmentationService {
    private let houghLineService = HoughLineSegmentationService()

    /// Segments a bookshelf image into individual book spines
    /// - Parameter image: Full bookshelf image as CIImage
    /// - Returns: Array of SegmentedBook with cropped images and bounding boxes
    /// - Throws: SegmentationError if no books detected or processing fails
    func segmentBooks(from image: CIImage) async throws -> [SegmentedBook] {
        // Try instance segmentation first (iOS 26 native)
        do {
            let books = try await segmentByInstanceMask(from: image)
            if books.count >= 2 {
                print("✅ Instance: \(books.count) books")
                return books
            }
            // Only 1 book detected - try Hough fallback
        } catch {
            // Instance segmentation failed - try Hough fallback
        }

        // Fallback to Hough Line Transform (vertical spine edge detection)
        return try await houghLineService.segmentBooksByVerticalLines(from: image)
    }

    /// Primary segmentation using iOS 26 VNGenerateForegroundInstanceMaskRequest
    private func segmentByInstanceMask(from image: CIImage) async throws -> [SegmentedBook] {
        let request = VNGenerateForegroundInstanceMaskRequest()

        // Perform segmentation
        let handler = VNImageRequestHandler(ciImage: image, options: [:])

        do {
            try handler.perform([request])
        } catch {
            throw SegmentationError.visionFrameworkError(error)
        }

        guard let results = request.results, !results.isEmpty else {
            throw SegmentationError.noInstancesFound
        }

        guard let observation = results.first else {
            throw SegmentationError.noInstancesFound
        }

        var books: [SegmentedBook] = []

        // Skip instance 0 (background), iterate 1-N (foreground objects)
        for instanceID in observation.allInstances where instanceID > 0 {
            let singleInstance = IndexSet(integer: instanceID)

            // Generate masked, cropped image for this book
            guard let croppedBuffer = try? observation.generateMaskedImage(
                ofInstances: singleInstance,
                from: handler,
                croppedToInstancesExtent: true
            ) else {
                // Silently skip failed instances
                continue
            }

            // Calculate tight bounding box
            let boundingBox = calculateBounds(from: croppedBuffer, fullImageSize: image.extent.size)

            books.append(SegmentedBook(
                instanceID: instanceID,
                croppedImage: CIImage(cvPixelBuffer: croppedBuffer),
                boundingBox: boundingBox
            ))
        }

        // Performance validation: <2s for 10 books
        if books.count > 20 {
            throw SegmentationError.tooManyBooks(count: books.count)
        }

        print("📚 Successfully segmented \(books.count) books from shelf photo")

        return books
    }

    /// Calculates normalized bounding box (0-1 range) from pixel buffer
    private func calculateBounds(from buffer: CVPixelBuffer, fullImageSize: CGSize) -> CGRect {
        // Scan pixel buffer for non-zero alpha values
        // Return CGRect in normalized coordinates (0-1 range)
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)

        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let pixelBuffer = baseAddress.assumingMemoryBound(to: UInt8.self)

        var minX = width, maxX = 0
        var minY = height, maxY = 0

        // Scan pixel buffer to find bounds of non-transparent pixels
        for y in 0..<height {
            for x in 0..<width {
                let pixelIndex = y * bytesPerRow + x * 4  // RGBA format
                let alpha = pixelBuffer[pixelIndex + 3]

                if alpha > 0 {
                    minX = min(minX, x)
                    maxX = max(maxX, x)
                    minY = min(minY, y)
                    maxY = max(maxY, y)
                }
            }
        }

        // Avoid division by zero if no pixels found
        guard minX <= maxX && minY <= maxY else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }

        // Normalize to 0-1 range
        return CGRect(
            x: CGFloat(minX) / fullImageSize.width,
            y: CGFloat(minY) / fullImageSize.height,
            width: CGFloat(maxX - minX + 1) / fullImageSize.width,
            height: CGFloat(maxY - minY + 1) / fullImageSize.height
        )
    }
}

enum SegmentationError: Error, LocalizedError {
    case noInstancesFound
    case tooManyBooks(count: Int)
    case visionFrameworkError(Error)

    var errorDescription: String? {
        switch self {
        case .noInstancesFound:
            return "No books detected in image"
        case .tooManyBooks(let count):
            return "Too many objects detected (\(count)). Maximum is 20 books per photo."
        case .visionFrameworkError(let error):
            return "Vision processing failed: \(error.localizedDescription)"
        }
    }
}
