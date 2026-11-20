import Foundation
import SwiftData
import SwiftUI

/// Launch arguments the UI tests and Device MCP `launch_app` share.
enum TestLaunch {
    static let uiTesting = "UI_TESTING"
    static let injectTestImage = "INJECT_TEST_IMAGE"
    static let seedLibrary = "SEED_LIBRARY"
    static let clearData = "CLEAR_DATA"
    static let forceOnboarding = "FORCE_ONBOARDING"
    static let forceCameraGuidance = "FORCE_CAMERA_GUIDANCE"
    static let shelfFixturePrefix = "SHELF_FIXTURE="

    static func shelfFixtureID(in arguments: [String] = ProcessInfo.processInfo.arguments) -> String? {
        guard let raw = arguments.first(where: { $0.hasPrefix(shelfFixturePrefix) }) else { return nil }
        let id = String(raw.dropFirst(shelfFixturePrefix.count))
        return id.isEmpty ? nil : id
    }
}

extension Notification.Name {
    static let showCameraGuidance = Notification.Name("swiftwing.showCameraGuidance")
}

/// One Wikimedia Commons shelf photo, served at a 1920 long edge for a Talaria-sized scan.
struct ShelfFixture: Identifiable, Sendable {
    let id: String
    let title: String
    let scene: String
    let license: String
    let fileName: String

    var jpegURL: URL {
        let encoded = fileName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? fileName
        let raw = "https://commons.wikimedia.org/wiki/Special:FilePath/\(encoded)?width=1920"
        guard let url = URL(string: raw) else {
            preconditionFailure("Shelf fixture URL failed for \(id)")
        }
        return url
    }

    static let catalog: [ShelfFixture] = [
        .make(
            "science-paperbacks",
            "Angled science paperbacks",
            "Close row, readable titles, slight lean",
            "CC BY-SA 3.0",
            "Let's-Read-and-Find-Out Science bookshelf.jpg"
        ),
        .make(
            "blyton-double",
            "Two rows of Blyton paperbacks",
            "Tight double row of colorful children's spines",
            "CC BY 3.0",
            "Bookshelf of Enid Blyton works.jpg"
        ),
        .make(
            "shop-wall",
            "Bookstore wall",
            "Tall multi-shelf shop, mixed languages",
            "CC BY-SA 4.0",
            "A bibliophile's favourite spot in a shop.jpg"
        ),
        .make(
            "african-studies",
            "Shallow-focus yearbooks",
            "Gold spine labels, only a few titles sharp",
            "CC BY-SA 4.0",
            "African Studies Bookshelf.jpg"
        ),
        .make(
            "norsk-set",
            "Matching encyclopedia set",
            "Nearly identical brown spines in one row",
            "CC BY-SA 3.0",
            "Norsk biografisk leksikon.jpg"
        ),
        .make(
            "kazakh-set",
            "Uniform green set",
            "Cyrillic spines, perspective, several shelves",
            "CC BY-SA 4.0",
            "100 tomdyq Babalar sozi jinaq kitaptary.jpg"
        ),
        .make(
            "winnington-stack",
            "Horizontal spine stack",
            "Spines face up; stresses the tall-shelf rotation",
            "CC0",
            "Alan Winnington books.jpg"
        ),
        .make(
            "mitre-stacks",
            "Dark library stacks",
            "Worn leather, low contrast, strong perspective",
            "CC BY-SA 2.0",
            "Biblioteca del Museo Mitre.jpg"
        ),
        .make(
            "walloon-home",
            "Uneven home shelf",
            "Mixed heights, with covers facing out on the bottom",
            "CC BY-SA 4.0",
            "Bibioteke lives e walon.jpg"
        ),
        .make(
            "glass-cabinet",
            "Glass-front cabinet",
            "Glare and a reflection over the spines",
            "CC BY-SA 3.0",
            "Biblioteca original.jpg"
        ),
        .make(
            "comic-bays",
            "Comic shop bays",
            "Thin spines plus face-out displays",
            "CC BY-SA 3.0",
            "500px photo (66157623).jpeg"
        ),
        .make(
            "manga-stacks",
            "Horizontal manga piles",
            "Stacked flat, not an upright spine row",
            "CC0",
            "Anime books.jpg"
        ),
        .make(
            "window-backlight",
            "Shelf beside a window",
            "Backlit, dark spines, one bay only",
            "CC BY-SA 4.0",
            "Biblioteca dj.JPG"
        ),
        .make(
            "loc-aisle",
            "Library of Congress aisle",
            "Long aisle, spines small in the frame",
            "CC0",
            "Around the Library of Congress in the Fall and Winter of 2024 - 19.jpg"
        ),
        .make(
            "account-ledgers",
            "Worn ledgers",
            "Close crop, faded cloth, partial titles",
            "CC BY-SA 2.0",
            "Account books (40161579285).jpg"
        )
    ]

    private static func make(
        _ id: String,
        _ title: String,
        _ scene: String,
        _ license: String,
        _ fileName: String
    ) -> ShelfFixture {
        ShelfFixture(id: id, title: title, scene: scene, license: license, fileName: fileName)
    }
}

enum ShelfFixtureError: Error, LocalizedError {
    case http(Int)
    case notJPEG

    var errorDescription: String? {
        switch self {
        case let .http(code):
            "Shelf photo download failed (\(code))"
        case .notJPEG:
            "Shelf photo was not a JPEG"
        }
    }
}

