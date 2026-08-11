import Foundation

struct PawGuardStats: Codable, Equatable {
    var detectionCount = 0
    var blockedEventCount = 0
    var totalProtectionDuration: TimeInterval = 0
    var lastDetectionDate: Date?
    var falsePositiveYesCount = 0
    var falsePositiveNoCount = 0
}

@MainActor
final class StatisticsStore: ObservableObject {
    @Published private(set) var stats: PawGuardStats

    private let defaults: UserDefaults
    private let key = "pawguard.statistics"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
            let decoded = try? JSONDecoder().decode(PawGuardStats.self, from: data)
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

    func recordBlockedEvent() {
        recordBlockedEvents(1)
    }

    func recordBlockedEvents(_ count: Int) {
        stats.blockedEventCount += max(0, count)
        save()
    }

    func recordProtectionDuration(_ duration: TimeInterval) {
        stats.totalProtectionDuration += max(0, duration)
        save()
    }

    func recordFalsePositive(wasCat: Bool) {
        if wasCat {
            stats.falsePositiveYesCount += 1
        } else {
            stats.falsePositiveNoCount += 1
        }
        save()
    }

    func save() {
        guard let data = try? JSONEncoder().encode(stats) else { return }
        defaults.set(data, forKey: key)
    }
}
