import SwiftUI
import SwiftData
import AVFoundation

struct RootView: View {
    @State private var cameraPermissionStatus: CameraPermissionStatus = .notDetermined
    @Query private var books: [Book]

    enum CameraPermissionStatus {
        case notDetermined
        case denied
        case authorized
    }

    var body: some View {
        Group {
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
        .onAppear {
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
/// TabView with Library and Camera tabs
/// Library tab shows book count badge when count > 0
struct MainTabView: View {
    let bookCount: Int

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

            // Camera Tab
            CameraView()
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
