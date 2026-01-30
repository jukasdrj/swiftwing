//
//  VisionOverlayView.swift
//  swiftwing
//
//  Created by Claude Code on 2026-01-30.
//

import SwiftUI

// Import VisionTypes for TextRegion
// Note: VisionTypes.swift is in Services/ directory but imports work via Xcode target membership

// MARK: - VisionOverlayView

/// Real-time text overlay that renders detected text regions with bounding boxes.
/// Displays Vision framework results with Swiss Glass design aesthetics.
///
/// Features:
/// - Normalized coordinate conversion (Vision uses 0-1, bottom-left origin)
/// - Confidence-based prominence (high confidence = more opaque)
/// - Smooth fade in/out animations
/// - White borders for bounding boxes
/// - .ultraThinMaterial text labels
///
/// Usage:
/// ```swift
/// ZStack {
///     CameraPreviewView(session: session)
///     VisionOverlayView(textRegions: detectedRegions)
/// }
/// ```
struct VisionOverlayView: View {
    /// Array of detected text regions from Vision framework
    let textRegions: [TextRegion]

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Render each text region with bounding box and label
                ForEach(Array(textRegions.enumerated()), id: \.offset) { _, region in
                    TextRegionOverlay(
                        region: region,
                        viewSize: geometry.size
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    .animation(.swissSpring, value: textRegions.count)
                }
            }
        }
    }
}

// MARK: - TextRegionOverlay

/// Individual text region overlay with bounding box and label.
/// Converts Vision's normalized coordinates (0-1, bottom-left origin) to SwiftUI screen space.
private struct TextRegionOverlay: View {
    let region: TextRegion
    let viewSize: CGSize

    /// Opacity based on confidence level
    /// - High confidence (>0.8): 100% opaque
    /// - Medium confidence (0.5-0.8): 70% opaque
    /// - Low confidence (<0.5): 40% opaque
    private var opacity: Double {
        switch region.confidence {
        case 0.8...1.0:
            return 1.0
        case 0.5..<0.8:
            return 0.7
        default:
            return 0.4
        }
    }

    /// Border width based on confidence level
    /// High confidence regions get thicker borders for prominence
    private var borderWidth: CGFloat {
        region.confidence > 0.8 ? 2.0 : 1.0
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Bounding box rectangle
            Rectangle()
                .strokeBorder(Color.white, lineWidth: borderWidth)
                .frame(width: convertedRect.width, height: convertedRect.height)
                .opacity(opacity)

            // Text label with glass background
            if !region.text.isEmpty {
                Text(region.text)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.swissText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.8))
                    .background(.ultraThinMaterial)
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.white.opacity(0.3), lineWidth: 1)
                    )
                    .opacity(opacity)
                    .offset(x: labelOffset.x, y: labelOffset.y)
            }
        }
        .position(x: convertedRect.midX, y: convertedRect.midY)
    }

    // MARK: - Coordinate Conversion

    /// Convert Vision's normalized coordinates (0-1, bottom-left origin) to SwiftUI screen space (top-left origin)
    ///
    /// Vision Framework Coordinate System:
    /// - Origin: Bottom-left (0, 0)
    /// - Range: 0.0 to 1.0 (normalized)
    /// - Y-axis: Increases upward
    ///
    /// SwiftUI Coordinate System:
    /// - Origin: Top-left (0, 0)
    /// - Range: 0 to viewSize (pixels)
    /// - Y-axis: Increases downward
    private var convertedRect: CGRect {
        let visionRect = region.boundingBox

        // Convert normalized coordinates to pixel coordinates
        let x = visionRect.origin.x * viewSize.width
        let width = visionRect.width * viewSize.width
        let height = visionRect.height * viewSize.height

        // Flip Y-axis: Vision's bottom-left origin → SwiftUI's top-left origin
        let y = viewSize.height - (visionRect.origin.y * viewSize.height) - height

        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// Smart label positioning to avoid overlap with bounding box
    /// - High confidence: Label inside box (top-left corner)
    /// - Low confidence: Label above box (to reduce clutter)
    private var labelOffset: CGPoint {
        if region.confidence > 0.8 {
            // High confidence: label inside, top-left with padding
            return CGPoint(x: 4, y: 4)
        } else {
            // Low confidence: label above box
            return CGPoint(x: 0, y: -24)
        }
    }
}

// MARK: - Preview

#Preview("Text Overlay - High Confidence") {
    VisionOverlayView(textRegions: [
        TextRegion(
            boundingBox: CGRect(x: 0.2, y: 0.6, width: 0.6, height: 0.15),
            text: "The Great Gatsby",
            confidence: 0.95
        ),
        TextRegion(
            boundingBox: CGRect(x: 0.25, y: 0.5, width: 0.5, height: 0.08),
            text: "F. Scott Fitzgerald",
            confidence: 0.88
        )
    ])
    .background(Color.swissBackground)
}

#Preview("Text Overlay - Mixed Confidence") {
    VisionOverlayView(textRegions: [
        TextRegion(
            boundingBox: CGRect(x: 0.1, y: 0.7, width: 0.8, height: 0.12),
            text: "CLEAR TITLE",
            confidence: 0.92
        ),
        TextRegion(
            boundingBox: CGRect(x: 0.15, y: 0.5, width: 0.7, height: 0.1),
            text: "Partial Text",
            confidence: 0.65
        ),
        TextRegion(
            boundingBox: CGRect(x: 0.2, y: 0.3, width: 0.6, height: 0.08),
            text: "Fuzzy",
            confidence: 0.42
        )
    ])
    .background(Color.swissBackground)
}

#Preview("Empty Overlay") {
    VisionOverlayView(textRegions: [])
        .background(Color.swissBackground)
}
