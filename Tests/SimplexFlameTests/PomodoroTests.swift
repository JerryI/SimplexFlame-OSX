import XCTest
@testable import SimplexFlame

final class PomodoroTests: XCTestCase {
    func testFreshSessionHasFixedTwentyMinuteDeadline() {
        var session = PomodoroSession()
        let now = ContinuousClock.now
        XCTAssertFalse(session.isActive)
        XCTAssertEqual(session.remainingSeconds(now: now), 1200)
        session.start(now: now)
        XCTAssertTrue(session.isActive)
        XCTAssertEqual(session.remainingSeconds(now: now), 1200)
        XCTAssertEqual(session.remainingSeconds(now: now.advanced(by: .seconds(1))), 1199)
    }

    func testPartialSecondsRoundUpUntilDeadline() {
        var session = PomodoroSession()
        let now = ContinuousClock.now
        session.start(now: now)
        XCTAssertEqual(session.remainingSeconds(now: now.advanced(by: .milliseconds(100))), 1200)
        XCTAssertEqual(session.remainingSeconds(now: now.advanced(by: .milliseconds(1_199_900))), 1)
        XCTAssertEqual(session.remainingSeconds(now: now.advanced(by: .seconds(1200))), 0)
    }

    func testDelayedUpdatesAndSleepDoNotExtendSession() {
        var session = PomodoroSession()
        let now = ContinuousClock.now
        session.start(now: now)
        XCTAssertEqual(session.remainingSeconds(now: now.advanced(by: .seconds(713))), 487)
        XCTAssertEqual(session.remainingSeconds(now: now.advanced(by: .seconds(1500))), 0)
    }

    func testInterruptResetsAndRestartGetsFullInterval() {
        var session = PomodoroSession()
        let now = ContinuousClock.now
        session.start(now: now)
        session.reset()
        XCTAssertFalse(session.isActive)
        XCTAssertNil(session.deadline)
        XCTAssertEqual(session.remainingSeconds(now: now.advanced(by: .seconds(100))), 1200)
        session.start(now: now.advanced(by: .seconds(100)))
        XCTAssertEqual(session.remainingSeconds(now: now.advanced(by: .seconds(101))), 1199)
    }

    func testCountdownFormatting() {
        XCTAssertEqual(PomodoroSession.label(for: 1200), "20:00")
        XCTAssertEqual(PomodoroSession.label(for: 1199), "19:59")
        XCTAssertEqual(PomodoroSession.label(for: 60), "01:00")
        XCTAssertEqual(PomodoroSession.label(for: 9), "00:09")
        XCTAssertEqual(PomodoroSession.label(for: 0), "00:00")
    }
}
