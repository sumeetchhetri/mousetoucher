import Foundation
import CoreGraphics

/// A touch on the normalized (0...1) Magic Mouse surface.
struct SurfaceTouch: Equatable {
    let identifier: Int32
    let position: CGPoint
}

enum TwoFingerTapResult: Equatable {
    case none
    case recognized
    case rejectedMultiTouchGesture
}

/// Detects a two-finger tap from successive MultitouchSupport frames.
///
/// The fingers do not have to land or lift in exactly the same callback frame. A gesture is
/// accepted after all fingers lift if exactly two identifiers participated, the two fingers
/// overlapped for at least one frame, and neither duration nor movement crossed its threshold.
final class TwoFingerTapDetector {
    let tapTimeThreshold: TimeInterval
    let movementThreshold: CGFloat

    private var sequenceStartTimestamp: TimeInterval?
    private var initialPositions: [Int32: CGPoint] = [:]
    private var sawTwoFingersSimultaneously = false
    private var isValid = true

    init(tapTimeThreshold: TimeInterval = 0.25, movementThreshold: CGFloat = 0.08) {
        self.tapTimeThreshold = tapTimeThreshold
        self.movementThreshold = movementThreshold
    }

    /// True after a second finger has participated and until every finger has lifted.
    /// The caller uses this to prevent the remaining finger from becoming a single-finger tap.
    var suppressesSingleFingerTap: Bool {
        initialPositions.count > 1 || sawTwoFingersSimultaneously
    }

    func process(touches: [SurfaceTouch], timestamp: TimeInterval) -> TwoFingerTapResult {
        guard !touches.isEmpty else {
            return finishSequence(at: timestamp)
        }

        if sequenceStartTimestamp == nil {
            sequenceStartTimestamp = timestamp
        }

        guard let startTimestamp = sequenceStartTimestamp else {
            return .none
        }

        if timestamp < startTimestamp || timestamp - startTimestamp >= tapTimeThreshold {
            isValid = false
        }

        if touches.count > 2 || Set(touches.map(\.identifier)).count != touches.count {
            isValid = false
        }

        if touches.count == 2 {
            sawTwoFingersSimultaneously = true
        }

        for touch in touches {
            if let initialPosition = initialPositions[touch.identifier] {
                let distance = hypot(
                    touch.position.x - initialPosition.x,
                    touch.position.y - initialPosition.y
                )
                if distance >= movementThreshold {
                    isValid = false
                }
            } else {
                initialPositions[touch.identifier] = touch.position
                if initialPositions.count > 2 {
                    isValid = false
                }
            }
        }

        return .none
    }

    func reset() {
        sequenceStartTimestamp = nil
        initialPositions.removeAll(keepingCapacity: true)
        sawTwoFingersSimultaneously = false
        isValid = true
    }

    private func finishSequence(at timestamp: TimeInterval) -> TwoFingerTapResult {
        guard let startTimestamp = sequenceStartTimestamp else {
            return .none
        }

        let involvedMultipleTouches = initialPositions.count > 1 || sawTwoFingersSimultaneously
        let duration = timestamp - startTimestamp
        let recognized = isValid
            && sawTwoFingersSimultaneously
            && initialPositions.count == 2
            && duration >= 0
            && duration < tapTimeThreshold

        reset()

        if recognized {
            return .recognized
        }
        return involvedMultipleTouches ? .rejectedMultiTouchGesture : .none
    }
}
