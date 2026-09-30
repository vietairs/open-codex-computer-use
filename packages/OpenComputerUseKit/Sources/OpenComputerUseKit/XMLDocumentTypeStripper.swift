import Foundation

/// Removes the document type declaration, internal subset included, from an XML document before it reaches a parser.
///
/// Without a DTD no entity can be declared, so neither a general entity nor a parameter entity whose replacement text
/// builds declarations out of character references (`&#60;!ENTITY …`) can expand: a reference to an undeclared
/// entity is a well-formedness error. The removal is byte-exact, so the document keeps its encoding and declaration.
///
/// The scan reads the document as code units in which every delimiter is its ASCII value, so it only accepts documents
/// the parser reads the same way: bytes with no declared encoding or a declared UTF-8, US-ASCII, ISO 8859 or
/// Windows-125x encoding (see `XMLDeclaredEncodingCheck`), or UTF-16 behind a byte-order mark. Any other declared
/// encoding (UTF-7, EBCDIC, UTF-32, an unknown name), a first unit other than `<` or whitespace, NUL bytes up front
/// without a UTF-16 mark, an XML declaration that cannot be read or does not start the document, a declaration that
/// does not end, and any `<!DOCTYPE` or `<!ENTITY` left anywhere after the removal each refuse the whole document. A
/// scan that ended the declaration too early or too late therefore never hands the parser a declaration.
enum XMLDocumentTypeStripper {
    enum Failure: Error, Equatable {
        case unsupportedEncoding
        case unterminatedMarkup
        case strayDeclaration
        case unreadableXMLDeclaration

        var message: String {
            switch self {
            case .unsupportedEncoding: return "unsupported text encoding"
            case .unterminatedMarkup: return "the document type declaration could not be read"
            case .strayDeclaration: return "entity or document type declarations are not supported here"
            case .unreadableXMLDeclaration: return "the XML declaration is malformed or does not start the document"
            }
        }
    }

    static func strippingDocumentType(from data: Data) throws -> Data {
        let (units, offset, width) = try codeUnits(of: data)
        try XMLDeclaredEncodingCheck.validate(units, isUTF16: width == 2)
        let scanner = Scanner(units: units)
        let declaration = try scanner.prologDocumentType()

        var remaining = units
        if let declaration {
            remaining.removeSubrange(declaration)
        }
        if Scanner(units: remaining).containsDeclaration() {
            throw Failure.strayDeclaration
        }

        guard let declaration else { return data }
        var stripped = data
        let start = data.startIndex + offset + declaration.lowerBound * width
        let end = data.startIndex + offset + declaration.upperBound * width
        stripped.removeSubrange(start..<end)
        return stripped
    }

    /// The document as code units in which every XML delimiter is its ASCII value: UTF-16 with a byte-order mark, or
    /// any other document byte by byte, which is only a faithful view for the ASCII-compatible encodings that
    /// `XMLDeclaredEncodingCheck` then enforces (a UTF-8 multi-byte sequence never contains an ASCII byte). `offset`
    /// is the byte length of the skipped mark, `width` the bytes per unit. NUL bytes up front without a UTF-16 mark
    /// (UTF-32, UTF-16 without a mark) are refused.
    private static func codeUnits(of data: Data) throws -> (units: [UInt16], offset: Int, width: Int) {
        let bytes = [UInt8](data)
        let head = Array(bytes.prefix(4))
        let isUTF16LE = head.count >= 2 && head[0] == 0xFF && head[1] == 0xFE
        let isUTF16BE = head.count >= 2 && head[0] == 0xFE && head[1] == 0xFF
        let isUTF32LE = head.count == 4 && isUTF16LE && head[2] == 0 && head[3] == 0
        if (isUTF16LE || isUTF16BE) && !isUTF32LE {
            guard bytes.count % 2 == 0 else { throw Failure.unsupportedEncoding }
            let units = stride(from: 2, to: bytes.count, by: 2).map { index -> UInt16 in
                let high: UInt16 = UInt16(bytes[isUTF16BE ? index : index + 1])
                let low: UInt16 = UInt16(bytes[isUTF16BE ? index + 1 : index])
                return (high << 8) | low
            }
            return (units, 2, 2)
        }
        if head.contains(0) {
            throw Failure.unsupportedEncoding
        }
        let offset = head.starts(with: [0xEF, 0xBB, 0xBF]) ? 3 : 0
        return (bytes.dropFirst(offset).map(UInt16.init), offset, 1)
    }

