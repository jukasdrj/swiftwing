import SwiftUI

// MARK: - Library Toolbar Content
struct LibraryToolbarContent: ToolbarContent {
    let isSelectionMode: Bool
    let showReviewNeeded: Bool
    let reviewNeededCount: Int
    let searchText: String
    let sortOption: LibrarySortOption
    let onCancelSelection: () -> Void
    let onExport: () -> Void
    let onToggleReviewFilter: () -> Void
    let onSelectSort: (LibrarySortOption) -> Void
    let onSelectOrSelectAll: () -> Void

    var body: some ToolbarContent {
        // Leading: Cancel (selection mode) or Export button
        ToolbarItem(placement: .topBarLeading) {
            if isSelectionMode {
                Button("Cancel") {
                    onCancelSelection()
                }
                .foregroundStyle(.swissText)
                .accessibilityIdentifier("library_cancel_selection")
            } else {
                Button {
                    onExport()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundStyle(.swissText)
                        .accessibilityLabel("Export library to CSV")
                }
                .accessibilityIdentifier("library_export_button")
            }
        }

        // US-319: Confidence filter toggle (hidden in selection mode)
        if !isSelectionMode {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation(.swissSpring) {
                        onToggleReviewFilter()
                    }
                } label: {
                    Label {
                        Text("Show Review Needed")
                    } icon: {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(showReviewNeeded ? .internationalOrange : .swissText)
                    }
                }
                .badge(reviewNeededCount > 0 ? "\(reviewNeededCount)" : nil)
                .accessibilityIdentifier("library_review_filter")
                .accessibilityLabel("Filter to show books that need review")
                .accessibilityHint(showReviewNeeded ? "Currently showing only low-confidence books" : "Tap to show only low-confidence books")
            }

            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ForEach(LibrarySortOption.allCases, id: \.self) { option in
                        Button {
                            withAnimation(.swissSpring) {
                                onSelectSort(option)
                            }
                        } label: {
                            HStack {
                                Label(option.rawValue, systemImage: option.icon)
                                if option == sortOption {
                                    Spacer()
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .foregroundStyle(.swissText)
                        .accessibilityLabel("Sort library")
                }
                .accessibilityIdentifier("library_sort_menu")
            }
        }

        // US-320: Select / Select All button (disabled during search)
        ToolbarItem(placement: .topBarTrailing) {
            Button(isSelectionMode ? "Select All" : "Select") {
                onSelectOrSelectAll()
            }
            .foregroundStyle(.internationalOrange)
            .disabled(!searchText.isEmpty)
            .accessibilityIdentifier("library_select_button")
        }
    }
}
