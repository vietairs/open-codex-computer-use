import Foundation
import XCTest
@testable import OpenComputerUseKit

private struct KeyMethodTestUnlockedSessionProvider: MacSessionStateProvider {
    func currentSnapshot() -> MacSessionSnapshot {
        MacSessionSnapshot(isLocked: false, isUnknown: false, rawKeysSeen: ["CGSSessionScreenIsLocked"])
    }
}

/// `key_method` on `type_text` and `press_key`: parsing, schema, the sky_key target rules and the release warning.
final class KeyMethodTests: XCTestCase {
    private func makeDispatcher() -> ComputerUseToolDispatcher {
        ComputerUseToolDispatcher(guard: MacSessionGuard(provider: KeyMethodTestUnlockedSessionProvider()))
    }

    // MARK: - Parsing

    func testKeyMethodDefaultsToAutoAndNormalizesExplicitValues() throws {
        XCTAssertEqual(try parseKeyMethod(nil), .auto)
        XCTAssertEqual(try parseKeyMethod(" AUTO "), .auto)
        XCTAssertEqual(try parseKeyMethod(" SKY_KEY "), .skyKey)
    }

    func testKeyMethodRejectsUnknownValuesListingTheAllowedOnes() {
        for value in ["global", "sky_click", ""] {
            XCTAssertThrowsError(try parseKeyMethod(value)) { error in
                XCTAssertEqual(
                    (error as? ComputerUseError)?.errorDescription,
                    "Invalid key_method '\(value)'. Expected one of: auto, sky_key"
                )
            }
        }
    }

    func testDispatcherRefusesANonStringKeyMethodInsteadOfFallingBackToAuto() {
        let dispatcher = makeDispatcher()
        for (tool, extra) in [("type_text", ["text": "x"]), ("press_key", ["key": "a"])] {
            for value: Any in [1, true, ["sky_key"]] {
                var arguments: [String: Any] = ["app": "NoSuchApp-key-method-test", "key_method": value]
                arguments.merge(extra) { _, new in new }
                let result = dispatcher.callToolAsResult(name: tool, arguments: arguments)
                XCTAssertTrue(result.isError, "\(tool) \(value)")
                XCTAssertTrue((result.primaryText ?? "").contains("key_method must be a string"), result.primaryText ?? "")
            }

            var arguments: [String: Any] = ["app": "NoSuchApp-key-method-test", "key_method": "fast"]
            arguments.merge(extra) { _, new in new }
            let result = dispatcher.callToolAsResult(name: tool, arguments: arguments)
            XCTAssertTrue(result.isError)
            XCTAssertTrue((result.primaryText ?? "").contains("Invalid key_method 'fast'"), result.primaryText ?? "")
        }
    }

    func testBatchStepsCarryTheirKeyMethodAndRejectBadValues() throws {
        let dispatcher = makeDispatcher()
        let steps = try dispatcher.parseBatchSteps([
            ["tool": "type_text", "args": ["text": "hello", "key_method": "sky_key"]],
            ["tool": "press_key", "args": ["key": "Return", "key_method": "SKY_KEY"]],
            ["tool": "press_key", "args": ["key": "Tab"]],
        ])
        XCTAssertEqual(steps, [
            .typeText(text: "hello", keyMethod: .skyKey),
            .pressKey(key: "Return", keyMethod: .skyKey),
            .pressKey(key: "Tab", keyMethod: .auto),
        ])
        XCTAssertEqual(steps.map(\.keyMethod), [.skyKey, .skyKey, .auto])

        for value: Any in [1, "fast"] {
            XCTAssertThrowsError(
                try dispatcher.parseBatchSteps([["tool": "type_text", "args": ["text": "x", "key_method": value]]])
            ) { error in
                guard case let .invalidArguments(message)? = error as? ComputerUseError else {
                    return XCTFail("\(error)")
                }
                XCTAssertTrue(message.hasPrefix("step 1: "), message)
                XCTAssertTrue(message.contains("key_method"), message)
            }
        }
    }

    func testOnlySkyKeyUsesReadOnlyActionSnapshotRefresh() {
        XCTAssertEqual(keyActionSnapshotRecoveryPolicy(for: .skyKey), .readOnly)
        XCTAssertEqual(keyActionSnapshotRecoveryPolicy(for: .auto), .allowActivation)
    }

    // MARK: - Schema

    func testKeyboardToolSchemasExposeKeyMethod() throws {
        for name in ["type_text", "press_key"] {
            let tool = try XCTUnwrap(ToolDefinitions.all.first { $0.name == name })
            let properties = try XCTUnwrap(tool.inputSchema["properties"] as? [String: Any])
            let keyMethod = try XCTUnwrap(properties["key_method"] as? [String: Any], name)
            XCTAssertEqual(keyMethod["enum"] as? [String], ["auto", "sky_key"], name)
            XCTAssertEqual(tool.inputSchema["required"] as? [String], ["app", name == "type_text" ? "text" : "key"])

            let description = try XCTUnwrap(keyMethod["description"] as? String)
            XCTAssertLessThanOrEqual(description.count, 240, description)
            XCTAssertTrue(description.contains("never falls back"), description)
            XCTAssertFalse(description.lowercased().contains("authenticated"), description)
        }
    }

    // MARK: - Target and release warning

    func testSkyKeyTargetNeedsAWindowAndRefusesOffStageWindows() throws {
        XCTAssertEqual(
            try skyKeyTarget(windowID: 42, isOffStage: false, pid: 7),
            SkyKeyboardTarget(windowID: 42, pid: 7)
        )

        XCTAssertThrowsError(try skyKeyTarget(windowID: nil, isOffStage: false, pid: 7)) { error in
            guard case let .stateUnavailable(message)? = error as? ComputerUseError else {
                return XCTFail("\(error)")
            }
            XCTAssertTrue(message.contains("get_app_state"), message)
        }

        XCTAssertThrowsError(try skyKeyTarget(windowID: 42, isOffStage: true, pid: 7)) { error in
            guard case let .stateUnavailable(message)? = error as? ComputerUseError else {
                return XCTFail("\(error)")
            }
            XCTAssertTrue(message.contains("off-stage"), message)
        }
    }

    func testFixtureAppsOnlyAcceptAutoKeyMethod() {
        XCTAssertNoThrow(try requireAutoKeyMethodForFixture(.auto))
        XCTAssertThrowsError(try requireAutoKeyMethodForFixture(.skyKey)) { error in
            XCTAssertEqual(
                (error as? ComputerUseError)?.errorDescription,
                "key_method 'sky_key' is not supported for fixture apps"
            )
        }
    }

    func testReleaseWarningIsAddedAsSuccessBeforeTheImage() {
        let image = ToolResultContentItem.pngImage(Data([0x89, 0x50]))
        let result = ToolCallResult(content: [.text("state"), image])

        let unchanged = appendingSkyKeyReleaseWarning(to: result, delivery: SkyKeyboardDelivery(releaseWarning: nil))
        XCTAssertEqual(unchanged.content.count, 2)

        let warned = appendingSkyKeyReleaseWarning(
            to: result, delivery: SkyKeyboardDelivery(releaseWarning: "OSStatus -600")
        )
        XCTAssertFalse(warned.isError, "the keys were delivered, so the action must not read as failed")
        XCTAssertEqual(warned.content.map { $0.dictionary["type"] as? String }, ["text", "text", "image"])
        let note = warned.content[1].dictionary["text"] as? String ?? ""
        XCTAssertTrue(note.contains("delivered the keys"), note)
        XCTAssertTrue(note.contains("Do not send the keys again"), note)
    }
}
