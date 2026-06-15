import Foundation
import CoreGraphics
import ImageIO

// Bounds tolerance for window position drift before requiring fresh get_app_state
let appScreenBoundsDriftTolerance: CGFloat = 8.0

// stale-state error text — exact string matters for tests
let appScreenStaleStateError = "Computer Use target screen changed. Call get_app_state for this app before acting again."

public struct SnapshotIdentity: Equatable {
    public let pid: pid_t
    public let bundleIdentifier: String?
    public let targetWindowID: CGWindowID?
    public let windowBounds: CGRect?
    public let screenshotPixelSize: CGSize?  // decoded once from PNG header, cached
    public let captureGeneration: UInt64
}

public struct AppScreenSession {
    public let identity: SnapshotIdentity

    // Require coordinate to be inside screenshot pixel bounds
    public func requireCoordinateInsideScreenshot(_ point: CGPoint) throws {
        guard let size = identity.screenshotPixelSize else {
            throw ComputerUseError.stateUnavailable("Coordinate action requires a screenshot. Call get_app_state first.")
        }
        guard point.x >= 0, point.y >= 0, point.x < size.width, point.y < size.height else {
            throw ComputerUseError.stateUnavailable("Coordinate (\(Int(point.x)), \(Int(point.y))) is outside screenshot bounds (\(Int(size.width))x\(Int(size.height))).")
        }
    }

    // Gate keyboard actions: require PID + bundle ID match (no AX focus required)
    public func requireKeyboardOwnership(pid: pid_t, bundleIdentifier: String?) throws {
        guard pid == identity.pid else {
            throw ComputerUseError.stateUnavailable(appScreenStaleStateError)
        }
        if let required = identity.bundleIdentifier, let provided = bundleIdentifier {
            guard required == provided else {
                throw ComputerUseError.stateUnavailable(appScreenStaleStateError)
            }
        }
    }
}

// Protocol seam for current-window identity — allows fixture mode to inject no-op
public protocol WindowIdentityProvider {
    func currentWindowID(forPID pid: pid_t) -> CGWindowID?
    func currentWindowBounds(forPID pid: pid_t, windowID: CGWindowID) -> CGRect?
}

public final class SystemWindowIdentityProvider: WindowIdentityProvider {
    public init() {}

    public func currentWindowID(forPID pid: pid_t) -> CGWindowID? {
        // Live CGWindow lookup — only called during get_app_state capture, not during validate()
        let options = CGWindowListOption([.excludeDesktopElements, .optionOnScreenOnly])
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return nil }
        return windows.first(where: { ($0[kCGWindowOwnerPID as String] as? pid_t) == pid })
            .flatMap { $0[kCGWindowNumber as String] as? CGWindowID }
    }

    public func currentWindowBounds(forPID pid: pid_t, windowID: CGWindowID) -> CGRect? {
        let options = CGWindowListOption([.excludeDesktopElements])
        guard let windows = CGWindowListCopyWindowInfo(options, windowID) as? [[String: Any]] else { return nil }
        guard let entry = windows.first(where: { ($0[kCGWindowNumber as String] as? CGWindowID) == windowID }),
              let boundsDict = entry[kCGWindowBounds as String] as? [String: Any]
        else { return nil }
        return CGRect(
            x: (boundsDict["X"] as? CGFloat) ?? 0,
            y: (boundsDict["Y"] as? CGFloat) ?? 0,
            width: (boundsDict["Width"] as? CGFloat) ?? 0,
            height: (boundsDict["Height"] as? CGFloat) ?? 0
        )
    }
}

// No-op provider for fixture mode — validate() performs zero live system calls
public final class FixtureWindowIdentityProvider: WindowIdentityProvider {
    public init() {}
    public func currentWindowID(forPID pid: pid_t) -> CGWindowID? { return nil }
    public func currentWindowBounds(forPID pid: pid_t, windowID: CGWindowID) -> CGRect? { return nil }
}

public final class AppScreenSessionValidator {
    // windowIdentityProvider is ONLY used at get_app_state capture time, NOT in validate()
    // validate() performs ZERO live system calls

    public init() {}

    // Build SnapshotIdentity from AppSnapshot during get_app_state
    // This is called once per snapshot capture, not per action
    public func buildIdentity(from snapshot: AppSnapshot, captureGeneration: UInt64) -> SnapshotIdentity {
        let pixelSize = snapshot.screenshotPNGData.flatMap { Self.pngPixelSize(from: $0) }
        return SnapshotIdentity(
            pid: snapshot.app.pid,
            bundleIdentifier: snapshot.app.bundleIdentifier,
            targetWindowID: snapshot.targetWindowID,
            windowBounds: snapshot.windowBounds,
            screenshotPixelSize: pixelSize,
            captureGeneration: captureGeneration
        )
    }

    // validate() is ZERO live system calls — pure field comparison against cached identity
    public func validate(cachedIdentity: SnapshotIdentity, currentSnapshot: AppSnapshot) throws -> AppScreenSession {
        guard currentSnapshot.app.pid == cachedIdentity.pid else {
            throw ComputerUseError.stateUnavailable(appScreenStaleStateError)
        }
        if let required = cachedIdentity.bundleIdentifier, let current = currentSnapshot.app.bundleIdentifier {
            guard required == current else {
                throw ComputerUseError.stateUnavailable(appScreenStaleStateError)
            }
        }
        if let required = cachedIdentity.targetWindowID, let current = currentSnapshot.targetWindowID,
           required != current {
            // CGWindowID changed but PID+bundleID still match — window was regenerated (tab, sheet, Spaces).
            // Log a diagnostic and continue rather than failing the action.
            fputs("[open-computer-use] Window ID changed \(required)→\(current) for \(currentSnapshot.app.bundleIdentifier ?? "?") (pid \(currentSnapshot.app.pid)); proceeding with matched PID+bundleID.\n", stderr)
        }
        if let requiredBounds = cachedIdentity.windowBounds, let currentBounds = currentSnapshot.windowBounds {
            let drift = max(
                abs(requiredBounds.minX - currentBounds.minX),
                abs(requiredBounds.minY - currentBounds.minY),
                abs(requiredBounds.width - currentBounds.width),
                abs(requiredBounds.height - currentBounds.height)
            )
            guard drift <= appScreenBoundsDriftTolerance else {
                throw ComputerUseError.stateUnavailable(appScreenStaleStateError)
            }
        }
        return AppScreenSession(identity: cachedIdentity)
    }

    static func pngPixelSize(from data: Data) -> CGSize? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let w = props[kCGImagePropertyPixelWidth as String] as? CGFloat,
              let h = props[kCGImagePropertyPixelHeight as String] as? CGFloat
        else { return nil }
        return CGSize(width: w, height: h)
    }
}
