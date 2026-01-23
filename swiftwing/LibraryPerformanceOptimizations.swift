import SwiftUI
import SwiftData

#if canImport(UIKit)
import UIKit
#endif

// MARK: - US-321: Library Performance Optimizations
/// Extensions and utilities for optimizing LibraryView performance with large datasets

// MARK: - Prefetch Coordinator
/// Manages intelligent prefetching of cover images for visible and upcoming rows
@Observable
class LibraryPrefetchCoordinator {

    // MARK: - Properties
    private var visibleBookIDs: Set<UUID> = []
    private var prefetchedURLs: Set<URL> = []

    // MARK: - Prefetching Logic

    /// Update visible books and trigger prefetching for upcoming rows
    /// - Parameter books: Currently visible books in the library
    func updateVisibleBooks(_ books: [Book]) {
        let newIDs = Set(books.map { $0.id })

        // Only prefetch if visible set changed significantly
        guard newIDs != visibleBookIDs else { return }

        visibleBookIDs = newIDs

        // Extract cover URLs (filter nil)
        let coverURLs = books.compactMap { $0.coverUrl }

        // Prefetch images
        Task {
            await ImageCacheManager.shared.prefetchImages(urls: coverURLs)
        }

        // Track prefetched URLs
        prefetchedURLs.formUnion(coverURLs)
    }

    /// Prefetch images for a range of books (e.g., next 20 rows during scroll)
    /// - Parameters:
    ///   - books: Array of books to prefetch
    ///   - maxCount: Maximum number of images to prefetch (default: 20)
    func prefetchUpcoming(books: [Book], maxCount: Int = 20) {
        let urls = books
            .prefix(maxCount)
            .compactMap { $0.coverUrl }
            .filter { !prefetchedURLs.contains($0) }  // Skip already prefetched

        guard !urls.isEmpty else { return }

        Task {
            await ImageCacheManager.shared.prefetchImages(urls: Array(urls))
        }

        prefetchedURLs.formUnion(urls)
    }

    /// Clear prefetch state (call when filter/sort changes)
    func reset() {
        visibleBookIDs.removeAll()
        prefetchedURLs.removeAll()

        Task {
            await ImageCacheManager.shared.cancelAllPrefetches()
        }
    }
}

// MARK: - Optimized Async Image
/// Drop-in replacement for AsyncImageWithLoading with optimized caching
/// Uses ImageCacheManager for aggressive memory + disk caching
struct OptimizedAsyncImage: View {
    let url: URL?
    @State private var loadedImage: Image?
    @State private var isLoading = false
    @State private var loadFailed = false
    @State private var retryTrigger = UUID()

    var body: some View {
        Group {
            if let image = loadedImage {
                // Success: Show loaded image
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .transition(.opacity)
            } else if loadFailed {
                // Error: Show retry UI
                errorStateView
            } else {
                // Loading: Show shimmer
                loadingStateView
            }
        }
        .id(retryTrigger)
        .task(id: url) {
            await loadImage()
        }
        .task(id: retryTrigger) {
            if loadFailed {
                await loadImage()
            }
        }
    }

    // MARK: - Loading State
    private var loadingStateView: some View {
        ZStack {
            Rectangle()
                .fill(.black)
                .background(.ultraThinMaterial)

            ShimmerView()
                .blendMode(.overlay)
        }
    }

    // MARK: - Error State
    private var errorStateView: some View {
        ZStack {
            Rectangle()
                .fill(Color.gray.opacity(0.2))
                .background(.ultraThinMaterial)

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

    // MARK: - Image Loading
    private func loadImage() async {
        guard let url = url else {
            loadFailed = true
            return
        }

        guard !isLoading else { return }

        isLoading = true
        loadFailed = false

        do {
            // US-321: Use optimized URLSession with aggressive caching
            let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad)
            let session = ImageCacheManager.shared.urlSession
            let (data, _) = try await session.data(for: request)

            #if canImport(UIKit)
            if let uiImage = UIImage(data: data) {
                loadedImage = Image(uiImage: uiImage)
                loadFailed = false
            } else {
                loadFailed = true
            }
            #else
            // Fallback for non-UIKit platforms
            loadFailed = true
            #endif
        } catch {
            loadFailed = true
        }

        isLoading = false
    }

    private func retryLoad() {
        withAnimation(Animation.swissSpring) {
            retryTrigger = UUID()
            loadFailed = false
        }
    }
}

// MARK: - Performance Monitoring View Modifier
/// View modifier that logs render performance for library views
struct PerformanceMonitorModifier: ViewModifier {
    let viewName: String
    let bookCount: Int

    @State private var renderStart: CFAbsoluteTime?

    func body(content: Content) -> some View {
        content
            .onAppear {
                renderStart = CFAbsoluteTimeGetCurrent()
            }
            .task {
                // Give view time to fully render (1 frame at 60fps)
                try? await Task.sleep(for: .milliseconds(16))

                if let start = renderStart {
                    let duration = CFAbsoluteTimeGetCurrent() - start
                    PerformanceLogger.logLibraryRendering(
                        bookCount: bookCount,
                        duration: duration
                    )
                }
            }
    }
}

extension View {
    /// Monitor library rendering performance
    /// - Parameters:
    ///   - viewName: Name of the view being monitored
    ///   - bookCount: Number of books being rendered
    func monitorLibraryPerformance(viewName: String, bookCount: Int) -> some View {
        modifier(PerformanceMonitorModifier(viewName: viewName, bookCount: bookCount))
    }
}

// MARK: - Scroll Position Tracker
/// Tracks scroll position to enable intelligent prefetching
struct ScrollPositionTracker: ViewModifier {
    let onScrollChange: (CGFloat) -> Void

    @State private var lastScrollOffset: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .preference(
                            key: ScrollOffsetPreferenceKey.self,
                            value: geometry.frame(in: .named("scroll")).minY
                        )
                }
            )
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                let delta = abs(value - lastScrollOffset)
                if delta > 50 {  // Only trigger on significant scroll
                    onScrollChange(value)
                    lastScrollOffset = value
                }
            }
    }
}

struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

extension View {
    /// Track scroll position for prefetching
    /// - Parameter onScrollChange: Callback when scroll position changes significantly
    func trackScrollPosition(onScrollChange: @escaping (CGFloat) -> Void) -> some View {
        modifier(ScrollPositionTracker(onScrollChange: onScrollChange))
    }
}
