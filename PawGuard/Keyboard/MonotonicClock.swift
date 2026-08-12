import CoreGraphics
import Darwin
import Foundation

/// One clock for the whole app.
///
/// `CGEvent.timestamp` is expressed in mach absolute time units, not
/// nanoseconds. On Apple Silicon one tick is 125/3 ns, so dividing the raw
/// value by a billion produces a clock running roughly 41x slow and unrelated
/// to `ProcessInfo.systemUptime`. Mixing the two made every timer evaluation
/// see held keys as though they had been down for days.
enum MonotonicClock {
    private static let timebase: (numerator: Double, denominator: Double) = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        let numerator = info.numer == 0 ? 1 : Double(info.numer)
        let denominator = info.denom == 0 ? 1 : Double(info.denom)
        return (numerator, denominator)
    }()

    /// Seconds since boot, the same reference `ProcessInfo.systemUptime` uses.
    static var now: TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }

    static func seconds(fromMachTime machTime: UInt64) -> TimeInterval {
        Double(machTime) * timebase.numerator / timebase.denominator / 1_000_000_000
    }

    /// Converts an event timestamp and sanity-checks it against the current
    /// time. Synthesized events carry a zero timestamp, and if the platform
    /// ever changes what unit it reports, a wildly out-of-range value falls
    /// back to now rather than poisoning every hold duration.
    static func eventSeconds(_ raw: UInt64, now: TimeInterval = MonotonicClock.now) -> TimeInterval {
        guard raw != 0 else { return now }
        let converted = seconds(fromMachTime: raw)
        guard abs(converted - now) <= 1.0 else { return now }
        return converted
    }
}