enum ShelfFixtureLoader {
    private static let jpegMagic: [UInt8] = [0xFF, 0xD8, 0xFF]

    static func jpeg(for fixture: ShelfFixture) async throws -> Data {
        let cache = cacheURL(id: fixture.id)
        if let cached = try? Data(contentsOf: cache), cached.starts(with: jpegMagic) {
            return cached
        }

        var request = URLRequest(url: fixture.jpegURL)
        request.setValue(
            "SwiftWing/1.0 (bookshelf test fixtures)",
            forHTTPHeaderField: "User-Agent"
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw ShelfFixtureError.http(status) }
        guard data.starts(with: jpegMagic) else { throw ShelfFixtureError.notJPEG }

        let folder = cache.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try data.write(to: cache, options: .atomic)
        return data
    }

    /// `SHELF_FIXTURE=<id>` downloads that shelf. Otherwise the legacy `test_book_stack.jpg` paths.
    static func dataForLaunchInjection() async -> Data? {
        if let id = TestLaunch.shelfFixtureID() {
            if let fixture = ShelfFixture.catalog.first(where: { $0.id == id }) {
                return try? await jpeg(for: fixture)
            }
            return nil
        }
        if let bundleURL = Bundle.main.url(forResource: "test_book_stack", withExtension: "jpg"),
           let data = try? Data(contentsOf: bundleURL) {
            return data
        }
        let paths = [
            "/Users/juju/dev_repos/swiftwing/test_book_stack.jpg",
            ProcessInfo.processInfo.environment["TEST_IMAGE_PATH"]
        ].compactMap(\.self)
        return paths.compactMap { try? Data(contentsOf: URL(fileURLWithPath: $0)) }.first
    }

    private static func cacheURL(id: String) -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ShelfFixtures", isDirectory: true)
            .appendingPathComponent(id)
            .appendingPathExtension("jpg")
    }
}

@MainActor
enum ShelfScanInjection {
    static func start(jpeg: Data, viewModel: CameraViewModel, modelContext: ModelContext) {
        let itemId = UUID()
        let scanTask = Task {
            await viewModel.processCaptureWithImageData(
                itemId: itemId,
                imageData: jpeg,
                modelContext: modelContext
            )
        }
        Task { await viewModel.scanCoordinator.trackJob(id: itemId, task: scanTask) }
    }
}

#if DEBUG
struct ShelfTestBenchView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let viewModel: CameraViewModel
    @Binding var selectedTab: AppTab
    @Binding var showOnboardingPreview: Bool

    @State private var status = "Wikimedia Commons shelves, long edge 1920."
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            List {
                Section("Screens") {
                    Button("Show onboarding") {
                        showOnboardingPreview = true
                        dismiss()
                    }
                    .accessibilityIdentifier("test_bench_show_onboarding")

                    Button("Show camera guidance") {
                        UserDefaults.standard.set(false, forKey: "hasSeenCameraGuidance")
                        NotificationCenter.default.post(name: .showCameraGuidance, object: nil)
                        selectedTab = .camera
                        dismiss()
                    }
                    .accessibilityIdentifier("test_bench_show_guidance")

                    Button("Library tab") {
                        selectedTab = .library
                        dismiss()
                    }
                    .accessibilityIdentifier("test_bench_tab_library")

                    Button("Review tab") {
                        selectedTab = .review
                        dismiss()
                    }
                    .accessibilityIdentifier("test_bench_tab_review")

                    Button("Camera tab") {
                        selectedTab = .camera
                        dismiss()
                    }
                    .accessibilityIdentifier("test_bench_tab_camera")
                }

                Section("Library data") {
                    Button("Clear library") { clearLibrary() }
                        .accessibilityIdentifier("test_bench_clear")
                    Button("Seed library") { seedLibrary() }
                        .accessibilityIdentifier("test_bench_seed")
                }

                Section("Shelf photos") {
                    ForEach(ShelfFixture.catalog) { fixture in
                        Button {
                            Task { await inject(fixture) }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(fixture.title)
                                Text("\(fixture.scene) · \(fixture.license)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .disabled(isLoading)
                        .accessibilityIdentifier("test_bench_shelf_\(fixture.id)")
                    }
                }
            }
            .navigationTitle("Test bench")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("Done") { dismiss() }
                    .accessibilityIdentifier("test_bench_done")
            }
            .safeAreaInset(edge: .bottom) {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .accessibilityIdentifier("test_bench_status")
            }
        }
        .accessibilityIdentifier("test_bench_sheet")
    }

    private func clearLibrary() {
        do {
            try modelContext.delete(model: Book.self)
            try modelContext.save()
            status = "Cleared the library."
        } catch {
            status = error.localizedDescription
        }
    }

    private func seedLibrary() {
        do {
            try modelContext.delete(model: Book.self)
            try modelContext.save()
            DataSeeder.seedLibrary(context: modelContext)
            status = "Seeded the library."
        } catch {
            status = error.localizedDescription
        }
    }

    private func inject(_ fixture: ShelfFixture) async {
        isLoading = true
        status = "Loading \(fixture.id)…"
        do {
            let jpeg = try await ShelfFixtureLoader.jpeg(for: fixture)
            ShelfScanInjection.start(jpeg: jpeg, viewModel: viewModel, modelContext: modelContext)
            status = "Sent \(fixture.id) (\(jpeg.count) bytes) to the scan pipeline."
            selectedTab = .camera
            dismiss()
        } catch {
            status = error.localizedDescription
        }
        isLoading = false
    }
}
#endif
