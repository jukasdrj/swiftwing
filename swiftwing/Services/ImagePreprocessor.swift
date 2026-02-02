//
//  ImagePreprocessor.swift
//  swiftwing
//
//  Created by Claude Code on 2026-02-01.
//

import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

/// Actor-isolated image preprocessing pipeline for book spine recognition
/// Applies contrast enhancement, brightness adjustment, denoising, and rotation correction
/// Runs OFF MainActor to avoid blocking UI during CIFilter processing
///
/// Performance target: < 500ms for 1920px max dimension images
/// Memory: Uses CIContext with RGBA8 working format for GPU optimization
actor ImagePreprocessor {

    /// Shared CIContext for filter rendering (reused across calls)
    private let ciContext: CIContext

    /// Processing metrics
    struct PreprocessingResult: Sendable, Codable {
        let processedData: Data
        let wasRotated: Bool
        let brightnessAdjustment: Float
        let processingTimeMs: Int
    }

    init() {
        // Use RGBA8 working format for optimized GPU/CPU handoff
        self.ciContext = CIContext(options: [
            .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            .highQualityDownsample: true
        ])
    }

    /// Full preprocessing pipeline
    func preprocess(_ imageData: Data) async -> PreprocessingResult {
        let startTime = CFAbsoluteTimeGetCurrent()

        guard let uiImage = UIImage(data: imageData),
              let cgImage = uiImage.cgImage else {
            return PreprocessingResult(
                processedData: imageData,
                wasRotated: false,
                brightnessAdjustment: 0,
                processingTimeMs: 0
            )
        }

        var ciImage = CIImage(cgImage: cgImage)

        // Step 1: Rotation detection and correction
        let wasRotated = detectAndCorrectRotation(&ciImage)

        // Step 2: Contrast enhancement (1.5x)
        applyContrastEnhancement(&ciImage, factor: 1.5)

        // Step 3: Adaptive brightness adjustment
        let brightnessAdj = applyAdaptiveBrightness(&ciImage)

        // Step 4: Noise reduction
        applyNoiseReduction(&ciImage)

        // Render to Data (JPEG, 0.85 quality)
        let outputData = renderToJPEG(ciImage, quality: 0.85) ?? imageData

        let duration = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)

        return PreprocessingResult(
            processedData: outputData,
            wasRotated: wasRotated,
            brightnessAdjustment: brightnessAdj,
            processingTimeMs: duration
        )
    }

    // MARK: - Private Filter Methods

    /// Detect vertical bookshelf orientation and rotate 90° CCW if needed
    /// Returns true if rotation was applied
    private func detectAndCorrectRotation(_ image: inout CIImage) -> Bool {
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

    /// Apply contrast enhancement using CIColorControls filter
    private func applyContrastEnhancement(_ image: inout CIImage, factor: Float) {
        guard let filter = CIFilter(name: "CIColorControls") else {
            print("ImagePreprocessor: CIColorControls filter unavailable")
            return
        }

        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(factor, forKey: kCIInputContrastKey)

        guard let outputImage = filter.outputImage else {
            print("ImagePreprocessor: Contrast filter failed to produce output")
            return
        }

        image = outputImage
    }

    /// Apply adaptive brightness adjustment based on image luminance
    /// Returns the brightness adjustment value applied
    private func applyAdaptiveBrightness(_ image: inout CIImage) -> Float {
        // Calculate average luminance by downscaling to 64x64
        let avgLuminance = calculateAverageLuminance(image)

        // Determine brightness adjustment
        let targetLuminance: Float = 128.0 // Mid-gray
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
                print("ImagePreprocessor: CIColorControls filter unavailable for brightness")
                return 0.0
            }

            filter.setValue(image, forKey: kCIInputImageKey)
            filter.setValue(brightnessAdjustment, forKey: kCIInputBrightnessKey)

            guard let outputImage = filter.outputImage else {
                print("ImagePreprocessor: Brightness filter failed to produce output")
                return 0.0
            }

            image = outputImage
        }

        return brightnessAdjustment
    }

    /// Calculate average luminance by sampling a downscaled version
    private func calculateAverageLuminance(_ image: CIImage) -> Float {
        // Downscale to 64x64 for performance
        let extent = image.extent
        let scaleX = 64.0 / extent.width
        let scaleY = 64.0 / extent.height
        let scale = min(scaleX, scaleY)

        let transform = CGAffineTransform(scaleX: scale, y: scale)
        let scaledImage = image.transformed(by: transform)

        // Use CIAreaAverage to get average color
        guard let filter = CIFilter(name: "CIAreaAverage") else {
            print("ImagePreprocessor: CIAreaAverage filter unavailable")
            return 128.0 // Default to mid-gray
        }

        filter.setValue(scaledImage, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgRect: scaledImage.extent), forKey: kCIInputExtentKey)

        guard let outputImage = filter.outputImage else {
            print("ImagePreprocessor: Average luminance calculation failed")
            return 128.0
        }

        // Render single pixel to bitmap
        var bitmap = [UInt8](repeating: 0, count: 4)
        ciContext.render(outputImage,
                        toBitmap: &bitmap,
                        rowBytes: 4,
                        bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                        format: .RGBA8,
                        colorSpace: CGColorSpace(name: CGColorSpace.sRGB))

        // Calculate luminance: 0.299*R + 0.587*G + 0.114*B
        let r = Float(bitmap[0])
        let g = Float(bitmap[1])
        let b = Float(bitmap[2])
        let luminance = 0.299 * r + 0.587 * g + 0.114 * b

        return luminance
    }

    /// Apply light noise reduction while preserving text detail
    private func applyNoiseReduction(_ image: inout CIImage) {
        guard let filter = CIFilter(name: "CINoiseReduction") else {
            print("ImagePreprocessor: CINoiseReduction filter unavailable")
            return
        }

        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(0.02, forKey: "inputNoiseLevel")
        filter.setValue(0.4, forKey: "inputSharpness")

        guard let outputImage = filter.outputImage else {
            print("ImagePreprocessor: Noise reduction failed to produce output")
            return
        }

        image = outputImage
    }

    /// Render CIImage to JPEG Data with specified quality
    private func renderToJPEG(_ image: CIImage, quality: CGFloat) -> Data? {
        // Primary method: Use CIContext JPEG representation
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        if let jpegData = ciContext.jpegRepresentation(
            of: image,
            colorSpace: colorSpace,
            options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: quality]
        ) {
            return jpegData
        }

        // Fallback: Render to CGImage then UIImage JPEG
        guard let cgImage = ciContext.createCGImage(image, from: image.extent) else {
            print("ImagePreprocessor: Failed to create CGImage from CIImage")
            return nil
        }

        let uiImage = UIImage(cgImage: cgImage)
        return uiImage.jpegData(compressionQuality: quality)
    }
}
