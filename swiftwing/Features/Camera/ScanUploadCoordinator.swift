import Foundation
import SwiftData
import os

private let uploadLogger = Logger(subsystem: "com.ooheynerds.swiftwing", category: "upload-coordinator")

/// Coordinates the complete scan upload pipeline: compress → upload → stream → deduplicate → save
/// Extracted from CameraViewModel for better separation of concerns and testability.
actor ScanUploadCoordinator {
    private let talariaService: TalariaService
    private let imagePreprocessor: ImagePreprocessor
    private var streamingAggregator: StreamingAggregator?
    
    nonisolated let deviceId: String
    
    init(talariaService: TalariaService, deviceId: String = DeviceIdentifier.current) {
        self.talariaService = talariaService
        self.deviceId = deviceId
        self.imagePreprocessor = ImagePreprocessor()
    }
    
    // MARK: - Main Pipeline
    
    /// Execute the complete upload pipeline for a single scan.
    /// Returns results or throws on error.
    func processUpload(
        imageData: Data,
        callbacks: ScanJobCallbacks,
        modelContext: ModelContext
    ) async throws {
        uploadLogger.info("Starting upload pipeline")
        
        // Step 1: Preprocess image
        let uploadStart = CFAbsoluteTimeGetCurrent()
        let preprocessed = try await preprocessImage(imageData)
        uploadLogger.debug("Preprocessing took \(Int((CFAbsoluteTimeGetCurrent() - uploadStart) * 1000))ms")
        
        // Step 2: Upload to Talaria
        let uploadResult = try await uploadToTalaria(imageData: preprocessed.compressedData)
        uploadLogger.info("Upload complete: jobId=\(uploadResult.jobId)")
        
        // Step 3: Setup streaming aggregator for deduplication
        let aggregator = StreamingAggregator(modelContext: modelContext)
        self.streamingAggregator = aggregator
        
        // Step 4: Stream SSE events
        try await streamSSEEvents(
            sseUrl: uploadResult.sseUrl,
            authToken: uploadResult.authToken,
            callbacks: callbacks,
            aggregator: aggregator
        )
        
        uploadLogger.info("Upload pipeline complete")
    }
    
    // MARK: - Image Preprocessing
    
    private func preprocessImage(_ imageData: Data) async throws -> (compressedData: Data, rotationApplied: Bool) {
        let result = try await imagePreprocessor.preprocess(imageData)
        return (result.data, result.rotationApplied)
    }
    
    // MARK: - Talaria Upload
    
    private func uploadToTalaria(imageData: Data) async throws -> (jobId: String, sseUrl: String, authToken: String) {
        let (jobId, sseUrl, authToken) = try await talariaService.uploadScan(imageData: imageData, filename: "scan-\(UUID().uuidString.prefix(8)).jpg")
        return (jobId, sseUrl, authToken)
    }
    
    // MARK: - SSE Streaming
    
    private func streamSSEEvents(
        sseUrl: String,
        authToken: String,
        callbacks: ScanJobCallbacks,
        aggregator: StreamingAggregator
    ) async throws {
        try await talariaService.streamEvents(from: sseUrl, authToken: authToken, callbacks: callbacks)
        
        // After streaming, perform deduplication via aggregator
        try await aggregator.deduplicateResults()
    }
    
    // MARK: - Error Recovery
    
    func retryUpload(
        imageData: Data,
        callbacks: ScanJobCallbacks,
        modelContext: ModelContext,
        delay: TimeInterval = 2.0
    ) async throws {
        // Introduce backoff delay before retry
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        
        uploadLogger.info("Retrying upload after \(Int(delay))s delay")
        try await processUpload(imageData: imageData, callbacks: callbacks, modelContext: modelContext)
    }
    
    // MARK: - Cleanup
    
    func cleanup(jobId: String) async throws {
        uploadLogger.debug("Cleaning up jobId: \(jobId)")
        try await talariaService.cleanup(jobId: jobId)
    }
}

// MARK: - Supporting Types

/// Result of a successful upload step.
struct ScanUploadResult {
    let jobId: String
    let sseUrl: String
    let authToken: String
}
