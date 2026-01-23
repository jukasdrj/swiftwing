import Foundation
import SwiftUI

/// Represents an item in the processing queue
/// Used for live UI feedback during image capture and processing
struct ProcessingItem: Identifiable, Equatable {
    let id: UUID
    let imageData: Data
    let captureDate: Date
    var state: ProcessingState

    init(imageData: Data, state: ProcessingState = .processing) {
        self.id = UUID()
        self.imageData = imageData
        self.captureDate = Date()
        self.state = state
    }

    enum ProcessingState: Equatable {
        case processing  // Yellow border
        case uploading   // Blue border (placeholder for Epic 4)
        case done        // Green border
        case error       // Red border (processing failed)

        var borderColor: Color {
            switch self {
            case .processing:
                return .swissProcessing
            case .uploading:
                return .swissUploading
            case .done:
                return .swissDone
            case .error:
                return .swissError
            }
        }
    }
}
