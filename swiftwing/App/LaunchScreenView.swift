import SwiftUI

/// SwiftUI launch screen for SwiftWing
/// Displays minimal Swiss Glass branding during app cold start
struct LaunchScreenView: View {
    var body: some View {
        ZStack {
            // Black Swiss background (OLED optimization)
            Color.swissBackground
                .ignoresSafeArea()

            VStack(spacing: 16) {
                // "SwiftWing" wordmark
                Text("SwiftWing")
                    .font(.custom("JetBrainsMono-Bold", size: 48))
                    .foregroundStyle(.swissText)
                    .tracking(2)

                // Tagline with orange accent
                HStack(spacing: 4) {
                    Text("AI-Powered")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.swissText.opacity(0.7))

                    Text("Book Scanner")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.internationalOrange)
                }
            }
        }
    }
}

#Preview {
    LaunchScreenView()
        .preferredColorScheme(.dark)
}
