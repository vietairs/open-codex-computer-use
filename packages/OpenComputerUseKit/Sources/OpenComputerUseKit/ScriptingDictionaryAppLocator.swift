import AppKit
import Foundation

/// Finds the `.app` bundle a `get_scripting_dictionary` query names, among running apps first, then by bundle id and
/// standard install locations. Kept apart from the definition parser, which never touches running processes.
extension ScriptingDictionaryLookup {
    /// The best running `.app` whose name or bundle id matches (see `bestRunningMatch`), else the app LaunchServices maps that bundle id to, else a
    /// standard install location. Nil when nothing matches.
    public static func locateAppBundle(_ query: String) -> URL? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let candidates = NSWorkspace.shared.runningApplications.map {
            RunningAppCandidate(
                name: $0.localizedName,
                bundleIdentifier: $0.bundleIdentifier,
                bundleURL: $0.bundleURL,
                activationPolicy: $0.activationPolicy,
                isTerminated: $0.isTerminated
            )
        }
        if let url = bestRunningMatch(trimmed, among: candidates) {
            return url
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

    /// The fields of a running app the name lookup reads, split from `NSRunningApplication` so the ranking is
    /// testable without real processes.
    struct RunningAppCandidate: Equatable {
        var name: String?
        var bundleIdentifier: String?
        var bundleURL: URL?
        var activationPolicy: NSApplication.ActivationPolicy
        var isTerminated: Bool
    }

    /// The `.app` bundle of the running app that best matches `query` by name or bundle id, case-insensitively.
    ///
    /// Several processes can share one name (Messages runs both `Messages.app` and an `.appex` assistant extension),
    /// so every match is ranked instead of taking the first: live `.app` bundles only, an exact bundle-id match before
    /// a name match, then regular before accessory before background-only apps, then enumeration order. Background-only
    /// apps stay eligible, because apps such as System Events are scriptable and have no regular window.
    static func bestRunningMatch(_ query: String, among candidates: [RunningAppCandidate]) -> URL? {
        let lowered = query.lowercased()
        var best: (rank: (Int, Int), url: URL)?
        for candidate in candidates {
            guard !candidate.isTerminated,
                  let bundleURL = candidate.bundleURL,
                  bundleURL.pathExtension.lowercased() == "app"
            else { continue }
            let bundleIdentifierMatches = candidate.bundleIdentifier?.lowercased() == lowered
            guard bundleIdentifierMatches || candidate.name?.lowercased() == lowered else { continue }
            let rank = (bundleIdentifierMatches ? 0 : 1, policyRank(candidate.activationPolicy))
            if best.map({ rank < $0.rank }) ?? true {
                best = (rank, bundleURL)
            }
        }
        return best?.url
    }

    private static func policyRank(_ policy: NSApplication.ActivationPolicy) -> Int {
        switch policy {
        case .regular: return 0
        case .accessory: return 1
        case .prohibited: return 2
        @unknown default: return 3
        }
    }
}
