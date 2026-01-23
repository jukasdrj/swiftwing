import SwiftUI
import Foundation

/// US-321: Coordinates image prefetching for smooth library scrolling
/// Prefetches cover images for upcoming books to improve perceived performance
@MainActor
@Observable
class LibraryPrefetchCoordinator {
    private var prefetchedURLs: Set<URL> = []

    /// Prefetch cover images for upcoming books
    /// - Parameters:
    ///   - books: Array of books to prefetch
    ///   - maxCount: Maximum number of images to prefetch (default: 20)
    func prefetchUpcoming(books: [Book], maxCount: Int = 20) {
        let urlsToPrefetch = books
            .prefix(maxCount)
            .compactMap { $0.coverUrl }
            .filter { !prefetchedURLs.contains($0) }

        guard !urlsToPrefetch.isEmpty else { return }

        // Mark as prefetched to avoid duplicates
        urlsToPrefetch.forEach { prefetchedURLs.insert($0) }

        // Delegate to ImageCacheManager which handles concurrency and caching efficiently
        Task {
            await ImageCacheManager.shared.prefetchImages(urls: Array(urlsToPrefetch))
        }
    }

    /// Cancel all pending prefetch tasks
    func cancelAll() {
        Task {
            await ImageCacheManager.shared.cancelAllPrefetches()
        }
    }
    
    /// Reset prefetch state (useful for when sort/filter changes)
    func reset() {
        cancelAll()
        prefetchedURLs.removeAll()
    }
}
