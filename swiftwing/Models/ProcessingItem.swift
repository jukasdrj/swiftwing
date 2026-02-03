import CoreImage
import Foundation
import SwiftUI

/// Item in the processing queue
struct ProcessingItem: Identifiable, Sendable {
    let id = UUID()
    let imageData: Data?  // Original captured image
    var state: ProcessingState
    var progressMessage: String?
    var errorMessage: String?

    // For storing intermediate results
    var segmentedPreview: CIImage?
    var detectedBookCount: Int?
    var currentBookIndex: Int?
    var originalImageData: Data? { imageData }

    // NEW: Retry context for failed result fetches (Fix #2)
    var retryContext: ResultsFetchRetryContext?

    enum ProcessingState: String, CaseIterable, Sendable {
        case preprocessing
        case analyzing
        case extracting
        case completed
        case error
    }

    init(imageData: Data?, state: ProcessingState, progressMessage: String? = nil) {
        self.imageData = imageData
        self.state = state
        self.progressMessage = progressMessage
    }
}

// Retry context for failed results API fetches
struct ResultsFetchRetryContext: Equatable, Sendable {
    let resultsUrl: URL
    let authToken: String?
    let jobId: String
}
