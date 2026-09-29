import ApplicationServices
import CoreGraphics
import Foundation

// MARK: - Index allocation

/// Hands out element indices for `find_elements` hits. They start far above any index a full tree assigns and only
/// grow within a process, so a hit never reuses an index a cached snapshot already holds, and a stale index does not
/// silently name a newer hit.
///
/// Residuals: after an agent restart the counter is re-seeded from the clock, so an index kept from before the
/// restart is unlikely, not impossible, to name a new element; and hit indices stay above full-tree indices only
/// while a full tree stays below `base` plus the seed offset.
final class ElementSearchIndexAllocator: @unchecked Sendable {
    static let base = 1_000_000

    /// Seeded per process so indices from a previous agent process rarely collide with this one's.
    static let shared = ElementSearchIndexAllocator(
        initialNext: base + (Int(Date().timeIntervalSince1970) % 100_000) * 100
    )

    private let lock = NSLock()
    private var next: Int

    init(initialNext: Int) {
        next = initialNext
    }

    /// `count` consecutive indices, all above `existingMaximum` and above every index handed out before.
    func allocate(count: Int, above existingMaximum: Int?) -> [Int] {
        guard count > 0 else {
            return []
        }

        lock.lock()
        defer { lock.unlock() }
        let start = max(next, Self.base, (existingMaximum ?? 0) + 1)
        next = start + count
        return Array(start..<(start + count))
    }
}

// MARK: - Snapshot merge

typealias ElementSearchWindowInfo = (
    windowID: CGWindowID?, layer: Int?, bounds: CGRect?, title: String?, focusedElement: AXUIElement?
)

/// Hits can join a cached snapshot only when it describes the same window in the same place: their frames are
/// converted with the cached snapshot's window bounds.
func canMergeElementSearchHits(into cached: AppSnapshot?, window: ElementSearchWindowInfo) -> Bool {
    guard let cached,
          cached.mode == .accessibility,
          let cachedWindowID = cached.targetWindowID,
          let cachedBounds = cached.windowBounds,
          let windowBounds = window.bounds
    else {
        return false
    }

    return cachedWindowID == window.windowID && cachedBounds == windowBounds
}

/// The snapshot to cache after a search: the cached one plus the hits when that is safe, else a snapshot holding
/// only the hits (with the focused element, so `type_text` does not fall back to activating the app).
func mergeElementSearchHits(
    _ hits: [ElementRecord],
    rows: [String],
    into cached: AppSnapshot?,
    window: ElementSearchWindowInfo,
    app: RunningAppDescriptor
) -> AppSnapshot {
    let hitsByIndex = Dictionary(hits.map { ($0.index, $0) }, uniquingKeysWith: { _, latest in latest })

    if let cached, canMergeElementSearchHits(into: cached, window: window) {
        return AppSnapshot(
            app: cached.app,
            windowTitle: cached.windowTitle,
            windowBounds: cached.windowBounds,
            targetWindowID: cached.targetWindowID,
            targetWindowLayer: cached.targetWindowLayer,
            screenshotPNGData: cached.screenshotPNGData,
            mode: cached.mode,
            treeLines: cached.treeLines,
            treeLineOffsets: cached.treeLineOffsets,
            focusedSummary: cached.focusedSummary,
            focusedElement: cached.focusedElement,
            selectedText: cached.selectedText,
            elements: cached.elements.merging(hitsByIndex, uniquingKeysWith: { _, hit in hit })
        )
    }

    return AppSnapshot(
        app: app,
        windowTitle: window.title,
        windowBounds: window.bounds,
        targetWindowID: window.windowID,
        targetWindowLayer: window.layer,
        screenshotPNGData: nil,
        mode: .accessibility,
        treeLines: rows,
        treeLineOffsets: [:],
        focusedSummary: nil,
        focusedElement: window.focusedElement,
        selectedText: nil,
        elements: hitsByIndex
    )
}

/// The keys a snapshot is cached under: the query, the app name and the bundle identifier, lowercased, empties
/// dropped. Matches the keys a full refresh writes, so both paths resolve the same lookups.
func snapshotCacheKeys(query: String, app: RunningAppDescriptor) -> Set<String> {
    Set(
        [query.lowercased(), app.name.lowercased(), (app.bundleIdentifier ?? "").lowercased()]
            .filter { !$0.isEmpty }
    )
}

// MARK: - Row rendering

/// Accessibility text is attacker-influenced (page titles, email subjects), so it is made single-line and unable to
/// close the quoted label: backslashes, quotes and every line-breaking character are escaped and the length is
/// capped by `sanitizeText`.
func escapeElementSearchText(_ value: String) -> String {
    var escaped = sanitizeText(value.replacingOccurrences(of: "\\", with: "\\\\"))
    let replacements: [(String, String)] = [
        ("\r", "\\r"),
        ("\u{0B}", "\\u000b"),
        ("\u{0C}", "\\u000c"),
        ("\u{85}", "\\u0085"),
        ("\u{2028}", "\\u2028"),
        ("\u{2029}", "\\u2029"),
        ("\"", "\\\""),
    ]
    for (character, replacement) in replacements {
        escaped = escaped.replacingOccurrences(of: character, with: replacement)
    }
    return escaped
}

/// Same `x=<Int>, y=<Int>, w=<Int>, h=<Int>` text the full snapshot prints for an element frame.
func elementSearchRenderedFrame(_ frame: CGRect) -> String {
    "x=\(Int(frame.origin.x)), y=\(Int(frame.origin.y)), w=\(Int(frame.width)), h=\(Int(frame.height))"
}

/// `[<index>] <role> "<label>" id=<identifier> frame=<frame> actions=<actions>`, omitting empty parts.
func renderElementSearchRow(
    index: Int,
    attributes: ElementSearchNodeAttributes,
    localFrame: CGRect?,
    prettyActions: [String]
) -> String {
    var parts = ["[\(index)]"]
    if let role = attributes.role, !role.isEmpty {
        parts.append(escapeElementSearchText(role))
    }
    if let label = attributes.title ?? attributes.description, !label.isEmpty {
        parts.append("\"\(escapeElementSearchText(label))\"")
    }
    if let identifier = attributes.identifier, !identifier.isEmpty {
        parts.append("id=\(escapeElementSearchText(identifier))")
    }
    if let localFrame {
        parts.append("frame=\(elementSearchRenderedFrame(localFrame))")
    }
    if !prettyActions.isEmpty {
        parts.append("actions=\(prettyActions.map(escapeElementSearchText).joined(separator: ", "))")
    }
    return parts.joined(separator: " ")
}
