import SwiftUI

struct HelloWorldView: View {
    var body: some View {
        VStack(spacing: 24) {
            Text("Hello SwiftWing")
                .font(.jetBrainsMono(size: 32))
                .foregroundColor(.internationalOrange)

            Text("Verifying theme constants:")
                .font(.jetBrainsMono(size: 16))
                .foregroundColor(.swissText)

            VStack(alignment: .leading, spacing: 12) {
                ThemeDemo(label: "Swiss Background", color: .swissBackground)
                ThemeDemo(label: "Swiss Text", color: .swissText)
                ThemeDemo(label: "International Orange", color: .internationalOrange)
            }
            .padding()
            .swissGlassCard()

            Text("JetBrains Mono Regular is loaded and working!")
                .font(.jetBrainsMono)
                .foregroundColor(.swissText.opacity(0.7))
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.swissBackground)
    }
}

struct ThemeDemo: View {
    let label: String
    let color: Color

    var body: some View {
        HStack {
            Rectangle()
                .fill(color)
                .frame(width: 40, height: 40)
                .cornerRadius(4)

            Text(label)
                .font(.jetBrainsMono)
                .foregroundColor(.swissText)
        }
    }
}

#Preview {
    HelloWorldView()
        .preferredColorScheme(.dark)
}
