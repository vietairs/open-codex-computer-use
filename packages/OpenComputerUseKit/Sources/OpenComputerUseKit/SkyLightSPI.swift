import CoreGraphics
import Darwin
import Foundation

let skyClickMethodLabel = "click_method 'sky_click'"
let skyKeyMethodLabel = "key_method 'sky_key'"

struct SkyLightActivationCommand: Equatable {
    let psn: [UInt8]
    let windowID: CGWindowID
    let focused: Bool
}

struct SkyLightSyntheticFocusContext {
    let deactivateTarget: SkyLightActivationCommand
}

struct SkyLightSyntheticFocusPlan: Equatable {
    let activateTarget: SkyLightActivationCommand
    let deactivateTarget: SkyLightActivationCommand
}

func skyLightSyntheticTargetFocusPlan(
    targetPSN: [UInt8],
    targetWindowID: CGWindowID
) -> SkyLightSyntheticFocusPlan {
    SkyLightSyntheticFocusPlan(
        activateTarget: SkyLightActivationCommand(
            psn: targetPSN,
            windowID: targetWindowID,
            focused: true
        ),
        deactivateTarget: SkyLightActivationCommand(
            psn: targetPSN,
            windowID: targetWindowID,
            focused: false
        )
    )
}

func skyLightActivationRecord(windowID: CGWindowID, focused: Bool) -> [UInt8] {
    var record = [UInt8](repeating: 0, count: 0xF8)
    record[0x04] = 0xF8
    record[0x08] = 0x0D
    record[0x3C] = UInt8(truncatingIfNeeded: windowID)
    record[0x3D] = UInt8(truncatingIfNeeded: windowID >> 8)
    record[0x3E] = UInt8(truncatingIfNeeded: windowID >> 16)
    record[0x3F] = UInt8(truncatingIfNeeded: windowID >> 24)
    record[0x8A] = focused ? 0x01 : 0x02
    return record
}

/// yabai's `window_manager_make_key_window` record pair. Posted to the target PSN after the target-only activation
/// record, it makes AppKit inside the target treat `windowID` as its key window without a front-process switch or a
/// raise. Chromium's page focus follows the key window, so this is what turns received key events into inserted text.
func skyLightKeyWindowRecords(windowID: CGWindowID) -> [[UInt8]] {
    var record = [UInt8](repeating: 0, count: 0xF8)
    record[0x04] = 0xF8
    record[0x3A] = 0x10
    record[0x3C] = UInt8(truncatingIfNeeded: windowID)
    record[0x3D] = UInt8(truncatingIfNeeded: windowID >> 8)
    record[0x3E] = UInt8(truncatingIfNeeded: windowID >> 16)
    record[0x3F] = UInt8(truncatingIfNeeded: windowID >> 24)
    for index in 0x20..<0x30 {
        record[index] = 0xFF
    }
    return [UInt8(0x01), UInt8(0x02)].map { eventKind in
        var copy = record
        copy[0x08] = eventKind
        return copy
    }
}

struct SkyLightSPICapability: Equatable, Sendable {
    let missingSymbols: [String]
    var feature: String = "click"

    var isAvailable: Bool {
        missingSymbols.isEmpty
    }

    var unavailableReason: String {
        if missingSymbols.isEmpty {
            return "available"
        }

        return "missing private \(feature) symbols: \(missingSymbols.joined(separator: ", "))"
    }
}

/// Runtime-only bridge for the private SkyLight functions used by `sky_click`
/// and `sky_key`.
///
/// The declarations, event-field recipe and key-window records are derived
/// from the MIT-licensed Cua Driver and yabai implementations. Keep all
/// undocumented ABI in this file so a future macOS compatibility change has
/// one review boundary.
final class SkyLightSPI: @unchecked Sendable {
    static let shared = SkyLightSPI()

    /// Held for every begin...end synthetic-focus sequence, whichever method runs it. Each host connection of the
    /// shared app agent runs its calls concurrently, and two sequences that interleave would release each other's
    /// target or make the wrong window key, so `sky_click` and `sky_key` take this one lock and never a lock of
    /// their own.
    static let syntheticFocusLock = NSLock()

    private static let frameworkPath = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
    private static let postToPidSymbol = "SLEventPostToPid"
    private static let setIntegerFieldSymbol = "SLEventSetIntegerValueField"
    private static let setWindowLocationSymbol = "CGEventSetWindowLocation"
    private static let postEventRecordSymbol = "SLPSPostEventRecordTo"
    private static let getProcessForPIDSymbol = "GetProcessForPID"
    private static let applicationServicesPath = "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices"

