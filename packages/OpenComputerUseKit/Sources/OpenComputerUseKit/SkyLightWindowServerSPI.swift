import CoreGraphics
import Darwin
import Foundation

/// macOS major versions on which the occlusion and hardware-capture calls below were checked against the running
/// system. Both pass pointers whose layout was read from disassembly, and a wrong guess writes or reads through a
/// pointer the callee interprets differently, so every other version fails closed: no pin, and screenshots come from
/// ScreenCaptureKit only.
let windowServerSPIVerifiedMajorVersions: Set<Int> = [27]

/// Written into the occlusion call's previous-state byte before the call. A value the call leaves unchanged, or any
/// value other than 0 or 1, means the previous state is unknown.
let occlusionPreviousStateSentinel: UInt8 = 0xFF

/// Whether an optional WindowServer feature can be used, and why not when it cannot.
struct WindowServerFeatureAvailability: Equatable, Sendable {
    let unavailableReason: String?

    var isAvailable: Bool {
        unavailableReason == nil
    }

    static let available = WindowServerFeatureAvailability(unavailableReason: nil)
}

/// Pure. Availability of a feature that needs `missingSymbols` resolved and, when `requiresVerifiedVersion`, runs
/// only on a verified macOS major version.
func windowServerFeatureAvailability(
    feature: String,
    missingSymbols: [String],
    majorVersion: Int,
    requiresVerifiedVersion: Bool,
    verifiedMajorVersions: Set<Int> = windowServerSPIVerifiedMajorVersions
) -> WindowServerFeatureAvailability {
    if !missingSymbols.isEmpty {
        return WindowServerFeatureAvailability(
            unavailableReason: "missing private \(feature) symbols: \(missingSymbols.joined(separator: ", "))"
        )
    }
    if requiresVerifiedVersion, !verifiedMajorVersions.contains(majorVersion) {
        return WindowServerFeatureAvailability(
            unavailableReason: "the private \(feature) call has not been verified on macOS \(majorVersion)"
        )
    }
    return .available
}

/// Pure. The previous state the occlusion call wrote: `false` only when it explicitly wrote 0, `true` for 1, and nil
/// for the untouched sentinel or any other value.
func occlusionPreviousState(rawByte: UInt8) -> Bool? {
    switch rawByte {
    case 0:
        return false
    case 1:
        return true
    default:
        return nil
    }
}

/// Pure. Space ids from a `SLSCopySpacesForWindows` result, or nil when the result is not a non-empty list of numbers.
func windowSpaceIDs(fromCopyResult value: Any?) -> Set<UInt64>? {
    guard let list = value as? [Any] else {
        return nil
    }
    let ids = Set(list.compactMap { ($0 as? NSNumber)?.uint64Value })
    return ids.isEmpty ? nil : ids
}

/// Pure. The current Space id of every display in a `SLSCopyManagedDisplaySpaces` result, or nil when no display
/// names one.
func currentSpaceIDs(fromManagedDisplaySpaces value: Any?) -> Set<UInt64>? {
    guard let displays = value as? [Any] else {
        return nil
    }
    let ids = Set(displays.compactMap { display -> UInt64? in
        guard let display = display as? [String: Any],
              let current = display["Current Space"] as? [String: Any]
        else {
            return nil
        }
        return (current["id64"] as? NSNumber)?.uint64Value ?? (current["ManagedSpaceID"] as? NSNumber)?.uint64Value
    })
    return ids.isEmpty ? nil : ids
}

/// Pure. The first image of a hardware-capture result. Every value is type-checked first: the result comes from
/// private API and a wrong type must not crash the shared agent. The returned image is retained by Swift, so it
/// outlives the array.
func firstCapturedImage(fromCaptureResult value: AnyObject) -> CGImage? {
    guard CFGetTypeID(value) == CFArrayGetTypeID() else {
        return nil
    }
    let array = unsafeDowncast(value, to: CFArray.self)
    guard CFArrayGetCount(array) > 0, let element = CFArrayGetValueAtIndex(array, 0) else {
        return nil
    }
    let object = Unmanaged<AnyObject>.fromOpaque(element).takeUnretainedValue()
    guard CFGetTypeID(object) == CGImage.typeID else {
        return nil
    }
    let image = unsafeDowncast(object, to: CGImage.self)
    return image.width > 0 && image.height > 0 ? image : nil
}

/// Pure. A hardware capture is used only when its pixel size is the window's bounds times the backing scale, within
/// two pixels. Any other size (a shadow margin, a different scale) would shift the mapping from screenshot pixels to
/// screen points, so the caller falls back to ScreenCaptureKit. Non-finite inputs never match.
func hardwareCaptureSizeMatches(imageWidth: Int, imageHeight: Int, bounds: CGRect, scale: CGFloat) -> Bool {
    let expectedWidth = bounds.width * scale
    let expectedHeight = bounds.height * scale
    guard scale.isFinite, scale > 0, expectedWidth.isFinite, expectedHeight.isFinite,
          expectedWidth > 0, expectedHeight > 0
    else {
        return false
    }
    let tolerance: CGFloat = 2
    return abs(CGFloat(imageWidth) - expectedWidth) <= tolerance
        && abs(CGFloat(imageHeight) - expectedHeight) <= tolerance
}

