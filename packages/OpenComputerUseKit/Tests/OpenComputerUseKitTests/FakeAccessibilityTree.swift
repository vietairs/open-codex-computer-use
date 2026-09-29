import ApplicationServices
import Foundation
@testable import OpenComputerUseKit

/// An in-memory accessibility tree served through `AccessibilityReadBackend`, so the real tree walk can run without
/// Accessibility permission. Each node is an application element for a fake pid (never a real process); its pid is
/// the node key. Every call is counted per node, so tests can pin how many round trips a walk makes.
final class FakeAccessibilityTree: @unchecked Sendable {
    enum Call: Hashable {
        case single(String)
        case multiple
        case actions
        case settable(String)
    }

    private let lock = NSLock()
    private var nextPID: pid_t = 70_000
    private var attributes: [pid_t: [String: CFTypeRef]] = [:]
    private var actionNames: [pid_t: [String]] = [:]
    private var settableAttributes: [pid_t: Set<String>] = [:]
    private var calls: [pid_t: [Call: Int]] = [:]

    /// When false, the multi-attribute call fails as a whole, so every read falls back to single reads.
    var supportsMultipleAttributeReads = true

    @discardableResult
    func node(
        _ role: String,
        _ values: [String: Any] = [:],
        frame: CGRect? = nil,
        children: [AXUIElement] = [],
        actions: [String] = [],
        settable: Set<String> = []
    ) -> AXUIElement {
        lock.lock()
        defer { lock.unlock() }

        let pid = nextPID
        nextPID += 1
        var stored: [String: CFTypeRef] = [kAXRoleAttribute: role as CFString]
        for (attribute, value) in values {
            stored[attribute] = Self.cfValue(value)
        }
        if !children.isEmpty, stored[kAXChildrenAttribute] == nil {
            stored[kAXChildrenAttribute] = children as CFArray
        }
        if let frame {
            var origin = frame.origin
            var size = frame.size
            stored[kAXPositionAttribute] = AXValueCreate(.cgPoint, &origin)
            stored[kAXSizeAttribute] = AXValueCreate(.cgSize, &size)
        }
        attributes[pid] = stored
        actionNames[pid] = actions
        settableAttributes[pid] = settable
        return AXUIElementCreateApplication(pid)
    }

    func setValue(_ value: Any, attribute: String, of element: AXUIElement) {
        lock.lock()
        defer { lock.unlock() }
        attributes[Self.pid(of: element), default: [:]][attribute] = Self.cfValue(value)
    }

    func callCount(_ call: Call, on element: AXUIElement) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return calls[Self.pid(of: element)]?[call] ?? 0
    }

    func calls(on element: AXUIElement) -> [Call: Int] {
        lock.lock()
        defer { lock.unlock() }
        return calls[Self.pid(of: element)] ?? [:]
    }

    func totalCalls(on element: AXUIElement) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return calls[Self.pid(of: element)]?.values.reduce(0, +) ?? 0
    }

    /// Every round trip made, one per AX API call.
    var totalRoundTrips: Int {
        lock.lock()
        defer { lock.unlock() }
        return calls.values.flatMap(\.values).reduce(0, +)
    }

    func resetCounts() {
        lock.lock()
        defer { lock.unlock() }
        calls = [:]
    }

    var backend: AccessibilityReadBackend {
        AccessibilityReadBackend(
            copyAttributeValue: { [self] element, attribute in
                record(.single(attribute), on: element)
                guard let value = value(attribute, of: element) else {
                    return (.noValue, nil)
                }
                return (.success, value)
            },
            copyMultipleAttributeValues: { [self] element, requested in
                record(.multiple, on: element)
                guard supportsMultipleAttributeReads else {
                    return (.failure, nil)
                }
                let values: [CFTypeRef] = requested.map { attribute in
                    value(attribute, of: element) ?? Self.errorSentinel()
                }
                return (.success, values as CFArray)
            },
            copyActionNames: { [self] element in
                record(.actions, on: element)
                lock.lock()
                defer { lock.unlock() }
                return (.success, (actionNames[Self.pid(of: element)] ?? []) as CFArray)
            },
            isAttributeSettable: { [self] element, attribute in
                record(.settable(attribute), on: element)
                lock.lock()
                defer { lock.unlock() }
                return (.success, settableAttributes[Self.pid(of: element)]?.contains(attribute) ?? false)
            }
        )
    }

    /// Runs `body` with this tree as the accessibility backend.
    func serving<T>(_ body: () throws -> T) rethrows -> T {
        try AccessibilityReads.$backend.withValue(backend, operation: body)
    }

    private func value(_ attribute: String, of element: AXUIElement) -> CFTypeRef? {
        lock.lock()
        defer { lock.unlock() }
        return attributes[Self.pid(of: element)]?[attribute]
    }

    private func record(_ call: Call, on element: AXUIElement) {
        lock.lock()
        defer { lock.unlock() }
        calls[Self.pid(of: element), default: [:]][call, default: 0] += 1
    }

    private static func pid(of element: AXUIElement) -> pid_t {
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        return pid
    }

    private static func errorSentinel() -> CFTypeRef {
        var error = AXError.noValue
        return AXValueCreate(.axError, &error)!
    }

    private static func cfValue(_ value: Any) -> CFTypeRef {
        switch value {
        case let string as String:
            return string as CFString
        case let bool as Bool:
            return (bool ? kCFBooleanTrue : kCFBooleanFalse)!
        case let number as NSNumber:
            return number
        case let elements as [AXUIElement]:
            return elements as CFArray
        case let url as URL:
            return url as CFURL
        default:
            return value as AnyObject
        }
    }
}
