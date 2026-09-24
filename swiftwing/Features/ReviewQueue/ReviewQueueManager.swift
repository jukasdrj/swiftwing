import Foundation
import os
import SwiftData
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

private let logger = Logger(subsystem: "com.ooheynerds.swiftwing", category: "review-queue")

/// Manages the review queue for scanned book results awaiting user approval.
/// Extracted from CameraViewModel (Phase 1A refactoring) to separate review queue
/// concerns from camera/scanning logic.
@MainActor
@Observable
final class ReviewQueueManager {
    // MARK: - Auto-Approve

    let autoApproveSettings = AutoApproveSettings()
    var autoApprovedBookTitle: String?
    var showAutoApproveToastFlag = false

    // MARK: - Review Queue State

    var pendingReviewBooks: [PendingBookResult] = []
    var pendingBookBeingApproved: PendingBookResult?

    // MARK: - Scan Complete Banner

    struct ScanCompleteBanner: Identifiable {
        let id = UUID()
        let bookCount: Int
        let thumbnailData: Data?
    }

    var scanCompleteBanner: ScanCompleteBanner?

    // MARK: - Scan Batch Summary

    struct ScanBatch {
        let timestamp: Date
        let totalBooks: Int
        let highConfidenceCount: Int
        let lowConfidenceCount: Int
        let thumbnailData: Data?
    }

    var lastScanBatch: ScanBatch?

    // MARK: - Duplicate Detection State (used during approve flow)

    var duplicateBook: Book?
    var showDuplicateAlert = false
    var pendingBookMetadata: BookMetadata?
    var pendingRawJSON: String?
    var pendingPreScannedISBN: String?

    // MARK: - Error Display (for handleBookResult validation errors)

    var processingErrorMessage: String?
    var showProcessingError = false

    // MARK: - US-405: Book Result Handling

    func handleBookResult(metadata: BookMetadata, rawJSON: String?, thumbnailData: Data? = nil, preScannedISBN: String? = nil, originalPhotoURL: URL? = nil, modelContext: ModelContext) {
        logger.debug("handleBookResult called for: \(metadata.resolvedTitle)")

        guard validateBookMetadata(metadata) else { return }

        if isDuplicateResult(metadata) {
            logger.warning("Duplicate book result suppressed: \(metadata.resolvedTitle) (ISBN: \(metadata.isbn ?? ""))")
            return
        }

        // Smart auto-approve: high-confidence results bypass review queue
        if autoApproveSettings.isEnabled,
           let confidence = metadata.confidence,
           confidence >= autoApproveSettings.confidenceThreshold
        {
            autoApproveBook(metadata: metadata, rawJSON: rawJSON, thumbnailData: thumbnailData, preScannedISBN: preScannedISBN, originalPhotoURL: originalPhotoURL, modelContext: modelContext)
            return
        }

        // Low confidence or auto-approve disabled -> add to review queue
        let pendingBook = PendingBookResult(
            metadata: metadata,
            rawJSON: rawJSON,
            thumbnailData: thumbnailData,
            preScannedISBN: preScannedISBN,
            originalPhotoURL: originalPhotoURL
        )

        withAnimation(.swissSpring) {
            pendingReviewBooks.append(pendingBook)
        }

        let pendingCount = pendingReviewBooks.count
        logger.info("Book added to review queue: \(metadata.resolvedTitle) (pending: \(pendingCount))")

        // Haptic feedback for new review item
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }

