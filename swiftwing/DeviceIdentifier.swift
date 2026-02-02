import Foundation

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
        print("📱 Generated new device ID: \(newId)")
        return newId
    }

    /// Reset device ID (for testing or user-initiated logout)
    static func reset() {
        UserDefaults.standard.removeObject(forKey: key)
        print("🔄 Device ID reset")
    }
}
