import Foundation
import SwiftData
import SwiftUI
import os

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
    func handleBookResult(metadata: BookMetadata, rawJSON: String?, thumbnailData: Data? = nil, preScannedISBN: String? = nil, modelContext: ModelContext) {
        logger.debug("handleBookResult called for: \(metadata.resolvedTitle)")

        // Debug logging for integration test
        if ProcessInfo.processInfo.arguments.contains("INJECT_TEST_IMAGE") {
            let logFile = URL(fileURLWithPath: "/tmp/swiftwing-integration-test.log")
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let line = "[\(timestamp)] handleBookResult: title='\(metadata.title ?? "nil")' author='\(metadata.author ?? "nil")' isbn='\(metadata.isbn ?? "nil")'\n"
            if let data = line.data(using: .utf8) {
                if let handle = try? FileHandle(forWritingTo: logFile) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            }
        }

        guard validateBookMetadata(metadata) else { return }

        if isDuplicateResult(metadata) {
            logger.warning("Duplicate book result suppressed: \(metadata.resolvedTitle) (ISBN: \(metadata.isbn ?? ""))")
            return
        }

        // Smart auto-approve: high-confidence results bypass review queue
        if autoApproveSettings.isEnabled,
           let confidence = metadata.confidence,
           confidence >= autoApproveSettings.confidenceThreshold {
            autoApproveBook(metadata: metadata, rawJSON: rawJSON, thumbnailData: thumbnailData, preScannedISBN: preScannedISBN, modelContext: modelContext)
            return
        }

        // Low confidence or auto-approve disabled -> add to review queue
        let pendingBook = PendingBookResult(
            metadata: metadata,
            rawJSON: rawJSON,
            thumbnailData: thumbnailData,
            preScannedISBN: preScannedISBN
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
    private func validateBookMetadata(_ metadata: BookMetadata) -> Bool {
        let title = (metadata.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let author = (metadata.author ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

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
            let matchesISBN = !isbn.isEmpty && pending.metadata.isbn == isbn
            let matchesTitleAuthor = pending.metadata.title == metadata.title &&
                                     pending.metadata.author == metadata.author
            let isRecent = pending.scannedDate.timeIntervalSinceNow > -60
            return (matchesISBN || matchesTitleAuthor) && isRecent
        }
    }

    // MARK: - Auto-Approve
    private func autoApproveBook(metadata: BookMetadata, rawJSON: String?, thumbnailData: Data?, preScannedISBN: String? = nil, modelContext: ModelContext) {
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

        // Light haptic for auto-approve (distinct from manual approve)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        // Show transient toast if enabled
        if autoApproveSettings.showAutoApproveToast {
            autoApprovedBookTitle = metadata.resolvedTitle
            withAnimation(.swissSpring) {
                showAutoApproveToastFlag = true
            }
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                withAnimation(.swissSpring) {
                    showAutoApproveToastFlag = false
                }
                try? await Task.sleep(nanoseconds: 200_000_000)
                autoApprovedBookTitle = nil
            }
        }
    }

    // MARK: - Review Queue Actions
    func approveBook(_ pendingBook: PendingBookResult, modelContext: ModelContext) {
        let isbn = pendingBook.resolvedISBN

        // Duplicate detection at approve time
        do {
            if let duplicate = try DuplicateDetection.findDuplicate(isbn: isbn, in: modelContext) {
                pendingBookBeingApproved = pendingBook
                pendingBookMetadata = pendingBook.metadata
                pendingRawJSON = pendingBook.rawJSON
                pendingPreScannedISBN = pendingBook.preScannedISBN
                duplicateBook = duplicate
                withAnimation(.swissSpring) {
                    showDuplicateAlert = true
                }
                return
            }
        } catch {
            // Proceed with add on detection failure
        }

        // Use resolved values (prefers user edits over AI results)
        addBookToLibrary(
            title: pendingBook.resolvedTitle,
            author: pendingBook.resolvedAuthor,
            metadata: pendingBook.metadata,
            rawJSON: pendingBook.rawJSON,
            preScannedISBN: pendingBook.preScannedISBN,
            modelContext: modelContext
        )

        withAnimation(.swissSpring) {
            pendingReviewBooks.removeAll { $0.id == pendingBook.id }
        }

        logger.info("Book approved and added to library: \(pendingBook.resolvedTitle)")
    }

    func rejectBook(_ pendingBook: PendingBookResult) {
        withAnimation(.swissSpring) {
            pendingReviewBooks.removeAll { $0.id == pendingBook.id }
        }

        logger.info("Book rejected from review queue: \(pendingBook.metadata.resolvedTitle)")
    }

    func approveAllBooks(modelContext: ModelContext) {
        let count = pendingReviewBooks.count
        for book in pendingReviewBooks {
            addBookToLibrary(
                title: book.resolvedTitle,
                author: book.resolvedAuthor,
                metadata: book.metadata,
                rawJSON: book.rawJSON,
                preScannedISBN: book.preScannedISBN,
                modelContext: modelContext
            )
        }

        withAnimation(.swissSpring) {
            pendingReviewBooks.removeAll()
        }

        logger.info("All \(count) books approved and added to library")
    }

    func approveHighConfidenceBooks(modelContext: ModelContext) {
        let highConfidence = pendingReviewBooks.filter { ($0.confidence ?? 1.0) >= 0.8 }
        let count = highConfidence.count
        guard count > 0 else { return }

        for book in highConfidence {
            addBookToLibrary(
                title: book.resolvedTitle,
                author: book.resolvedAuthor,
                metadata: book.metadata,
                rawJSON: book.rawJSON,
                preScannedISBN: book.preScannedISBN,
                modelContext: modelContext
            )
        }

        let approvedIds = Set(highConfidence.map { $0.id })
        withAnimation(.swissSpring) {
            pendingReviewBooks.removeAll { approvedIds.contains($0.id) }
        }

        logger.info("\(count) high-confidence books approved and added to library")
    }

    func addBookToLibrary(title: String? = nil, author: String? = nil, metadata: BookMetadata, rawJSON: String?, preScannedISBN: String? = nil, modelContext: ModelContext) {
        let resolvedTitle = (title ?? metadata.resolvedTitle).trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedAuthor = (author ?? metadata.resolvedAuthor).trimmingCharacters(in: .whitespacesAndNewlines)

        guard !resolvedTitle.isEmpty, !resolvedAuthor.isEmpty else {
            logger.error("Rejected addBookToLibrary: empty title or author")
            return
        }

        let publishedDate: Date?
        if let dateString = metadata.publishedDate {
            let formatter = ISO8601DateFormatter()
            publishedDate = formatter.date(from: dateString)
        } else {
            publishedDate = nil
        }

        let newBook = Book(
            title: resolvedTitle,
            author: resolvedAuthor,
            isbn: metadata.isbn ?? preScannedISBN ?? "UNKNOWN-\(UUID().uuidString)",
            coverUrl: metadata.coverUrl,
            format: metadata.format,
            publisher: metadata.publisher,
            publishedDate: publishedDate,
            pageCount: metadata.pageCount,
            spineConfidence: metadata.confidence,
            addedDate: Date(),
            rawJSON: rawJSON,
            enrichmentStatus: metadata.enrichmentStatus?.rawValue
        )

        modelContext.insert(newBook)

        do {
            try modelContext.save()
            logger.info("Book added to library: \(resolvedTitle)")

            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)

        } catch {
            logger.error("Failed to save book: \(error)")
        }
    }

    // MARK: - Pending Book Edits
    func updatePendingBookEdits(id: UUID, title: String?, author: String?) {
        if let index = pendingReviewBooks.firstIndex(where: { $0.id == id }) {
            pendingReviewBooks[index].editedTitle = title
            pendingReviewBooks[index].editedAuthor = author
        }
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
            if let metadata = pendingBookMetadata {
                addBookToLibrary(
                    title: pendingBookBeingApproved?.resolvedTitle,
                    author: pendingBookBeingApproved?.resolvedAuthor,
                    metadata: metadata,
                    rawJSON: pendingRawJSON,
                    preScannedISBN: pendingPreScannedISBN,
                    modelContext: modelContext
                )
            }
            // Remove from review queue if it was an approve-time duplicate
            if let pending = pendingBookBeingApproved {
                pendingReviewBooks.removeAll { $0.id == pending.id }
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
            try? await Task.sleep(nanoseconds: 5_000_000_000)
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

    // MARK: - Error Display
    private func showProcessingErrorOverlay(_ message: String) async {
        processingErrorMessage = message
        withAnimation(.swissSpring) {
            showProcessingError = true
        }

        try? await Task.sleep(nanoseconds: 5_000_000_000)
        withAnimation(.swissSpring) {
            showProcessingError = false
        }

        try? await Task.sleep(nanoseconds: 200_000_000)
        processingErrorMessage = nil
    }
}
