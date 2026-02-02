import CoreImage
import Vision
import Accelerate
import Foundation

/// Hough Line Transform-based book spine segmentation
/// Inspired by: https://github.com/LakshyaKhatri/Bookshelf-Reader-API
/// Uses edge detection + vertical line detection to find spine boundaries
actor HoughLineSegmentationService {
    /// Segment books by detecting vertical spine edges using Hough Line Transform
    /// - Parameter image: Full bookshelf CIImage
    /// - Returns: Array of SegmentedBook with cropped spine regions
    func segmentBooksByVerticalLines(from image: CIImage) async throws -> [SegmentedBook] {
        // Step 1: Convert to grayscale
        let grayscaleImage = image.applyingFilter("CIPhotoEffectMono")

        // Step 2: Edge detection using Vision framework
        let edgeImage = try await detectEdges(in: grayscaleImage)

        // Step 3: Detect vertical lines (spine boundaries)
        let verticalLines = try await detectVerticalLines(in: edgeImage)

        guard !verticalLines.isEmpty else {
            throw SegmentationError.noInstancesFound
        }

        // Step 4: Group lines into book boundaries (pairs of lines = 1 book)
        let bookRegions = groupLinesIntoBooks(verticalLines, imageWidth: image.extent.width)

        print("📐 Hough: \(bookRegions.count) books from \(verticalLines.count) lines")

        // Step 5: Crop each book region
        var books: [SegmentedBook] = []
        for (index, region) in bookRegions.enumerated() {
            let croppedImage = cropImage(image, to: region)
            books.append(SegmentedBook(
                instanceID: index + 1,
                croppedImage: croppedImage,
                boundingBox: region
            ))
        }

        return books
    }

    // MARK: - Edge Detection

    private func detectEdges(in image: CIImage) async throws -> CIImage {
        // Use CIEdges filter for Canny-style edge detection
        guard let edgeFilter = CIFilter(name: "CIEdges") else {
            throw SegmentationError.visionFrameworkError(
                NSError(domain: "HoughLine", code: -1, userInfo: [NSLocalizedDescriptionKey: "CIEdges filter unavailable"])
            )
        }

        edgeFilter.setValue(image, forKey: kCIInputImageKey)
        edgeFilter.setValue(1.5, forKey: kCIInputIntensityKey)  // Intensity controls sensitivity

        guard let outputImage = edgeFilter.outputImage else {
            throw SegmentationError.visionFrameworkError(
                NSError(domain: "HoughLine", code: -2, userInfo: [NSLocalizedDescriptionKey: "Edge detection failed"])
            )
        }

        return outputImage
    }

    // MARK: - Vertical Line Detection

    private func detectVerticalLines(in edgeImage: CIImage) async throws -> [VerticalLine] {
        // Use VNDetectHorizonRequest as inspiration - Vision framework doesn't have direct Hough API
        // Fallback: Rectangle detection with vertical aspect ratio constraint
        let request = VNDetectRectanglesRequest()
        request.minimumAspectRatio = 0.1  // Very tall/narrow rectangles (spine-like)
        request.maximumAspectRatio = 0.3
        request.minimumSize = 0.05  // At least 5% of image height
        request.maximumObservations = 40  // Allow many detections for dense shelves

        let handler = VNImageRequestHandler(ciImage: edgeImage, options: [:])

        do {
            try handler.perform([request])
        } catch {
            throw SegmentationError.visionFrameworkError(error)
        }

        guard let rectangles = request.results, !rectangles.isEmpty else {
            throw SegmentationError.noInstancesFound
        }

        // Convert rectangles to vertical lines (use left/right edges)
        var lines: [VerticalLine] = []
        for rect in rectangles {
            let bbox = rect.boundingBox

            // Left edge of rectangle
            lines.append(VerticalLine(
                x: bbox.minX,
                y1: bbox.minY,
                y2: bbox.maxY,
                confidence: rect.confidence
            ))

            // Right edge of rectangle
            lines.append(VerticalLine(
                x: bbox.maxX,
                y1: bbox.minY,
                y2: bbox.maxY,
                confidence: rect.confidence
            ))
        }

        // Sort by x-coordinate (left to right)
        lines.sort { $0.x < $1.x }

        // Remove duplicate lines (within 25 pixels, per original algorithm)
        let deduplicatedLines = removeDuplicateLines(lines, threshold: 0.05)  // 5% of image width

        return deduplicatedLines
    }

    private func removeDuplicateLines(_ lines: [VerticalLine], threshold: CGFloat) -> [VerticalLine] {
        var uniqueLines: [VerticalLine] = []
        var lastX: CGFloat = -1.0

        for line in lines {
            if lastX < 0 || abs(line.x - lastX) >= threshold {
                uniqueLines.append(line)
                lastX = line.x
            }
        }

        return uniqueLines
    }

    // MARK: - Book Region Grouping

    private func groupLinesIntoBooks(_ lines: [VerticalLine], imageWidth: CGFloat) -> [CGRect] {
        // Each pair of consecutive lines defines a book
        // Line[i] = left edge, Line[i+1] = right edge

        var regions: [CGRect] = []

        // If odd number of lines, ignore the last one
        let pairCount = lines.count / 2

        for i in 0..<pairCount {
            let leftLine = lines[i * 2]
            let rightLine = lines[i * 2 + 1]

            // Create bounding box
            let x = leftLine.x
            let width = rightLine.x - leftLine.x
            let y = min(leftLine.y1, rightLine.y1)
            let height = max(leftLine.y2, rightLine.y2) - y

            // Validate region (must be tall and narrow)
            let aspectRatio = width / height
            if aspectRatio > 0.05 && aspectRatio < 0.5 && width > 0.02 {
                regions.append(CGRect(x: x, y: y, width: width, height: height))
            }
        }

        return regions
    }

    // MARK: - Image Cropping

    private func cropImage(_ image: CIImage, to region: CGRect) -> CIImage {
        // Convert normalized coordinates to pixel coordinates
        let imageExtent = image.extent
        let pixelRect = CGRect(
            x: region.origin.x * imageExtent.width,
            y: region.origin.y * imageExtent.height,
            width: region.width * imageExtent.width,
            height: region.height * imageExtent.height
        )

        return image.cropped(to: pixelRect)
    }
}

// MARK: - Supporting Types

struct VerticalLine {
    let x: CGFloat          // Normalized x-coordinate (0-1)
    let y1: CGFloat         // Top y-coordinate (0-1)
    let y2: CGFloat         // Bottom y-coordinate (0-1)
    let confidence: Float   // Detection confidence
}
