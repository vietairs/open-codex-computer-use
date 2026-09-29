import AppKit
import Darwin
import Foundation

public enum ScriptingDictionaryLookupError: Error, Equatable {
    case appNotFound(String)
    case noScriptingDefinition(String)
    case definitionOutsideBundle(String)
    case definitionTooLarge(Int)
    case definitionNotRegularFile(String)
    case malformedDefinition(String)
}

/// Reads an app's scripting definition (`.sdef`) straight from its bundle and renders a compact summary of its
/// commands and classes.
///
/// This is a static, read-only lookup. It never asks the OS for the dictionary (which can send an Apple Event to the
/// target or launch it), never shells out to `sdef`, and never lets the XML parser touch the network or the file
/// system on its own:
/// - the parser runs with external entities disabled and XInclude processing off;
/// - `xi:include` elements are resolved by hand, only for `file:` or relative targets whose real path lies inside
///   the app bundle or under `allowedIncludeRoots`, with depth, count and total-size limits;
/// - files are opened `O_NOFOLLOW | O_NONBLOCK`, checked with `fstat` to be regular files of bounded size, and read
///   by descriptor, so a FIFO or device cannot hang the caller.
public struct ScriptingDictionaryLookup {
    public static let allowedIncludeRoots: [String] = ["/System/Library/ScriptingDefinitions"]
    public static let maximumIncludeDepth = 2
    public static let maximumIncludesPerDocument = 16
    public static let maximumDefinitionBytes = 4 * 1024 * 1024
    public static let maximumExpandedBytes = 8 * 1024 * 1024
    public static let maximumSummaryCharacters = 16_000

    private static let truncationSuffix = "... (truncated; pass term to narrow)"
    private static let includeNamespaces: Set<String> = [
        "http://www.w3.org/2003/XInclude",
        "http://www.w3.org/2001/XInclude",
    ]
    private static let maximumNotes = 32
    private static let maximumDescriptionCharacters = 240

    public init() {}

    // MARK: - Summary

    public func summary(appBundleURL: URL, term: String?) throws -> String {
        let appName = appBundleURL.deletingPathExtension().lastPathComponent
        guard let definition = try Self.definitionURL(appBundleURL: appBundleURL) else {
            throw ScriptingDictionaryLookupError.noScriptingDefinition(
                "\(appName) has no static scripting dictionary (no .sdef in its bundle)"
            )
        }
        guard let bundleRoot = Self.realPath(appBundleURL.path) else {
            throw ScriptingDictionaryLookupError.appNotFound(appBundleURL.path)
        }

        let data = try Self.readDefinitionFile(definition)
        var state = ExpansionState(loadedBytes: data.count)
        let document = try Self.parse(data)
        if let root = document.rootElement() {
            Self.expandIncludes(
                in: root,
                directory: (definition.path as NSString).deletingLastPathComponent,
                bundleRoot: bundleRoot,
                depth: 0,
                state: &state
            )
        }

        let normalizedTerm = term?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let filter = (normalizedTerm?.isEmpty ?? true) ? nil : normalizedTerm

        var lines = ["Scripting dictionary: \(Self.clean(appName, limit: 80)) (\(definition.lastPathComponent))"]
        if !state.notes.isEmpty {
            lines.append("Notes:")
            lines += state.notes.map { "- \($0)" }
        }

        var rendered = 0
        for suite in Self.collectSuites(from: document.rootElement()) {
            let block = Self.renderSuite(suite, filter: filter)
            if block.isEmpty { continue }
            lines.append("")
            lines += block
            rendered += 1
        }
        if rendered == 0 {
            lines.append("")
            lines.append(filter == nil ? "No commands or classes found." : "No commands or classes match the term.")
        }

        let full = lines.joined(separator: "\n")
        if full.count > Self.maximumSummaryCharacters {
            return String(full.prefix(Self.maximumSummaryCharacters)) + "\n" + Self.truncationSuffix
        }
        return full
    }

    // MARK: - Locating the definition file

