import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

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
///
/// Usage:
/// ```swift
/// AsyncImageWithLoading(url: book.coverUrl)
///     .frame(width: 100, height: 150)
///     .cornerRadius(8)
/// ```
struct AsyncImageWithLoading: View {
    let url: URL?
    @State private var retryTrigger = UUID()

    var body: some View {
        AsyncImage(url: url, transaction: Transaction(animation: Animation.swissSpring)) { phase in
            switch phase {
            case .empty:
                loadingStateView
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .transition(.opacity)
            case .failure:
                errorStateView
            @unknown default:
                loadingStateView
            }
        }
        .id(retryTrigger) // Trigger reload when retryTrigger changes
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
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Actions
    private func retryLoad() {
        withAnimation(Animation.swissSpring) {
            retryTrigger = UUID()
        }
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
