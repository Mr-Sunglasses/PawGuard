import Foundation

struct PawGuardStats: Codable, Equatable {
    var detectionCount = 0
    var blockedEventCount = 0
    var totalProtectionDuration: TimeInterval = 0
    var lastDetectionDate: Date?
    /// Locks the user said were not the cat, or ended with the emergency
    /// shortcut moments after they began.
    var falseAlarmCount = 0
}

@MainActor
final class StatisticsStore: ObservableObject {
    @Published private(set) var stats: PawGuardStats

    private let defaults: UserDefaults
    private let key = "pawguard.statistics"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
            let decoded = LenientDecoding.decode(PawGuardStats.self, from: data, fallback: PawGuardStats())
        {
            stats = decoded
        } else {
            stats = PawGuardStats()
        }
    }

    func recordDetection(at date: Date = .now) {
        stats.detectionCount += 1
        stats.lastDetectionDate = date
        save()
    }

    func recordBlockedEvents(_ count: Int) {
        stats.blockedEventCount += max(0, count)
        save()
    }

    func recordProtectionDuration(_ duration: TimeInterval) {
        stats.totalProtectionDuration += max(0, duration)
        save()
    }

    func recordFalseAlarm() {
        stats.falseAlarmCount += 1
        save()
    }

    func save() {
        guard let data = try? JSONEncoder().encode(stats) else { return }
        defaults.set(data, forKey: key)
    }
}
