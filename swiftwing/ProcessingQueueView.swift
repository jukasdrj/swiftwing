import SwiftUI
import UIKit

/// Processing queue UI showing live thumbnails of captured images
/// Horizontal scrolling view above shutter button
struct ProcessingQueueView: View {
    let items: [ProcessingItem]
    let onRetry: (ProcessingItem) -> Void  // US-407: Retry callback for failed items

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Main queue (only show if items exist)
            if !items.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 8) {
                        ForEach(items) { item in
                            ProcessingThumbnailView(item: item, onRetry: onRetry)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .frame(height: 60)  // Accommodate larger thumbnails
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
/// 60x90px with state-based border color and progress text overlay
struct ProcessingThumbnailView: View {
    let item: ProcessingItem
    let onRetry: (ProcessingItem) -> Void  // US-407: Retry callback

    var body: some View {
        ZStack {
            // Thumbnail image (pre-processed to 60x90px for performance)
            if let uiImage = UIImage(data: item.thumbnailData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 60, height: 90)
                    .clipped()
                    .cornerRadius(4)
            } else {
                // Fallback for invalid image data
                Color.gray.opacity(0.3)
                    .frame(width: 60, height: 90)
                    .cornerRadius(4)
            }

            // Progress text overlay (if available)
            if let progressMessage = item.progressMessage {
                VStack {
                    Spacer()
                    Text(progressMessage)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(2)
                        .padding(.bottom, 2)
                }
                .frame(width: 60, height: 90)
            }

            // US-407: Error icon overlay (if error state)
            if item.state == .error {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.red)
                    .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
            }

            // US-407: Error message overlay (if error message available)
            if let errorMessage = item.errorMessage {
                VStack {
                    Spacer()
                    Text(errorMessage)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.9))
                        .cornerRadius(2)
                        .padding(.bottom, 2)
                }
                .frame(width: 60, height: 90)
            }

            // State-based border
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(item.state.borderColor, lineWidth: 2)
                .frame(width: 60, height: 90)

            // US-407: Retry button overlay (only for error state)
            if item.state == .error {
                Button(action: {
                    onRetry(item)
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 24, height: 24)
                        .background(Color.red)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                }
                .buttonStyle(PlainButtonStyle())
                .offset(y: 20)  // Position below center
            }
        }
        .transition(.scale.combined(with: .opacity))
    }
}

#Preview {
    // Preview with sample items
    let sampleData = UIImage(systemName: "book")!
        .pngData() ?? Data()

    var errorItem = ProcessingItem(imageData: sampleData, state: .error)
    errorItem.errorMessage = "No text found"

    let items = [
        ProcessingItem(imageData: sampleData, state: .uploading, progressMessage: "Uploading..."),
        ProcessingItem(imageData: sampleData, state: .analyzing, progressMessage: "Looking..."),
        ProcessingItem(imageData: sampleData, state: .done),
        errorItem
    ]

    return ZStack {
        Color.black.ignoresSafeArea()

        VStack {
            Spacer()

            ProcessingQueueView(items: items, onRetry: { item in
                print("Retry item: \(item.id)")
            })
                .padding(.bottom, 140)
        }
    }
    .preferredColorScheme(.dark)
}
