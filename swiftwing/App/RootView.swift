import AVFoundation
import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var cameraPermissionStatus: CameraPermissionStatus = .notDetermined
    @State private var showOnboarding = false
    @State private var wasPermissionPreviouslyDenied = false

    enum CameraPermissionStatus {
        case notDetermined
        case denied
        case authorized
    }

    private var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains(TestLaunch.uiTesting)
    }

    var body: some View {
        Group {
            if showOnboarding {
                // Show onboarding on first launch
                OnboardingView(onComplete: {
                    showOnboarding = false
                })
            } else if isUITesting {
                // Skip camera permission gate during UI testing
                MainTabView()
            } else {
                // Normal app flow
                switch cameraPermissionStatus {
                case .notDetermined:
                    CameraPermissionPrimerView(
                        isPermissionGranted: cameraPermissionBinding,
                        wasPreviouslyDenied: false
                    )
                case .denied:
                    CameraPermissionPrimerView(
                        isPermissionGranted: cameraPermissionBinding,
                        wasPreviouslyDenied: true
                    )
                case .authorized:
                    MainTabView()
                }
            }
        }
        .onAppear {
            // Check if this is first launch
            if !hasCompletedOnboarding {
                showOnboarding = true
            }
            checkCameraPermission()
        }
        .onChange(of: showOnboarding) { _, newValue in
            if !newValue {
                checkCameraPermission()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            // A grant or denial made in Settings is visible only after the scene is active again.
            if newPhase == .active {
                checkCameraPermission()
            }
        }
    }

    /// Continue writes true. A system denial writes false, which has to stick as `.denied`
    /// or the primer offers Continue again and iOS will not show the prompt a second time.
    private var cameraPermissionBinding: Binding<Bool> {
        Binding(
            get: { cameraPermissionStatus == .authorized },
            set: { granted in
                cameraPermissionStatus = granted ? .authorized : .denied
            }
        )
    }

    private func checkCameraPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraPermissionStatus = .authorized
        case .denied, .restricted:
            cameraPermissionStatus = .denied
        case .notDetermined:
            cameraPermissionStatus = .notDetermined
        @unknown default:
            cameraPermissionStatus = .notDetermined
        }
    }
}

enum AppTab: Int, Hashable {
    case library = 0
    case review = 1
    case camera = 2
}

// MARK: - Main Tab View

/// TabView with Library, Review, and Camera tabs
/// Review tab shows pending book count badge
struct MainTabView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = CameraViewModel()
    @State private var selectedTab: AppTab = Self.initialTab

    private static var initialTab: AppTab {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains(TestLaunch.injectTestImage) ? .camera : .library
    }
    #if DEBUG
    @State private var showTestBench = false
    @State private var showOnboardingPreview = false
    #endif
    /// Cached book count refreshed via fetchCount — avoids loading full Book objects into memory.
    @State private var bookCount: Int = 0

    private func refreshBookCount() {
        bookCount = (try? modelContext.fetchCount(FetchDescriptor<Book>())) ?? 0
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Library", systemImage: "books.vertical", value: AppTab.library) {
                LibraryView()
                    .onAppear { refreshBookCount() }
            }
            .badge(bookCount > 0 ? Text("\(bookCount)") : nil)

            Tab("Review", systemImage: "checklist", value: AppTab.review) {
                ReviewQueueView(viewModel: viewModel)
            }
            .badge(viewModel.reviewQueueManager.pendingReviewBooks.count > 0 ? Text("\(viewModel.reviewQueueManager.pendingReviewBooks.count)") : nil)

            Tab("Camera", systemImage: "camera", value: AppTab.camera) {
                CameraView(viewModel: viewModel)
                    .onDisappear { refreshBookCount() }
            }
        }
        .tint(.internationalOrange) // Swiss Glass accent color for selected tab
        .onAppear { refreshBookCount() }
        .onChange(of: viewModel.requestedTab) { _, newTab in
            if let tab = newTab {
                selectedTab = AppTab(rawValue: tab) ?? .library
                viewModel.requestedTab = nil
            }
        }
        #if DEBUG
        .overlay(alignment: .bottomLeading) {
            Button("Test bench") {
                showTestBench = true
            }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.leading, 12)
            .padding(.bottom, 8)
            .accessibilityIdentifier("test_bench_open")
        }
        .sheet(isPresented: $showTestBench) {
            ShelfTestBenchView(
                viewModel: viewModel,
                selectedTab: $selectedTab,
                showOnboardingPreview: $showOnboardingPreview
            )
        }
        .fullScreenCover(isPresented: $showOnboardingPreview) {
            OnboardingView {
                showOnboardingPreview = false
            }
        }
        #endif
    }
}

#Preview {
    RootView()
        .modelContainer(for: Book.self, inMemory: true)
        .preferredColorScheme(.dark)
}
