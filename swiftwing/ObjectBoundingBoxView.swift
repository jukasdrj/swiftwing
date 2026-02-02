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
        // Vision uses bottom-left origin, SwiftUI uses top-left
        let flippedY = 1.0 - visionRect.origin.y - visionRect.height

        // Scale from normalized [0,1] to view points
        let x = visionRect.origin.x * viewSize.width
        let y = flippedY * viewSize.height
        let width = visionRect.width * viewSize.width
        let height = visionRect.height * viewSize.height

        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// Line width based on confidence (high confidence = thicker border)
    private func confidenceBasedLineWidth(_ confidence: Float) -> CGFloat {
        return confidence > 0.85 ? 3.0 : 2.0
    }
}
