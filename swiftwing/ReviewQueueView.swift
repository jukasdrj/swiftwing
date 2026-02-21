import SwiftData
import SwiftUI

struct ReviewQueueView: View {
    @Environment(\.modelContext) private var modelContext
    var viewModel: CameraViewModel

    // US-B3: Selected processing item for detail view
    @State private var selectedProcessingItem: ProcessingItem?
    // Bounding box overlay
    @State private var selectedBookForOverlay: PendingBookResult?

    private var sortedPendingBooks: [PendingBookResult] {
        viewModel.reviewQueueManager.pendingReviewBooks.sorted { a, b in
            // Low confidence first (needs most attention)
            let confA = a.confidence ?? 1.0
            let confB = b.confidence ?? 1.0
            return confA < confB
        }
    }

    private var lowConfidenceBooks: [PendingBookResult] {
        sortedPendingBooks.filter { ($0.confidence ?? 1.0) < 0.5 }
    }

    private var mediumConfidenceBooks: [PendingBookResult] {
        sortedPendingBooks.filter {
            let c = $0.confidence ?? 1.0
            return c >= 0.5 && c < 0.8
        }
    }

    private var highConfidenceBooks: [PendingBookResult] {
        sortedPendingBooks.filter { ($0.confidence ?? 1.0) >= 0.8 }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                Color.swissBackground.ignoresSafeArea()

                // Content
                if viewModel.reviewQueueManager.pendingReviewBooks.isEmpty && viewModel.processingQueue.isEmpty {
                    emptyStateView
                } else {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            // Scan batch summary header
                            if let batch = viewModel.reviewQueueManager.lastScanBatch {
                                ScanBatchHeaderView(batch: batch)
                                    .padding(.bottom, 8)
                            }

                            // US-B3: Processing items section (at top for immediate visibility)
                            if !viewModel.processingQueue.isEmpty {
                                SectionHeader(
                                    title: "Processing", count: viewModel.processingQueue.count,
                                    color: .internationalOrange)
                                ForEach(viewModel.processingQueue) { item in
                                    ProcessingItemRow(item: item)
                                        .onTapGesture {
                                            selectedProcessingItem = item
                                        }
                                }
                            }

                            // Low confidence section (red - needs review)
                            if !lowConfidenceBooks.isEmpty {
                                SectionHeader(
                                    title: "Needs Review", count: lowConfidenceBooks.count,
                                    color: .red)
                                ForEach(lowConfidenceBooks) { book in
                                    reviewCard(for: book)
                                }
                            }

                            // Medium confidence section (orange - verify)
                            if !mediumConfidenceBooks.isEmpty {
                                SectionHeader(
                                    title: "Verify", count: mediumConfidenceBooks.count,
                                    color: .orange)
                                ForEach(mediumConfidenceBooks) { book in
                                    reviewCard(for: book)
                                }
                            }

                            // High confidence section (green - ready to add)
                            if !highConfidenceBooks.isEmpty {
                                SectionHeader(
                                    title: "Ready to Add", count: highConfidenceBooks.count,
                                    color: .green,
                                    actionLabel: "Approve All",
                                    onAction: {
                                        viewModel.reviewQueueManager.approveHighConfidenceBooks(modelContext: modelContext)
                                    }
                                )
                                ForEach(highConfidenceBooks) { book in
                                    reviewCard(for: book)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 24)
                    }
                    .refreshable {
                        // US-B3: Pull-to-refresh updates processing states
                        // Note: processingQueue is reactive via @Observable
                        try? await Task.sleep(nanoseconds: 100_000_000)  // Minimal delay for animation
                    }
                }
            }
            .navigationTitle("Review Queue")
            .sheet(item: $selectedProcessingItem) { item in
                ProcessingItemDetailSheet(item: item) { title, author, isbn in
                    let metadata = item.bookMetadata ?? BookMetadata(
                        title: title,
                        author: author,
                        isbn: isbn,
                        confidence: nil
                    )
                    viewModel.reviewQueueManager.addBookToLibrary(
                        title: title,
                        author: author,
                        metadata: metadata,
                        rawJSON: nil,
                        modelContext: modelContext
                    )
                    if let index = viewModel.processingQueue.firstIndex(where: { $0.id == item.id })
                    {
                        let _ = withAnimation(.swissSpring) {
                            viewModel.processingQueue.remove(at: index)
                        }
                    }
                }
            }
            .sheet(item: $selectedBookForOverlay) { book in
                if let photoURL = book.originalPhotoURL,
                   let boundingBox = book.metadata.boundingBox {
                    BoundingBoxOverlay(
                        photoURL: photoURL,
                        boundingBox: boundingBox,
                        bookTitle: book.resolvedTitle
                    )
                }
            }
            .toolbar {
                if !viewModel.reviewQueueManager.pendingReviewBooks.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Approve All") {
                            viewModel.reviewQueueManager.approveAllBooks(modelContext: modelContext)
                        }
                        .foregroundColor(.internationalOrange)
                        .accessibilityIdentifier("review_approve_all")
                    }
                }
            }
            .overlay {
                if viewModel.reviewQueueManager.showDuplicateAlert, let duplicate = viewModel.reviewQueueManager.duplicateBook {
                    DuplicateBookAlert(
                        duplicateBook: duplicate,
                        onCancel: {
                            viewModel.reviewQueueManager.dismissDuplicateAlert()
                        },
                        onAddAnyway: {
                            viewModel.reviewQueueManager.addDuplicateAnyway(modelContext: modelContext)
                        },
                        onViewExisting: {
                            viewModel.reviewQueueManager.dismissDuplicateAlert()
                        }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func reviewCard(for book: PendingBookResult) -> some View {
        let hasOverlay = book.metadata.boundingBox != nil && book.originalPhotoURL != nil
        ReviewCardView(
            book: book,
            onApprove: {
                viewModel.reviewQueueManager.approveBook(book, modelContext: modelContext)
            },
            onReject: {
                viewModel.reviewQueueManager.rejectBook(book)
            },
            onEdit: { editedTitle, editedAuthor in
                viewModel.reviewQueueManager.updatePendingBookEdits(
                    id: book.id,
                    title: editedTitle,
                    author: editedAuthor
                )
            },
            onShowOverlay: hasOverlay ? { selectedBookForOverlay = book } : nil
        )
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("No items to review")
                .font(.headline)
                .foregroundColor(.swissText)

            Text("Take a photo to get started")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
    }

}

// MARK: - US-B3: Processing Item Row

/// Row view for processing items in the review queue
/// Shows thumbnail with status-colored border, progress message, and status icon
struct ProcessingItemRow: View {
    let item: ProcessingItem

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail with border color indicating status
            if let thumbnail = UIImage(data: item.thumbnailData) {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 60, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(item.state.borderColor, lineWidth: 2)
                    )
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.progressMessage ?? "Processing...")
                    .font(.headline)
                    .foregroundColor(.swissText)

                Text(statusDescription(for: item.state))
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                if let error = item.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .lineLimit(2)
                }
            }

            Spacer()

            statusIcon(for: item.state)
        }
        .padding(.vertical, 4)
        .padding(16)
        .swissGlassCard()
    }

    @ViewBuilder
    private func statusIcon(for state: ProcessingItem.ProcessingState) -> some View {
        switch state {
        case .preprocessing:
            ProgressView()
                .tint(.purple)
        case .uploading:
            ProgressView()
                .tint(.yellow)
        case .analyzing:
            ProgressView()
                .tint(.internationalOrange)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.title2)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
                .font(.title2)
        case .offline:
            Image(systemName: "icloud.slash")
                .foregroundColor(.gray)
                .font(.title2)
        }
    }

    private func statusDescription(for state: ProcessingItem.ProcessingState) -> String {
        switch state {
        case .preprocessing:
            return "Preparing image..."
        case .uploading:
            return "Uploading to AI..."
        case .analyzing:
            return "Analyzing book spine..."
        case .done:
            return "Ready for review"
        case .error:
            return "Processing failed"
        case .offline:
            return "Queued (offline)"
        }
    }
}

