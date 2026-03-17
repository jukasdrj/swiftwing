import SwiftUI

/// Overlay displayed when API rate limit is reached
/// Shows countdown timer and queued scan count
struct RateLimitOverlay: View {
    let remainingSeconds: Int
    let queuedScansCount: Int

    var body: some View {
        VStack(spacing: 20) {
            // Warning icon
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.internationalOrange)
                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)

            // Title
            Text("Rate Limit Reached")
                .font(.title2.bold())
                .foregroundStyle(.swissText)

            // Countdown message
            VStack(spacing: 8) {
                Text("Too many requests.")
                    .font(.body)
                    .foregroundStyle(.swissText.opacity(0.8))

                Text("Try again in")
                    .font(.body)
                    .foregroundStyle(.swissText.opacity(0.8))

                // Countdown timer (large, prominent)
                Text("\(remainingSeconds)")
                    .font(.system(size: 72, weight: .bold, design: .rounded))
                    .foregroundStyle(.internationalOrange)
                    .monospacedDigit()  // Prevents jitter during countdown

                Text("seconds")
                    .font(.body)
                    .foregroundStyle(.swissText.opacity(0.8))
            }

            // Queued scans info (if any)
            if queuedScansCount > 0 {
                HStack(spacing: 8) {
                    Image(systemName: "photo.stack")
                        .font(.subheadline)
                        .foregroundStyle(.swissText.opacity(0.6))

                    Text("\(queuedScansCount) scan\(queuedScansCount == 1 ? "" : "s") queued")
                        .font(.subheadline)
                        .foregroundStyle(.swissText.opacity(0.6))
                }
                .padding(.top, 8)
            }

            // Info text
            Text("Your scans will be processed automatically when the limit resets.")
                .font(.caption)
                .foregroundStyle(.swissText.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.top, 8)
        }
        .padding(32)
        .swissGlassCard()
        .padding(.horizontal, 24)
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        RateLimitOverlay(remainingSeconds: 42, queuedScansCount: 3)
    }
    .preferredColorScheme(.dark)
}
