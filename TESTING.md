# Mouse Toucher - Testing

Run the test suite with:

```bash
./run_tests.sh
```

or directly:

```bash
swift test
```

The SwiftPM target contains the platform-independent gesture detectors. The app integration is
also compiled by `./build.sh`, which links Apple's private MultitouchSupport framework.

## Automated coverage

- `TapDetectorTests`: one-finger tap timing, movement thresholds, reset behavior, and edge cases.
- `TwoFingerTapDetectorTests`: staggered finger landing/lift, timing and movement rejection,
  three-finger rejection, residual-finger suppression, reset behavior, and recovery after an
  invalid gesture.

## Manual drag-lock checklist

- [ ] A quick two-finger tap holds the primary mouse button.
- [ ] Moving the mouse after locking drags without fingers remaining on the touch surface.
- [ ] A second two-finger tap releases the primary mouse button.
- [ ] A one-finger tap safely releases the primary mouse button if drag lock is active.
- [ ] A one-finger tap still produces its configured left/right click while unlocked.
- [ ] One-finger taps do not disturb an active drag lock.
- [ ] Slow, moving, or three-finger gestures do not toggle drag lock.
- [ ] Disabling or quitting Mouse Toucher releases an active drag lock.
- [ ] The menu status changes between `Locked` and `Unlocked`.