/// The occlusion call `WindowOcclusionKeepAlive` makes. `SkyLightWindowServerSPI` is the only production conformer;
/// tests pass a fake so no real WindowServer state is written.
protocol WindowOcclusionControlling: AnyObject {
    var occlusionAvailability: WindowServerFeatureAvailability { get }

    /// Enables or disables WindowServer occlusion notifications for one window of another process and returns the
    /// previous state, nil when the call did not report it.
    func setWindowOcclusionNotificationsEnabled(_ enabled: Bool, windowID: CGWindowID) throws -> Bool?
}

/// Runtime-only bridge for the private SkyLight WindowServer calls behind the occlusion keep-alive, the Space check
/// and the hardware window capture. Kept apart from `SkyLightSPI` so a missing symbol here never disables
/// `sky_click` or `sky_key`. The declarations of the Space and capture calls follow the MIT-licensed yabai project;
/// the occlusion call's four-argument form was read from its function prologue on macOS 27.
final class SkyLightWindowServerSPI: WindowOcclusionControlling, @unchecked Sendable {
    static let shared = SkyLightWindowServerSPI()

    private static let frameworkPath = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
    private static let mainConnectionSymbol = "SLSMainConnectionID"
    private static let enableOcclusionNotificationsSymbol = "SLSPackagesEnableWindowOcclusionNotifications"
    private static let copySpacesForWindowsSymbol = "SLSCopySpacesForWindows"
    private static let copyManagedDisplaySpacesSymbol = "SLSCopyManagedDisplaySpaces"
    private static let hardwareCaptureWindowListSymbol = "SLSHWCaptureWindowList"
    /// Every Space a window belongs to: current, other and user Spaces.
    private static let allSpacesSelector: Int32 = 0x7
    /// Ignore the global clip shape, so a covered window is captured whole.
    private static let hardwareCaptureOptions: UInt32 = 0x800

    private typealias MainConnectionFunction = @convention(c) () -> UInt32
    // (cid, wid, enable, previousStateOut): the out pointer is optional and receives one byte.
    private typealias EnableOcclusionNotificationsFunction = @convention(c) (
        UInt32, CGWindowID, UInt8, UnsafeMutablePointer<UInt8>?
    ) -> Int32
    // The results follow the Copy rule (+1) and are typed as raw pointers so the CF type can be checked before use.
    private typealias CopySpacesForWindowsFunction = @convention(c) (UInt32, Int32, CFArray) -> UnsafeMutableRawPointer?
    private typealias CopyManagedDisplaySpacesFunction = @convention(c) (UInt32) -> UnsafeMutableRawPointer?
    // (cid, windowIDs, count, options), returning a +1 array of CGImage.
    private typealias HardwareCaptureWindowListFunction = @convention(c) (
        UInt32, UnsafePointer<CGWindowID>, Int32, UInt32
    ) -> UnsafeMutableRawPointer?

    private let mainConnectionFunction: MainConnectionFunction?
    private let enableOcclusionNotificationsFunction: EnableOcclusionNotificationsFunction?
    private let copySpacesForWindowsFunction: CopySpacesForWindowsFunction?
    private let copyManagedDisplaySpacesFunction: CopyManagedDisplaySpacesFunction?
    private let hardwareCaptureWindowListFunction: HardwareCaptureWindowListFunction?

    let occlusionAvailability: WindowServerFeatureAvailability
    let spacesAvailability: WindowServerFeatureAvailability
    let hardwareCaptureAvailability: WindowServerFeatureAvailability

    private init() {
        let handle = dlopen(Self.frameworkPath, RTLD_LAZY | RTLD_GLOBAL)
        mainConnectionFunction = Self.resolve(handle: handle, symbol: Self.mainConnectionSymbol)
        enableOcclusionNotificationsFunction = Self.resolve(handle: handle, symbol: Self.enableOcclusionNotificationsSymbol)
        copySpacesForWindowsFunction = Self.resolve(handle: handle, symbol: Self.copySpacesForWindowsSymbol)
        copyManagedDisplaySpacesFunction = Self.resolve(handle: handle, symbol: Self.copyManagedDisplaySpacesSymbol)
        hardwareCaptureWindowListFunction = Self.resolve(handle: handle, symbol: Self.hardwareCaptureWindowListSymbol)

        let majorVersion = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        let missingConnection = mainConnectionFunction == nil ? [Self.mainConnectionSymbol] : []
        occlusionAvailability = windowServerFeatureAvailability(
            feature: "occlusion",
            missingSymbols: missingConnection
                + (enableOcclusionNotificationsFunction == nil ? [Self.enableOcclusionNotificationsSymbol] : []),
            majorVersion: majorVersion,
            requiresVerifiedVersion: true
        )
        // Read-only Copy calls with type-checked results, in use by yabai across many macOS versions.
        spacesAvailability = windowServerFeatureAvailability(
            feature: "Space",
            missingSymbols: missingConnection
                + (copySpacesForWindowsFunction == nil ? [Self.copySpacesForWindowsSymbol] : [])
                + (copyManagedDisplaySpacesFunction == nil ? [Self.copyManagedDisplaySpacesSymbol] : []),
            majorVersion: majorVersion,
            requiresVerifiedVersion: false
        )
        hardwareCaptureAvailability = windowServerFeatureAvailability(
            feature: "window capture",
            missingSymbols: missingConnection
                + (hardwareCaptureWindowListFunction == nil ? [Self.hardwareCaptureWindowListSymbol] : []),
            majorVersion: majorVersion,
            requiresVerifiedVersion: true
        )
    }

