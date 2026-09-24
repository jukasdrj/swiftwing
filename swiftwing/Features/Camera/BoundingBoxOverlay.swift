import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

/// Full-screen sheet showing the original captured photo with bounding box overlay
/// highlighting the detected book spine position from Talaria AI.
/// Pinch to zoom, two fingers to rotate, one finger to pan once moved. The box is
/// inside the same transform as the photo, so it stays on the spine.
struct BoundingBoxOverlay: View {
    let photoURL: URL
    let boundingBox: BoundingBox
    let bookTitle: String

    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var magnification: CGFloat = 1
    @State private var baseMagnification: CGFloat = 1
    @State private var rotation = Angle.zero
    @State private var baseRotation = Angle.zero
    @State private var pan: CGSize = .zero
    @State private var basePan: CGSize = .zero
    @State private var twoFingerGestureActive = false

    private let maximumMagnification: CGFloat = 5

    /// True once the photo is no longer sitting in its fitted frame.
    /// Sheet drag-to-dismiss stays available until then, so a pan can move the photo.
    private var photoIsMoved: Bool {
        magnification > 1.01 || abs(rotation.degrees) > 1
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.swissBackground.ignoresSafeArea()

            if let image {
                GeometryReader { geo in
                    let fitted = aspectFitSize(imageSize: image.size, in: geo.size)
                    let rect = boundingBox.toCGRect(in: fitted)

                    ZStack {
                        Image(uiImage: image)
                            .resizable()
                            .frame(width: fitted.width, height: fitted.height)
                            .accessibilityLabel("Photo of \(bookTitle)")

                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.internationalOrange, lineWidth: 3 / magnification)
                            .frame(width: rect.width, height: rect.height)
                            .offset(
                                x: rect.midX - fitted.width / 2,
                                y: rect.midY - fitted.height / 2
                            )
                            .allowsHitTesting(false)
                    }
                    .frame(width: fitted.width, height: fitted.height)
                    .scaleEffect(magnification)
                    .rotationEffect(rotation)
                    .offset(pan)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(magnifyGesture)
                    .simultaneousGesture(rotateGesture)
                    .simultaneousGesture(panGesture)
                    .onTapGesture(count: 2) { resetTransform() }
                    .accessibilityHint("Pinch to zoom. Rotate with two fingers. Double-tap to reset.")
                    .accessibilityZoomAction { action in
                        applyAccessibilityZoom(action)
                    }
                }
                .clipped()
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("Unable to load photo")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(16)
            }
            .accessibilityLabel("Close")
        }
        .overlay(alignment: .bottom) {
            if image != nil {
                Text(bookTitle)
                    .font(.subheadline.bold())
                    .foregroundStyle(.swissText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .swissGlassOverlay()
                    .padding(.bottom, 24)
                    .allowsHitTesting(false)
            }
        }
        .interactiveDismissDisabled(photoIsMoved)
        .onAppear {
            image = UIImage(contentsOfFile: photoURL.path)
        }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                twoFingerGestureActive = true
                let next = baseMagnification * value.magnification
                magnification = min(max(next, 1), maximumMagnification)
            }
            .onEnded { _ in
                twoFingerGestureActive = false
                baseMagnification = magnification
                if magnification <= 1.01 {
                    pan = .zero
                    basePan = .zero
                }
            }
    }

    private var rotateGesture: some Gesture {
        RotateGesture()
            .onChanged { value in
                twoFingerGestureActive = true
                rotation = baseRotation + value.rotation
            }
            .onEnded { _ in
                twoFingerGestureActive = false
                baseRotation = rotation
            }
    }

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard photoIsMoved, twoFingerGestureActive == false else { return }
                pan = CGSize(
                    width: basePan.width + value.translation.width,
                    height: basePan.height + value.translation.height
                )
            }
            .onEnded { _ in
                basePan = pan
            }
    }

    private func resetTransform() {
        withAnimation(.swissSpring) {
            magnification = 1
            baseMagnification = 1
            rotation = .zero
            baseRotation = .zero
            pan = .zero
            basePan = .zero
        }
    }

    private func applyAccessibilityZoom(_ action: AccessibilityZoomGestureAction) {
        switch action.direction {
        case .zoomIn:
            magnification = min(magnification * 1.25, maximumMagnification)
        case .zoomOut:
            magnification = max(magnification / 1.25, 1)
        }
        baseMagnification = magnification
        if magnification <= 1.01 {
            pan = .zero
            basePan = .zero
        }
    }

    /// Calculate the rendered size of an image when displayed with aspect fit.
    /// `UIImage.size` is the upright size, which matches the pixels Talaria measured
    /// after EXIF orientation is baked into the upload.
    private func aspectFitSize(imageSize: CGSize, in containerSize: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let widthRatio = containerSize.width / imageSize.width
        let heightRatio = containerSize.height / imageSize.height
        let scale = min(widthRatio, heightRatio)
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }
}
