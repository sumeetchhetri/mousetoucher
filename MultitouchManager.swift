import Foundation
import CoreGraphics
import AppKit

// Swift wrapper for Multitouch framework
class MultitouchManager {
    private var devices: [MTDeviceRef] = []
    private var tapDetector = TapDetector(tapTimeThreshold: 0.25, tapMovementThreshold: 0.08)
    private var twoFingerTapDetector = TwoFingerTapDetector(tapTimeThreshold: 0.35, movementThreshold: 0.12)
    private var isEnabled = true
    private var isDragLockAvailable = false
    private var activeTouch: Int32 = -1
    private var touchStartX: Float = 0.0
    private var touchStartY: Float = 0.0
    private var surfaceMovementThreshold: Float = 0.15  // Max finger movement on surface (0-1 scale)

    /// Taps with a normalized x above this are right clicks. Configurable from the menu bar.
    var rightClickThreshold: Float = Preferences.rightClickThreshold {
        didSet {
            rightClickThreshold = Preferences.clamp(rightClickThreshold)
        }
    }

    fileprivate static var sharedInstance: MultitouchManager?

    var onClickSynthesized: ((CGPoint, Bool) -> Void)?
    var onDragLockChanged: ((CGPoint, Bool) -> Void)?
    private(set) var isDragLocked = false

    init() {
        MultitouchManager.sharedInstance = self
    }

    func start() {
        guard let deviceList = MTDeviceCreateList() else {
            return
        }

        let deviceArray = deviceList.takeRetainedValue() as NSArray
        let count = CFArrayGetCount(deviceArray)

        for i in 0..<count {
            let device = unsafeBitCast(CFArrayGetValueAtIndex(deviceArray, i), to: MTDeviceRef.self)

            // Only monitor external devices (Magic Mouse), skip built-in trackpads
            let isBuiltIn = MTDeviceIsBuiltIn(device)

            if !isBuiltIn {
                devices.append(device)
                MTRegisterContactFrameCallback(device, touchCallback)
                MTDeviceStart(device, 0)
            }
        }
    }

    func stop() {
        releaseDragLock()
        resetTouchTracking()

        for device in devices {
            MTUnregisterContactFrameCallback(device, touchCallback)
            MTDeviceStop(device)
        }
        devices.removeAll()
    }

    func setEnabled(_ enabled: Bool) {
        if !enabled {
            releaseDragLock()
            resetTouchTracking()
        }
        isEnabled = enabled
    }

    func setDragLockAvailable(_ available: Bool) {
        if !available {
            releaseDragLock()
        }
        isDragLockAvailable = available
    }

    func processTouches(_ touches: UnsafeMutablePointer<MTTouch>, numTouches: Int, timestamp: Double) {
        guard isEnabled else { return }

        // The callback comes from a private framework; don't trust a negative count.
        guard numTouches >= 0 else { return }

        let surfaceTouches = (0..<numTouches).map { index in
            let touch = touches[index]
            return SurfaceTouch(
                identifier: touch.identifier,
                position: CGPoint(
                    x: CGFloat(touch.normalized.position.x),
                    y: CGFloat(touch.normalized.position.y)
                )
            )
        }
        let twoFingerResult = twoFingerTapDetector.process(
            touches: surfaceTouches,
            timestamp: timestamp
        )

        switch twoFingerResult {
        case .recognized:
            cancelSingleTouchTracking()
            if isDragLockAvailable {
                toggleDragLock()
            }
            return
        case .rejectedMultiTouchGesture:
            cancelSingleTouchTracking()
            return
        case .none:
            break
        }

        // Once a second finger has participated, wait for every finger to lift. Otherwise the
        // last remaining finger could be mistaken for a fresh one-finger click.
        if twoFingerTapDetector.suppressesSingleFingerTap {
            cancelSingleTouchTracking()
            return
        }

        if numTouches == 0 {
            if activeTouch != -1 {
                // Get cursor position directly from CGEvent (already in correct coordinate space)
                let cgLocation = CGEvent(source: nil)?.location ?? CGPoint.zero

                if isDragLocked {
                    // Fallback release: a clean one-finger tap releases an active drag lock without
                    // producing another click. Moving the mouse or resting a finger while dragging
                    // is not a tap and will not release the lock.
                    if tapDetector.touchEnded(at: cgLocation) != nil {
                        releaseDragLock()
                    }
                } else if let tapLocation = tapDetector.touchEnded(at: cgLocation) {
                    let isRightClick = touchStartX > rightClickThreshold
                    onClickSynthesized?(tapLocation, isRightClick)
                }
                activeTouch = -1
                touchStartX = 0.0
                touchStartY = 0.0
            }
            return
        }

        if numTouches == 1 {
            let touch = touches[0]
            // Get cursor position directly from CGEvent (already in correct coordinate space)
            let cgLocation = CGEvent(source: nil)?.location ?? CGPoint.zero

            if touch.state == 4 || touch.state == 7 {
                if activeTouch == -1 {
                    // New touch started - record starting position on surface
                    activeTouch = touch.identifier
                    touchStartX = touch.normalized.position.x
                    touchStartY = touch.normalized.position.y
                    tapDetector.touchBegan(at: cgLocation)
                } else if activeTouch == touch.identifier {
                    // Same touch continuing - check if finger moved too much on surface (scrolling)
                    let deltaX = abs(touch.normalized.position.x - touchStartX)
                    let deltaY = abs(touch.normalized.position.y - touchStartY)
                    let surfaceMovement = max(deltaX, deltaY)

                    if surfaceMovement > surfaceMovementThreshold {
                        // Finger moved too much on surface - likely scrolling, cancel tap
                        tapDetector.reset()
                        activeTouch = -1
                        touchStartX = 0.0
                        touchStartY = 0.0
                    } else {
                        // Check cursor movement too (physical mouse movement cancels tap)
                        let moved = tapDetector.touchMoved(to: cgLocation)
                        if moved {
                            activeTouch = -1
                            touchStartX = 0.0
                            touchStartY = 0.0
                        }
                    }
                }
            }
        } else if numTouches > 1 {
            cancelSingleTouchTracking()
        }
    }

    private func toggleDragLock() {
        isDragLocked.toggle()
        let location = CGEvent(source: nil)?.location ?? CGPoint.zero
        onDragLockChanged?(location, isDragLocked)
    }

    private func releaseDragLock() {
        guard isDragLocked else { return }
        isDragLocked = false
        let location = CGEvent(source: nil)?.location ?? CGPoint.zero
        onDragLockChanged?(location, false)
    }

    private func resetTouchTracking() {
        twoFingerTapDetector.reset()
        cancelSingleTouchTracking()
    }

    private func cancelSingleTouchTracking() {
        tapDetector.reset()
        activeTouch = -1
        touchStartX = 0.0
        touchStartY = 0.0
    }

    deinit {
        stop()
    }
}

private func touchCallback(device: Int32, touches: UnsafeMutablePointer<MTTouch>?, numTouches: Int32, timestamp: Double, frame: Int32) -> Int32 {
    if let manager = MultitouchManager.sharedInstance, let touches = touches {
        manager.processTouches(touches, numTouches: Int(numTouches), timestamp: timestamp)
    }
    return 0
}
