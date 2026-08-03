import SwiftUI

/// One-time coach overlay for the camera tab. Uses its own AppStorage key —
/// separate from `hasCompletedOnboarding` — so it can be reset or shown
/// independently of app onboarding.
struct CameraFirstRunGuidance: View {
    @AppStorage("hasSeenCameraGuidance") private var hasSeenCameraGuidance = false
    let onDismiss: () -> Void

    private let tips: [(icon: String, title: String, body: String)] = [
        (
            "books.vertical", "Fill the frame",
            "Get the spines edge to edge — one shelf at a time works best."
        ),
        ("hand.tap", "Tap to focus", "Tap any spine to focus and set exposure there."),
        ("lock", "Lock it in", "Tap AE/AF to hold focus across a run of shots."),
        (
            "checklist", "Review before saving",
            "Everything lands in the review queue first — nothing is added without your approval."
        )
    ]

    var body: some View {
        ZStack {
            Color.black.opacity(0.75).ignoresSafeArea()

            VStack(spacing: 24) {
                Text("Scanning Shelves")
                    .font(.title2.bold())
                    .foregroundStyle(.white)

                VStack(alignment: .leading, spacing: 18) {
                    ForEach(tips, id: \.title) { tip in
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: tip.icon)
                                .font(.title3)
                                .foregroundStyle(Color.internationalOrange)
                                .frame(width: 28)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(tip.title)
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                Text(tip.body)
                                    .font(.subheadline)
                                    .foregroundStyle(.white.opacity(0.75))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .dynamicTypeSize(.xSmall ... .accessibility3)

                Button(action: dismiss) {
                    Text("Start Scanning")
                        .font(.body.bold())
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.internationalOrange)
                        .clipShape(.rect(cornerRadius: 8))
                }
                .accessibilityIdentifier("camera_guidance_dismiss_button")
            }
            .padding(28)
            .swissGlassCard()
            .padding(24)
        }
        .transition(.opacity)
    }

    private func dismiss() {
        hasSeenCameraGuidance = true
        onDismiss()
    }
}

#Preview {
    CameraFirstRunGuidance {}
        .preferredColorScheme(ColorScheme.dark)
}
