import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

/// Full-screen sheet showing the original captured photo with bounding box overlay
/// highlighting the detected book spine position from Talaria AI
struct BoundingBoxOverlay: View {
    let photoURL: URL
    let boundingBox: BoundingBox
    let bookTitle: String

    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.swissBackground.ignoresSafeArea()

            if let image {
                GeometryReader { geo in
                    let fitted = aspectFitSize(imageSize: image.size, in: geo.size)
                    let offset = aspectFitOffset(fittedSize: fitted, in: geo.size)

                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .overlay {
                            // Bounding box rectangle
                            let rect = boundingBox.toCGRect(in: fitted)
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.internationalOrange, lineWidth: 3)
                                .frame(width: rect.width, height: rect.height)
                                .position(
                                    x: offset.x + rect.midX,
                                    y: offset.y + rect.midY
                                )
                        }
                        .overlay(alignment: .bottom) {
                            // Book title label
                            Text(bookTitle)
                                .font(.subheadline.bold())
                                .foregroundStyle(.swissText)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .swissGlassOverlay()
                                .padding(.bottom, 24)
                        }
                }
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

            // Close button
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(16)
            }
        }
        .transition(.opacity)
        .onAppear {
            image = UIImage(contentsOfFile: photoURL.path)
        }
    }

    // MARK: - Aspect Fit Helpers

    /// Calculate the rendered size of an image when displayed with .scaledToFit()
    private func aspectFitSize(imageSize: CGSize, in containerSize: CGSize) -> CGSize {
        let widthRatio = containerSize.width / imageSize.width
        let heightRatio = containerSize.height / imageSize.height
        let scale = min(widthRatio, heightRatio)
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }

    /// Calculate the top-left offset for a fitted image centered in its container
    private func aspectFitOffset(fittedSize: CGSize, in containerSize: CGSize) -> CGPoint {
        CGPoint(
            x: (containerSize.width - fittedSize.width) / 2,
            y: (containerSize.height - fittedSize.height) / 2
        )
    }
}
