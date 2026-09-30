//
//  ImagePreprocessor.swift
//  swiftwing
//
//  Created by Claude Code on 2026-02-01.
//

import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import os
import UniformTypeIdentifiers

private let logger = Logger(subsystem: "com.ooheynerds.swiftwing", category: "image-preprocessor")

/// Prepares one shelf photo for Talaria. Gemini receives those bytes unchanged.
///
/// Upright pixels, EXIF tag 1, long edge at most 1920. A dark or bright frame
/// gets one brightness nudge. A very narrow crop is turned once. Contrast and
/// noise reduction stay off: they rewrite spine color and small type.
/// The JPEG is encoded once, and an already-upright JPEG or PNG inside the
/// long-edge cap is uploaded as captured.
///
/// Performance target: < 500ms for 1920px max dimension images.
/// CPU-bound Core Image work runs off the actor executor.
actor ImagePreprocessor {
    /// Longest edge Talaria asks clients to send. Gemini's default image budget holds about this much.
    static let uploadLongEdge: CGFloat = 1920
    /// Shared CIContext for filter rendering (reused across calls)
    private let ciContext: CIContext

    /// Processing metrics
    struct PreprocessingResult: Sendable, Codable {
        let processedData: Data
        let wasRotated: Bool
        let brightnessAdjustment: Float
        let processingTimeMs: Int
        /// False when the capture bytes were already an upright JPEG or PNG inside the long-edge cap.
        let didReencode: Bool
    }

    init() {
        // Use RGBA8 working format for optimized GPU/CPU handoff
        ciContext = CIContext(options: [
            .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            .highQualityDownsample: true,
        ])
    }

    /// Full preprocessing pipeline
    /// CPU-bound CIFilter work runs in a detached task to avoid blocking the actor executor.
    func preprocess(_ imageData: Data) async -> PreprocessingResult {
        let startTime = CFAbsoluteTimeGetCurrent()

        // Capture context before entering the detached task (CIContext is thread-safe)
        let context = ciContext

        let prepared = await Task.detached(priority: .userInitiated) {
            guard let source = CIImage(data: imageData) else {
                return (imageData, false, Float(0), false)
            }
            // Upright pixels before the bookshelf check, so that check sees the photo
            // the user shot, not the sensor buffer.
            let exif = ImagePreprocessor.exifOrientation(of: source)
            var ciImage = exif == 1 ? source : source.oriented(forExifOrientation: exif)

            let wasRotated = ImagePreprocessor.detectAndCorrectRotation(&ciImage)
            let brightnessAdj = ImagePreprocessor.applyAdaptiveBrightness(&ciImage, context: context)
            let didScale = ImagePreprocessor.scaleToLongEdge(&ciImage, maxDimension: ImagePreprocessor.uploadLongEdge)

            let unchanged = exif == 1 && !wasRotated && brightnessAdj == 0 && !didScale
            if unchanged, ImagePreprocessor.isJPEGOrPNG(imageData) {
                return (imageData, false, brightnessAdj, false)
            }

            let outputData = ImagePreprocessor.renderToJPEG(ciImage, context: context, quality: 0.85) ?? imageData
            return (outputData, wasRotated, brightnessAdj, outputData != imageData)
        }.value
        let (outputData, wasRotated, brightnessAdj, didReencode) = prepared

        let duration = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)
        let outputBytes = outputData.count
        let inputSize = Self.pixelSize(of: imageData)
        let outputSize = Self.pixelSize(of: outputData)
        let brightnessText = String(format: "%.3f", brightnessAdj)
        let sizeSummary = "\(inputSize.width)x\(inputSize.height) -> \(outputSize.width)x\(outputSize.height)"
        logger.info("Upload prep \(sizeSummary, privacy: .public) \(outputBytes, privacy: .public)B")
        let flagSummary = "reencoded \(didReencode) rotated \(wasRotated) brightness \(brightnessText)"
        logger.info("Upload prep \(flagSummary, privacy: .public)")

        return PreprocessingResult(
            processedData: outputData,
            wasRotated: wasRotated,
            brightnessAdjustment: brightnessAdj,
            processingTimeMs: duration,
            didReencode: didReencode
        )
    }

    // MARK: - Private Filter Methods (nonisolated static — safe to call from detached tasks)

    /// Missing tag is treated as upright. Tag 1 is already upright.
    private static func exifOrientation(of image: CIImage) -> Int32 {
        let raw = image.properties[kCGImagePropertyOrientation as String]
        if let number = raw as? NSNumber {
            return number.int32Value
        }
        if let number = raw as? Int {
            return Int32(number)
        }
        return 1
    }

    private static func isJPEGOrPNG(_ data: Data) -> Bool {
        guard data.count >= 8 else { return false }
        let bytes = [UInt8](data.prefix(8))
        if bytes[0] == 0xFF, bytes[1] == 0xD8, bytes[2] == 0xFF {
            return true
        }
        return bytes == [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
    }

    private static func pixelSize(of data: Data) -> (width: Int, height: Int) {
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else {
            return (0, 0)
        }
        func dimension(_ key: CFString) -> Int {
            if let number = props[key] as? Int {
                return number
            }
            if let number = props[key] as? NSNumber {
                return number.intValue
            }
            return 0
        }
        return (dimension(kCGImagePropertyPixelWidth), dimension(kCGImagePropertyPixelHeight))
    }

    /// A missing orientation tag is upright. Any other tag still needs a bake.
    private static func orientationIsUpright(_ props: [CFString: Any]) -> Bool {
        let raw = props[kCGImagePropertyOrientation]
        if raw == nil {
            return true
        }
        if let number = raw as? NSNumber {
            return number.intValue == 1
        }
        if let number = raw as? Int {
            return number == 1
        }
        return false
    }

    /// Quarter-turn clockwise when the upright frame is taller than twice its width.
    /// Returns true if rotation was applied. A normal shelf does not take this path.
    private static func detectAndCorrectRotation(_ image: inout CIImage) -> Bool {
        let aspectRatio = image.extent.height / image.extent.width

        // Tall narrow image (aspect > 2.0) indicates vertical bookshelf
        guard aspectRatio > 2.0 else {
            return false
        }

        // Rotate 90 degrees counterclockwise
        let rotationTransform = CGAffineTransform(rotationAngle: -.pi / 2)
        image = image.transformed(by: rotationTransform)

        // Translate origin back to (0,0) after rotation
        let translationTransform = CGAffineTransform(translationX: 0, y: image.extent.height)
        image = image.transformed(by: translationTransform)

        return true
    }

    /// Shrink so the longest edge is `maxDimension`. A smaller photo is left alone.
    private static func scaleToLongEdge(_ image: inout CIImage, maxDimension: CGFloat) -> Bool {
        let extent = image.extent
        guard !extent.isInfinite, !extent.isNull, !extent.isEmpty else { return false }
        let longest = max(extent.width, extent.height)
        guard longest > maxDimension else { return false }
        let scale = maxDimension / longest
        image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return true
    }

    /// Apply adaptive brightness adjustment based on image luminance
    /// Returns the brightness adjustment value applied
    private static func applyAdaptiveBrightness(_ image: inout CIImage, context: CIContext) -> Float {
        // Calculate average luminance by downscaling to 64x64
        let avgLuminance = calculateAverageLuminance(image, context: context)

        // Determine brightness adjustment (target: mid-gray ~128)
        var brightnessAdjustment: Float = 0.0

        if avgLuminance < 100 {
            // Image is too dark - brighten
            brightnessAdjustment = 0.1 + (100 - avgLuminance) / 500.0
            brightnessAdjustment = min(brightnessAdjustment, 0.2) // Cap at +0.2
        } else if avgLuminance > 180 {
            // Image is too bright - darken
            brightnessAdjustment = -0.1 - (avgLuminance - 180) / 500.0
            brightnessAdjustment = max(brightnessAdjustment, -0.2) // Cap at -0.2
        }

        // Apply brightness adjustment if needed
        if brightnessAdjustment != 0.0 {
            guard let filter = CIFilter(name: "CIColorControls") else {
                logger.error("CIColorControls filter unavailable for brightness")
                return 0.0
            }

            filter.setValue(image, forKey: kCIInputImageKey)
            filter.setValue(brightnessAdjustment, forKey: kCIInputBrightnessKey)

            guard let outputImage = filter.outputImage else {
                logger.error("Brightness filter failed to produce output")
                return 0.0
            }

            image = outputImage
        }

        return brightnessAdjustment
    }

    /// Calculate average luminance by sampling a downscaled version
    private static func calculateAverageLuminance(_ image: CIImage, context: CIContext) -> Float {
        // Downscale to 64x64 for performance
        let extent = image.extent
        let scaleX = 64.0 / extent.width
        let scaleY = 64.0 / extent.height
        let scale = min(scaleX, scaleY)

        let transform = CGAffineTransform(scaleX: scale, y: scale)
        let scaledImage = image.transformed(by: transform)

        // Use CIAreaAverage to get average color
        guard let filter = CIFilter(name: "CIAreaAverage") else {
            logger.error("CIAreaAverage filter unavailable")
            return 128.0 // Default to mid-gray
        }

        filter.setValue(scaledImage, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgRect: scaledImage.extent), forKey: kCIInputExtentKey)

        guard let outputImage = filter.outputImage else {
            logger.error("Average luminance calculation failed")
            return 128.0
        }

        // Render single pixel to bitmap
        var bitmap = [UInt8](repeating: 0, count: 4)
        context.render(
            outputImage,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
        )

        // Calculate luminance: 0.299*R + 0.587*G + 0.114*B
        let r = Float(bitmap[0])
        let g = Float(bitmap[1])
        let b = Float(bitmap[2])
        return 0.299 * r + 0.587 * g + 0.114 * b
    }

    // MARK: - Resize and Compress (ImageIO)

    /// Resize and compress image data using ImageIO for memory efficiency.
    /// - Parameters:
    ///   - imageData: Source JPEG/PNG image data
    ///   - maxDimension: Maximum width or height in pixels (default 1920)
    ///   - compressionQuality: JPEG quality 0.0–1.0 (default 0.85)
    /// - Returns: Resized and compressed JPEG data
    /// - Throws: ImageProcessingError if the image cannot be read or encoded
    func resizeAndCompress(
        _ imageData: Data,
        maxDimension: CGFloat = ImagePreprocessor.uploadLongEdge,
        compressionQuality: Double = 0.85
    ) throws -> Data {
        // Create CGImageSource from raw data (zero-copy read)
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let pixelWidth = props[kCGImagePropertyPixelWidth] as? CGFloat,
              let pixelHeight = props[kCGImagePropertyPixelHeight] as? CGFloat
        else {
            throw ImageProcessingError.invalidImageData
        }

        // An upright JPEG or PNG already inside the cap is the upload body.
        // Re-encoding it here was the second JPEG pass.
        let longestEdge = max(pixelWidth, pixelHeight)
        if longestEdge <= maxDimension, Self.isJPEGOrPNG(imageData), Self.orientationIsUpright(props) {
            return imageData
        }

        let thumbnailMaxPixels = if longestEdge <= maxDimension {
            // No resize needed — still re-encode to normalise orientation/format
            Int(longestEdge)
        } else {
            Int(maxDimension)
        }

        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: thumbnailMaxPixels,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true, // Honour EXIF orientation
            kCGImageSourceShouldCacheImmediately: false,
        ]

        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ImageProcessingError.invalidImageData
        }

        // Encode to JPEG via ImageIO
        let outputData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            outputData,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw ImageProcessingError.compressionFailed
        }

        let destOptions: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: compressionQuality,
        ]
        CGImageDestinationAddImage(destination, thumbnail, destOptions as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            throw ImageProcessingError.compressionFailed
        }

        return outputData as Data
    }

    /// Writes the JPEG from `preprocess`. Does not filter again.
    /// An upright JPEG or PNG already inside the long-edge cap is copied through.
    /// - Parameter imageData: Output of `preprocess()`
    /// - Returns: URL of a temp JPEG file (auto-cleaned after 30 minutes)
    /// - Throws: ImageProcessingError on failure
    func processImageForUpload(_ imageData: Data) async throws -> URL {
        // Resize and compress using ImageIO (preprocessing already done by caller)
        let finalData = try resizeAndCompress(imageData)

        // Write to temp file
        let filename = "\(UUID().uuidString).jpg"
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try finalData.write(to: fileURL)

        // Schedule auto-cleanup after 30 minutes
        Task.detached(priority: .utility) {
            try? await Task.sleep(for: .seconds(1800))
            do {
                try FileManager.default.removeItem(at: fileURL)
                logger.debug("Fallback cleanup for temp file: \(filename, privacy: .public)")
            } catch CocoaError.fileNoSuchFile {
            } catch {
                logger.warning("Fallback cleanup failed for \(filename, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        return fileURL
    }

    /// Render CIImage to JPEG Data with specified quality.
    /// Pixels are written upright (orientation tag 1). `jpegRepresentation` copies a
    /// stale EXIF tag onto pixels that were already rotated, and the upload pass
    /// would apply that tag again.
    private static func renderToJPEG(_ image: CIImage, context: CIContext, quality: CGFloat) -> Data? {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let extent = image.extent.integral
        if !extent.isInfinite, !extent.isNull, !extent.isEmpty,
           let cgImage = context.createCGImage(image, from: extent, format: .RGBA8, colorSpace: colorSpace),
           let jpegData = jpegData(cgImage, quality: quality)
        {
            return jpegData
        }

        guard let cgImage = context.createCGImage(image, from: image.extent) else {
            logger.error("Failed to create CGImage from CIImage")
            return nil
        }
        return jpegData(cgImage, quality: quality)
    }

    private static func jpegData(_ cgImage: CGImage, quality: CGFloat) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality,
            kCGImagePropertyOrientation: 1,
        ]
        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
