import SwiftUI
import AVFoundation

struct RootView: View {
    @State private var cameraPermissionStatus: CameraPermissionStatus = .notDetermined

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
                ContentView()
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

#Preview {
    RootView()
        .preferredColorScheme(.dark)
}