    private typealias PostToPidFunction = @convention(c) (pid_t, UnsafeMutableRawPointer?) -> Void
    private typealias SetIntegerFieldFunction = @convention(c) (UnsafeMutableRawPointer?, UInt32, Int64) -> Void
    // Cua's current Rust bridge models this private ABI as
    // (CGEventRef, double x, double y). Keeping the scalar form here avoids
    // relying on Swift's aggregate CGPoint calling convention.
    private typealias SetWindowLocationFunction = @convention(c) (UnsafeMutableRawPointer?, Double, Double) -> Void
    private typealias PostEventRecordFunction = @convention(c) (UnsafeRawPointer?, UnsafePointer<UInt8>?) -> Int32
    private typealias GetProcessForPIDFunction = @convention(c) (pid_t, UnsafeMutableRawPointer?) -> Int32

    private let frameworkHandle: UnsafeMutableRawPointer?
    private let applicationServicesHandle: UnsafeMutableRawPointer?
    private let postToPidFunction: PostToPidFunction?
    private let setIntegerFieldFunction: SetIntegerFieldFunction?
    private let setWindowLocationFunction: SetWindowLocationFunction?
    private let postEventRecordFunction: PostEventRecordFunction?
    private let getProcessForPIDFunction: GetProcessForPIDFunction?

    let capability: SkyLightSPICapability

    /// The same symbol check as `capability`, worded for `sky_key`, so its unavailable error is about the keyboard
    /// path rather than clicks.
    var keyboardCapability: SkyLightSPICapability {
        SkyLightSPICapability(missingSymbols: capability.missingSymbols, feature: "keyboard")
    }

    private init() {
        let handle = dlopen(Self.frameworkPath, RTLD_LAZY | RTLD_GLOBAL)
        let appServicesHandle = dlopen(Self.applicationServicesPath, RTLD_LAZY | RTLD_GLOBAL)
        frameworkHandle = handle
        applicationServicesHandle = appServicesHandle
        postToPidFunction = Self.resolve(handle: handle, symbol: Self.postToPidSymbol)
        setIntegerFieldFunction = Self.resolve(handle: handle, symbol: Self.setIntegerFieldSymbol)
        setWindowLocationFunction = Self.resolve(handle: handle, symbol: Self.setWindowLocationSymbol)
        postEventRecordFunction = Self.resolve(handle: handle, symbol: Self.postEventRecordSymbol)
        getProcessForPIDFunction = Self.resolve(handle: appServicesHandle, symbol: Self.getProcessForPIDSymbol)

        var missingSymbols: [String] = []
        if postToPidFunction == nil {
            missingSymbols.append(Self.postToPidSymbol)
        }
        if setIntegerFieldFunction == nil {
            missingSymbols.append(Self.setIntegerFieldSymbol)
        }
        if setWindowLocationFunction == nil {
            missingSymbols.append(Self.setWindowLocationSymbol)
        }
        if postEventRecordFunction == nil {
            missingSymbols.append(Self.postEventRecordSymbol)
        }
        if getProcessForPIDFunction == nil {
            missingSymbols.append(Self.getProcessForPIDSymbol)
        }
        capability = SkyLightSPICapability(missingSymbols: missingSymbols)
    }

    func postToPid(_ event: CGEvent, pid: pid_t) throws {
        guard let postToPidFunction else {
            throw unavailableError(methodLabel: skyClickMethodLabel)
        }

        postToPidFunction(pid, opaquePointer(for: event))
    }

    func setIntegerField(_ event: CGEvent, field: UInt32, value: Int64) throws {
        guard let setIntegerFieldFunction else {
            throw unavailableError(methodLabel: skyClickMethodLabel)
        }

        setIntegerFieldFunction(opaquePointer(for: event), field, value)
    }

    func setWindowLocation(_ event: CGEvent, point: CGPoint) throws {
        guard let setWindowLocationFunction else {
            throw unavailableError(methodLabel: skyClickMethodLabel)
        }

        setWindowLocationFunction(opaquePointer(for: event), point.x, point.y)
    }

