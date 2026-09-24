import Foundation

/// Phase A placeholder. Vision extraction replaces this failure in the next commit.
enum OnDeviceScanError: LocalizedError, Sendable {
    case notReady

    var errorDescription: String? {
        switch self {
        case .notReady:
            "On-device scanning is not ready yet"
        }
    }
}

/// On-device extraction result. `ocrText` is the review-queue provenance string.
struct OnDeviceScanOutcome: Sendable {
    var metadata: BookMetadata
    var ocrText: String?
}

protocol BookSpineExtracting: Sendable {
    func extract(_ imageData: Data) async throws -> OnDeviceScanOutcome
}

actor OnDeviceScanner: BookSpineExtracting {
    func extract(_ imageData: Data) async throws -> OnDeviceScanOutcome {
        guard !imageData.isEmpty else {
            throw OnDeviceScanError.notReady
        }
        throw OnDeviceScanError.notReady
    }
}
