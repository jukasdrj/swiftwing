import Foundation
import CoreImage
import SwiftUI

/// Represents a single book detected by instance segmentation
/// Used during processing pipeline before saving to SwiftData
struct SegmentedBook: Identifiable, Sendable {
    let id: Int  // Instance ID from Vision framework
    let instanceID: Int
    let croppedImage: CIImage
    let boundingBox: CGRect  // Normalized coordinates (0-1)
    let timestamp: Date

    /// Size of cropped image in pixels
    var imageSize: CGSize {
        croppedImage.extent.size
    }

    init(instanceID: Int, croppedImage: CIImage, boundingBox: CGRect) {
        self.id = instanceID
        self.instanceID = instanceID
        self.croppedImage = croppedImage
        self.boundingBox = boundingBox
        self.timestamp = Date()
    }
}