// MARK: - US-B3: Processing Item Detail Placeholder

/// Placeholder detail view for processing items
/// Sprint 2 will implement full book detail editing here
struct ProcessingItemDetailPlaceholder: View {
    let item: ProcessingItem

    var body: some View {
        NavigationStack {
            ZStack {
                Color.swissBackground.ignoresSafeArea()

                VStack(spacing: 20) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)

                    Text("Detail View")
                        .font(.title2.weight(.semibold))
                        .foregroundColor(.swissText)

                    Text("Sprint 2 will implement book detail editing here")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
            }
            .navigationTitle("Book Details")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// Section header for confidence grouping with optional batch action
struct SectionHeader: View {
    let title: String
    let count: Int
    let color: Color
    var actionLabel: String? = nil
    var onAction: (() -> Void)? = nil

    var body: some View {
        HStack {
            Text(title)
                .font(.headline.bold())
                .foregroundColor(color)

            Text("(\(count))")
                .font(.subheadline)
                .foregroundColor(color.opacity(0.7))

            Spacer()

            if let label = actionLabel, let action = onAction {
                Button(label) {
                    action()
                }
                .font(.subheadline.bold())
                .foregroundColor(.internationalOrange)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
}

struct ReviewCardView: View {
    let book: PendingBookResult
    let onApprove: () -> Void
    let onReject: () -> Void
    let onEdit: (String?, String?) -> Void
    var onShowOverlay: (() -> Void)?

    @State private var isEditing = false
    @State private var editedTitle: String
    @State private var editedAuthor: String

    init(
        book: PendingBookResult, onApprove: @escaping () -> Void, onReject: @escaping () -> Void,
        onEdit: @escaping (String?, String?) -> Void,
        onShowOverlay: (() -> Void)? = nil
    ) {
        self.book = book
        self.onApprove = onApprove
        self.onReject = onReject
        self.onEdit = onEdit
        self.onShowOverlay = onShowOverlay
        self._editedTitle = State(initialValue: book.resolvedTitle)
        self._editedAuthor = State(initialValue: book.resolvedAuthor)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Thumbnail (if available from processing item)
            if let thumbData = book.thumbnailData,
               let thumbnail = UIImage(data: thumbData) {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 60, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(alignment: .bottomTrailing) {
                        if onShowOverlay != nil {
                            Image(systemName: "magnifyingglass")
                                .font(.caption2.bold())
                                .foregroundColor(.white)
                                .padding(4)
                                .background(Color.internationalOrange)
                                .clipShape(Circle())
                                .offset(x: 4, y: 4)
                        }
                    }
                    .onTapGesture {
                        onShowOverlay?()
                    }
            }

            VStack(alignment: .leading, spacing: 12) {
                // Confidence badge + edit button
                HStack {
                    confidenceBadge
                    Spacer()
                    Button(action: {
                        isEditing.toggle()
                    }) {
                        Image(systemName: isEditing ? "checkmark.circle.fill" : "pencil.circle")
                            .font(.title3)
                            .foregroundColor(.internationalOrange)
                    }
                }

                // Title (editable if in edit mode)
                if isEditing {
                    TextField("Title", text: $editedTitle)
                        .textFieldStyle(.roundedBorder)
                        .font(.title3.bold())
                        .onChange(of: editedTitle) { oldValue, newValue in
                            onEdit(newValue, editedAuthor)
                        }
                } else {
                    Text(book.resolvedTitle)
                        .font(.title3.bold())
                        .foregroundColor(.swissText)
                }

                // Author (editable if in edit mode)
                if isEditing {
                    TextField("Author", text: $editedAuthor)
                        .textFieldStyle(.roundedBorder)
                        .font(.body)
                        .onChange(of: editedAuthor) { oldValue, newValue in
                            onEdit(editedTitle, newValue)
                        }
                } else {
                    Text(book.resolvedAuthor)
                        .font(.body)
                        .foregroundColor(.swissText.opacity(0.8))
                }

                // ISBN (JetBrains Mono for data)
                if let isbn = book.metadata.isbn {
                    Text("ISBN: \(isbn)")
                        .font(.custom("JetBrainsMono-Regular", size: 12))
                        .foregroundColor(.swissText.opacity(0.6))
                }

                // Action Buttons
                HStack(spacing: 12) {
                    // Approve Button
                    Button(action: onApprove) {
                        Text("Approve")
                            .font(.body.bold())
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.internationalOrange)
                            .cornerRadius(8)
                    }
                    .accessibilityIdentifier("review_approve_button")

                    // Reject Button
                    Button(action: onReject) {
                        Text("Reject")
                            .font(.body.bold())
                            .foregroundColor(.swissText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.swissText, lineWidth: 1)
                            )
                    }
                    .accessibilityIdentifier("review_reject_button")
                }
            }
        }
        .padding(16)
        .swissGlassCard()
    }

    private var confidenceBadge: some View {
        let confidence = book.confidence ?? 1.0
        let (icon, color, label) = confidenceDisplay(confidence)

        return HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
            Text(label)
                .font(.caption.bold())
        }
        .foregroundColor(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.15))
        .cornerRadius(6)
    }

