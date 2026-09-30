import Foundation

public enum ScriptLanguage: String, Sendable, CaseIterable {
    case applescript
    case javascript
}

public enum ScriptPolicyVerdict: Equatable, Sendable {
    case allowed
    case rejected(matchedPattern: String)
}

/// Best-effort friction against script text that reaches a shell or loads code, not a security boundary.
///
/// The filter matches normalized text, not syntax, so it has false positives (a denied phrase inside a string
/// literal is rejected) and known bypass classes. Hosts that can run a shell (Claude Code, Codex) bypass it
/// entirely by invoking `osascript` from Bash. Its job is to stop an accidental or prompt-injected shell verb in a
/// script that was expected to only talk to an app.
public enum ScriptPolicyFilter {
    /// Denied phrases, matched against normalized text. Applies to both languages (union).
    public static let deniedPatterns: [String] = [
        "do shell script",
        "run script",
        "load script",
        "store script",
        "do script",
        "«event",
        "<<event",
        "use framework",
        "use scripting additions",
        "use script",
        "doshellscript",
        "runscript",
        "loadscript",
        "doscript",
        "objc.",
        "library(",
        "$.ns",
    ]

    /// Folds a script into one comparable line: NFKC, lowercase, line continuations joined, every Unicode
    /// whitespace run collapsed to one space, spaces inside chevron delimiters removed.
    public static func normalize(_ source: String) -> String {
        var text = source.precomposedStringWithCompatibilityMapping.lowercased()
        text = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        text = removeLineContinuations(text)
        text = collapseWhitespace(text)
        for opener in ["« ", "<< "] {
            text = text.replacingOccurrences(of: opener, with: String(opener.dropLast()))
        }
        for closer in [" »", " >>"] {
            text = text.replacingOccurrences(of: closer, with: String(closer.dropFirst()))
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func evaluate(source: String, language: ScriptLanguage) -> ScriptPolicyVerdict {
        // Both views are checked: a comment marker inside a string literal cannot hide a denied phrase, because the
        // unstripped view still contains it, while a real comment placed between words cannot split one.
        let views = [normalize(source), normalize(stripBlockComments(source))]
        for pattern in deniedPatterns where views.contains(where: { $0.contains(pattern) }) {
            return .rejected(matchedPattern: pattern)
        }
        return .allowed
    }

    /// Deletes each `¬` that is followed only by horizontal whitespace and a newline, together with that newline.
    private static func removeLineContinuations(_ text: String) -> String {
        let scalars = Array(text.unicodeScalars)
        var output = String.UnicodeScalarView()
        var index = 0
        while index < scalars.count {
            if scalars[index] == "\u{00AC}" {
                var probe = index + 1
                while probe < scalars.count, CharacterSet.whitespaces.contains(scalars[probe]) {
                    probe += 1
                }
                if probe < scalars.count, scalars[probe] == "\n" {
                    index = probe + 1
                    continue
                }
            }
            output.append(scalars[index])
            index += 1
        }
        return String(output)
    }

    private static func collapseWhitespace(_ text: String) -> String {
        var output = String.UnicodeScalarView()
        var previousWasSpace = false
        for scalar in text.unicodeScalars {
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                if !previousWasSpace {
                    output.append(" ")
                }
                previousWasSpace = true
            } else {
                output.append(scalar)
                previousWasSpace = false
            }
        }
        return String(output)
    }

    /// Replaces every `(*` ... `*)` span (shortest match, repeated until none is left) with one space.
    private static func stripBlockComments(_ source: String) -> String {
        var text = source
        while let open = text.range(of: "(*"),
              let close = text.range(of: "*)", range: open.upperBound..<text.endIndex) {
            text.replaceSubrange(open.lowerBound..<close.upperBound, with: " ")
        }
        return text
    }
}
