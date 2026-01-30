//
//  CaptureGuidanceView.swift
//  swiftwing
//
//  Created by Claude Code on 2026-01-30.
//

import SwiftUI
import Foundation

/// Smart capture guidance overlay that displays real-time feedback to users
/// during camera capture. Uses Swiss Glass design system with smooth animations.
///
/// Position: Top center of screen with safe area insets
/// Design: Black base + .ultraThinMaterial with rounded corners
/// Animations: Spring-based slide in/out transitions
struct CaptureGuidanceView: View {
    // MARK: - Properties

    /// Current guidance state to display
    let guidance: CaptureGuidance

    // MARK: - Computed Properties

    /// Message text based on current guidance state
    private var message: String {
        switch guidance {
        case .spineDetected:
            return "Spine detected ✓"
        case .moveCloser:
            return "Move closer"
        case .holdSteady:
            return "Hold steady"
        case .noBookDetected:
            return "Position book spine"
        }
    }

    /// Text color based on guidance state
    /// Success state (spineDetected) uses International Orange, others use white
    private var textColor: Color {
        switch guidance {
        case .spineDetected:
            return .internationalOrange
        default:
            return .swissText
        }
    }

    /// Icon for guidance state (checkmark for success)
    private var icon: String? {
        switch guidance {
        case .spineDetected:
            return "checkmark.circle.fill"
        default:
            return nil
        }
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 8) {
            // Optional icon for success state
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(textColor)
            }

            // Guidance message
            Text(message)
                .font(.system(size: 16, weight: .semibold, design: .default))
                .foregroundColor(textColor)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.black)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(textColor.opacity(0.3), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(.swissSpring, value: guidance)
    }
}

// MARK: - Preview Provider

#Preview("Spine Detected") {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack {
            CaptureGuidanceView(guidance: .spineDetected)
                .padding(.top, 60)
            Spacer()
        }
    }
}

#Preview("Move Closer") {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack {
            CaptureGuidanceView(guidance: .moveCloser)
                .padding(.top, 60)
            Spacer()
        }
    }
}

#Preview("Hold Steady") {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack {
            CaptureGuidanceView(guidance: .holdSteady)
                .padding(.top, 60)
            Spacer()
        }
    }
}

#Preview("No Book Detected") {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack {
            CaptureGuidanceView(guidance: .noBookDetected)
                .padding(.top, 60)
            Spacer()
        }
    }
}

#Preview("Animated States") {
    ZStack {
        Color.black.ignoresSafeArea()

        CaptureGuidanceAnimationPreview()
    }
}

/// Preview helper that cycles through all guidance states
private struct CaptureGuidanceAnimationPreview: View {
    @State private var currentGuidance: CaptureGuidance = .noBookDetected

    var body: some View {
        VStack {
            CaptureGuidanceView(guidance: currentGuidance)
                .padding(.top, 60)
            Spacer()
        }
        .onAppear {
            startCycling()
        }
    }

    private func startCycling() {
        let states: [CaptureGuidance] = [
            .noBookDetected,
            .moveCloser,
            .holdSteady,
            .spineDetected
        ]

        var currentIndex = 0
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            currentIndex = (currentIndex + 1) % states.count
            currentGuidance = states[currentIndex]
        }
    }
}
