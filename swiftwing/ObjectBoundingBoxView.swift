//
//  ObjectBoundingBoxView.swift
//  swiftwing
//
//  Created by Claude Code on 2026-02-01.
//

import SwiftUI

/// Displays green bounding boxes for detected rectangle objects (potential book spines).
/// Uses Swiss Glass design with frosted overlay and confidence-based visual hierarchy.
struct ObjectBoundingBoxView: View {
    let detectedObjects: [DetectedObject]
    let imageSize: CGSize

    var body: some View {
        GeometryReader { geometry in
            let _ = print("🎨 ObjectBoundingBoxView: Rendering \(detectedObjects.count) boxes, viewSize=\(geometry.size)")

            ForEach(detectedObjects, id: \.observationUUID) { object in
                let rect = convertToViewCoordinates(
                    visionRect: object.boundingBox,
                    imageSize: imageSize,
                    viewSize: geometry.size
                )

                Rectangle()
                    .stroke(
                        Color.green.opacity(Double(object.confidence)),
                        lineWidth: confidenceBasedLineWidth(object.confidence)
                    )
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                    .animation(.spring(duration: 0.2), value: object.boundingBox)
            }
        }
    }

    /// Convert Vision framework normalized coordinates to SwiftUI view coordinates
    /// - Parameters:
    ///   - visionRect: Normalized CGRect from Vision (origin: bottom-left, range: [0,1])
    ///   - imageSize: Size of the captured image
    ///   - viewSize: Size of the preview view
    /// - Returns: CGRect in SwiftUI coordinates (origin: top-left, points)
    private func convertToViewCoordinates(
        visionRect: CGRect,
        imageSize: CGSize,
        viewSize: CGSize
    ) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }

        // Adjust imageSize for orientation if needed.
        // Assuming the app is Portrait and camera sensor is Landscape (standard).
        var effectiveImageSize = imageSize
        if viewSize.height > viewSize.width && imageSize.width > imageSize.height {
            effectiveImageSize = CGSize(width: imageSize.height, height: imageSize.width)
        }

        // Calculate Aspect Fill scale
        let widthRatio = viewSize.width / effectiveImageSize.width
        let heightRatio = viewSize.height / effectiveImageSize.height
        let scale = max(widthRatio, heightRatio)

        let scaledWidth = effectiveImageSize.width * scale
        let scaledHeight = effectiveImageSize.height * scale

        let offsetX = (viewSize.width - scaledWidth) / 2
        let offsetY = (viewSize.height - scaledHeight) / 2

        // Vision uses bottom-left origin, SwiftUI uses top-left
        // Normalized coordinates relative to the effective image
        let x = visionRect.origin.x * effectiveImageSize.width
        let y = (1.0 - visionRect.maxY) * effectiveImageSize.height
        let width = visionRect.width * effectiveImageSize.width
        let height = visionRect.height * effectiveImageSize.height

        return CGRect(
            x: x * scale + offsetX,
            y: y * scale + offsetY,
            width: width * scale,
            height: height * scale
        )
    }

    /// Line width based on confidence (high confidence = thicker border)
    private func confidenceBasedLineWidth(_ confidence: Float) -> CGFloat {
        return confidence > 0.85 ? 3.0 : 2.0
    }
}
