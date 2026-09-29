import XCTest
@testable import OpenComputerUseKit

/// Pins type_text delivery: a settable text field gets an accessibility write, a non-settable text control gets keys
/// posted to the process, and anything else, including a settable non-text control, fails closed. The only side effects are the two injected closures, so
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

    // MARK: - Production focus classification

    /// A focused control with a settable value that is not text entry (slider, list, stepper) is refused before any
    /// value write or keystroke, whether or not the write would have been accepted.
    func testSettableNonTextControlIsRefusedWithoutWriteOrKeys() {
        let controls: [(role: String, description: String)] = [
            ("AXSlider", "slider"),
            ("AXList", "list"),
            ("AXIncrementor", "stepper"),
        ]
        for control in controls {
            let focus = makeTypeTextFocus(
                role: control.role,
                subrole: nil,
                roleDescription: control.description,
                isValueSettable: true
            )
            XCTAssertEqual(typeTextRoute(focus: focus), .refuse, control.role)
            for setValueSucceeds in [true, false] {
                let recorder = Recorder()
                XCTAssertThrowsError(
                    try deliver(focus, setValueSucceeds: setValueSucceeds, recorder: recorder),
                    control.role
                ) { error in
                    let message = (error as? LocalizedError)?.errorDescription ?? ""
                    XCTAssertTrue(message.contains("no focused text field in Mail"), message)
                }
                XCTAssertEqual(recorder.setValueCalls, 0, control.role)
                XCTAssertEqual(recorder.postKeysCalls, 0, control.role)
            }
        }
    }

    func testSettableTextFieldWritesValueThenFallsBackToKeys() throws {
        let focus = makeTypeTextFocus(
            role: "AXTextField",
            subrole: "AXSearchField",
            roleDescription: "search text field",
            isValueSettable: true
        )
        let written = Recorder()
        XCTAssertEqual(try deliver(focus, recorder: written), .setFocusedValue)
        XCTAssertEqual(written.setValueCalls, 1)
        XCTAssertEqual(written.postKeysCalls, 0)

        let refused = Recorder()
        XCTAssertEqual(try deliver(focus, setValueSucceeds: false, recorder: refused), .postKeysToProcess)
        XCTAssertEqual(refused.setValueCalls, 1)
        XCTAssertEqual(refused.postKeysCalls, 1)
    }

    func testNonSettableWebTextEntryPostsKeys() throws {
        let focus = makeTypeTextFocus(
            role: "AXGroup",
            subrole: nil,
            roleDescription: "text entry area",
            isValueSettable: false
        )
        let recorder = Recorder()
        XCTAssertEqual(try deliver(focus, recorder: recorder), .postKeysToProcess)
        XCTAssertEqual(recorder.setValueCalls, 0)
        XCTAssertEqual(recorder.postKeysCalls, 1)
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
