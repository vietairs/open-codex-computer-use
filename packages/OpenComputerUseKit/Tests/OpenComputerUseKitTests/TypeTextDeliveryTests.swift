import XCTest
@testable import OpenComputerUseKit

/// Pins type_text delivery: a settable field gets an accessibility write, a non-settable text control gets keys
/// posted to the process, and anything else fails closed. The only side effects are the two injected closures, so
/// no route can activate the target app.
final class TypeTextDeliveryTests: XCTestCase {
    private let settableField = TypeTextFocus(isValueSettable: true, acceptsKeyboardText: true)
    private let keyboardOnlyField = TypeTextFocus(isValueSettable: false, acceptsKeyboardText: true)
    private let messageList = TypeTextFocus(isValueSettable: false, acceptsKeyboardText: false)

    private final class Recorder {
        var setValueCalls = 0
        var postKeysCalls = 0
    }

    private func deliver(
        _ focus: TypeTextFocus?,
        setValueSucceeds: Bool = true,
        recorder: Recorder
    ) throws -> TypeTextRoute {
        try deliverTypedText(
            focus: focus,
            appName: "Mail",
            setValue: {
                recorder.setValueCalls += 1
                return setValueSucceeds
            },
            postKeys: { recorder.postKeysCalls += 1 }
        )
    }

    // MARK: - Route decision

    func testRouteForSettableFocusIsAccessibilityWrite() {
        XCTAssertEqual(typeTextRoute(focus: settableField), .setFocusedValue)
    }

    func testRouteForNonSettableTextFocusIsProcessKeys() {
        XCTAssertEqual(typeTextRoute(focus: keyboardOnlyField), .postKeysToProcess)
    }

    func testRouteWithoutConfirmedFocusRefuses() {
        XCTAssertEqual(typeTextRoute(focus: nil), .refuse)
    }

    func testRouteForNonTextFocusRefuses() {
        XCTAssertEqual(typeTextRoute(focus: messageList), .refuse)
    }

    // MARK: - Delivery

    func testSettableFocusWritesValueAndPostsNoKeys() throws {
        let recorder = Recorder()
        XCTAssertEqual(try deliver(settableField, recorder: recorder), .setFocusedValue)
        XCTAssertEqual(recorder.setValueCalls, 1)
        XCTAssertEqual(recorder.postKeysCalls, 0)
    }

    func testRefusedValueWriteOnTextControlFallsBackToProcessKeys() throws {
        let recorder = Recorder()
        XCTAssertEqual(try deliver(settableField, setValueSucceeds: false, recorder: recorder), .postKeysToProcess)
        XCTAssertEqual(recorder.setValueCalls, 1)
        XCTAssertEqual(recorder.postKeysCalls, 1)
    }

    func testRefusedValueWriteOnNonTextElementFailsClosed() {
        let recorder = Recorder()
        let settableNonText = TypeTextFocus(isValueSettable: true, acceptsKeyboardText: false)
        XCTAssertThrowsError(try deliver(settableNonText, setValueSucceeds: false, recorder: recorder))
        XCTAssertEqual(recorder.postKeysCalls, 0)
    }

    func testNonSettableTextFocusPostsKeysOnly() throws {
        let recorder = Recorder()
        XCTAssertEqual(try deliver(keyboardOnlyField, recorder: recorder), .postKeysToProcess)
        XCTAssertEqual(recorder.setValueCalls, 0)
        XCTAssertEqual(recorder.postKeysCalls, 1)
    }

    func testNoConfirmedFocusThrowsAndDeliversNothing() {
        let recorder = Recorder()
        XCTAssertThrowsError(try deliver(nil, recorder: recorder)) { error in
            let message = (error as? LocalizedError)?.errorDescription ?? ""
            XCTAssertTrue(message.contains("no focused text field in Mail"), message)
            XCTAssertTrue(message.contains("set_value"), message)
            XCTAssertTrue(message.contains("without bringing the app to the front"), message)
        }
        XCTAssertEqual(recorder.setValueCalls, 0)
        XCTAssertEqual(recorder.postKeysCalls, 0)
    }

    func testNonTextFocusThrowsAndDeliversNothing() {
        let recorder = Recorder()
        XCTAssertThrowsError(try deliver(messageList, recorder: recorder))
        XCTAssertEqual(recorder.setValueCalls, 0)
        XCTAssertEqual(recorder.postKeysCalls, 0)
    }

    func testPostKeysErrorPropagates() {
        struct PostFailed: Error {}
        XCTAssertThrowsError(
            try deliverTypedText(
                focus: keyboardOnlyField,
                appName: "Mail",
                setValue: { true },
                postKeys: { throw PostFailed() }
            )
        ) { error in
            XCTAssertTrue(error is PostFailed)
        }
    }
}
