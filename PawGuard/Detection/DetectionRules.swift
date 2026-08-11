import Foundation

enum DetectionRules {
    static let simultaneousWindow: TimeInterval = 0.120
    static let fastBurstWindow: TimeInterval = 0.450
    static let generalWindow: TimeInterval = 1.200
    static let holdThreshold: TimeInterval = 0.700
    static let extendedHoldThreshold: TimeInterval = 1.500
    static let defaultThreshold = 70
    static let cooldown: TimeInterval = 3
    static let activityExtension: TimeInterval = 8
}
