import SwiftUI
import UIKit

/// Processing queue UI showing live thumbnails of captured images
/// Horizontal scrolling view above shutter button
struct ProcessingQueueView: View {
    let items: [ProcessingItem]

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Main queue (only show if items exist)
            if !items.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 8) {
                        ForEach(items) { item in
                            ProcessingThumbnailView(item: item)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .frame(height: 40)
            }

            // Count badge (only show if > 3 items)
            if items.count > 3 {
                Text("\(items.count)")
                    .font(.caption.bold())
                    .foregroundColor(.black)
                    .frame(minWidth: 24, minHeight: 24)
                    .background(Color.white)
                    .clipShape(Circle())
                    .padding(.trailing, 16)
                    .padding(.top, 8)
            }
        }
    }
}

/// Individual thumbnail in the processing queue
/// 40x60px with state-based border color
struct ProcessingThumbnailView: View {
    let item: ProcessingItem

    var body: some View {
        ZStack {
            // Thumbnail image (pre-processed to 40x60px for performance)
            if let uiImage = UIImage(data: item.thumbnailData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 40, height: 60)
                    .clipped()
                    .cornerRadius(4)
            } else {
                // Fallback for invalid image data
                Color.gray.opacity(0.3)
                    .frame(width: 40, height: 60)
                    .cornerRadius(4)
            }

            // State-based border
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(item.state.borderColor, lineWidth: 2)
                .frame(width: 40, height: 60)
        }
        .transition(.scale.combined(with: .opacity))
    }
}

#Preview {
    // Preview with sample items
    let sampleData = UIImage(systemName: "book")!
        .pngData() ?? Data()

    let items = [
        ProcessingItem(imageData: sampleData, state: .processing),
        ProcessingItem(imageData: sampleData, state: .uploading),
        ProcessingItem(imageData: sampleData, state: .done)
    ]

    ZStack {
        Color.black.ignoresSafeArea()

        VStack {
            Spacer()

            ProcessingQueueView(items: items)
                .padding(.bottom, 140)
        }
    }
    .preferredColorScheme(.dark)
}