    /// The definition file named by `OSAScriptingDefinition` (an extension-less value gets `.sdef`), else the first
    /// `.sdef` directly inside `Contents/Resources`. Nil when the bundle has none.
    static func definitionURL(appBundleURL: URL) throws -> URL? {
        guard let bundleRoot = realPath(appBundleURL.path) else {
            throw ScriptingDictionaryLookupError.appNotFound(appBundleURL.path)
        }
        let resources = appBundleURL.appendingPathComponent("Contents/Resources", isDirectory: true)

        if var name = declaredDefinitionName(appBundleURL: appBundleURL), !name.isEmpty {
            if (name as NSString).pathExtension.isEmpty {
                name += ".sdef"
            }
            let candidate = resources.appendingPathComponent(name).path
            if let resolved = realPath(candidate) {
                guard resolved.hasPrefix(bundleRoot + "/") else {
                    throw ScriptingDictionaryLookupError.definitionOutsideBundle(name)
                }
                return URL(fileURLWithPath: resolved)
            }
        }

        let entries = (try? FileManager.default.contentsOfDirectory(atPath: resources.path)) ?? []
        for entry in entries.filter({ $0.hasSuffix(".sdef") }).sorted() {
            guard let resolved = realPath(resources.appendingPathComponent(entry).path),
                  resolved.hasPrefix(bundleRoot + "/") else { continue }
            var info = stat()
            guard stat(resolved, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { continue }
            return URL(fileURLWithPath: resolved)
        }
        return nil
    }

    private static func declaredDefinitionName(appBundleURL: URL) -> String? {
        let plistURL = appBundleURL.appendingPathComponent("Contents/Info.plist")
        guard let data = try? readDefinitionFile(plistURL, byteLimit: 1024 * 1024),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dictionary = plist as? [String: Any] else {
            return nil
        }
        return dictionary["OSAScriptingDefinition"] as? String
    }

    // MARK: - Reading and parsing

    static func readDefinitionFile(_ url: URL) throws -> Data {
        try readDefinitionFile(url, byteLimit: maximumDefinitionBytes)
    }

    /// Never a URL-based data load: it blocks forever on a FIFO. The descriptor is inspected before any read.
    private static func readDefinitionFile(_ url: URL, byteLimit: Int) throws -> Data {
        let path = url.path
        let descriptor = open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else {
            if errno == ELOOP {
                throw ScriptingDictionaryLookupError.definitionNotRegularFile(path)
            }
            throw ScriptingDictionaryLookupError.malformedDefinition("cannot open definition (errno \(errno))")
        }
        defer { close(descriptor) }

        var info = stat()
        guard fstat(descriptor, &info) == 0 else {
            throw ScriptingDictionaryLookupError.malformedDefinition("cannot inspect definition (errno \(errno))")
        }
        guard (info.st_mode & S_IFMT) == S_IFREG else {
            throw ScriptingDictionaryLookupError.definitionNotRegularFile(path)
        }
        let size = Int(info.st_size)
        guard size <= byteLimit else {
            throw ScriptingDictionaryLookupError.definitionTooLarge(size)
        }

        var buffer = [UInt8](repeating: 0, count: size)
        var filled = 0
        while filled < size {
            let count = buffer.withUnsafeMutableBytes { pointer -> Int in
                guard let base = pointer.baseAddress else { return 0 }
                return read(descriptor, base + filled, size - filled)
            }
            if count > 0 {
                filled += count
            } else if count < 0 && errno == EINTR {
                continue
            } else {
                break
            }
        }
        return Data(buffer[0..<filled])
    }

    /// Only the bytes are handed to the parser, never a URL, with external entities disabled. XInclude processing is
    /// left off; includes are resolved by `expandIncludes`.
    private static func parse(_ data: Data) throws -> XMLDocument {
        do {
            return try XMLDocument(data: data, options: [.nodeLoadExternalEntitiesNever])
        } catch {
            throw ScriptingDictionaryLookupError.malformedDefinition("not a well-formed definition")
        }
    }

    // MARK: - Include resolution

    private struct ExpansionState {
        var loadedBytes: Int
        var notes: [String] = []

        mutating func skip(_ reason: String) {
            guard notes.count < ScriptingDictionaryLookup.maximumNotes else { return }
            notes.append("include skipped: \(reason)")
        }
    }

    /// True when `resolvedPath` (already a real path) is inside the bundle or an allowed include root.
    static func isAllowedIncludePath(_ resolvedPath: String, bundleRoot: String) -> Bool {
        let roots = [bundleRoot] + allowedIncludeRoots
        return roots.contains { root in
            let prefix = root.hasSuffix("/") ? root : root + "/"
            return resolvedPath.hasPrefix(prefix)
        }
    }

    /// Exactly the expressions Apple's definitions use: the whole suite, or the suite's children minus commands
    /// selected by name.
    static func isSupportedXPointer(_ attribute: String) -> Bool {
        let name = "[A-Za-z ]{1,40}"
        let single = "@name = '\(name)'"
        let one = "\\(@name = '\(name)'\\)"
        let pattern = "\\Axpointer\\((?:/dictionary/suite"
            + "|/dictionary/suite/node\\(\\)\\[not\\(self::command and (?:\(single)|\\(\(one)(?: or \(one))*\\))\\)\\])\\)\\z"
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(attribute.startIndex..., in: attribute)
        return expression.firstMatch(in: attribute, options: [], range: range) != nil
    }

    private static func expandIncludes(
        in root: XMLElement,
        directory: String,
        bundleRoot: String,
        depth: Int,
        state: inout ExpansionState
    ) {
        var includes: [XMLElement] = []
        collectIncludes(from: root, into: &includes)

        for (position, include) in includes.enumerated() {
            if position == maximumIncludesPerDocument {
                state.skip("more than \(maximumIncludesPerDocument) includes in one document")
            }
            if position >= maximumIncludesPerDocument {
                include.detach()
                continue
            }
            guard let parent = include.parent as? XMLElement else {
                include.detach()
                continue
            }
            let index = include.index
            let replacement = resolveInclude(
                include,
                directory: directory,
                bundleRoot: bundleRoot,
                depth: depth,
                state: &state
            )
            include.detach()
            for (offset, node) in replacement.enumerated() {
                parent.insertChild(node, at: index + offset)
            }
        }
    }

    private static func collectIncludes(from element: XMLElement, into result: inout [XMLElement]) {
        for child in element.children ?? [] {
            guard let childElement = child as? XMLElement else { continue }
            if childElement.localName == "include",
               let namespace = childElement.uri,
               includeNamespaces.contains(namespace) {
                result.append(childElement)
            } else {
                collectIncludes(from: childElement, into: &result)
            }
        }
    }

    /// Returns the nodes that replace `include`, or nothing after recording why it was skipped.
    private static func resolveInclude(
        _ include: XMLElement,
        directory: String,
        bundleRoot: String,
        depth: Int,
        state: inout ExpansionState
    ) -> [XMLNode] {
        guard depth + 1 <= maximumIncludeDepth else {
            state.skip("nesting deeper than \(maximumIncludeDepth) levels")
            return []
        }
        if let parse = include.attribute(forName: "parse")?.stringValue, parse != "xml" {
            state.skip("only xml includes are supported")
            return []
        }
        guard let href = include.attribute(forName: "href")?.stringValue,
              !href.isEmpty, !href.contains("\0") else {
            state.skip("missing or invalid href")
            return []
        }
        guard let targetPath = includeTargetPath(href: href, directory: directory) else {
            state.skip("only file includes are supported")
            return []
        }
        guard let resolved = realPath(targetPath) else {
            state.skip("target not found")
            return []
        }
        guard isAllowedIncludePath(resolved, bundleRoot: bundleRoot) else {
            state.skip("target is outside the app bundle and the system definitions")
            return []
        }

        let data: Data
        do {
            data = try readDefinitionFile(URL(fileURLWithPath: resolved))
        } catch let error as ScriptingDictionaryLookupError {
            switch error {
            case .definitionTooLarge: state.skip("target is too large")
            case .definitionNotRegularFile: state.skip("target is not a regular file")
            default: state.skip("target is unreadable")
            }
            return []
        } catch {
            state.skip("target is unreadable")
            return []
        }
        guard state.loadedBytes + data.count <= maximumExpandedBytes else {
            state.skip("total included size limit reached")
            return []
        }
        state.loadedBytes += data.count

        guard let document = try? parse(data), let includedRoot = document.rootElement() else {
            state.skip("target is not well-formed")
            return []
        }
        expandIncludes(
            in: includedRoot,
            directory: (resolved as NSString).deletingLastPathComponent,
            bundleRoot: bundleRoot,
            depth: depth + 1,
            state: &state
        )

        let selected: [XMLNode]
        if let pointer = include.attribute(forName: "xpointer")?.stringValue {
            guard isSupportedXPointer(pointer) else {
                state.skip("unsupported xpointer")
                return []
            }
            let expression = String(pointer.dropFirst("xpointer(".count).dropLast())
            guard let matches = try? document.nodes(forXPath: expression) else {
                state.skip("xpointer could not be evaluated")
                return []
            }
            selected = matches
        } else {
            selected = includedRoot.children ?? []
        }
        return selected.compactMap { $0.copy() as? XMLNode }
    }

    /// A `file:` URL (empty or `localhost` host) or a relative path becomes an absolute path; any other scheme is nil.
    private static func includeTargetPath(href: String, directory: String) -> String? {
        if let url = URL(string: href), let scheme = url.scheme {
            guard scheme.lowercased() == "file" else { return nil }
            guard let host = url.host, !host.isEmpty, host.lowercased() != "localhost" else {
                return url.path.isEmpty ? nil : url.path
            }
            return nil
        }
        let decoded = href.removingPercentEncoding ?? href
        return decoded.hasPrefix("/") ? decoded : directory + "/" + decoded
    }

    // MARK: - Rendering

    private static func collectSuites(from element: XMLElement?) -> [XMLElement] {
        guard let element else { return [] }
        var suites: [XMLElement] = []
        for child in element.children ?? [] {
            guard let childElement = child as? XMLElement else { continue }
            if childElement.name == "suite" {
                suites.append(childElement)
            }
            suites += collectSuites(from: childElement)
        }
        return suites
    }

    private static func renderSuite(_ suite: XMLElement, filter: String?) -> [String] {
        var commandLines: [String] = []
        var classLines: [String] = []

        for child in suite.children ?? [] {
            guard let element = child as? XMLElement else { continue }
            switch element.name {
            case "command":
                if let lines = renderCommand(element, filter: filter) { commandLines += lines }
            case "class", "class-extension":
                if let lines = renderClass(element, filter: filter) { classLines += lines }
            default:
                continue
            }
        }
        if commandLines.isEmpty && classLines.isEmpty { return [] }

        var lines = ["Suite: " + labelled(suite.attribute(forName: "name")?.stringValue, suite)]
        if !commandLines.isEmpty {
            lines.append("  Commands:")
            lines += commandLines
        }
        if !classLines.isEmpty {
            lines.append("  Classes:")
            lines += classLines
        }
        return lines
    }

    private static func renderCommand(_ command: XMLElement, filter: String?) -> [String]? {
        let name = clean(command.attribute(forName: "name")?.stringValue ?? "", limit: 80)
        let description = clean(command.attribute(forName: "description")?.stringValue ?? "")
        guard !name.isEmpty, matches(filter, name, description) else { return nil }

        var line = "    \(name)"
        if !description.isEmpty { line += " - \(description)" }
        var lines = [line]

        for child in command.children ?? [] {
            guard let element = child as? XMLElement else { continue }
            if element.name == "direct-parameter" {
                let type = typeText(of: element)
                lines.append("      direct parameter: \(type.isEmpty ? "any" : type)")
            } else if element.name == "parameter" {
                let parameterName = clean(element.attribute(forName: "name")?.stringValue ?? "", limit: 80)
                guard !parameterName.isEmpty else { continue }
                let optional = element.attribute(forName: "optional")?.stringValue == "yes" ? " (optional)" : ""
                lines.append("      parameter \(parameterName): \(typeText(of: element))\(optional)")
            }
        }
        return lines
    }

    private static func renderClass(_ classElement: XMLElement, filter: String?) -> [String]? {
        let rawName = classElement.attribute(forName: "name")?.stringValue
            ?? classElement.attribute(forName: "extends")?.stringValue ?? ""
        let name = clean(rawName, limit: 80)
        let description = clean(classElement.attribute(forName: "description")?.stringValue ?? "")
        guard !name.isEmpty, matches(filter, name, description) else { return nil }

        var line = "    \(name)"
        if !description.isEmpty { line += " - \(description)" }
        var lines = [line]

        var properties: [String] = []
        var elements: [String] = []
        for child in classElement.children ?? [] {
            guard let element = child as? XMLElement else { continue }
            if element.name == "property" {
                let propertyName = clean(element.attribute(forName: "name")?.stringValue ?? "", limit: 80)
                if !propertyName.isEmpty { properties.append("\(propertyName):\(typeText(of: element))") }
            } else if element.name == "element" {
                let type = clean(element.attribute(forName: "type")?.stringValue ?? "", limit: 80)
                if !type.isEmpty { elements.append(type) }
            }
        }
        if !properties.isEmpty { lines.append("      properties: " + properties.joined(separator: ", ")) }
        if !elements.isEmpty { lines.append("      elements: " + elements.joined(separator: ", ")) }
        return lines
    }

    private static func typeText(of element: XMLElement) -> String {
        if let type = element.attribute(forName: "type")?.stringValue {
            return clean(type, limit: 80)
        }
        let types: [String] = (element.children ?? []).compactMap { child in
            guard let typeElement = child as? XMLElement, typeElement.name == "type",
                  let type = typeElement.attribute(forName: "type")?.stringValue else { return nil }
            let text = clean(type, limit: 80)
            return typeElement.attribute(forName: "list")?.stringValue == "yes" ? "list of \(text)" : text
        }
        return types.joined(separator: " | ")
    }

    private static func labelled(_ name: String?, _ element: XMLElement) -> String {
        let text = clean(name ?? "(unnamed)", limit: 80)
        let description = clean(element.attribute(forName: "description")?.stringValue ?? "")
        return description.isEmpty ? text : "\(text) - \(description)"
    }

    private static func matches(_ filter: String?, _ name: String, _ description: String) -> Bool {
        guard let filter else { return true }
        return name.lowercased().contains(filter) || description.lowercased().contains(filter)
    }

    /// Definition text is app-controlled and reaches the agent's context: control characters and line breaks become
    /// single spaces and each value is length-capped.
    private static func clean(_ text: String, limit: Int = maximumDescriptionCharacters) -> String {
        var result = ""
        var pendingSpace = false
        for scalar in text.unicodeScalars {
            let isControl = scalar.properties.generalCategory == .control
                || scalar.properties.generalCategory == .lineSeparator
                || scalar.properties.generalCategory == .paragraphSeparator
                || scalar.properties.isWhitespace
            if isControl {
                pendingSpace = !result.isEmpty
                continue
            }
            if pendingSpace {
                result.append(" ")
                pendingSpace = false
            }
            result.unicodeScalars.append(scalar)
            if result.count >= limit { break }
        }
        return result
    }

    // MARK: - App lookup

    /// A running app whose name or bundle id matches, else the app LaunchServices maps that bundle id to, else a
    /// standard install location. Nil when nothing matches.
    public static func locateAppBundle(_ query: String) -> URL? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lowered = trimmed.lowercased()

        for app in NSWorkspace.shared.runningApplications {
            guard let bundleURL = app.bundleURL else { continue }
            if app.localizedName?.lowercased() == lowered || app.bundleIdentifier?.lowercased() == lowered {
                return bundleURL
            }
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: trimmed) {
            return url
        }
        guard !trimmed.contains("/") else { return nil }
        for directory in ["/Applications", "/System/Applications", "/System/Applications/Utilities"] {
            let path = "\(directory)/\(trimmed).app"
            if FileManager.default.fileExists(atPath: path) {
                return URL(fileURLWithPath: path, isDirectory: true)
            }
        }
        return nil
    }

    // MARK: - Paths

    private static func realPath(_ path: String) -> String? {
        guard let resolved = realpath(path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }
}
