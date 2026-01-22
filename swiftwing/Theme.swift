import SwiftUI

// MARK: - Color Extensions
extension Color {
    static let swissBackground = Color(red: 0.05, green: 0.05, blue: 0.05) // #0D0D0D
    static let swissText = Color.white
    static let internationalOrange = Color(red: 1.0, green: 0.31, blue: 0.0) // #FF4F00
}

// MARK: - Font Extensions
extension Font {
    static let jetBrainsMono = Font.custom("JetBrainsMono-Regular", size: 16)
    static func jetBrainsMono(size: CGFloat) -> Font {
        return Font.custom("JetBrainsMono-Regular", size: size)
    }
}

// MARK: - ViewModifiers
struct SwissGlassCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.black)
            .background(.thinMaterial)
            .cornerRadius(8)
    }
}

extension View {
    func swissGlassCard() -> some View {
        modifier(SwissGlassCard())
    }
}
