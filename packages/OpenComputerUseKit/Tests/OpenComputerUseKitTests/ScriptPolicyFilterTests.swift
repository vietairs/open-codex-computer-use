import Foundation
import XCTest
@testable import OpenComputerUseKit

/// Pins the best-effort script deny list: what it rejects across spelling variants, and what plain app queries it
/// still allows. The filter is friction, not a security boundary.
final class ScriptPolicyFilterTests: XCTestCase {

    private struct Case {
        let source: String
        let language: ScriptLanguage
    }

    private func apple(_ source: String) -> Case { Case(source: source, language: .applescript) }
    private func js(_ source: String) -> Case { Case(source: source, language: .javascript) }

    func testFilterRejectsEveryDeniedForm() {
        let cases: [Case] = [
            apple("do shell script \"id\""),
            apple("DO   SHELL\tSCRIPT \"id\""),
            apple("do shell ¬\nscript \"id\""),
            apple("do shell ¬\r\nscript \"id\""),
            apple("run script \"x\""),
            apple("load script file \"x\""),
            apple("store script s in \"x\""),
            apple("tell application \"Terminal\" to do script \"id\""),
            apple("«event sysoexec» \"id\""),
            apple("<<event sysoexec>> \"id\""),
            apple("use framework \"Foundation\""),
            apple("use scripting additions"),
            apple("use script \"Lib\""),
            js("app.doShellScript(\"id\")"),
            js("app.runScript(\"x\")"),
            js("ObjC.import(\"stdlib\")"),
            js("Library(\"x\")"),
            js("$.NSTask.alloc"),
            js("Application(\"Terminal\").doScript(\"id\")"),
            js("app.loadScript(\"x\")"),
            // Union rule: the AppleScript verb is refused under the JavaScript language too.
            js("do shell script \"id\""),
            // Unicode and comment spellings.
            apple("do\u{00A0}shell\u{00A0}script \"id\""),
            apple("do shell\u{2028}script \"id\""),
            apple("ｄｏ ｓｈｅｌｌ ｓｃｒｉｐｔ \"id\""),
            apple("do (* x *) shell script \"id\""),
            apple("do (* a *) shell (* b *) script \"id\""),
            apple("« event sysoexec » \"id\""),
            apple("<< event sysoexec >> \"id\""),
            apple("do shell ¬   \nscript \"id\""),
        ]
        XCTAssertEqual(cases.count, 29)
        for entry in cases {
            let verdict = ScriptPolicyFilter.evaluate(source: entry.source, language: entry.language)
            if case .rejected = verdict { continue }
            XCTFail("expected rejection for \(entry.source.debugDescription) (\(entry.language)), got \(verdict)")
        }
    }

    func testCommentMarkerInsideStringCannotHideDeniedPhrase() {
        let source = "set x to \"(*\" & (do shell script \"id\") & \"*)\""
        let verdict = ScriptPolicyFilter.evaluate(source: source, language: .applescript)
        guard case .rejected = verdict else {
            return XCTFail("a comment marker inside a string literal must not hide a denied phrase; got \(verdict)")
        }
    }

    func testFilterAllowsPlainMailSearch() {
        XCTAssertEqual(
            ScriptPolicyFilter.evaluate(
                source: "tell application \"Mail\" to get subject of (messages of inbox whose subject contains \"combio\")",
                language: .applescript
            ),
            .allowed
        )
        XCTAssertEqual(
            ScriptPolicyFilter.evaluate(
                source: "Application(\"Mail\").inbox.messages.whose({subject: {_contains: \"combio\"}})().map(m => m.subject())",
                language: .javascript
            ),
            .allowed
        )
        XCTAssertEqual(
            ScriptPolicyFilter.evaluate(source: "return 1 + 1", language: .applescript),
            .allowed
        )
    }

    func testNormalizeJoinsContinuationAndCollapsesWhitespace() {
        XCTAssertEqual(ScriptPolicyFilter.normalize("Do Shell ¬\r\n   Script"), "do shell script")
    }

    /// Documented false positive, pinned on purpose: the filter matches text, not syntax.
    func testFilterRejectsDeniedPhraseInsideStringLiteral() {
        let source = "tell application \"Mail\" to get subject of (messages of inbox whose subject contains \"do script\")"
        guard case .rejected = ScriptPolicyFilter.evaluate(source: source, language: .applescript) else {
            return XCTFail("a denied phrase inside a string literal is rejected by design")
        }
    }
}
