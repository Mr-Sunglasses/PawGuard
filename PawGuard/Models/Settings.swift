import Foundation

enum AccentTheme: String, CaseIterable, Codable, Identifiable {
    case automatic
    case pink
    case mint
    case blue
    case lavender
    case orange
    case monochrome

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: "Automatic"
        case .pink: "Pink"
        case .mint: "Mint"
        case .blue: "Blue"
        case .lavender: "Lavender"
        case .orange: "Orange"
        case .monochrome: "Monochrome"
        }
    }
}

enum SensitivityPreset: String, CaseIterable, Codable, Identifiable {
    case relaxed
    case balanced
    case sensitive
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .relaxed: "Relaxed"
        case .balanced: "Balanced"
        case .sensitive: "Sensitive"
        case .custom: "Custom"
        }
    }

    var threshold: Int? {
        switch self {
        case .relaxed: 85
        case .balanced: 70
        case .sensitive: 55
        case .custom: nil
        }
    }
}

struct PawGuardSettings: Codable, Equatable {
    var hasCompletedOnboarding = false
    var lockDuration: TimeInterval = 20
    var extendOnActivity = true
    var showProtectionOverlay = true
    var playProtectionSound = true
    var launchAtLogin = false
    var sensitivity: SensitivityPreset = .balanced
    var customThreshold = 70
    var accentTheme: AccentTheme = .automatic
    var showCatPhoto = true
    var animationIntensity: Double = 0.8
    /// Withhold borderline input briefly and replay it if it turns out human,
    /// instead of locking on the first crossing of the threshold.
    var useGraceWindow = true
    /// Let PawGuard learn from emergency unlocks and from how this user types.
    var adaptiveCalibration = true
    /// Offer to remove what the cat typed before protection engaged.
    var offerUndo = true
    /// Stay out of the way while a full-screen app such as a game is frontmost.
    var pauseInFullscreen = true
    /// Bundle identifiers PawGuard never protects.
    var disabledBundleIdentifiers: [String] = []

    var detectionThreshold: Int {
        sensitivity.threshold ?? max(30, min(100, customThreshold))
    }

    static let lockDurations: [TimeInterval] = [10, 20, 30, 45, 60]
}

@MainActor
final class SettingsStore: ObservableObject {
    @Published var settings: PawGuardSettings {
        didSet { save() }
    }

    private let defaults: UserDefaults
    private let key = "pawguard.settings"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
            let decoded = LenientDecoding.decode(PawGuardSettings.self, from: data, fallback: PawGuardSettings())
        {
            settings = decoded
        } else {
            settings = PawGuardSettings()
        }
    }

    func save() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: key)
    }
}