    /// `methodLabel` names the tool option in error text, for example `click_method 'sky_click'`.
    func beginSyntheticTargetFocus(
        targetPID: pid_t,
        targetWindowID: CGWindowID,
        methodLabel: String = skyClickMethodLabel
    ) throws -> SkyLightSyntheticFocusContext {
        guard let getProcessForPIDFunction else {
            throw unavailableError(methodLabel: methodLabel)
        }

        var targetPSN = [UInt8](repeating: 0, count: 8)
        let targetStatus = targetPSN.withUnsafeMutableBytes { bytes in
            getProcessForPIDFunction(targetPID, bytes.baseAddress)
        }
        guard targetStatus == 0 else {
            throw ComputerUseError.message(
                "\(methodLabel) could not resolve target PID \(targetPID) to a PSN (OSStatus \(targetStatus))"
            )
        }

        let plan = skyLightSyntheticTargetFocusPlan(
            targetPSN: targetPSN,
            targetWindowID: targetWindowID
        )
        try postActivationCommand(plan.activateTarget, methodLabel: methodLabel)
        Thread.sleep(forTimeInterval: 0.040)

        return SkyLightSyntheticFocusContext(
            deactivateTarget: plan.deactivateTarget
        )
    }

    /// Makes the target window key inside the target app while it is synthetic-active. Must follow
    /// `beginSyntheticTargetFocus`: posted the other way round, the records are ignored. `endSyntheticTargetFocus`
    /// releases the key state again.
    func makeSyntheticTargetWindowKey(_ context: SkyLightSyntheticFocusContext) throws {
        guard let postEventRecordFunction else {
            throw unavailableError(methodLabel: skyKeyMethodLabel)
        }

        let command = context.deactivateTarget
        for record in skyLightKeyWindowRecords(windowID: command.windowID) {
            let status = command.psn.withUnsafeBytes { psnBytes in
                record.withUnsafeBufferPointer { recordBytes in
                    postEventRecordFunction(psnBytes.baseAddress, recordBytes.baseAddress)
                }
            }
            guard status == 0 else {
                throw ComputerUseError.message(
                    "\(skyKeyMethodLabel) synthetic key-window event failed (OSStatus \(status))"
                )
            }
        }
    }

    func endSyntheticTargetFocus(
        _ context: SkyLightSyntheticFocusContext,
        methodLabel: String = skyClickMethodLabel
    ) throws {
        try postActivationCommand(context.deactivateTarget, methodLabel: methodLabel)
        Thread.sleep(forTimeInterval: 0.040)
    }

    private func unavailableError(methodLabel: String) -> ComputerUseError {
        let reason = methodLabel == skyKeyMethodLabel ? keyboardCapability.unavailableReason : capability.unavailableReason
        return ComputerUseError.message("\(methodLabel) is unavailable: \(reason)")
    }

    private func opaquePointer(for event: CGEvent) -> UnsafeMutableRawPointer {
        Unmanaged.passUnretained(event).toOpaque()
    }

    private func postActivationCommand(_ command: SkyLightActivationCommand, methodLabel: String) throws {
        guard let postEventRecordFunction else {
            throw unavailableError(methodLabel: methodLabel)
        }

        let record = skyLightActivationRecord(
            windowID: command.windowID,
            focused: command.focused
        )
        let status = command.psn.withUnsafeBytes { psnBytes in
            record.withUnsafeBufferPointer { recordBytes in
                postEventRecordFunction(psnBytes.baseAddress, recordBytes.baseAddress)
            }
        }
        guard status == 0 else {
            throw ComputerUseError.message(
                "\(methodLabel) synthetic target-focus event failed (OSStatus \(status))"
            )
        }
    }

    private static func resolve<T>(handle: UnsafeMutableRawPointer?, symbol: String) -> T? {
        guard let handle, let pointer = dlsym(handle, symbol) else {
            return nil
        }

        return unsafeBitCast(pointer, to: T.self)
    }
}

/// The synthetic-focus calls `SkyKeyboardDispatcher` makes. `SkyLightSPI` is the only production conformer; the
/// protocol exists so the begin, make-key and end order, and the release of the target on every error path, can be
/// unit tested without posting real records.
protocol SyntheticFocusControlling {
    var keyboardCapability: SkyLightSPICapability { get }

    func beginSyntheticTargetFocus(
        targetPID: pid_t,
        targetWindowID: CGWindowID,
        methodLabel: String
    ) throws -> SkyLightSyntheticFocusContext

    func makeSyntheticTargetWindowKey(_ context: SkyLightSyntheticFocusContext) throws

    func endSyntheticTargetFocus(_ context: SkyLightSyntheticFocusContext, methodLabel: String) throws
}

extension SkyLightSPI: SyntheticFocusControlling {}
