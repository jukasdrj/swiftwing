import SwiftUI
import AVFoundation
import UIKit

struct CameraPermissionPrimerView: View {
    @State private var showPermissionDeniedAlert = false
    @Binding var isPermissionGranted: Bool
    var wasPreviouslyDenied: Bool = false

    var body: some View {
        ZStack {
            Color.swissBackground
                .ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                VStack(spacing: 16) {
                    Text(wasPreviouslyDenied ? "Camera Access Required" : "SwiftWing Needs Camera Access")
                        .font(.title.bold())
                        .foregroundColor(.swissText)
                        .multilineTextAlignment(.center)

                    Text(wasPreviouslyDenied ? "Camera access was denied. Please enable it in Settings to scan book spines." : "We use your camera to scan book spines. Images are processed and deleted immediately.")
                        .font(.body)
                        .foregroundColor(.swissText.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                Spacer()

                Button {
                    if wasPreviouslyDenied {
                        if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(settingsURL)
                        }
                    } else {
                        requestCameraPermission()
                    }
                } label: {
                    Text(wasPreviouslyDenied ? "Open Settings" : "Continue")
                        .font(.body.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                }
                .padding(.vertical, 16)
                .background(Color.internationalOrange)
                .cornerRadius(12)
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
                .accessibilityIdentifier("permission_continue")
            }
        }
        .alert("Camera Access Needed", isPresented: $showPermissionDeniedAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Open Settings") {
                if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsURL)
                }
            }
        } message: {
            Text("SwiftWing needs camera access to scan book spines. Please enable it in Settings > SwiftWing > Camera.")
        }
    }

    private func requestCameraPermission() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            Task { @MainActor in
                if granted {
                    isPermissionGranted = true
                } else {
                    showPermissionDeniedAlert = true
                }
            }
        }
    }
}

#Preview {
    CameraPermissionPrimerView(isPermissionGranted: .constant(false), wasPreviouslyDenied: false)
        .preferredColorScheme(.dark)
}
