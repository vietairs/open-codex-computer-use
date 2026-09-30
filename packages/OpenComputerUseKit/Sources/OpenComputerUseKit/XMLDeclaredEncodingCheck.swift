import Foundation

/// Refuses a document whose parser would read it in an encoding where the XML delimiters are not the ASCII code units
/// the document type stripper scans for.
///
/// The parser (libxml2) follows the `encoding` of the XML declaration even after a byte-order mark, so a document can
/// look like plain bytes to a scan and still be read as UTF-7 or EBCDIC, where `<` is not 0x3C. Only encodings that
/// keep every ASCII character at its ASCII value are let through, plus UTF-16 when a byte-order mark fixes the unit
/// order. Every other name, known or not, is refused.
enum XMLDeclaredEncodingCheck {
    /// `units` is the document after any byte-order mark; `isUTF16` is true when that mark was a UTF-16 one.
    static func validate(_ units: [UInt16], isUTF16: Bool) throws {
        guard let first = units.first else { return }
        // A document starts with markup or whitespace. Anything else is a delimiter this scan cannot see, such as an
        // EBCDIC `<` (0x4C).
        guard first == lessThan || isWhitespace(first) else {
            throw XMLDocumentTypeStripper.Failure.unsupportedEncoding
        }
        for name in try declaredEncodings(in: units) {
            let normalized = name.lowercased()
            let allowed = isUTF16 ? utf16Names.contains(normalized) : asciiCompatibleNames.contains(normalized)
            guard allowed else { throw XMLDocumentTypeStripper.Failure.unsupportedEncoding }
        }
    }

    /// Names whose single-byte (or UTF-8) code units keep all of ASCII in place.
    static let asciiCompatibleNames: Set<String> = {
        var names: Set<String> = ["utf-8", "utf8", "us-ascii", "ascii", "latin1"]
        // ISO 8859 has no part 12.
        for part in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 14, 15] {
            names.formUnion(["iso-8859-\(part)", "iso8859-\(part)", "iso_8859-\(part)"])
        }
        for page in 1250...1258 {
            names.formUnion(["windows-\(page)", "cp\(page)"])
        }
        return names
    }()

    static let utf16Names: Set<String> = ["utf-16", "utf16"]

    /// Every `encoding` pseudo-attribute of an XML declaration at the very start of `units`, in any letter case; empty
    /// when there is no declaration. The attributes are read in any order and without requiring whitespace between
    /// them, because the parser also honours an encoding in those malformed shapes. A declaration this cannot read to
    /// its `?>` is refused rather than guessed at.
    private static func declaredEncodings(in units: [UInt16]) throws -> [String] {
        guard startsDeclaration(units, at: 0) else { return [] }
        var index = 5
        var encodings: [String] = []
        while true {
            while index < units.count, isWhitespace(units[index]) { index += 1 }
            guard index < units.count else { throw XMLDocumentTypeStripper.Failure.unreadableXMLDeclaration }
            if units[index] == questionMark {
                guard index + 1 < units.count, units[index + 1] == greaterThan else {
                    throw XMLDocumentTypeStripper.Failure.unreadableXMLDeclaration
                }
                return encodings
            }
            let nameStart = index
            while index < units.count, isNameUnit(units[index]) { index += 1 }
            guard index > nameStart else { throw XMLDocumentTypeStripper.Failure.unreadableXMLDeclaration }
            let name = String(decoding: units[nameStart..<index], as: UTF16.self)
            while index < units.count, isWhitespace(units[index]) { index += 1 }
            guard index < units.count, units[index] == equals else {
                throw XMLDocumentTypeStripper.Failure.unreadableXMLDeclaration
            }
            index += 1
            while index < units.count, isWhitespace(units[index]) { index += 1 }
            guard index < units.count, units[index] == quote || units[index] == apostrophe,
                  let close = units[(index + 1)...].firstIndex(of: units[index]) else {
                throw XMLDocumentTypeStripper.Failure.unreadableXMLDeclaration
            }
            if name.lowercased() == "encoding" {
                encodings.append(String(decoding: units[(index + 1)..<close], as: UTF16.self))
            }
            index = close + 1
        }
    }

    /// True when `<?xml` in any letter case, followed by whitespace or `?`, starts at `index`: the XML declaration,
    /// or a processing instruction with the reserved target that the parser refuses anywhere else.
    static func startsDeclaration(_ units: [UInt16], at index: Int) -> Bool {
        let target: [UInt16] = [0x58, 0x4D, 0x4C] // "XML"
        guard index >= 0, index + 5 < units.count,
              units[index] == lessThan, units[index + 1] == questionMark else { return false }
        for offset in 0..<3 {
            var unit = units[index + 2 + offset]
            if unit >= 0x61, unit <= 0x7A { unit -= 0x20 }
            if unit != target[offset] { return false }
        }
        let next = units[index + 5]
        return isWhitespace(next) || next == questionMark
    }

    static func isWhitespace(_ unit: UInt16) -> Bool {
        unit == 0x20 || unit == 0x09 || unit == 0x0A || unit == 0x0D
    }

    private static func isNameUnit(_ unit: UInt16) -> Bool {
        (unit >= 0x61 && unit <= 0x7A) || (unit >= 0x41 && unit <= 0x5A) || (unit >= 0x30 && unit <= 0x39)
            || unit == 0x2D || unit == 0x2E || unit == 0x5F || unit == 0x3A
    }

    private static let lessThan = UInt16(UInt8(ascii: "<"))
    private static let greaterThan = UInt16(UInt8(ascii: ">"))
    private static let questionMark = UInt16(UInt8(ascii: "?"))
    private static let equals = UInt16(UInt8(ascii: "="))
    private static let quote = UInt16(UInt8(ascii: "\""))
    private static let apostrophe = UInt16(UInt8(ascii: "'"))
}
