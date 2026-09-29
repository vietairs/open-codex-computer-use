import ApplicationServices
import XCTest
@testable import OpenComputerUseKit

/// Pins the batched attribute read: error sentinels never leak as values, routing prefers the prefetch, and the
/// prefetched attribute list stays exactly the set the tree walk reads for every node.
final class AXAttributePrefetchTests: XCTestCase {
    private func errorSentinel() -> CFTypeRef {
        var error = AXError.noValue
        return AXValueCreate(.axError, &error)!
    }

    func testNormalizeDropsErrorSentinelAndKeepsRealValue() {
        let normalized = AXAttributePrefetch.normalize(
            attributes: ["AXRole", "AXTitle"],
            rawValues: ["AXButton" as CFString, errorSentinel()]
        )
        XCTAssertEqual(Set(normalized.keys), ["AXRole"])
        XCTAssertEqual(normalized["AXRole"] as? String, "AXButton")
    }

    func testNormalizeDropsNullValues() {
        let normalized = AXAttributePrefetch.normalize(
            attributes: ["AXRole", "AXHelp"],
            rawValues: ["AXButton" as CFString, kCFNull]
        )
        XCTAssertEqual(Set(normalized.keys), ["AXRole"])
    }

    func testNormalizeReturnsEmptyWhenCountsDiffer() {
        let normalized = AXAttributePrefetch.normalize(attributes: ["a", "b"], rawValues: ["x" as CFString])
        XCTAssertTrue(normalized.isEmpty)
    }

    func testCoversRequestedAttributeEvenWhenValueAbsent() {
        let prefetch = AXAttributePrefetch(
            requested: ["AXRole", "AXTitle"],
            values: ["AXRole": "AXButton" as CFString]
        )
        XCTAssertTrue(prefetch.covers("AXTitle"))
        XCTAssertNil(prefetch.value("AXTitle"))
        XCTAssertFalse(prefetch.covers("AXHelp"))
        XCTAssertEqual(prefetch.value("AXRole") as? String, "AXButton")
    }

    func testPrefetchedOrLiveSkipsLiveForCoveredAttribute() {
        let prefetch = AXAttributePrefetch(requested: ["AXRole"], values: ["AXRole": "AXButton" as CFString])
        var liveCalls = 0
        let result = prefetchedOrLive(prefetch, "AXRole") {
            liveCalls += 1
            return "live" as CFString
        }
        XCTAssertEqual(result as? String, "AXButton")
        XCTAssertEqual(liveCalls, 0)
    }

    func testPrefetchedOrLiveDoesNotFallBackForCoveredButAbsentAttribute() {
        let prefetch = AXAttributePrefetch(requested: ["AXTitle"], values: [:])
        var liveCalls = 0
        let result = prefetchedOrLive(prefetch, "AXTitle") {
            liveCalls += 1
            return "live" as CFString
        }
        XCTAssertNil(result)
        XCTAssertEqual(liveCalls, 0)
    }

    func testPrefetchedOrLiveCallsLiveOnceForUncoveredAttribute() {
        let prefetch = AXAttributePrefetch(requested: ["AXRole"], values: ["AXRole": "AXButton" as CFString])
        var liveCalls = 0
        let result = prefetchedOrLive(prefetch, "AXHelp") {
            liveCalls += 1
            return "live" as CFString
        }
        XCTAssertEqual(result as? String, "live")
        XCTAssertEqual(liveCalls, 1)
    }

    func testPrefetchedOrLiveCallsLiveWhenPrefetchIsNil() {
        var liveCalls = 0
        let result = prefetchedOrLive(nil, "AXRole") {
            liveCalls += 1
            return "live" as CFString
        }
        XCTAssertEqual(result as? String, "live")
        XCTAssertEqual(liveCalls, 1)
    }

    func testRenderAttributesArePinnedInOrder() {
        XCTAssertEqual(
            AXAttributePrefetch.renderAttributes,
            [
                kAXRoleAttribute, kAXSubroleAttribute, kAXDescriptionAttribute, kAXHelpAttribute, kAXValueAttribute,
                kAXIdentifierAttribute, kAXSelectedAttribute, kAXExpandedAttribute, kAXEnabledAttribute,
                kAXPositionAttribute, kAXSizeAttribute, kAXFocusedAttribute,
            ]
        )
    }
}