    func setWindowOcclusionNotificationsEnabled(_ enabled: Bool, windowID: CGWindowID) throws -> Bool? {
        guard occlusionAvailability.isAvailable,
              let mainConnectionFunction,
              let enableOcclusionNotificationsFunction
        else {
            throw ComputerUseError.message(
                "occlusion keep-alive is unavailable: \(occlusionAvailability.unavailableReason ?? "unknown reason")"
            )
        }

        var previous = occlusionPreviousStateSentinel
        let status = enableOcclusionNotificationsFunction(mainConnectionFunction(), windowID, enabled ? 1 : 0, &previous)
        guard status == 0 else {
            throw ComputerUseError.message("\(Self.enableOcclusionNotificationsSymbol) failed (CGError \(status))")
        }
        return occlusionPreviousState(rawByte: previous)
    }

    /// The Spaces `windowID` belongs to, or nil when the call is unavailable or reports none.
    func spaceIDs(forWindow windowID: CGWindowID) -> Set<UInt64>? {
        guard spacesAvailability.isAvailable,
              let mainConnectionFunction,
              let copySpacesForWindowsFunction,
              let raw = copySpacesForWindowsFunction(
                  mainConnectionFunction(), Self.allSpacesSelector, [NSNumber(value: windowID)] as CFArray
              )
        else {
            return nil
        }
        return windowSpaceIDs(fromCopyResult: Self.checkedArray(Unmanaged<AnyObject>.fromOpaque(raw).takeRetainedValue()))
    }

    /// The current Space of every display, or nil when the call is unavailable or reports none.
    func currentSpaceIDs() -> Set<UInt64>? {
        guard spacesAvailability.isAvailable,
              let mainConnectionFunction,
              let copyManagedDisplaySpacesFunction,
              let raw = copyManagedDisplaySpacesFunction(mainConnectionFunction())
        else {
            return nil
        }
        return OpenComputerUseKit.currentSpaceIDs(
            fromManagedDisplaySpaces: Self.checkedArray(Unmanaged<AnyObject>.fromOpaque(raw).takeRetainedValue())
        )
    }

    /// True when the window is on the current Space of some display, false when it is not, and nil when either side
    /// cannot be read.
    func windowIsOnCurrentSpace(_ windowID: CGWindowID) -> Bool? {
        guard let windowSpaces = spaceIDs(forWindow: windowID), let current = currentSpaceIDs() else {
            return nil
        }
        return !windowSpaces.isDisjoint(with: current)
    }

    /// The window's backing store read by WindowServer, or nil when the call is unavailable or returned no image.
    /// Callers check permission, lock state, sharing state and image size first or after; see `WindowCapture`.
    func hardwareCaptureWindow(_ windowID: CGWindowID) -> CGImage? {
        guard hardwareCaptureAvailability.isAvailable,
              let mainConnectionFunction,
              let hardwareCaptureWindowListFunction
        else {
            return nil
        }
        var id = windowID
        guard let raw = hardwareCaptureWindowListFunction(mainConnectionFunction(), &id, 1, Self.hardwareCaptureOptions) else {
            return nil
        }
        // Released when `result` goes out of scope; the image was retained separately.
        let result = Unmanaged<AnyObject>.fromOpaque(raw).takeRetainedValue()
        return firstCapturedImage(fromCaptureResult: result)
    }

    /// The value as a Swift array when it is a CFArray, else nil.
    private static func checkedArray(_ value: AnyObject) -> [Any]? {
        guard CFGetTypeID(value) == CFArrayGetTypeID() else {
            return nil
        }
        return unsafeDowncast(value, to: CFArray.self) as? [Any]
    }

    private static func resolve<T>(handle: UnsafeMutableRawPointer?, symbol: String) -> T? {
        guard let handle, let pointer = dlsym(handle, symbol) else {
            return nil
        }
        return unsafeBitCast(pointer, to: T.self)
    }
}
