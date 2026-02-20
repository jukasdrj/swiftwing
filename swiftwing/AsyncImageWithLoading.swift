import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

// MARK: - URL ATS Helper
extension URL {
    /// Upgrades http:// to https:// to satisfy iOS App Transport Security.
    /// Talaria may return http:// cover URLs; ATS blocks them without this upgrade.
    var upgradedToHTTPS: URL {
        guard scheme?.lowercased() == "http" else { return self }
        var components = URLComponents(url: self, resolvingAgainstBaseURL: false)
        components?.scheme = "https"
        return components?.url ?? self
    }
}

// MARK: - Shimmer Effect View
/// Animated gradient shimmer for loading states
/// Matches Swiss Glass aesthetic with white glow on black
struct ShimmerView: View {
    @State private var animationPhase: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .white.opacity(0.3), location: 0.4),
                    .init(color: .white.opacity(0.5), location: 0.5),
                    .init(color: .white.opacity(0.3), location: 0.6),
                    .init(color: .clear, location: 1)
                ]),
                startPoint: .leading,
                endPoint: .trailing
            )
            .offset(x: animationPhase * geometry.size.width * 2 - geometry.size.width)
            .onAppear {
                withAnimation(
                    .linear(duration: 1.5)
                    .repeatForever(autoreverses: false)
                ) {
                    animationPhase = 1
                }
            }
        }
    }
}

// MARK: - Async Image with Loading States
/// AsyncImage wrapper with skeleton shimmer, error states, and retry functionality
/// Uses ImageCacheManager's optimized URLSession for caching
///
/// Usage:
/// ```swift
/// AsyncImageWithLoading(url: book.coverUrl)
///     .frame(width: 100, height: 150)
///     .cornerRadius(8)
/// ```
struct GeneratedCoverView: View {
    let title: String
    let author: String

    private static let coverPalette: [Color] = [
        Color(red: 0.6, green: 0.2, blue: 0.2),
        Color(red: 0.2, green: 0.4, blue: 0.6),
        Color(red: 0.4, green: 0.3, blue: 0.6),
        Color(red: 0.2, green: 0.5, blue: 0.4),
        Color(red: 0.6, green: 0.4, blue: 0.2),
        Color(red: 0.3, green: 0.5, blue: 0.3),
        Color(red: 0.5, green: 0.2, blue: 0.4),
        Color(red: 0.3, green: 0.3, blue: 0.5),
    ]

    private var baseColor: Color {
        // Safe hashValue to non-negative index: mask off sign bit to avoid abs() trap on Int.min
        let index = Int(UInt(bitPattern: title.hashValue) % UInt(Self.coverPalette.count))
        return Self.coverPalette[index]
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [baseColor, baseColor.opacity(0.6)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(spacing: 4) {
                Text(title)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)

                Text(author)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .padding(8)
        }
    }
}

struct AsyncImageWithLoading: View {
    let url: URL?
    var title: String?
    var author: String?
    @State private var loadedImage: UIImage?
    @State private var isLoading = false
    @State private var loadFailed = false
    @State private var retryTrigger = UUID()

    var body: some View {
        Group {
            if url == nil {
                noCoverPlaceholderView
            } else if let image = loadedImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .transition(.opacity)
            } else if loadFailed {
                errorStateView
            } else {
                loadingStateView
            }
        }
        .task(id: retryTrigger) {
            await loadImage()
        }
    }

    // MARK: - Loading State
    private var loadingStateView: some View {
        ZStack {
            // Base layer: Black + ultraThinMaterial for glass effect
            Rectangle()
                .fill(.black)
                .background(.ultraThinMaterial)

            // Shimmer animation overlay
            ShimmerView()
                .blendMode(.overlay)
        }
    }

    // MARK: - Error State
    private var errorStateView: some View {
        ZStack {
            // Base layer: Dark background
            Rectangle()
                .fill(Color.gray.opacity(0.2))
                .background(.ultraThinMaterial)

            // Error icon and retry button
            VStack(spacing: 8) {
                Image(systemName: "photo.badge.exclamationmark")
                    .font(.title2)
                    .foregroundColor(.gray)

                Button {
                    retryLoad()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption2)
                        Text("Retry")
                            .font(.caption2)
                    }
                    .foregroundColor(Color.swissText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .frame(minHeight: 28)
                    .background(.ultraThinMaterial)
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5)
                    )
                }
                .accessibilityIdentifier("image_retry")
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - No Cover Placeholder
    private var noCoverPlaceholderView: some View {
        Group {
            if let title = title, let author = author {
                GeneratedCoverView(title: title, author: author)
            } else if let title = title {
                GeneratedCoverView(title: title, author: "")
            } else {
                ZStack {
                    Rectangle()
                        .fill(Color.gray.opacity(0.15))
                        .background(.ultraThinMaterial)

                    VStack(spacing: 6) {
                        Image(systemName: "book.closed")
                            .font(.title2)
                            .foregroundColor(.gray.opacity(0.6))
                        Text("No Cover")
                            .font(.caption2)
                            .foregroundColor(.gray.opacity(0.6))
                    }
                }
            }
        }
    }

    // MARK: - Actions
    private func retryLoad() {
        withAnimation(Animation.swissSpring) {
            loadFailed = false
            retryTrigger = UUID()
        }
    }

    /// Loads image using ImageCacheManager's optimized URLSession
    private func loadImage() async {
        guard let url = url?.upgradedToHTTPS else {
            loadFailed = true
            return
        }

        guard !isLoading else { return }

        isLoading = true
        loadFailed = false

        do {
            // Use ImageCacheManager's URLSession for automatic caching
            let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad)
            let session = ImageCacheManager.shared.urlSession
            let (data, _) = try await session.data(for: request)

            if let uiImage = UIImage(data: data) {
                withAnimation(Animation.swissSpring) {
                    loadedImage = uiImage
                }
            } else {
                loadFailed = true
            }
        } catch {
            loadFailed = true
        }

        isLoading = false
    }
}

// MARK: - Preview
#Preview("Loading State") {
    VStack(spacing: 20) {
        // Loading shimmer (nil URL triggers .empty state)
        AsyncImageWithLoading(url: nil)
            .frame(width: 100, height: 150)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
            )

        Text("Loading State (Shimmer)")
            .foregroundColor(Color.swissText)
    }
    .padding()
    .background(Color.swissBackground)
}

#Preview("Error State") {
    VStack(spacing: 20) {
        // Invalid URL triggers .failure state
        AsyncImageWithLoading(url: URL(string: "https://invalid.url.test/image.jpg"))
            .frame(width: 100, height: 150)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
            )

        Text("Error State (Retry Button)")
            .foregroundColor(Color.swissText)
    }
    .padding()
    .background(Color.swissBackground)
}

#Preview("Success State") {
    VStack(spacing: 20) {
        // Valid URL shows image
        AsyncImageWithLoading(url: URL(string: "https://covers.openlibrary.org/b/isbn/9780544003415-L.jpg"))
            .frame(width: 100, height: 150)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
            )

        Text("Success State (Image Loaded)")
            .foregroundColor(Color.swissText)
    }
    .padding()
    .background(Color.swissBackground)
}