    private func confidenceDisplay(_ confidence: Double) -> (String, Color, String) {
        if confidence >= 0.8 {
            return ("checkmark.circle.fill", .green, "\(Int(confidence * 100))%")
        } else if confidence >= 0.5 {
            return ("exclamationmark.triangle.fill", .orange, "\(Int(confidence * 100))%")
        } else {
            return ("xmark.octagon.fill", .red, "\(Int(confidence * 100))%")
        }
    }
}

// MARK: - Scan Batch Header

struct ScanBatchHeaderView: View {
    let batch: ReviewQueueManager.ScanBatch

    var body: some View {
        HStack(spacing: 12) {
            // Scan thumbnail
            if let data = batch.thumbnailData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.internationalOrange.opacity(0.2))
                    .frame(width: 48, height: 48)
                    .overlay(
                        Image(systemName: "camera.fill")
                            .foregroundColor(.internationalOrange)
                    )
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Last Scan")
                    .font(.headline)
                    .foregroundColor(.swissText)

                HStack(spacing: 8) {
                    Text("\(batch.totalBooks) book\(batch.totalBooks == 1 ? "" : "s")")
                        .font(.subheadline.bold())
                        .foregroundColor(.internationalOrange)

                    if batch.highConfidenceCount > 0 {
                        Label("\(batch.highConfidenceCount) ready", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                    }

                    if batch.lowConfidenceCount > 0 {
                        Label("\(batch.lowConfidenceCount) review", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }

                Text(batch.timestamp.formatted(.relative(presentation: .named)))
                    .font(.caption)
                    .foregroundColor(.gray)
            }

            Spacer()
        }
        .padding(16)
        .swissGlassCard()
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.internationalOrange.opacity(0.2), lineWidth: 1)
        )
    }
}

