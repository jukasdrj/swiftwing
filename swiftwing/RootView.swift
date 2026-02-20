import AVFoundation
import SwiftData
import SwiftUI

struct RootView: View {
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
        ProcessInfo.processInfo.arguments.contains("UI_TESTING")
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
                        isPermissionGranted: Binding(
                            get: { cameraPermissionStatus == .authorized },
                            set: { if $0 { cameraPermissionStatus = .authorized } }
                        ),
                        wasPreviouslyDenied: false
                    )
                case .denied:
                    CameraPermissionPrimerView(
                        isPermissionGranted: Binding(
                            get: { cameraPermissionStatus == .authorized },
                            set: { if $0 { cameraPermissionStatus = .authorized } }
                        ),
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

// MARK: - Main Tab View
/// TabView with Library, Review, and Camera tabs
/// Review tab shows pending book count badge
struct MainTabView: View {
    @Query private var books: [Book]
    @State private var viewModel = CameraViewModel()
    @State private var selectedTab: Int = ProcessInfo.processInfo.arguments.contains("INJECT_TEST_IMAGE") ? 2 : 0

    var body: some View {
        TabView(selection: $selectedTab) {
            // Library Tab
            LibraryView()
                .tabItem {
                    Label("Library", systemImage: "books.vertical")
                }
                .badge(books.count > 0 ? "\(books.count)" : nil)
                .tag(0)

            // Review Tab
            ReviewQueueView(viewModel: viewModel)
                .tabItem {
                    Label("Review", systemImage: "checklist")
                }
                .badge(viewModel.reviewQueueManager.pendingReviewBooks.count > 0 ? "\(viewModel.reviewQueueManager.pendingReviewBooks.count)" : nil)
                .tag(1)

            // Camera Tab
            CameraView(viewModel: viewModel)
                .tabItem {
                    Label("Camera", systemImage: "camera")
                }
                .tag(2)
        }
        .tint(.internationalOrange)  // Swiss Glass accent color for selected tab
        .onChange(of: viewModel.requestedTab) { _, newTab in
            if let tab = newTab {
                selectedTab = tab
                viewModel.requestedTab = nil
            }
        }
    }
}

#Preview {
    RootView()
        .modelContainer(for: Book.self, inMemory: true)
        .preferredColorScheme(.dark)
}
