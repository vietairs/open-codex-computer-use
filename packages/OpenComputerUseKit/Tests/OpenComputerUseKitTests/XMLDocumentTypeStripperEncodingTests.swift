import Foundation
import XCTest
@testable import OpenComputerUseKit

/// The stripper scans ASCII code units, so a document the parser would read in an encoding where `<` is not 0x3C
/// (UTF-7, EBCDIC, UTF-32) must be refused before the parser ever sees its document type declaration.
final class XMLDocumentTypeStripperEncodingTests: XCTestCase {

    /// Three levels of tenfold entity expansion: harmless in size, but any expansion proves the DTD reached the parser.
    private static let amplifyingSubset = "<!DOCTYPE r [<!ENTITY a0 \"lol\">"
        + "<!ENTITY a1 \"&a0;&a0;&a0;&a0;&a0;&a0;&a0;&a0;&a0;&a0;\">"
        + "<!ENTITY a2 \"&a1;&a1;&a1;&a1;&a1;&a1;&a1;&a1;&a1;&a1;\">]>"
    private static let body = "<r>&a2;</r>"

    private func encoded(_ text: String, _ encoding: CFStringEncodings) throws -> Data {
        let converted = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(encoding.rawValue))
        return try XCTUnwrap(text.data(using: String.Encoding(rawValue: converted), allowLossyConversion: false))
    }

    private func ascii(_ text: String) -> Data {
        Data(text.utf8)
    }

    private func assertRefused(
        _ data: Data,
        _ expected: XMLDocumentTypeStripper.Failure = .unsupportedEncoding,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let started = Date()
        XCTAssertThrowsError(try XMLDocumentTypeStripper.strippingDocumentType(from: data), file: file, line: line) {
            XCTAssertEqual($0 as? XMLDocumentTypeStripper.Failure, expected, file: file, line: line)
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 1, "the refusal must not wait on the parser", file: file, line: line)
    }

    /// Strips, parses, and returns the root element's text, so an expanded entity would show up in it.
    private func strippedRootText(_ data: Data, file: StaticString = #filePath, line: UInt = #line) throws -> String {
        let stripped = try XMLDocumentTypeStripper.strippingDocumentType(from: data)
        let document = try XMLDocument(data: stripped, options: [.nodeLoadExternalEntitiesNever])
        XCTAssertNil(document.dtd, "the document type declaration must be gone", file: file, line: line)
        return try XCTUnwrap(document.rootElement()?.stringValue, file: file, line: line)
    }

    // MARK: - Refused encodings

    func testUTF7DeclarationIsRefused() {
        var data = ascii("<?xml version=\"1.0\" encoding=\"UTF-7\"?>")
        // `<!DOCTYPE r [<!ENTITY a0 "lol"><!ENTITY a1 "&a0;&a0;">]><r>&a1;</r>` with every delimiter in UTF-7 base64.
        data.append(ascii("+ADw-!DOCTYPE r +AFsAPA-!ENTITY a0 +ACI-lol+ACIAPgA8-!ENTITY a1 +ACIAJg-a0+ADsAJg-a0+ADsAIgA+AF0APg-+ADw-r+AD4AJg-a1+ADsAPA-/r+AD4-"))
        assertRefused(data)
    }

    func testEBCDICIsRefusedWithAndWithoutDeclaration() throws {
        let declared = "<?xml version=\"1.0\" encoding=\"IBM037\"?>" + Self.amplifyingSubset + Self.body
        assertRefused(try encoded(declared, .EBCDIC_CP037))
        assertRefused(try encoded(Self.amplifyingSubset + Self.body, .EBCDIC_CP037))
        // The declaration spelled in ASCII, as a document that switches encoding after it would be.
        assertRefused(ascii("<?xml version=\"1.0\" encoding=\"IBM037\"?><r/>"))
        assertRefused(ascii("<?xml version=\"1.0\" encoding=\"cp037\"?><r/>"))
        assertRefused(ascii("<?xml version=\"1.0\" encoding=\"EBCDIC-US\"?><r/>"))
    }

    func testUTF32IsRefused() throws {
        let text = "<?xml version=\"1.0\" encoding=\"UTF-32\"?>" + Self.amplifyingSubset + Self.body
        assertRefused(Data([0xFF, 0xFE, 0x00, 0x00]) + (try XCTUnwrap(text.data(using: .utf32LittleEndian))))
        assertRefused(Data([0x00, 0x00, 0xFE, 0xFF]) + (try XCTUnwrap(text.data(using: .utf32BigEndian))))
        assertRefused(try XCTUnwrap(text.data(using: .utf32BigEndian)))
        assertRefused(ascii("<?xml version=\"1.0\" encoding=\"UTF-32\"?><r/>"))
    }

    func testUnknownOrUTF16WithoutMarkIsRefused() {
        assertRefused(ascii("<?xml version=\"1.0\" encoding=\"x-made-up\"?><r/>"))
        assertRefused(ascii("<?xml version=\"1.0\" encoding=\"\"?><r/>"))
        assertRefused(ascii("<?xml version=\"1.0\" encoding=\"UTF-16\"?><r/>"))
    }

    /// The parser follows the declared encoding even after a byte-order mark.
    func testDeclarationBehindByteOrderMarkIsChecked() throws {
        assertRefused(Data([0xEF, 0xBB, 0xBF]) + ascii("<?xml version=\"1.0\" encoding=\"UTF-7\"?><r/>"))
        let utf16 = try XCTUnwrap("<?xml version=\"1.0\" encoding=\"UTF-7\"?><r/>".data(using: .utf16))
        assertRefused(utf16)
        let latin = try XCTUnwrap("<?xml version=\"1.0\" encoding=\"ISO-8859-1\"?><r/>".data(using: .utf16))
        assertRefused(latin)
    }

    func testDeclarationSpellingsCannotHideTheEncoding() {
        let spellings = [
            "<?xml version='1.0' encoding='UTF-7'?>",
            "<?xml version = \"1.0\"\n\tencoding\t=\r\n 'utf-7' ?>",
            "<?xml encoding=\"UTF-7\" version=\"1.0\"?>",
            "<?xml version=\"1.0\"encoding=\"UTF-7\"?>",
            "<?xml version=\"1.0\" ENCODING=\"UTF-7\"?>",
            "<?XML version=\"1.0\" encoding=\"UTF-7\"?>",
            "<?xml version=\"1.0\" encoding=\"UTF-8\" encoding=\"UTF-7\"?>",
        ]
        for spelling in spellings {
            assertRefused(ascii(spelling + "<r/>"))
        }
    }

    func testUnreadableOrMisplacedDeclarationIsRefused() {
        assertRefused(ascii("<?xml version=\"1.0\" encoding=UTF-8?><r/>"), .unreadableXMLDeclaration)
        assertRefused(ascii("<?xml version=\"1.0\" encoding=\"UTF-8"), .unreadableXMLDeclaration)
        assertRefused(ascii("\n<?xml version=\"1.0\" encoding=\"UTF-7\"?><r/>"), .unreadableXMLDeclaration)
        assertRefused(ascii("<!-- c --><?xml version=\"1.0\"?><r/>"), .unreadableXMLDeclaration)
    }

    func testFirstUnitMustBeMarkupOrWhitespace() {
        assertRefused(ascii("x<r/>"))
        assertRefused(Data([0xEF, 0xBB, 0xBF]) + Data([0x4C, 0x6F, 0xA7, 0x94]))
    }

    // MARK: - Accepted encodings

    func testASCIICompatibleDeclarationsStillStripAndParse() throws {
        for name in ["UTF-8", "utf8", "ISO-8859-1", "iso_8859-15", "latin1", "US-ASCII", "windows-1252", "CP1252"] {
            let text = "<?xml version=\"1.0\" encoding=\"\(name)\"?>" + Self.amplifyingSubset + "<r>kept</r>"
            XCTAssertEqual(try strippedRootText(ascii(text)), "kept", name)
        }
    }

    func testISO88591DocumentKeepsItsText() throws {
        let text = "<?xml version=\"1.0\" encoding=\"ISO-8859-1\"?>" + Self.amplifyingSubset + "<r>caf\u{E9}</r>"
        let data = try XCTUnwrap(text.data(using: .isoLatin1))
        XCTAssertEqual(try strippedRootText(data), "caf\u{E9}")
    }

    func testEntityInAcceptedDocumentStillFailsAsUndeclared() throws {
        let text = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>" + Self.amplifyingSubset + Self.body
        XCTAssertThrowsError(try strippedRootText(ascii(text)))
    }

    func testDocumentsWithoutDeclarationOrWithUTF16MarkAreAccepted() throws {
        XCTAssertEqual(try strippedRootText(ascii(Self.amplifyingSubset + "<r>kept</r>")), "kept")
        XCTAssertEqual(try strippedRootText(ascii("\n  <r>kept</r>")), "kept")
        XCTAssertEqual(try strippedRootText(Data([0xEF, 0xBB, 0xBF]) + ascii("<r>kept</r>")), "kept")
        let utf16 = "<?xml version=\"1.0\" encoding=\"UTF-16\"?>" + Self.amplifyingSubset + "<r>kept</r>"
        XCTAssertEqual(try strippedRootText(try XCTUnwrap(utf16.data(using: .utf16))), "kept")
        XCTAssertEqual(try strippedRootText(try XCTUnwrap("<r>kept</r>".data(using: .utf16))), "kept")
    }

    func testRefusalSurfacesAsMalformedDefinition() {
        XCTAssertThrowsError(try ScriptingDictionaryLookup.parse(ascii("<?xml version=\"1.0\" encoding=\"UTF-7\"?><r/>"))) {
            XCTAssertEqual(
                $0 as? ScriptingDictionaryLookupError,
                .malformedDefinition(XMLDocumentTypeStripper.Failure.unsupportedEncoding.message)
            )
        }
    }
}
