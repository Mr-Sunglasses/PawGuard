import Darwin
import Foundation
import XCTest

@testable import PawGuard

final class MonotonicClockTests: XCTestCase {
    /// The bug this guards against: `CGEvent.timestamp` is in mach absolute
    /// time units, so dividing it by a billion produces a clock unrelated to
    /// `ProcessInfo.systemUptime`. On Apple Silicon the two differ by a factor
    /// of about 41, which made every held key look days old.
    func testMachTimeConvertsOntoTheSystemUptimeClock() {
        let mach = mach_absolute_time()
        let uptime = ProcessInfo.processInfo.systemUptime
        let converted = MonotonicClock.seconds(fromMachTime: mach)
        XCTAssertEqual(converted, uptime, accuracy: 0.5)
    }

    func testRawNanosecondDivisionWouldNotAgreeWithUptime() throws {
        // Documents why the naive conversion is wrong wherever the timebase is
        // not 1:1. If this ever stops holding, the platform changed, and
        // `eventSeconds` has a fallback for exactly that.
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        guard info.numer != info.denom else {
            throw XCTSkip("This machine has a 1:1 mach timebase, so both readings agree.")
        }
        let mach = mach_absolute_time()
        let naive = Double(mach) / 1_000_000_000
        XCTAssertGreaterThan(abs(naive - ProcessInfo.processInfo.systemUptime), 1)
    }

    func testEventSecondsFallsBackWhenTheStampIsUnusable() {
        let now: TimeInterval = 5_000
        // Synthesized events carry a zero timestamp.
        XCTAssertEqual(MonotonicClock.eventSeconds(0, now: now), now)
        // An out-of-range conversion must not poison hold durations.
        XCTAssertEqual(MonotonicClock.eventSeconds(1, now: now), now)
    }

    func testEventSecondsKeepsAPlausibleStamp() {
        let uptime = ProcessInfo.processInfo.systemUptime
        let mach = mach_absolute_time()
        let converted = MonotonicClock.eventSeconds(mach, now: uptime)
        XCTAssertEqual(converted, MonotonicClock.seconds(fromMachTime: mach), accuracy: 0.001)
    }

    func testDetectionWindowsAreExpressedInRealSeconds() {
        // A sanity bound on the rules themselves: if the clock is ever wrong
        // again, these constants stop meaning what their names say.
        XCTAssertEqual(DetectionRules.generalWindow, 1.2, accuracy: 0.0001)
        XCTAssertLessThan(DetectionRules.synchronyWindow, DetectionRules.simultaneousWindow)
        XCTAssertLessThan(DetectionRules.simultaneousWindow, DetectionRules.fastBurstWindow)
        XCTAssertLessThan(DetectionRules.fastBurstWindow, DetectionRules.generalWindow)
        XCTAssertLessThan(DetectionRules.graceWindow, DetectionRules.holdThreshold)
    }
}
