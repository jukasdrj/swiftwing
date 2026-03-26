import Foundation

#if DEBUG
/// File-based debug logger for integration test diagnosis.
/// Writes timestamped messages to /tmp/swiftwing-integration-test.log
/// only when the INJECT_TEST_IMAGE launch argument is present.
func integrationLog(_ msg: String) {
    guard ProcessInfo.processInfo.arguments.contains("INJECT_TEST_IMAGE") else { return }
    let logFile = URL(fileURLWithPath: "/tmp/swiftwing-integration-test.log")
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let line = "[\(timestamp)] \(msg)\n"
    guard let data = line.data(using: .utf8) else { return }
    if FileManager.default.fileExists(atPath: logFile.path) {
        if let handle = try? FileHandle(forWritingTo: logFile) {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        }
    } else {
        try? data.write(to: logFile)
    }
}
#endif
