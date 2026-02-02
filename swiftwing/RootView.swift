import SwiftUI
import SwiftData
import AVFoundation

struct RootView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var cameraPermissionStatus: CameraPermissionStatus = .notDetermined
    @State private var showOnboarding = false
    @Query private var books: [Book]

    enum CameraPermissionStatus {
        case notDetermined
        case denied
        case authorized
    }

    var body: some View {
        Group {
            if showOnboarding {
                // Show onboarding on first launch
                OnboardingView(onComplete: {
                    showOnboarding = false
                })
            } else {
                // Normal app flow
                switch cameraPermissionStatus {
                case .notDetermined, .denied:
                    CameraPermissionPrimerView(isPermissionGranted: Binding(
                        get: { cameraPermissionStatus == .authorized },
                        set: { if $0 { cameraPermissionStatus = .authorized } }
                    ))
                case .authorized:
                    MainTabView(bookCount: books.count)
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
    let bookCount: Int
    @State private var viewModel = CameraViewModel()

    var body: some View {
        TabView {
            // Library Tab
            Group {
                if bookCount > 0 {
                    LibraryView()
                        .badge(bookCount)
                } else {
                    LibraryView()
                }
            }
            .tabItem {
                Label("Library", systemImage: "books.vertical")
            }

            // Review Tab
            ReviewQueueView(viewModel: viewModel)
                .tabItem {
                    Label("Review", systemImage: "checklist")
                }
                .badge(viewModel.pendingReviewBooks.count > 0 ? viewModel.pendingReviewBooks.count : 0)

            // Camera Tab
            CameraView(viewModel: viewModel)
                .tabItem {
                    Label("Camera", systemImage: "camera")
                }
        }
        .tint(.internationalOrange)  // Swiss Glass accent color for selected tab
    }
}

#Preview {
    RootView()
        .modelContainer(for: Book.self, inMemory: true)
        .preferredColorScheme(.dark)
}
