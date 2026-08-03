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
    let preScannedISBN: String?     // Vision-detected ISBN from barcode scanner
    let originalPhotoURL: URL?      // Temp file for bounding box overlay

    // Editable overrides (nil = use metadata value)
    var editedTitle: String?         // NEW
    var editedAuthor: String?        // NEW

    /// Whole-metadata override from a manual `/v3/books/search` lookup.
    /// Kept separate from `metadata` so the original AI result stays available
    /// for provenance and debugging.
    var recoveredMetadata: BookMetadata?

    /// Metadata to display and persist: manual lookup wins over the AI result.
    var resolvedMetadata: BookMetadata { recoveredMetadata ?? metadata }

    // Resolved values (prefer edit over recovery over original)
    var resolvedTitle: String { editedTitle ?? resolvedMetadata.resolvedTitle }
    var resolvedAuthor: String { editedAuthor ?? resolvedMetadata.resolvedAuthor }

    /// ISBN resolution: prefer resolved metadata, fall back to Vision barcode, then generate placeholder
    var resolvedISBN: String { resolvedMetadata.isbn ?? preScannedISBN ?? "UNKNOWN-\(id.uuidString)" }

    init(metadata: BookMetadata, rawJSON: String?, thumbnailData: Data? = nil, preScannedISBN: String? = nil, originalPhotoURL: URL? = nil) {
        self.id = UUID()
        self.metadata = metadata
        self.rawJSON = rawJSON
        self.thumbnailData = thumbnailData
        self.scannedDate = Date()
        self.confidence = metadata.confidence
        self.preScannedISBN = preScannedISBN
        self.originalPhotoURL = originalPhotoURL
        self.editedTitle = nil
        self.editedAuthor = nil
        self.recoveredMetadata = nil
    }

    static func == (lhs: PendingBookResult, rhs: PendingBookResult) -> Bool {
        lhs.id == rhs.id
            && lhs.editedTitle == rhs.editedTitle
            && lhs.editedAuthor == rhs.editedAuthor
            && lhs.recoveredMetadata == rhs.recoveredMetadata
    }
}
