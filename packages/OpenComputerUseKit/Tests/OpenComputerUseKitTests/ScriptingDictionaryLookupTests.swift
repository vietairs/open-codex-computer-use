import AppKit
import Foundation
import XCTest
@testable import OpenComputerUseKit

/// Builds fake `.app` bundles inside a private temporary directory and reads their scripting definitions through the
/// static lookup. No test launches an app, sends an Apple Event or calls the scripting-definition APIs of the OS; the
/// only real file read outside the temporary directory is the system's shared standard suite.
final class ScriptingDictionaryLookupTests: XCTestCase {

    private var root: URL!
    private var bundle: URL!
    private var resources: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("scripting-dictionary-tests-\(UUID().uuidString)", isDirectory: true)
        bundle = root.appendingPathComponent("Fake.app", isDirectory: true)
        resources = bundle.appendingPathComponent("Contents/Resources", isDirectory: true)
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        try super.tearDownWithError()
    }

    // MARK: - Fixture helpers

    private static let xincludeNamespace = "http://www.w3.org/2003/XInclude"

    private func writeInfoPlist(definitionKey: String?) throws {
        var plist: [String: Any] = [
            "CFBundleIdentifier": "test.fake.app",
            "CFBundleName": "Fake",
            "CFBundleExecutable": "Fake",
        ]
        if let definitionKey {
            plist["OSAScriptingDefinition"] = definitionKey
        }
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: bundle.appendingPathComponent("Contents/Info.plist"))
    }

    private func sdef(suiteBody: String, prolog: String = "") -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE dictionary SYSTEM "file://localhost/System/Library/DTDs/sdef.dtd"\(prolog)>
        <dictionary title="Fake Terminology">
            <suite name="Fake Suite" code="fake" description="Fake suite for tests.">
        \(suiteBody)
            </suite>
        </dictionary>
        """
    }

    private func commandXML(_ name: String, description: String = "A fake command.") -> String {
        "        <command name=\"\(name)\" code=\"fakecmd0\" description=\"\(description)\"/>"
    }

    private func includeXML(href: String, xpointer: String? = nil) -> String {
        let pointer = xpointer.map { " xpointer=\"\($0)\"" } ?? ""
        return "        <xi:include xmlns:xi=\"\(Self.xincludeNamespace)\" href=\"\(href)\"\(pointer)/>"
    }

    /// Writes a definition file next to the bundle's other resources and returns its URL.
    @discardableResult
    private func writeResource(_ name: String, _ text: String) throws -> URL {
        let url = resources.appendingPathComponent(name)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// A minimal valid definition that lives outside the bundle and defines `leakedcommand`.
    @discardableResult
    private func writeOutsideDefinition(named name: String = "outside.sdef") throws -> URL {
        let url = root.appendingPathComponent(name)
        try sdef(suiteBody: commandXML("leakedcommand")).write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func installMainDefinition(_ text: String) throws {
        try writeInfoPlist(definitionKey: "Fake.sdef")
        try writeResource("Fake.sdef", text)
    }

    private func summary(term: String? = nil) throws -> String {
        try ScriptingDictionaryLookup().summary(appBundleURL: bundle, term: term)
    }

    // MARK: - Summary content

    func testSummaryListsCommandsAndClasses() throws {
        try installMainDefinition(sdef(suiteBody: """
        \(commandXML("search mailbox", description: "Search a mailbox."))
                <class name="message" code="mssg" description="An item in a mailbox.">
                    <property name="subject" code="subj" type="text" description="The subject line."/>
                </class>
        """))

        let text = try summary()

        XCTAssertTrue(text.contains("Fake Suite"))
        XCTAssertTrue(text.contains("search mailbox"))
        XCTAssertTrue(text.contains("message"))
        XCTAssertTrue(text.contains("subject"))
    }

    func testTermFiltersSummary() throws {
        try installMainDefinition(sdef(suiteBody: """
        \(commandXML("search mailbox", description: "Search a mailbox."))
                <class name="message" code="mssg" description="An item in a mailbox.">
                    <property name="subject" code="subj" type="text" description="The subject line."/>
                </class>
        """))

        let text = try summary(term: "search")

        XCTAssertTrue(text.contains("search mailbox"))
        XCTAssertFalse(text.contains("message"))
    }

    func testExtensionlessDefinitionKeyResolves() throws {
        try writeInfoPlist(definitionKey: "Fake")
        try writeResource("Fake.sdef", sdef(suiteBody: commandXML("extensionless command")))

        XCTAssertTrue(try summary().contains("extensionless command"))
    }

    func testAppWithoutKeyUsesBundledSdef() throws {
        try writeInfoPlist(definitionKey: nil)
        try writeResource("Other.sdef", sdef(suiteBody: commandXML("bundled command")))

        XCTAssertTrue(try summary().contains("bundled command"))
    }

    func testAppWithoutAnySdefThrowsNoScriptingDefinition() throws {
        try writeInfoPlist(definitionKey: nil)

        XCTAssertThrowsError(try summary()) { error in
            guard case ScriptingDictionaryLookupError.noScriptingDefinition = error else {
                return XCTFail("expected noScriptingDefinition, got \(error)")
            }
        }
    }

    func testSummaryIsCapped() throws {
        let commands = (0..<2000).map { commandXML("generated command \($0)") }.joined(separator: "\n")
        try installMainDefinition(sdef(suiteBody: commands))

        let text = try summary()

        XCTAssertLessThanOrEqual(text.count, ScriptingDictionaryLookup.maximumSummaryCharacters + 60)
        XCTAssertTrue(text.contains("truncated"))
        XCTAssertTrue(text.hasSuffix("... (truncated; pass term to narrow)"))
    }

    // MARK: - Definition location

    func testDefinitionOutsideBundleIsRefused() throws {
        // Three levels up from Contents/Resources is the directory holding the bundle, so the target really is
        // outside it.
        try writeInfoPlist(definitionKey: "../../../outside.sdef")
        try writeOutsideDefinition()

        XCTAssertThrowsError(try summary()) { error in
            guard case ScriptingDictionaryLookupError.definitionOutsideBundle = error else {
                return XCTFail("expected definitionOutsideBundle, got \(error)")
            }
        }
    }

    func testFifoDefinitionIsRefusedWithoutBlocking() throws {
        try writeInfoPlist(definitionKey: "Fake.sdef")
        let fifoPath = resources.appendingPathComponent("Fake.sdef").path
        XCTAssertEqual(mkfifo(fifoPath, 0o600), 0, "mkfifo failed: errno \(errno)")

        let outcome = OutcomeBox()
        let finished = expectation(description: "lookup returns instead of blocking on the fifo")
        let bundleURL: URL = bundle
        DispatchQueue.global().async {
            do {
                outcome.value = .success(try ScriptingDictionaryLookup().summary(appBundleURL: bundleURL, term: nil))
            } catch {
                outcome.value = .failure(error)
            }
            finished.fulfill()
        }

        let waiter = XCTWaiter().wait(for: [finished], timeout: 10)
        if waiter != .completed {
            // Release a reader stuck in a blocking open so the worker thread does not outlive the test.
            let releaseDescriptor = open(fifoPath, O_RDWR | O_NONBLOCK)
            if releaseDescriptor >= 0 { close(releaseDescriptor) }
            return XCTFail("a fifo definition blocked the lookup for 10 seconds")
        }

        guard case .failure(let error)? = outcome.value else {
            return XCTFail("expected a failure, got \(String(describing: outcome.value))")
        }
        guard case ScriptingDictionaryLookupError.definitionNotRegularFile = error else {
            return XCTFail("expected definitionNotRegularFile, got \(error)")
        }
    }

    // MARK: - Includes

    func testAllowedSystemIncludeIsResolved() throws {
        let systemSuite = "file://localhost/System/Library/ScriptingDefinitions/CocoaStandard.sdef"
        let pointer = "xpointer(/dictionary/suite/node()[not(self::command and ((@name = 'delete')))])"
        try installMainDefinition(sdef(suiteBody: """
        \(includeXML(href: systemSuite, xpointer: pointer))
        \(commandXML("ping"))
        """))

        let text = try summary()

        XCTAssertTrue(text.contains("ping"))
        XCTAssertTrue(text.contains("count"), "the standard suite commands are pulled in")
        XCTAssertFalse(text.contains("delete"), "the xpointer excludes the delete command")
    }

    func testIncludeOutsideAllowedRootsIsSkipped() throws {
        let outside = try writeOutsideDefinition()
        try installMainDefinition(sdef(suiteBody: """
        \(commandXML("kept command"))
        \(includeXML(href: "file://localhost\(outside.path)"))
        """))

        let text = try summary()

        XCTAssertTrue(text.contains("kept command"))
        XCTAssertFalse(text.contains("leakedcommand"))
        XCTAssertTrue(text.contains("include skipped"))
    }

    func testTraversalAndSymlinkIncludesAreSkipped() throws {
        let outside = try writeOutsideDefinition()
        try FileManager.default.createSymbolicLink(
            at: resources.appendingPathComponent("link.sdef"),
            withDestinationURL: outside
        )
        try installMainDefinition(sdef(suiteBody: """
        \(commandXML("kept command"))
        \(includeXML(href: "../../../outside.sdef"))
        \(includeXML(href: "link.sdef"))
        """))

        let text = try summary()

        XCTAssertTrue(text.contains("kept command"))
        XCTAssertFalse(text.contains("leakedcommand"))
        XCTAssertTrue(text.contains("include skipped"))
    }

    func testNonFileIncludeSchemeIsSkipped() throws {
        try installMainDefinition(sdef(suiteBody: """
        \(commandXML("kept command"))
        \(includeXML(href: "http://127.0.0.1:9/x.sdef"))
        """))

        let started = Date()
        let text = try summary()

        XCTAssertLessThan(Date().timeIntervalSince(started), 10)
        XCTAssertTrue(text.contains("kept command"))
        XCTAssertTrue(text.contains("include skipped"))
    }

    func testExternalEntityIsNotLoaded() throws {
        let secret = root.appendingPathComponent("secret.txt")
        try "TOPSECRET".write(to: secret, atomically: true, encoding: .utf8)
        let prolog = " [<!ENTITY leak SYSTEM \"file://\(secret.path)\">]"

        // Entity referenced from element text and from an attribute value. A parser may legitimately refuse the
        // attribute form as malformed; what must never happen is the secret reaching the summary.
        let variants = [
            sdef(
                suiteBody: "        <command name=\"probe\" code=\"fakecmd0\" description=\"A probe.\">&leak;</command>",
                prolog: prolog
            ),
            sdef(
                suiteBody: "        <command name=\"probe\" code=\"fakecmd0\" description=\"&leak;\"/>",
                prolog: prolog
            ),
        ]
        for variant in variants {
            try installMainDefinition(variant)
            do {
                let text = try summary()
                XCTAssertFalse(text.contains("TOPSECRET"))
            } catch ScriptingDictionaryLookupError.malformedDefinition {
                // Refusing the document is also safe.
            }
        }
    }

    func testInternalEntityExpansionIsBounded() throws {
        var declarations = "<!ENTITY lol0 \"lol\">"
        for level in 1...9 {
            let previous = String(repeating: "&lol\(level - 1);", count: 10)
            declarations += "<!ENTITY lol\(level) \"\(previous)\">"
        }
        let prolog = " [\(declarations)]"
        let variants = [
            sdef(
                suiteBody: "        <command name=\"probe\" code=\"fakecmd0\" description=\"A probe.\">&lol9;</command>",
                prolog: prolog
            ),
            sdef(
                suiteBody: "        <command name=\"probe\" code=\"fakecmd0\" description=\"&lol9;\"/>",
                prolog: prolog
            ),
        ]
        for variant in variants {
            try installMainDefinition(variant)
            let started = Date()
            do {
                let text = try summary()
                XCTAssertLessThanOrEqual(
                    text.count,
                    ScriptingDictionaryLookup.maximumSummaryCharacters + 200,
                    "an expanded entity must not blow up the summary"
                )
            } catch ScriptingDictionaryLookupError.malformedDefinition {
                // The parser refusing the amplification is the expected bounded failure.
            }
            XCTAssertLessThan(Date().timeIntervalSince(started), 10)
        }
    }

    func testParameterEntityDeclarationsAreAccepted() throws {
        // iWork definitions declare parameter entities in their internal subset; they must keep working.
        try installMainDefinition(sdef(
            suiteBody: commandXML("kept command"),
            prolog: " [<!ENTITY % common.attrib \"name CDATA #IMPLIED\">]"
        ))

        XCTAssertTrue(try summary().contains("kept command"))
    }

    /// A parameter entity whose literal spells its declarations with character references declares general entities
    /// only when `%p;` is referenced, so no text search for `<!ENTITY` sees them. Dropping the whole document type
    /// declaration leaves the body referring to an undeclared entity, which is refused before anything expands.
    private func parameterEntityAmplificationDefinition(levels: Int, inDescription: Bool) -> String {
        var declarations = "&#60;!ENTITY a0 'lol'>"
        for level in 1...levels {
            declarations += "&#60;!ENTITY a\(level) '" + String(repeating: "&#38;a\(level - 1);", count: 10) + "'>"
        }
        let body = inDescription
            ? "        <command name=\"probe\" code=\"fakecmd0\" description=\"&a\(levels);\"/>"
            : "        <command name=\"probe\" code=\"fakecmd0\" description=\"A probe.\">&a\(levels);</command>"
        return sdef(suiteBody: body, prolog: " [<!ENTITY % p \"\(declarations)\"> %p;]")
    }

    func testParameterEntityBuiltDeclarationsNeverExpand() throws {
        for inDescription in [false, true] {
            try installMainDefinition(parameterEntityAmplificationDefinition(levels: 9, inDescription: inDescription))
            let started = Date()
            XCTAssertThrowsError(try summary()) { error in
                guard case ScriptingDictionaryLookupError.malformedDefinition = error else {
                    return XCTFail("expected malformedDefinition, got \(error)")
                }
            }
            XCTAssertLessThan(Date().timeIntervalSince(started), 1, "the definition must be refused, not expanded")
        }
    }

    func testDocumentTypeWithInternalSubsetAndNoEntityUseParses() throws {
        // Quoted literals, a comment and a processing instruction in the subset hold `]`, `>` and quotes that must
        // not end the declaration early.
        let subset = """
         [
            <!-- a comment with ]> and 'quotes" inside -->
            <?note keep ]> here?>
            <!ATTLIST command hint CDATA "a ] and a > in a literal">
            <!ATTLIST class note CDATA 'it"s ]>'>
            <!ENTITY % common.attrib "name CDATA #IMPLIED">
        ]
        """
        let text = sdef(suiteBody: commandXML("kept command"), prolog: subset)

        try installMainDefinition(text)
        XCTAssertTrue(try summary().contains("kept command"))

        // The same document in UTF-16 with a byte-order mark: the declaration is cut at code-unit boundaries.
        let utf16Text = text.replacingOccurrences(of: "encoding=\"UTF-8\"", with: "encoding=\"UTF-16\"")
        try writeInfoPlist(definitionKey: "Fake.sdef")
        try XCTUnwrap(utf16Text.data(using: .utf16)).write(to: resources.appendingPathComponent("Fake.sdef"))
        XCTAssertTrue(try summary().contains("kept command"))
    }

    func testUnreadableOrRepeatedDocumentTypeIsRefused() throws {
        let variants = [
            // The internal subset never closes.
            sdef(suiteBody: commandXML("probe"), prolog: " [<!ATTLIST command hint CDATA \"open"),
            // A second declaration after the first would otherwise reach the parser.
            sdef(
                suiteBody: commandXML("probe"),
                prolog: "><!DOCTYPE dictionary [<!ENTITY a \"lol\">]"
            ),
        ]
        for variant in variants {
            try installMainDefinition(variant)
            XCTAssertThrowsError(try summary()) { error in
                guard case ScriptingDictionaryLookupError.malformedDefinition = error else {
                    return XCTFail("expected malformedDefinition, got \(error)")
                }
            }
        }
    }

    func testIncludeByteLimitIsTheRemainingExpansionBudget() {
        let perFile = ScriptingDictionaryLookup.maximumDefinitionBytes
        let total = ScriptingDictionaryLookup.maximumExpandedBytes
        XCTAssertEqual(ScriptingDictionaryLookup.includeByteLimit(loadedBytes: 0), perFile)
        XCTAssertEqual(ScriptingDictionaryLookup.includeByteLimit(loadedBytes: total - 10), 10)
        XCTAssertEqual(ScriptingDictionaryLookup.includeByteLimit(loadedBytes: total), 0)
        XCTAssertEqual(ScriptingDictionaryLookup.includeByteLimit(loadedBytes: total + 1), 0)
    }

    func testIncludeBeyondTheExpansionBudgetIsSkipped() throws {
        let padding = String(repeating: " ", count: ScriptingDictionaryLookup.maximumDefinitionBytes - 4_096)
        try writeResource("big1.sdef", sdef(suiteBody: commandXML("first big") + "\n" + padding))
        try writeResource("big2.sdef", sdef(suiteBody: commandXML("second big") + "\n" + padding))
        try writeResource("big3.sdef", sdef(suiteBody: commandXML("third big") + "\n" + padding))
        try installMainDefinition(sdef(suiteBody: """
        \(commandXML("kept command"))
        \(includeXML(href: "big1.sdef"))
        \(includeXML(href: "big2.sdef"))
        \(includeXML(href: "big3.sdef"))
        """))

        let text = try summary()

        XCTAssertTrue(text.contains("kept command"))
        XCTAssertTrue(text.contains("first big"))
        XCTAssertTrue(text.contains("second big"))
        XCTAssertFalse(text.contains("third big"))
        XCTAssertTrue(text.contains("total included size limit reached"), text)
    }

    func testIncludeDepthIsBounded() throws {
        try writeResource("B.sdef", sdef(suiteBody: """
        \(commandXML("command b"))
        \(includeXML(href: "C.sdef"))
        """))
        try writeResource("C.sdef", sdef(suiteBody: """
        \(commandXML("command c"))
        \(includeXML(href: "D.sdef"))
        """))
        try writeResource("D.sdef", sdef(suiteBody: commandXML("command d")))
        try installMainDefinition(sdef(suiteBody: """
        \(commandXML("command a"))
        \(includeXML(href: "B.sdef"))
        """))

        let started = Date()
        let text = try summary()

        XCTAssertLessThan(Date().timeIntervalSince(started), 10)
        XCTAssertTrue(text.contains("command a"))
        XCTAssertTrue(text.contains("include skipped"), "the third nested include exceeds the depth limit")
    }

    func testIncludeCountIsBounded() throws {
        try writeResource("small.sdef", sdef(suiteBody: commandXML("small command")))
        let includes = Array(repeating: includeXML(href: "small.sdef"), count: 100).joined(separator: "\n")
        try installMainDefinition(sdef(suiteBody: """
        \(commandXML("kept command"))
        \(includes)
        """))

        let started = Date()
        let text = try summary()

        XCTAssertLessThan(Date().timeIntervalSince(started), 10)
        XCTAssertTrue(text.contains("kept command"))
        XCTAssertTrue(text.contains("include skipped"), "includes beyond the per-document limit are skipped")
    }

    func testUnsupportedXPointerIsSkipped() throws {
        try writeResource("small.sdef", sdef(suiteBody: commandXML("small command")))
        try installMainDefinition(sdef(suiteBody: """
        \(commandXML("kept command"))
        \(includeXML(href: "small.sdef", xpointer: "xpointer(//*)"))
        \(includeXML(href: "small.sdef", xpointer: "xpointer(/dictionary/suite[1]/command[1])"))
        """))

        let text = try summary()

        XCTAssertTrue(text.contains("kept command"))
        XCTAssertFalse(text.contains("small command"))
        let occurrences = text.components(separatedBy: "unsupported xpointer").count - 1
        XCTAssertGreaterThanOrEqual(occurrences, 2)
    }

    // MARK: - Pure helpers

    func testSupportedXPointerShapes() {
        XCTAssertTrue(ScriptingDictionaryLookup.isSupportedXPointer("xpointer(/dictionary/suite)"))
        XCTAssertTrue(ScriptingDictionaryLookup.isSupportedXPointer(
            "xpointer(/dictionary/suite/node()[not(self::command and @name = 'save')])"
        ))
        XCTAssertTrue(ScriptingDictionaryLookup.isSupportedXPointer(
            "xpointer(/dictionary/suite/node()[not(self::command and ((@name = 'delete') or (@name = 'duplicate') or (@name = 'move')))])"
        ))

        XCTAssertFalse(ScriptingDictionaryLookup.isSupportedXPointer("xpointer(//*)"))
        XCTAssertFalse(ScriptingDictionaryLookup.isSupportedXPointer(
            "xpointer(/dictionary/suite/node()[not(self::command and @name = 'x' or 1=1)])"
        ))
        XCTAssertFalse(ScriptingDictionaryLookup.isSupportedXPointer(""))
        XCTAssertFalse(ScriptingDictionaryLookup.isSupportedXPointer(
            "xpointer(/dictionary/suite/node()[not(self::command and @name = 'a1')])"
        ), "names outside [A-Za-z ] are refused")
        let overlong = String(repeating: "a", count: 41)
        XCTAssertFalse(ScriptingDictionaryLookup.isSupportedXPointer(
            "xpointer(/dictionary/suite/node()[not(self::command and @name = '\(overlong)')])"
        ), "names longer than 40 characters are refused")
    }

    func testIncludeRootsAreBundleAndSystemDefinitions() {
        XCTAssertEqual(ScriptingDictionaryLookup.allowedIncludeRoots, ["/System/Library/ScriptingDefinitions"])
        XCTAssertTrue(ScriptingDictionaryLookup.isAllowedIncludePath(
            "/System/Library/ScriptingDefinitions/CocoaStandard.sdef",
            bundleRoot: "/Applications/Fake.app"
        ))
        XCTAssertTrue(ScriptingDictionaryLookup.isAllowedIncludePath(
            "/Applications/Fake.app/Contents/Resources/x.sdef",
            bundleRoot: "/Applications/Fake.app"
        ))
        XCTAssertFalse(ScriptingDictionaryLookup.isAllowedIncludePath(
            "/Applications/Fake.app.evil/x.sdef",
            bundleRoot: "/Applications/Fake.app"
        ), "a sibling that shares the bundle path as a prefix is outside")
        XCTAssertFalse(ScriptingDictionaryLookup.isAllowedIncludePath(
            "/System/Library/ScriptingDefinitionsEvil/x.sdef",
            bundleRoot: "/Applications/Fake.app"
        ))
        XCTAssertFalse(ScriptingDictionaryLookup.isAllowedIncludePath("/etc/hosts", bundleRoot: "/Applications/Fake.app"))
    }

    // MARK: - Running app matching

    private func candidate(
        _ name: String?,
        _ bundleIdentifier: String?,
        _ path: String?,
        _ policy: NSApplication.ActivationPolicy = .regular,
        terminated: Bool = false
    ) -> ScriptingDictionaryLookup.RunningAppCandidate {
        ScriptingDictionaryLookup.RunningAppCandidate(
            name: name,
            bundleIdentifier: bundleIdentifier,
            bundleURL: path.map { URL(fileURLWithPath: $0, isDirectory: true) },
            activationPolicy: policy,
            isTerminated: terminated
        )
    }

    func testRunningMatchSkipsAppExtensionWithSameName() {
        let candidates = [
            candidate(
                "Messages", "com.apple.messages.AssistantExtension",
                "/System/Library/Messages/PlugIns/AssistantExtension.appex", .prohibited
            ),
            candidate("Messages", "com.apple.MobileSMS", "/System/Applications/Messages.app"),
        ]
        XCTAssertEqual(
            ScriptingDictionaryLookup.bestRunningMatch("Messages", among: candidates)?.path,
            "/System/Applications/Messages.app"
        )
    }

    func testRunningMatchPrefersRegularOverBackgroundOnlyWithSameName() {
        let candidates = [
            candidate("Helper", "test.helper.agent", "/Applications/Helper Agent.app", .prohibited),
            candidate("Helper", "test.helper.menu", "/Applications/Helper Menu.app", .accessory),
            candidate("helper", "test.helper", "/Applications/Helper.app", .regular),
        ]
        XCTAssertEqual(
            ScriptingDictionaryLookup.bestRunningMatch("Helper", among: candidates)?.path,
            "/Applications/Helper.app"
        )
    }

    func testBackgroundOnlyAppMatchesWhenItIsTheOnlyCandidate() {
        let candidates = [
            candidate("Finder", "com.apple.finder", "/System/Library/CoreServices/Finder.app"),
            candidate(
                "System Events", "com.apple.systemevents",
                "/System/Library/CoreServices/System Events.app", .prohibited
            ),
        ]
        XCTAssertEqual(
            ScriptingDictionaryLookup.bestRunningMatch("system events", among: candidates)?.path,
            "/System/Library/CoreServices/System Events.app"
        )
    }

    func testMenuBarAccessoryAppMatches() {
        let candidates = [
            candidate("Tray", "test.tray", "/Applications/Tray.app", .accessory),
        ]
        XCTAssertEqual(
            ScriptingDictionaryLookup.bestRunningMatch("Tray", among: candidates)?.path,
            "/Applications/Tray.app"
        )
    }

    func testBundleIdentifierMatchBeatsNameMatch() {
        let candidates = [
            candidate("test.target", "test.impostor", "/Applications/Impostor.app"),
            candidate("Target", "test.target", "/Applications/Target.app", .prohibited),
        ]
        XCTAssertEqual(
            ScriptingDictionaryLookup.bestRunningMatch("TEST.TARGET", among: candidates)?.path,
            "/Applications/Target.app"
        )
    }

    func testEqualRankCandidatesResolveToTheFirstInEnumerationOrder() {
        let candidates = [
            candidate("Twin", "test.twin.first", "/Applications/Twin First.app"),
            candidate("Twin", "test.twin.second", "/Applications/Twin Second.app"),
        ]
        XCTAssertEqual(
            ScriptingDictionaryLookup.bestRunningMatch("Twin", among: candidates)?.path,
            "/Applications/Twin First.app"
        )
    }

    func testNoRunningCandidateReturnsNil() {
        let candidates = [
            candidate("Messages", "com.apple.messages.ext", "/System/Library/PlugIns/Ext.appex"),
            candidate("Messages", "com.apple.MobileSMS", "/System/Applications/Messages.app", terminated: true),
            candidate("Messages", "com.apple.MobileSMS", nil),
            candidate("Notes", "com.apple.Notes", "/System/Applications/Notes.app"),
        ]
        XCTAssertNil(ScriptingDictionaryLookup.bestRunningMatch("Messages", among: candidates))
        XCTAssertNil(ScriptingDictionaryLookup.bestRunningMatch("Messages", among: []))
    }
}

/// Hands a result from a background thread to the test thread; the expectation orders the write before the read.
private final class OutcomeBox: @unchecked Sendable {
    var value: Result<String, Error>?
}
