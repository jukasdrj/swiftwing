import SwiftUI

/// Manual book lookup for scans whose enrichment failed (`not_found` /
/// `circuit_open`). Wraps `GET /v3/books/search` and hands the chosen result
/// back to the review queue.
struct ManualLookupSheet: View {
    let book: PendingBookResult
    let talariaService: TalariaService
    let onApply: (BookSearchResult) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var author: String
    @State private var isbn: String
    @State private var result: BookSearchResult?
    @State private var isSearching = false
    @State private var message: String?

    init(
        book: PendingBookResult,
        talariaService: TalariaService,
        onApply: @escaping (BookSearchResult) -> Void
    ) {
        self.book = book
        self.talariaService = talariaService
        self.onApply = onApply
        // Seed from whatever the scan did manage to read. A placeholder author
        // ("Unknown Author") is left blank so the search can match on title alone.
        _title = State(initialValue: book.resolvedMetadata.title ?? "")
        _author = State(initialValue: book.resolvedMetadata.authorForManualSearch ?? "")
        _isbn = State(initialValue: book.resolvedMetadata.isbn ?? book.preScannedISBN ?? "")
    }

    private var titleQuery: String? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var authorQuery: String? {
        BookMetadata.manualSearchField(author, dropping: BookMetadata.unknownAuthorPlaceholders)
    }

    private var isbnQuery: String? {
        let trimmed = isbn.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var canSearch: Bool {
        !isSearching && [titleQuery, authorQuery, isbnQuery].contains { $0 != nil }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.swissBackground.ignoresSafeArea()

                Form {
                    Section("Search") {
                        TextField("Title", text: $title)
                            .textInputAutocapitalization(.words)
                            .accessibilityIdentifier("lookup_title_field")
                        TextField("Author", text: $author)
                            .textInputAutocapitalization(.words)
                            .accessibilityIdentifier("lookup_author_field")
                        TextField("ISBN", text: $isbn)
                            .keyboardType(.numbersAndPunctuation)
                            .font(.custom("JetBrainsMono-Regular", size: 15))
                            .accessibilityIdentifier("lookup_isbn_field")
                    }

                    Section {
                        Button(action: { Task { await search() } }) {
                            HStack {
                                if isSearching {
                                    ProgressView().padding(.trailing, 4)
                                }
                                Text(isSearching ? "Searching…" : "Search")
                            }
                        }
                        .disabled(!canSearch)
                        .accessibilityIdentifier("lookup_search_button")
                    }

                    if let message {
                        Section { Text(message).foregroundStyle(.secondary) }
                    }

                    if let result {
                        Section("Best match") {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(result.title).font(.headline)
                                Text(result.joinedAuthors).font(.subheadline).foregroundStyle(.secondary)
                                if let isbn = result.isbn13 ?? result.isbn {
                                    Text("ISBN: \(isbn)")
                                        .font(.custom("JetBrainsMono-Regular", size: 12))
                                        .foregroundStyle(.secondary)
                                }
                                Text("\(Int(result.confidence * 100))% match · \(result.source)\(result.fuzzyMatched ? " · fuzzy" : "")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Button("Use this book") {
                                onApply(result)
                                dismiss()
                            }
                            .accessibilityIdentifier("lookup_apply_button")
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Find This Book")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func search() async {
        isSearching = true
        message = nil
        result = nil
        defer { isSearching = false }

        do {
            result = try await talariaService.searchBook(
                isbn: isbnQuery,
                title: titleQuery,
                author: authorQuery
            )
        } catch let NetworkError.apiError(problem) where problem.status == 404 {
            message = "No match found. Try a different spelling, or search by ISBN."
        } catch NetworkError.noConnection {
            message = "No connection. Check your network and try again."
        } catch {
            message = "Search failed. Please try again."
        }
    }
}