    private struct Scanner {
        let units: [UInt16]

        private static let doctype = ascii("<!DOCTYPE")
        private static let entity = ascii("<!ENTITY")
        private static let commentOpen = ascii("<!--")
        private static let commentClose = ascii("-->")
        private static let instructionOpen = ascii("<?")
        private static let instructionClose = ascii("?>")
        private static let lessThan = UInt16(UInt8(ascii: "<"))
        private static let greaterThan = UInt16(UInt8(ascii: ">"))
        private static let openBracket = UInt16(UInt8(ascii: "["))
        private static let closeBracket = UInt16(UInt8(ascii: "]"))
        private static let quote = UInt16(UInt8(ascii: "\""))
        private static let apostrophe = UInt16(UInt8(ascii: "'"))

        private static func ascii(_ text: String) -> [UInt16] {
            text.utf8.map(UInt16.init)
        }

        /// The range of the first document type declaration in the prolog, walking the XML declaration, processing
        /// instructions, comments and whitespace that may precede it. Nil when the prolog has none.
        func prologDocumentType() throws -> Range<Int>? {
            var index = 0
            while index < units.count {
                if XMLDeclaredEncodingCheck.isWhitespace(units[index]) {
                    index += 1
                } else if matches(Self.instructionOpen, at: index) {
                    // The parser refuses an XML declaration anywhere but the start; refuse it here too, so its
                    // encoding can never be read differently from how this scan read the document.
                    if index > 0 && XMLDeclaredEncodingCheck.startsDeclaration(units, at: index) {
                        throw Failure.unreadableXMLDeclaration
                    }
                    index = try end(of: Self.instructionClose, from: index + Self.instructionOpen.count)
                } else if matches(Self.commentOpen, at: index) {
                    index = try end(of: Self.commentClose, from: index + Self.commentOpen.count)
                } else if matches(Self.doctype, at: index, ignoringCase: true) {
                    return index..<(try declarationEnd(from: index + Self.doctype.count))
                } else {
                    return nil
                }
            }
            return nil
        }

        /// True when `<!DOCTYPE` or `<!ENTITY` occurs anywhere, in any letter case.
        func containsDeclaration() -> Bool {
            var index = 0
            while let found = units[index...].firstIndex(of: Self.lessThan) {
                if matches(Self.doctype, at: found, ignoringCase: true)
                    || matches(Self.entity, at: found, ignoringCase: true) {
                    return true
                }
                index = found + 1
            }
            return false
        }

        /// The index just past the `>` that closes the declaration. Quoted literals are skipped whole, and inside the
        /// internal subset so are comments and processing instructions, so a `]` or `>` inside any of them does not
        /// end the declaration.
        private func declarationEnd(from start: Int) throws -> Int {
            var index = start
            var inSubset = false
            while index < units.count {
                let unit = units[index]
                if unit == Self.quote || unit == Self.apostrophe {
                    guard let close = units[(index + 1)...].firstIndex(of: unit) else {
                        throw Failure.unterminatedMarkup
                    }
                    index = close + 1
                } else if inSubset && matches(Self.commentOpen, at: index) {
                    index = try end(of: Self.commentClose, from: index + Self.commentOpen.count)
                } else if inSubset && matches(Self.instructionOpen, at: index) {
                    index = try end(of: Self.instructionClose, from: index + Self.instructionOpen.count)
                } else if inSubset {
                    inSubset = unit != Self.closeBracket
                    index += 1
                } else if unit == Self.greaterThan {
                    return index + 1
                } else {
                    inSubset = unit == Self.openBracket
                    index += 1
                }
            }
            throw Failure.unterminatedMarkup
        }

        /// The index just past the first `terminator` at or after `start`.
        private func end(of terminator: [UInt16], from start: Int) throws -> Int {
            var index = start
            while index + terminator.count <= units.count {
                if matches(terminator, at: index) {
                    return index + terminator.count
                }
                index += 1
            }
            throw Failure.unterminatedMarkup
        }

        /// `literal` must be upper case when `ignoringCase` is set.
        private func matches(_ literal: [UInt16], at index: Int, ignoringCase: Bool = false) -> Bool {
            guard index >= 0, index + literal.count <= units.count else { return false }
            for (offset, expected) in literal.enumerated() {
                var unit = units[index + offset]
                if ignoringCase, unit >= 0x61, unit <= 0x7A {
                    unit -= 0x20
                }
                if unit != expected { return false }
            }
            return true
        }
    }
}