#Preview {
    @Previewable @State var viewModel = {
        let vm = CameraViewModel()
        vm.reviewQueueManager.pendingReviewBooks = [
            PendingBookResult(
                metadata: BookMetadata(
                    title: "The Swift Programming Language",
                    author: "Apple Inc.",
                    isbn: "9781234567890",
                    coverUrl: nil,
                    publisher: "Apple Books",
                    publishedDate: nil,
                    pageCount: 500,
                    format: nil,
                    confidence: 0.95,
                    enrichmentStatus: nil
                ),
                rawJSON: nil
            ),
            PendingBookResult(
                metadata: BookMetadata(
                    title: "Low Confidence Book",
                    author: "Unknown",
                    isbn: "9780000000000",
                    coverUrl: nil,
                    publisher: nil,
                    publishedDate: nil,
                    pageCount: nil,
                    format: nil,
                    confidence: 0.35,
                    enrichmentStatus: nil
                ),
                rawJSON: nil
            ),
            PendingBookResult(
                metadata: BookMetadata(
                    title: "Medium Confidence Book",
                    author: "Someone",
                    isbn: "9781111111111",
                    coverUrl: nil,
                    publisher: nil,
                    publishedDate: nil,
                    pageCount: nil,
                    format: nil,
                    confidence: 0.65,
                    enrichmentStatus: nil
                ),
                rawJSON: nil
            ),
        ]
        return vm
    }()

    ReviewQueueView(viewModel: viewModel)
        .modelContainer(for: Book.self, inMemory: true)
        .preferredColorScheme(.dark)
}
