import SwiftUI

/// Offline network status indicator with queued scan count
/// Displayed in top-right corner when network is unavailable
struct OfflineIndicatorView: View {
    let offlineQueuedCount: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
                .font(.caption)
                .foregroundColor(.swissError)

            Text("OFFLINE")
                .font(.jetBrainsMono)
                .foregroundColor(.swissError)

            if offlineQueuedCount > 0 {
                Text("(\(offlineQueuedCount))")
                    .font(.jetBrainsMono)
                    .foregroundColor(.swissText.opacity(0.7))
            }
        }
        .swissGlassOverlay()
        .padding(.top, 60)
        .padding(.trailing, 8)
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack {
            HStack {
                Spacer()
                OfflineIndicatorView(offlineQueuedCount: 3)
            }

            Spacer()
        }
    }
    .preferredColorScheme(.dark)
}
