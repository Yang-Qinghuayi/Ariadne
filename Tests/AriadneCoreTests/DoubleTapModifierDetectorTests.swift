import AppKit
import AriadneCore
import Carbon.HIToolbox
import XCTest

final class DoubleTapModifierDetectorTests: XCTestCase {
    func testDoubleTapCommandTriggersOnSecondRelease() {
        let detector = DoubleTapModifierDetector(targetModifier: .command)

        XCTAssertNil(detector.processFlagsChanged(modifierFlags: [.command], timestamp: 1.00))
        XCTAssertNil(detector.processFlagsChanged(modifierFlags: [], timestamp: 1.08))
        XCTAssertNil(detector.processFlagsChanged(modifierFlags: [.command], timestamp: 1.20))

        // Should fire on second release
        XCTAssertEqual(
            detector.processFlagsChanged(modifierFlags: [], timestamp: 1.27),
            .command
        )
        XCTAssertEqual(detector.state, .idle)
    }

    func testCopyPasteRapidCommandKeysDoNotTrigger() {
        let detector = DoubleTapModifierDetector(targetModifier: .command)

        // User presses Cmd + C
        XCTAssertNil(detector.processFlagsChanged(modifierFlags: [.command], timestamp: 2.00))
        detector.processInterruptingEvent() // 'c' keyDown
        XCTAssertNil(detector.processFlagsChanged(modifierFlags: [], timestamp: 2.08))

        // User immediately presses Cmd + V within double-tap window
        XCTAssertNil(detector.processFlagsChanged(modifierFlags: [.command], timestamp: 2.18))
        detector.processInterruptingEvent() // 'v' keyDown
        XCTAssertNil(detector.processFlagsChanged(modifierFlags: [], timestamp: 2.25))
    }

    func testLongHoldDoesNotCountAsTap() {
        let detector = DoubleTapModifierDetector(
            targetModifier: .command,
            maxTapHoldDuration: 0.35,
            maxInterTapInterval: 0.38
        )

        // Held for 0.6s -> too long for a tap
        XCTAssertNil(detector.processFlagsChanged(modifierFlags: [.command], timestamp: 1.0))
        XCTAssertNil(detector.processFlagsChanged(modifierFlags: [], timestamp: 1.6))

        // Follow-up single tap must NOT fire double-tap
        XCTAssertNil(detector.processFlagsChanged(modifierFlags: [.command], timestamp: 1.7))
        XCTAssertNil(detector.processFlagsChanged(modifierFlags: [], timestamp: 1.78))
    }

    func testSlowGapResetsFirstTapAndAllowsSubsequentDoubleTap() {
        let detector = DoubleTapModifierDetector(
            targetModifier: .command,
            maxTapHoldDuration: 0.35,
            maxInterTapInterval: 0.38
        )

        // First tap
        XCTAssertNil(detector.processFlagsChanged(modifierFlags: [.command], timestamp: 1.0))
        XCTAssertNil(detector.processFlagsChanged(modifierFlags: [], timestamp: 1.05))

        // Too slow (0.6s gap) -> restarts as new first tap
        XCTAssertNil(detector.processFlagsChanged(modifierFlags: [.command], timestamp: 1.65))
        XCTAssertNil(detector.processFlagsChanged(modifierFlags: [], timestamp: 1.72))

        // Quick follow-up tap -> now fires!
        XCTAssertNil(detector.processFlagsChanged(modifierFlags: [.command], timestamp: 1.85))
        XCTAssertEqual(detector.processFlagsChanged(modifierFlags: [], timestamp: 1.92), .command)
    }

    func testCapsLockDoesNotPreventDoubleTapCommand() {
        let detector = DoubleTapModifierDetector(targetModifier: .command)

        XCTAssertNil(detector.processFlagsChanged(modifierFlags: [.command, .capsLock], timestamp: 3.00))
        XCTAssertNil(detector.processFlagsChanged(modifierFlags: [.capsLock], timestamp: 3.07))
        XCTAssertNil(detector.processFlagsChanged(modifierFlags: [.command, .capsLock], timestamp: 3.18))
        XCTAssertEqual(detector.processFlagsChanged(modifierFlags: [.capsLock], timestamp: 3.25), .command)
    }

    func testAutoDetectModeCapturesAnySingleDoubleTappedModifier() {
        let detector = DoubleTapModifierDetector(targetModifier: nil)

        // Tap Option twice
        XCTAssertNil(detector.processFlagsChanged(modifierFlags: [.option], timestamp: 5.00))
        XCTAssertNil(detector.processFlagsChanged(modifierFlags: [], timestamp: 5.08))
        XCTAssertNil(detector.processFlagsChanged(modifierFlags: [.option], timestamp: 5.20))
        XCTAssertEqual(detector.processFlagsChanged(modifierFlags: [], timestamp: 5.26), .option)
    }

    func testMultipleModifiersHeldSimultaneouslyCancelDoubleTap() {
        let detector = DoubleTapModifierDetector(targetModifier: nil)

        XCTAssertNil(detector.processFlagsChanged(modifierFlags: [.command], timestamp: 6.00))
        XCTAssertNil(detector.processFlagsChanged(modifierFlags: [.command, .shift], timestamp: 6.04))
        XCTAssertEqual(detector.state, .idle)
        XCTAssertNil(detector.processFlagsChanged(modifierFlags: [], timestamp: 6.10))
    }
}
