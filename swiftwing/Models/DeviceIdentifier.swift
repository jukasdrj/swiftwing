import Foundation
import os

private let logger = Logger(subsystem: "com.ooheynerds.swiftwing", category: "device")

/// Persistent device identifier stored in UserDefaults
/// Generates UUID v4 on first access, then persists across app sessions
struct DeviceIdentifier {
    private static let key = "com.swiftwing.deviceId"

    /// Retrieve or generate persistent device ID
    static var current: String {
        if let existingId = UserDefaults.standard.string(forKey: key) {
            return existingId
        }

        // Generate new UUID v4 and persist
        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: key)
        logger.info("Generated new device ID")
        return newId
    }

    /// Reset device ID (for testing or user-initiated logout)
    static func reset() {
        UserDefaults.standard.removeObject(forKey: key)
        logger.info("Device ID reset")
    }
}
