import Foundation
@testable import swiftwing
import Testing

@MainActor
@Suite("Scan mode settings")
struct ScanModeSettingsTests {
    @Test func modeDefaultsToTalariaAndRoundTrips() throws {
        let suiteName = "ScanModeSettingsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let settings = ScanModeSettings(defaults: defaults)
        #expect(settings.mode == .talaria)

        settings.mode = .onDevice
        let reread = ScanModeSettings(defaults: defaults)
        #expect(reread.mode == .onDevice)
        #expect(defaults.string(forKey: "scanMode") == ScanMode.onDevice.rawValue)
    }
}
