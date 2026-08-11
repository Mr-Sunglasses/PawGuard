import SwiftUI

struct PawAnimation: View {
    let accent: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isSettled = false

    var body: some View {
        Image(systemName: "pawprint.fill")
            .font(.system(size: 26, weight: .medium))
            .foregroundStyle(accent)
            .rotationEffect(.degrees(isSettled ? -8 : 12))
            .offset(y: isSettled ? 0 : -8)
            .opacity(isSettled ? 1 : 0.45)
            .onAppear {
                if reduceMotion {
                    isSettled = true
                } else {
                    withAnimation(.easeOut(duration: 0.45)) {
                        isSettled = true
                    }
                }
            }
    }
}
