import CoreGraphics
import Foundation

/// Converts a coordinate or size to `Int` for display text without ever trapping.
///
/// `Int(_:)` on a `Double` traps on NaN, infinity, and values outside the `Int` range, and
/// accessibility frames and caller-supplied coordinates can carry any of those. A non-finite
/// value renders as 0, an out-of-range one clamps to the `Int` bounds, and anything else
/// truncates toward zero exactly like `Int(_:)`.
public func renderedInt(_ value: Double) -> Int {
    guard value.isFinite else {
        return 0
    }
    // `Double(Int.max)` rounds up to 2^63, which `Int(_:)` cannot represent, so the upper bound is exclusive.
    if value >= Double(Int.max) {
        return Int.max
    }
    if value <= Double(Int.min) {
        return Int.min
    }
    return Int(value)
}

/// `x=<Int>, y=<Int>, w=<Int>, h=<Int>` text for a frame, safe for non-finite components.
func renderedFrameText(_ frame: CGRect) -> String {
    "x=\(renderedInt(frame.origin.x)), y=\(renderedInt(frame.origin.y)), w=\(renderedInt(frame.width)), h=\(renderedInt(frame.height))"
}
