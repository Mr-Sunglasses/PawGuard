import Foundation

struct RollingEventBuffer {
    private(set) var samples: [KeyboardEventSample] = []
    let duration: TimeInterval

    init(duration: TimeInterval = DetectionRules.generalWindow) {
        self.duration = duration
    }

    mutating func append(_ sample: KeyboardEventSample) {
        samples.append(sample)
        trim(through: sample.timestamp)
    }

    mutating func trim(through timestamp: TimeInterval) {
        let cutoff = timestamp - duration
        samples.removeAll { $0.timestamp < cutoff }
    }

    mutating func removeAll() {
        samples.removeAll(keepingCapacity: true)
    }
}
