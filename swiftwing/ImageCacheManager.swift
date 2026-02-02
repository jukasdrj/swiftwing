import Foundation
import SwiftUI
import UIKit

// MARK: - Image Cache Manager
/// US-321: Aggressive URLCache configuration and image prefetching for library performance
/// Implements disk + memory caching with intelligent prefetching for smooth scrolling
actor ImageCacheManager {

    // MARK: - Shared Instance
    static let shared = ImageCacheManager()

    // MARK: - Properties
    // URLSession is Sendable and immutable after initialization, safe for non-isolated access
    private let _urlSession: URLSession
    private var prefetchTasks: [URL: Task<Void, Never>] = [:]

    // Nonisolated accessor for URLSession
    // Safe because URLSession is Sendable and _urlSession is immutable after init
    nonisolated var urlSession: URLSession {
        _urlSession
    }

    // MARK: - Initialization
    private init() {
        // US-321: Configure aggressive URLCache for image caching
        // Memory: 50MB (holds ~50 cover images at 1MB each)
        // Disk: 200MB (holds ~200 cover images)
        let memoryCapacity = 50 * 1024 * 1024   // 50MB
        let diskCapacity = 200 * 1024 * 1024    // 200MB

        let cache = URLCache(
            memoryCapacity: memoryCapacity,
            diskCapacity: diskCapacity
        )

        // Create URLSession with optimized configuration
        let config = URLSessionConfiguration.default
        config.urlCache = cache
        config.requestCachePolicy = .returnCacheDataElseLoad  // Prefer cache
        config.timeoutIntervalForRequest = 30                 // 30s timeout
        config.waitsForConnectivity = false                   // Don't wait for network

        self._urlSession = URLSession(configuration: config)

        print("📦 US-321: ImageCacheManager initialized")
        print("  Memory Cache: \(memoryCapacity / 1024 / 1024)MB")
        print("  Disk Cache: \(diskCapacity / 1024 / 1024)MB")
    }

    // MARK: - Cache Statistics
    /// Get current cache usage statistics (for debugging/logging)
    func getCacheStatistics() -> (memoryUsed: Int, diskUsed: Int) {
        let cache = _urlSession.configuration.urlCache
        return (
            memoryUsed: cache?.currentMemoryUsage ?? 0,
            diskUsed: cache?.currentDiskUsage ?? 0
        )
    }

    /// Log cache statistics to console
    func logCacheStatistics() {
        let stats = getCacheStatistics()
        print("📊 Image Cache Statistics:")
        print("  Memory: \(stats.memoryUsed / 1024 / 1024)MB / 50MB")
        print("  Disk: \(stats.diskUsed / 1024 / 1024)MB / 200MB")
    }

    // MARK: - Prefetching

    /// Prefetch images for an array of URLs
    /// - Parameter urls: Array of image URLs to prefetch
    /// - Note: Prefetches in background, does not block caller
    func prefetchImages(urls: [URL]) {
        Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return }

            await withTaskGroup(of: Void.self) { group in
                for url in urls {
                    group.addTask {
                        await self.prefetchImage(url: url)
                    }
                }
            }
        }
    }

    /// Prefetch a single image URL
    /// - Parameter url: Image URL to prefetch
    private func prefetchImage(url: URL) async {
        // Check if already prefetching this URL
        guard prefetchTasks[url] == nil else { return }

        // Check if already in cache
        let request = URLRequest(url: url, cachePolicy: .returnCacheDataDontLoad)
        if _urlSession.configuration.urlCache?.cachedResponse(for: request) != nil {
            // Already cached, no need to prefetch
            return
        }

        // Create prefetch task
        let task = Task {
            do {
                // Fetch and cache image
                let (_, _) = try await self._urlSession.data(from: url)
                // Data is now cached by URLCache automatically
            } catch {
                // Silently fail - this is a prefetch, not critical
            }

            // Remove from active tasks
            self.removePrefetchTask(url: url)
        }

        // Track task
        prefetchTasks[url] = task
    }

    /// Remove prefetch task from tracking
    private func removePrefetchTask(url: URL) {
        prefetchTasks.removeValue(forKey: url)
    }

    /// Cancel all pending prefetch tasks
    func cancelAllPrefetches() {
        for (_, task) in prefetchTasks {
            task.cancel()
        }
        prefetchTasks.removeAll()
    }

    /// Cancel prefetch for specific URL
    /// - Parameter url: URL to cancel prefetch for
    func cancelPrefetch(url: URL) {
        if let task = prefetchTasks[url] {
            task.cancel()
            prefetchTasks.removeValue(forKey: url)
        }
    }

    // MARK: - Cache Management

    /// Clear all cached images (memory + disk)
    func clearCache() {
        _urlSession.configuration.urlCache?.removeAllCachedResponses()
        print("🧹 Image cache cleared")
    }

    /// Clear cached image for specific URL
    /// - Parameter url: URL to clear from cache
    func clearCachedImage(url: URL) {
        let request = URLRequest(url: url)
        _urlSession.configuration.urlCache?.removeCachedResponse(for: request)
    }
}

// MARK: - SwiftUI Integration

/// Custom AsyncImage replacement that uses optimized URLSession with caching
/// Drop-in replacement for AsyncImage with identical API
struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL?
    let content: (Image) -> Content
    let placeholder: () -> Placeholder

    @State private var loadedImage: UIImage?
    @State private var isLoading = false

    init(
        url: URL?,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.content = content
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            if let image = loadedImage {
                content(Image(uiImage: image))
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            await loadImage()
        }
    }

    private func loadImage() async {
        guard let url = url else { return }
        guard !isLoading else { return }

        isLoading = true

        // Use ImageCacheManager's URLSession for automatic caching
        do {
            let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad)
            let session = ImageCacheManager.shared.urlSession
            let (data, _) = try await session.data(for: request)

            if let uiImage = UIImage(data: data) {
                loadedImage = uiImage
            }
        } catch {
            // Failed to load image
        }

        isLoading = false
    }
}

// MARK: - Convenience Initializer

extension CachedAsyncImage where Content == Image, Placeholder == Color {
    /// Convenience initializer with default placeholder
    init(url: URL?) {
        self.init(
            url: url,
            content: { $0 },
            placeholder: { Color.gray.opacity(0.2) }
        )
    }
}
