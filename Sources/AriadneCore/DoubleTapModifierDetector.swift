import AppKit
import Foundation

public final class DoubleTapModifierDetector {
    public enum State: Equatable {
        case idle
        case firstPressDown(ModifierTapKey, timestamp: TimeInterval)
        case firstTapReleased(ModifierTapKey, timestamp: TimeInterval)
        case secondPressDown(ModifierTapKey, timestamp: TimeInterval)

        public var activeModifier: ModifierTapKey? {
            switch self {
            case .idle:
                return nil
            case .firstPressDown(let mod, _),
                 .firstTapReleased(let mod, _),
                 .secondPressDown(let mod, _):
                return mod
            }
        }
    }

    public var targetModifier: ModifierTapKey?
    public let maxTapHoldDuration: TimeInterval
    public let maxInterTapInterval: TimeInterval

    public private(set) var state: State = .idle

    public init(
        targetModifier: ModifierTapKey? = nil,
        maxTapHoldDuration: TimeInterval = 0.35,
        maxInterTapInterval: TimeInterval = 0.38
    ) {
        self.targetModifier = targetModifier
        self.maxTapHoldDuration = maxTapHoldDuration
        self.maxInterTapInterval = maxInterTapInterval
    }

    public func reset() {
        state = .idle
    }

    public func processInterruptingEvent() {
        state = .idle
    }

    @discardableResult
    public func processFlagsChanged(
        modifierFlags: NSEvent.ModifierFlags,
        timestamp: TimeInterval
    ) -> ModifierTapKey? {
        let relevant = modifierFlags.intersection([.command, .option, .control, .shift])

        if relevant.isEmpty {
            switch state {
            case .firstPressDown(let mod, let pressTime):
                if timestamp - pressTime <= maxTapHoldDuration {
                    state = .firstTapReleased(mod, timestamp: timestamp)
                } else {
                    state = .idle
                }
                return nil

            case .secondPressDown(let mod, let pressTime):
                state = .idle
                if timestamp - pressTime <= maxTapHoldDuration {
                    return mod
                }
                return nil

            case .firstTapReleased, .idle:
                return nil
            }
        }

        guard let singleMod = KeyCodeTranslator.singleModifierTapKey(from: relevant) else {
            // Multiple modifiers held simultaneously (e.g. ⌘⇧)
            state = .idle
            return nil
        }

        if let targetModifier, singleMod != targetModifier {
            state = .idle
            return nil
        }

        switch state {
        case .idle:
            state = .firstPressDown(singleMod, timestamp: timestamp)

        case .firstPressDown(let currentMod, _):
            if currentMod != singleMod {
                state = .firstPressDown(singleMod, timestamp: timestamp)
            }

        case .firstTapReleased(let previousMod, let releaseTime):
            if previousMod == singleMod, timestamp - releaseTime <= maxInterTapInterval {
                state = .secondPressDown(singleMod, timestamp: timestamp)
            } else {
                state = .firstPressDown(singleMod, timestamp: timestamp)
            }

        case .secondPressDown(let currentMod, _):
            if currentMod != singleMod {
                state = .firstPressDown(singleMod, timestamp: timestamp)
            }
        }

        return nil
    }
}
