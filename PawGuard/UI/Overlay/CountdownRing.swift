import SwiftUI

struct CountdownRing: View {
    let remaining: TimeInterval
    let total: TimeInterval
    let accent: Color

    var progress: Double {
        min(1, max(0, remaining / max(total, 1)))
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(accent.opacity(0.16), lineWidth: 5)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.25), value: progress)
            VStack(spacing: -2) {
                Text("\(max(0, Int(remaining.rounded(.up))))")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                Text("seconds")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 72, height: 72)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Keyboard protected")
        .accessibilityValue("\(max(0, Int(remaining.rounded(.up)))) seconds remaining")
    }
}
