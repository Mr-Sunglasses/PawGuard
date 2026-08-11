import AppKit
import SwiftUI

struct CatAvatarView: View {
    let path: String?
    var size: CGFloat = 54
    var cornerRadius: CGFloat = 18
    var accent: Color = .pink

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
            if let path, let image = NSImage(contentsOfFile: path) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            } else {
                Image(systemName: "cat.fill")
                    .font(.system(size: size * 0.42, weight: .medium))
                    .foregroundStyle(accent)
            }
        }
        .frame(width: size, height: size)
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        }
    }
}

enum PawGuardStyle {
    static func accent(for theme: AccentTheme) -> Color {
        switch theme {
        case .automatic: return Color(red: 0.88, green: 0.49, blue: 0.66)
        case .pink: return Color(red: 0.92, green: 0.43, blue: 0.63)
        case .mint: return Color(red: 0.35, green: 0.76, blue: 0.66)
        case .blue: return Color(red: 0.38, green: 0.63, blue: 0.92)
        case .lavender: return Color(red: 0.64, green: 0.54, blue: 0.88)
        case .orange: return Color(red: 0.93, green: 0.58, blue: 0.31)
        case .monochrome: return Color(nsColor: .labelColor)
        }
    }

    static let panelBackground = Color(
        nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(calibratedWhite: 0.12, alpha: 0.97)
                : NSColor(calibratedWhite: 0.96, alpha: 0.97)
        })
}
