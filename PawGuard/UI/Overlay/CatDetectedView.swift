import SwiftUI

struct CatDetectedView: View {
    let profile: CatProfile?
    let message: String
    let remaining: TimeInterval
    let total: TimeInterval
    let accentTheme: AccentTheme
    let isTest: Bool
    let onUnlock: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private var accent: Color { PawGuardStyle.accent(for: accentTheme) }
    private var catName: String { profile?.displayName ?? "your cat" }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 18) {
                ZStack(alignment: .topTrailing) {
                    CatAvatarView(path: profile?.selectedPhotoPath, size: 78, cornerRadius: 24, accent: accent)
                        .scaleEffect(appeared || reduceMotion ? 1 : 0.92)
                    PawAnimation(accent: accent)
                        .offset(x: 18, y: -11)
                }

                VStack(alignment: .leading, spacing: 7) {
                    Text(isTest ? "Meet your keyboard guardian" : message)
                        .font(.system(size: 19, weight: .semibold, design: .rounded))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .layoutPriority(1)
                    Text(
                        isTest
                            ? "Preview only — your keyboard stays active."
                            : CatMessage.subtitle(remaining: remaining)
                    )
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 0)
                CountdownRing(remaining: remaining, total: total, accent: accent)
            }

            Divider()
                .opacity(0.28)
                .padding(.vertical, 14)

            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Label(isTest ? "Safe preview" : "Mouse and trackpad stay active", systemImage: isTest ? "sparkles" : "cursorarrow")
                        .font(.system(size: 12, weight: .medium))
                    if !isTest {
                        Text("Emergency unlock: ⌃⌥⌘ Esc")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button(isTest ? "Close Preview" : "Unlock Now", action: onUnlock)
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
                    .controlSize(.regular)
            }
        }
        .padding(22)
        .frame(width: 520, height: 224)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(accent.opacity(0.32), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.25), radius: 24, y: 12)
        .opacity(appeared || reduceMotion ? 1 : 0)
        .scaleEffect(appeared || reduceMotion ? 1 : 0.94)
        .onAppear {
            if reduceMotion {
                appeared = true
            } else {
                withAnimation(.easeOut(duration: 0.5)) { appeared = true }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("PawGuard protection for \(catName)")
        .accessibilityValue(isTest ? "Preview mode" : CatMessage.subtitle(remaining: remaining))
    }
}
