import SwiftUI

struct ConfidenceBadge: View {
    let confidence: Float
    var size: Size = .small

    enum Size {
        case small, large

        var fontSize: CGFloat {
            switch self {
            case .small: return 11
            case .large: return 14
            }
        }

        var padding: CGFloat {
            switch self {
            case .small: return 4
            case .large: return 8
            }
        }
    }

    var body: some View {
        Text("\(Int(confidence * 100))%")
            .font(.system(size: size.fontSize, weight: .semibold, design: .rounded))
            .foregroundColor(.white)
            .padding(.horizontal, size.padding)
            .padding(.vertical, size.padding / 2)
            .background(
                Capsule()
                    .fill(color)
            )
    }

    var color: Color {
        if confidence >= 0.9 { return .green }
        if confidence >= 0.7 { return .yellow }
        return .red
    }
}

#Preview {
    VStack(spacing: 16) {
        HStack(spacing: 8) {
            ConfidenceBadge(confidence: 0.95, size: .small)
            ConfidenceBadge(confidence: 0.75, size: .small)
            ConfidenceBadge(confidence: 0.55, size: .small)
        }

        HStack(spacing: 8) {
            ConfidenceBadge(confidence: 0.95, size: .large)
            ConfidenceBadge(confidence: 0.75, size: .large)
            ConfidenceBadge(confidence: 0.55, size: .large)
        }
    }
    .padding()
}
