import Foundation

/// Represents a book scan result awaiting user review
/// In-memory only -- does not persist across app launches
/// Used by ReviewQueueView for approve/reject workflow
struct PendingBookResult: Identifiable, Equatable {
    let id: UUID
    let metadata: BookMetadata      // Original AI result (immutable)
    let rawJSON: String?
    let thumbnailData: Data?        // From ProcessingItem for visual reference
    let scannedDate: Date
    let confidence: Double?
    let preScannedISBN: String?     // Vision-detected ISBN fallback

    // Editable overrides (nil = use metadata value)
    var editedTitle: String?         // NEW
    var editedAuthor: String?        // NEW

    // Resolved values (prefer edit over original)
    var resolvedTitle: String { editedTitle ?? metadata.resolvedTitle }
    var resolvedAuthor: String { editedAuthor ?? metadata.resolvedAuthor }

    /// ISBN from metadata or pre-scanned barcode fallback
    var resolvedISBN: String? {
        metadata.isbn ?? preScannedISBN
    }

    init(metadata: BookMetadata, rawJSON: String?, thumbnailData: Data? = nil, preScannedISBN: String? = nil) {
        self.id = UUID()
        self.metadata = metadata
        self.rawJSON = rawJSON
        self.thumbnailData = thumbnailData
        self.scannedDate = Date()
        self.confidence = metadata.confidence
        self.preScannedISBN = preScannedISBN
        self.editedTitle = nil
        self.editedAuthor = nil
    }

    static func == (lhs: PendingBookResult, rhs: PendingBookResult) -> Bool {
        lhs.id == rhs.id
    }
}