    /// Validate title and author are non-empty. Shows error overlay and returns false if invalid.
    /// A `review_needed` row may have a null title or author. It still enters the queue so the user can edit it or look it up.
    private func validateBookMetadata(_ metadata: BookMetadata) -> Bool {
        let title = (metadata.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let author = (metadata.author ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        if metadata.enrichmentStatus != .reviewNeeded {
            guard !title.isEmpty else {
                logger.error("Rejected book result: empty title")
                Task { await showProcessingErrorOverlay("Book title is empty - unable to add to review queue") }
                return false
            }

            guard !author.isEmpty else {
                logger.error("Rejected book result: empty author")
                Task { await showProcessingErrorOverlay("Book author is empty - unable to add to review queue") }
                return false
            }
        }

        // Warn on low confidence (but don't reject)
        if let confidence = metadata.confidence, confidence < 0.3 {
            let pct = Int(confidence * 100)
            logger.warning("Low confidence result: \(pct)% for '\(title)'")
        }

        return true
    }

    /// Returns true if a matching book is already in the pending review queue (dedup guard).
    private func isDuplicateResult(_ metadata: BookMetadata) -> Bool {
        let isbn = metadata.isbn ?? ""
        return pendingReviewBooks.contains { pending in
            // Match on ISBN OR (title + author) within last 60 seconds
            let matchesISBN = !isbn.isEmpty && pending.resolvedMetadata.isbn == isbn
            let matchesTitleAuthor = pending.resolvedMetadata.title == metadata.title &&
                pending.resolvedMetadata.author == metadata.author
            let isRecent = pending.scannedDate.timeIntervalSinceNow > -60
            return (matchesISBN || matchesTitleAuthor) && isRecent
        }
    }

    // MARK: - Auto-Approve

    private func autoApproveBook(metadata: BookMetadata, rawJSON: String?, thumbnailData _: Data?, preScannedISBN: String? = nil, originalPhotoURL: URL? = nil, modelContext: ModelContext) {
        let confidence = metadata.confidence ?? 0
        logger.info("Auto-approving high-confidence book: \(metadata.resolvedTitle) (confidence: \(confidence))")

        addBookToLibrary(
            title: metadata.resolvedTitle,
            author: metadata.resolvedAuthor,
            metadata: metadata,
            rawJSON: rawJSON,
            preScannedISBN: preScannedISBN,
            modelContext: modelContext
        )

        // Auto-approved books skip review — clean up photo immediately
        cleanupPhoto(originalPhotoURL)

        // Light haptic for auto-approve (distinct from manual approve)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        // Show transient toast if enabled
        if autoApproveSettings.showAutoApproveToast {
            autoApprovedBookTitle = metadata.resolvedTitle
            withAnimation(.swissSpring) {
                showAutoApproveToastFlag = true
            }
            Task {
                try? await Task.sleep(for: .seconds(2))
                withAnimation(.swissSpring) {
                    showAutoApproveToastFlag = false
                }
                try? await Task.sleep(for: .milliseconds(200))
                autoApprovedBookTitle = nil
            }
        }
    }

    // MARK: - Review Queue Actions

    func approveBook(_ pendingBook: PendingBookResult, modelContext: ModelContext) {
        let isbn = pendingBook.resolvedISBN

        // Duplicate detection at approve time. An UNKNOWN- ISBN matches title and author,
        // the same pair DataSyncActor.save uses.
        do {
            if let duplicate = try DuplicateDetection.findDuplicate(
                isbn: isbn,
                title: pendingBook.resolvedTitle,
                author: pendingBook.resolvedAuthor,
                in: modelContext
            ) {
                pendingBookBeingApproved = pendingBook
                pendingBookMetadata = pendingBook.resolvedMetadata
                pendingRawJSON = pendingBook.rawJSON
                pendingPreScannedISBN = pendingBook.preScannedISBN
                duplicateBook = duplicate
                withAnimation(.swissSpring) {
                    showDuplicateAlert = true
                }
                return
            }
        } catch {
            logger.warning("Duplicate detection failed, proceeding with add: \(error)")
        }

        // Use resolved values (prefers user edits over recovery over AI results)
        let saved = addBookToLibrary(
            title: pendingBook.resolvedTitle,
            author: pendingBook.resolvedAuthor,
            metadata: pendingBook.resolvedMetadata,
            rawJSON: pendingBook.rawJSON,
            preScannedISBN: pendingBook.preScannedISBN,
            modelContext: modelContext
        )
        guard saved else {
            logger.info("Approve left the card in the queue; save wrote nothing for \(pendingBook.resolvedTitle)")
            return
        }

        let photoURL = pendingBook.originalPhotoURL
        withAnimation(.swissSpring) {
            pendingReviewBooks.removeAll { $0.id == pendingBook.id }
        }
        cleanupPhoto(photoURL)

        if pendingReviewBooks.isEmpty {
            UserDefaults.standard.set(false, forKey: "show_review_needed")
        }

        logger.info("Book approved and added to library: \(pendingBook.resolvedTitle)")
    }

    func rejectBook(_ pendingBook: PendingBookResult) {
        let photoURL = pendingBook.originalPhotoURL
        withAnimation(.swissSpring) {
            pendingReviewBooks.removeAll { $0.id == pendingBook.id }
        }
        cleanupPhoto(photoURL)

        if pendingReviewBooks.isEmpty {
            UserDefaults.standard.set(false, forKey: "show_review_needed")
        }

        logger.info("Book rejected from review queue: \(pendingBook.metadata.resolvedTitle)")
    }

    func approveAllBooks(modelContext: ModelContext) {
        let count = pendingReviewBooks.count
        var removedIds = Set<UUID>()
        var photoURLs: [URL] = []
        for book in pendingReviewBooks {
            if addBookToLibraryIfNotDuplicate(pendingBook: book, modelContext: modelContext) {
                removedIds.insert(book.id)
                if let url = book.originalPhotoURL {
                    photoURLs.append(url)
                }
            }
        }

        withAnimation(.swissSpring) {
            pendingReviewBooks.removeAll { removedIds.contains($0.id) }
        }

        for url in photoURLs {
            cleanupPhoto(url)
        }

        if pendingReviewBooks.isEmpty {
            UserDefaults.standard.set(false, forKey: "show_review_needed")
        }
        logger.info("All \(count) books approved and added to library")
    }

    func approveHighConfidenceBooks(modelContext: ModelContext) {
        let highConfidence = pendingReviewBooks.filter { ($0.confidence ?? 1.0) >= 0.8 }
        let count = highConfidence.count
        guard count > 0 else { return }

        var approvedIds = Set<UUID>()
        var photoURLs: [URL] = []
        for book in highConfidence {
            if addBookToLibraryIfNotDuplicate(pendingBook: book, modelContext: modelContext) {
                approvedIds.insert(book.id)
                if let url = book.originalPhotoURL {
                    photoURLs.append(url)
                }
            }
        }

        withAnimation(.swissSpring) {
            pendingReviewBooks.removeAll { approvedIds.contains($0.id) }
        }

        for url in photoURLs {
            cleanupPhoto(url)
        }

        if pendingReviewBooks.isEmpty {
            UserDefaults.standard.set(false, forKey: "show_review_needed")
        }

        logger.info("\(count) high-confidence books approved and added to library")
    }

    @discardableResult
    func addBookToLibrary(title: String? = nil, author: String? = nil, metadata: BookMetadata, rawJSON: String?, preScannedISBN: String? = nil, modelContext: ModelContext) -> Bool {
        let resolvedTitle = (title ?? metadata.resolvedTitle).trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedAuthor = (author ?? metadata.resolvedAuthor).trimmingCharacters(in: .whitespacesAndNewlines)

        guard !resolvedTitle.isEmpty, !resolvedAuthor.isEmpty else {
            logger.error("Rejected addBookToLibrary: empty title or author")
            return false
        }

        // Build a synthetic PendingBookResult so DataSyncActor can handle construction + persistence.
        let syntheticMetadata = BookMetadata(
            title: resolvedTitle,
            author: resolvedAuthor,
            isbn: metadata.isbn,
            coverUrl: metadata.coverUrl,
            publisher: metadata.publisher,
            publishedDate: metadata.publishedDate,
            pageCount: metadata.pageCount,
            format: metadata.format,
            confidence: metadata.confidence,
            boundingBox: metadata.boundingBox,
            enrichmentStatus: metadata.enrichmentStatus
        )
        let pendingBook = PendingBookResult(
            metadata: syntheticMetadata,
            rawJSON: rawJSON,
            preScannedISBN: preScannedISBN
        )

        do {
            let saved = try DataSyncActor.shared.save(book: pendingBook, in: modelContext)
            if saved {
                logger.info("Book added to library: \(resolvedTitle)")
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
            } else {
                logger.info("Save refused duplicate: \(resolvedTitle)")
            }
            return saved
        } catch {
            logger.error("Failed to save book: \(error)")
            return false
        }
    }

    /// Adds book to library only if no duplicate exists. Silent (no UI alert) — for bulk operations.
    /// Returns true if added, false if skipped as duplicate.
    @discardableResult
    private func addBookToLibraryIfNotDuplicate(
        pendingBook: PendingBookResult,
        modelContext: ModelContext
    ) -> Bool {
        let isbn = pendingBook.resolvedISBN
        if (try? DuplicateDetection.findDuplicate(
            isbn: isbn,
            title: pendingBook.resolvedTitle,
            author: pendingBook.resolvedAuthor,
            in: modelContext
        )) != nil {
            logger.info("Bulk approve: skipping duplicate '\(pendingBook.resolvedTitle)'")
            return false
        }
        return addBookToLibrary(
            title: pendingBook.resolvedTitle,
            author: pendingBook.resolvedAuthor,
            metadata: pendingBook.resolvedMetadata,
            rawJSON: pendingBook.rawJSON,
            preScannedISBN: pendingBook.preScannedISBN,
            modelContext: modelContext
        )
    }

    // MARK: - Pending Book Edits

    func updatePendingBookEdits(id: UUID, title: String?, author: String?) {
        if let index = pendingReviewBooks.firstIndex(where: { $0.id == id }) {
            pendingReviewBooks[index].editedTitle = title
            pendingReviewBooks[index].editedAuthor = author
        }
    }

    /// Graft a manual `/v3/books/search` result onto a pending review item.
    ///
    /// Clears any prior inline edits so the card shows the looked-up values
    /// rather than a half-edited mix, and marks enrichment `.success` — the
    /// data now comes from a real lookup, not a failed enrichment pass.
    func applyRecoveredMetadata(id: UUID, from result: BookSearchResult) {
        guard let index = pendingReviewBooks.firstIndex(where: { $0.id == id }) else { return }
        let existing = pendingReviewBooks[index]

        pendingReviewBooks[index].recoveredMetadata = BookMetadata(
            title: result.title,
            author: result.joinedAuthors,
            isbn: result.isbn13 ?? result.isbn,
            coverUrl: result.coverUrl,
            publisher: result.publisher,
            publishedDate: result.publishedDate,
            pageCount: existing.metadata.pageCount,
            format: existing.metadata.format,
            confidence: result.confidence,
            boundingBox: existing.metadata.boundingBox,
            enrichmentStatus: .success
        )
        pendingReviewBooks[index].editedTitle = nil
        pendingReviewBooks[index].editedAuthor = nil
    }

    // MARK: - Duplicate Alert Management

    func dismissDuplicateAlert() {
        withAnimation(.swissSpring) {
            showDuplicateAlert = false
            duplicateBook = nil
            pendingBookMetadata = nil
            pendingRawJSON = nil
            pendingPreScannedISBN = nil
            pendingBookBeingApproved = nil
        }
    }

    func addDuplicateAnyway(modelContext: ModelContext) {
        withAnimation(.swissSpring) {
            showDuplicateAlert = false
            let saved: Bool = if let metadata = pendingBookMetadata {
                addBookToLibrary(
                    title: pendingBookBeingApproved?.resolvedTitle,
                    author: pendingBookBeingApproved?.resolvedAuthor,
                    metadata: metadata,
                    rawJSON: pendingRawJSON,
                    preScannedISBN: pendingPreScannedISBN,
                    modelContext: modelContext
                )
            } else {
                false
            }
            // A refused save leaves the card on screen.
            if saved, let pending = pendingBookBeingApproved {
                pendingReviewBooks.removeAll { $0.id == pending.id }
            }
            if pendingReviewBooks.isEmpty {
                UserDefaults.standard.set(false, forKey: "show_review_needed")
            }
            duplicateBook = nil
            pendingBookMetadata = nil
            pendingRawJSON = nil
            pendingPreScannedISBN = nil
            pendingBookBeingApproved = nil
        }
    }

    // MARK: - Banner Management

    func dismissScanCompleteBanner() {
        withAnimation(.swissSpring) {
            scanCompleteBanner = nil
        }
    }

    /// Show scan complete banner and update batch summary
    func showScanComplete(booksAdded: Int, thumbnailData: Data?) {
        guard booksAdded > 0 else { return }

        let banner = ScanCompleteBanner(
            bookCount: booksAdded,
            thumbnailData: thumbnailData
        )
        let bannerId = banner.id
        withAnimation(.swissSpring) {
            scanCompleteBanner = banner
        }
        // Auto-dismiss after 5 seconds (only if banner still matches)
        Task {
            try? await Task.sleep(for: .seconds(5))
            if scanCompleteBanner?.id == bannerId {
                withAnimation(.swissSpring) {
                    scanCompleteBanner = nil
                }
            }
        }

        // Update scan batch summary header
        let booksFromScan = pendingReviewBooks.suffix(booksAdded)
        let high = booksFromScan.lazy.filter { ($0.confidence ?? 1.0) >= 0.8 }.count
        let low = booksFromScan.lazy.filter { ($0.confidence ?? 1.0) < 0.5 }.count
        lastScanBatch = ScanBatch(
            timestamp: Date(),
            totalBooks: booksAdded,
            highConfidenceCount: high,
            lowConfidenceCount: low,
            thumbnailData: thumbnailData
        )
    }

    // MARK: - Photo Cleanup

    /// Clean up temp photo file if no other pending result references the same URL
    private func cleanupPhoto(_ url: URL?) {
        guard let url else { return }
        let stillReferenced = pendingReviewBooks.contains { $0.originalPhotoURL == url }
        guard !stillReferenced else { return }
        do {
            try FileManager.default.removeItem(at: url)
            logger.debug("Cleaned up temp photo: \(url.lastPathComponent)")
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            logger.debug("Temp photo already deleted: \(url.lastPathComponent)")
        } catch {
            logger.warning("Failed to clean up temp photo \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    // MARK: - Error Display

    private func showProcessingErrorOverlay(_ message: String) async {
        processingErrorMessage = message
        withAnimation(.swissSpring) {
            showProcessingError = true
        }

        try? await Task.sleep(for: .seconds(5))
        withAnimation(.swissSpring) {
            showProcessingError = false
        }

        try? await Task.sleep(for: .milliseconds(200))
        processingErrorMessage = nil
    }
}
