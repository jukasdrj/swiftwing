import CoreImage
import SwiftUI
import Vision

/// Actor-isolated service for segmenting bookshelf photos into individual book spines
/// Uses iOS 26 GenerateForegroundInstanceMaskRequest for instance segmentation
actor InstanceSegmentationService {

    /// Segments a bookshelf image into individual book spines
    /// - Parameter image: Full bookshelf image as CIImage
    /// - Returns: Array of SegmentedBook with cropped images and bounding boxes
    func segmentBooks(from image: CIImage) async throws -> [SegmentedBook] {
        let request = GenerateForegroundInstanceMaskRequest()

        // Swift 6.2 / iOS 26 async API
        // Returns Optional<InstanceMaskObservation> directly, not an array
        let observationOrNil = try await request.perform(on: image)

        guard let observation = observationOrNil else { return [] }

        var books: [SegmentedBook] = []

        // Iterate over each detected instance (excluding background at index 0)
        let allInstances = observation.allInstances

        for instanceID in allInstances {
            // Skip background (0)
            if instanceID == 0 { continue }

            let singleInstance = IndexSet(integer: instanceID)

            // iOS 26 API uses ImageRequestHandler (not VNImageRequestHandler) and different parameter names
            let handler = ImageRequestHandler(image)

            // Generate masked, cropped image for this book (iOS 26 API)
            let croppedBuffer = try observation.generateMaskedImage(
                for: singleInstance,
                imageFrom: handler,
                croppedToInstancesExtent: true
            )

            // Generate full-size mask for bounding box calculation (iOS 26 API)
            let maskBuffer = try observation.generateMaskedImage(
                for: singleInstance,
                imageFrom: handler,
                croppedToInstancesExtent: false
            )
            let boundingBox = calculateBoundingBox(from: maskBuffer, imageSize: image.extent.size)

            books.append(
                SegmentedBook(
                    instanceID: instanceID,
                    croppedImage: CIImage(cvPixelBuffer: croppedBuffer),
                    boundingBox: boundingBox
                ))
        }

        print("📚 Successfully segmented \(books.count) books from shelf photo")
        return books
    }

    // User provided helper
    private func calculateBoundingBox(from maskBuffer: CVPixelBuffer, imageSize: CGSize) -> CGRect {
        CVPixelBufferLockBaseAddress(maskBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(maskBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(maskBuffer)
        let height = CVPixelBufferGetHeight(maskBuffer)

        guard let baseAddress = CVPixelBufferGetBaseAddress(maskBuffer) else { return .zero }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(maskBuffer)
        let bufferObj = baseAddress.assumingMemoryBound(to: UInt8.self)

        var minX = width
        var maxX = 0
        var minY = height
        var maxY = 0
        var found = false

        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x
                let value = bufferObj[offset]
                if value > 0 {
                    found = true
                    if x < minX { minX = x }
                    if x > maxX { maxX = x }
                    if y < minY { minY = y }
                    if y > maxY { maxY = y }
                }
            }
        }

        if !found { return .zero }

        let normalizedHeight = CGFloat(maxY - minY + 1) / CGFloat(height)
        let normalizedY = 1.0 - (CGFloat(maxY) / CGFloat(height)) - (1.0 / CGFloat(height))  // rough approx

        // Let's stick to standard rect and let UI flip if needed, OR flip here.
        // Given user snippet "convertVisionToSwiftUI" does `(1 - visionRect.origin.y - visionRect.height)`,
        // it expects Vision coordinates (Bottom-Left).

        return CGRect(
            x: CGFloat(minX) / CGFloat(width),
            y: 1.0 - (CGFloat(maxY) / CGFloat(height)),
            width: CGFloat(maxX - minX + 1) / CGFloat(width),
            height: normalizedHeight
        )
    }
}

// Ensure SegmentedBook struct exists or is compatible
// (It was in Models/SegmentedBook.swift)
