import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

// MARK: - Swiss Glass Design System
//
// SwiftWing's design language: 60% Swiss Utility + 40% Liquid Glass
// - Black base (#0D0D0D) for OLED optimization
// - .ultraThinMaterial overlays for depth
// - Rounded corners (12px) with white borders
// - Spring animations for fluidity
// - JetBrains Mono for data/IDs, SF Pro for UI

// MARK: - Color Extensions
extension Color {
    // Base Colors
    static let swissBackground = Color(red: 0.05, green: 0.05, blue: 0.05) // #0D0D0D
    static let swissText = Color.white
    static let internationalOrange = Color(red: 1.0, green: 0.31, blue: 0.0) // #FF4F00

    // State Colors (Processing Queue & UI Feedback)
    /// Yellow - Processing state (image being compressed/resized)
    /// Example: `.foregroundColor(.swissProcessing)`
    static let swissProcessing = Color.yellow

    /// Blue - Uploading state (network transfer in progress)
    /// Example: `.foregroundColor(.swissUploading)`
    static let swissUploading = Color.blue

    /// Green - Done state (operation completed successfully)
    /// Example: `.foregroundColor(.swissDone)`
    static let swissDone = Color.green

    /// Red - Error state (operation failed)
    /// Example: `.foregroundColor(.swissError)`
    static let swissError = Color.red
}

// MARK: - Font Extensions
extension Font {
    /// Cached check for whether JetBrains Mono font is available
    /// Performed once at app launch to avoid repeated file system checks
    private static let isJetBrainsMonoAvailable: Bool = {
        #if canImport(UIKit)
        let testFont = UIFont(name: "JetBrainsMono-Regular", size: 16)
        if testFont == nil {
            print("⚠️ JetBrains Mono not found, falling back to system monospaced font")
            return false
        }
        return true
        #else
        return true  // Assume available on non-UIKit platforms
        #endif
    }()

    /// Default JetBrains Mono font scaled to body text style
    /// Respects Dynamic Type for accessibility
    /// Falls back to system monospaced font if JetBrains Mono is unavailable
    static let jetBrainsMono: Font = {
        guard isJetBrainsMonoAvailable else {
            return Font.system(size: 16, design: .monospaced).weight(.regular)
        }
        return Font.custom("JetBrainsMono-Regular", size: 16, relativeTo: .body)
    }()

    /// JetBrains Mono font with custom size, scaled relative to specified text style
    /// Falls back to system monospaced font if JetBrains Mono is unavailable
    /// - Parameters:
    ///   - size: Base font size
    ///   - relativeTo: Text style to scale relative to (default: .body)
    /// - Returns: Dynamic Type-aware custom font
    static func jetBrainsMono(size: CGFloat, relativeTo textStyle: TextStyle = .body) -> Font {
        guard isJetBrainsMonoAvailable else {
            return Font.system(size: size, design: .monospaced).weight(.regular)
        }
        return Font.custom("JetBrainsMono-Regular", size: size, relativeTo: textStyle)
    }
}

// MARK: - ViewModifiers
/// Swiss Glass Card - Black background with ultra-thin material overlay
///
/// Usage:
/// ```swift
/// VStack {
///     Text("Title")
///     Text("Subtitle")
/// }
/// .padding()
/// .swissGlassCard()
/// ```
struct SwissGlassCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.black)
            .background(.ultraThinMaterial)
            .cornerRadius(12)
    }
}

/// Swiss Glass Overlay - Floating overlay with ultra-thin material and white border
///
/// Usage:
/// ```swift
/// Text("2.5x")
///     .swissGlassOverlay()
/// ```
struct SwissGlassOverlay: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
            )
    }
}

/// Swiss Glass Button - Interactive button with material background and spring animation
///
/// Usage:
/// ```swift
/// Button("Scan") { }
///     .swissGlassButton()
/// ```
struct SwissGlassButton: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.vertical, 16)
            .padding(.horizontal, 24)
            .background(.ultraThinMaterial)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.white.opacity(0.3), lineWidth: 1)
            )
    }
}

// MARK: - Animation Extensions
extension Animation {
    /// Swiss Spring - Standard spring animation for all UI transitions
    /// Duration: 0.2s for snappy, fluid feel
    ///
    /// Usage:
    /// ```swift
    /// withAnimation(.swissSpring) {
    ///     showOverlay = true
    /// }
    /// ```
    static let swissSpring = Animation.spring(duration: 0.2)
}

// MARK: - View Extensions
extension View {
    /// Applies Swiss Glass Card styling
    func swissGlassCard() -> some View {
        modifier(SwissGlassCard())
    }

    /// Applies Swiss Glass Overlay styling (floating badges, labels)
    func swissGlassOverlay() -> some View {
        modifier(SwissGlassOverlay())
    }

    /// Applies Swiss Glass Button styling
    func swissGlassButton() -> some View {
        modifier(SwissGlassButton())
    }

    /// Adds Swiss Spring animation to any view modifier
    ///
    /// Usage:
    /// ```swift
    /// Circle()
    ///     .swissSpring()
    ///     .scaleEffect(isPressed ? 0.95 : 1.0)
    /// ```
    func swissSpring() -> some View {
        self.animation(.swissSpring, value: UUID())
    }

    /// Triggers haptic feedback on value change
    /// Shorthand for `.sensoryFeedback(.impact, trigger: value)`
    ///
    /// Usage:
    /// ```swift
    /// Button("Capture") { showFlash.toggle() }
    ///     .haptic(.impact, trigger: showFlash)
    /// ```
    func haptic<T: Equatable>(_ feedback: SensoryFeedback, trigger: T) -> some View {
        self.sensoryFeedback(feedback, trigger: trigger)
    }
}
