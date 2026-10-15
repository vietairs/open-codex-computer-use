import ApplicationServices
import CoreGraphics
import Darwin
import Foundation

/// Chromium-derived engines (Chrome, Electron, CEF hosts) build their web accessibility tree only after the first
/// accessibility request, which can take Chrome about two seconds, and drop it while their window is hidden. A
/// snapshot of such a window waits briefly for the web area while the window is visible, and says why it is missing
/// while the window is hidden.

/// What a snapshot does about a missing web area.
enum LazyWebRewalkDecision: Equatable {
    case none
    /// Wait for the web area and walk the window again.
    case rewalk
    /// The window is hidden from its app, so the web content is not there to wait for; say so in the result.
    case hiddenNote
}

/// Pure. `waitAllowed` is true only for `get_app_state`: an action's result never waits. `exhausted` is true for a
/// window that already used up a wait without producing a web area, so it does not cost every snapshot again.
func lazyWebRewalkDecision(
    lazyWeb: Bool,
    hasWebArea: Bool,
    visibleNow: Bool,
    waitAllowed: Bool,
    exhausted: Bool
) -> LazyWebRewalkDecision {
    guard lazyWeb, !hasWebArea else {
        return .none
    }
    guard visibleNow else {
        return .hiddenNote
    }
    return waitAllowed && !exhausted ? .rewalk : .none
}

/// The note for a lazy web window whose content is hidden. The second sentence holds only where the keep-alive can
/// pin windows.
func hiddenWebContentNote(keepAliveAvailable: Bool) -> String {
    let base = "Note: this window is covered, minimized or on another Space, so the app hides its web content and it is "
        + "not in the tree."
    if keepAliveAvailable {
        return base + " Bring the window into view once; covering it afterwards keeps working."
    }
    return base + " Bring the window into view to read it."
}

/// How long and how widely a snapshot looks for a web area that is still being built.
struct LazyWebWaitLimits: Equatable {
    var timeBudget: TimeInterval
    var pollInterval: TimeInterval
    /// Bounds for each shallow probe: it reads only roles and children, not the full tree.
    var probeMaxDepth: Int
    var probeMaxNodes: Int

    static let standard = LazyWebWaitLimits(timeBudget: 2.0, pollInterval: 0.1, probeMaxDepth: 10, probeMaxNodes: 400)
}

/// Pure. Breadth-first search for a web-area role, bounded by depth, node count and a deadline.
func treeContainsWebArea<Element>(
    root: Element,
    maxDepth: Int,
    maxNodes: Int,
    deadline: TimeInterval,
    now: () -> TimeInterval,
    isWebArea: (Element) -> Bool,
    children: (Element) -> [Element]
) -> Bool {
    var queue: [(element: Element, depth: Int)] = [(root, 0)]
    var head = 0
    while head < queue.count, head < maxNodes, now() <= deadline {
        let (element, depth) = queue[head]
        head += 1
        if isWebArea(element) {
            return true
        }
        if depth < maxDepth {
            queue.append(contentsOf: children(element).map { ($0, depth + 1) })
        }
    }
    return false
}

/// Pure. Polls `probe` until it answers true or the budget runs out. Returns whether it did.
func waitForLazyWebArea(
    limits: LazyWebWaitLimits,
    now: () -> TimeInterval,
    sleep: (TimeInterval) -> Void,
    probe: (_ deadline: TimeInterval) -> Bool
) -> Bool {
    let deadline = now() + limits.timeBudget
    while now() < deadline {
        sleep(limits.pollInterval)
        if probe(deadline) {
            return true
        }
    }
    return false
}

/// Live shallow probe of a window for an `AXWebArea`, with a short per-element messaging timeout so a busy app
/// cannot stretch the wait.
func liveWindowContainsWebArea(_ window: AXUIElement, limits: LazyWebWaitLimits, deadline: TimeInterval) -> Bool {
    let messagingTimeout: Float = 0.25
    // The snapshot reuses the window element after the probe; give it back the default timeout so a slow read just
    // after the web tree appears is not cut short.
    defer {
        AXUIElementSetMessagingTimeout(window, 0)
    }
    func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value
    }
    return treeContainsWebArea(
        root: window,
        maxDepth: limits.probeMaxDepth,
        maxNodes: limits.probeMaxNodes,
        deadline: deadline,
        now: { ProcessInfo.processInfo.systemUptime },
        isWebArea: { copy($0, kAXRoleAttribute) as? String == "AXWebArea" },
        children: { element in
            (copy(element, kAXChildrenAttribute) as? [AnyObject] ?? []).compactMap { skyLightAccessibilityElement($0) }
        }
    )
}

/// Windows that used up a wait without producing a web area, so later snapshots of them do not wait again. Process
/// wide and bounded: it is cleared when it grows past `capacity`.
final class LazyWebExhaustedWindows: @unchecked Sendable {
    static let shared = LazyWebExhaustedWindows()

    private let lock = NSLock()
    private var windowIDs: Set<CGWindowID> = []
    private let capacity: Int

    init(capacity: Int = 256) {
        self.capacity = capacity
    }

    func contains(_ windowID: CGWindowID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return windowIDs.contains(windowID)
    }

    func insert(_ windowID: CGWindowID) {
        lock.lock()
        defer { lock.unlock() }
        if windowIDs.count >= capacity {
            windowIDs.removeAll()
        }
        windowIDs.insert(windowID)
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return windowIDs.count
    }
}

/// Pure. Whether the app bundle ships a Chromium, Electron or CEF engine, judged by the names in its
/// `Contents/Frameworks` (not a bundle-identifier list).
func frameworkNamesIndicateLazyWebEngine(_ names: [String]) -> Bool {
    names.contains { name in
        let lowered = name.lowercased()
        return lowered.contains("chrom") || lowered.contains("electron") || lowered.contains("cef")
    }
}

/// Pure. Only bundles under these roots have their frameworks listed. Listing a bundle in Downloads, Desktop,
/// Documents or on a removable volume can raise a privacy prompt under the agent's identity, and a grant there would
/// persist for the agent; such apps rely on the `AXManualAccessibility` answer instead. A symbolic link anywhere below
/// the root on the way to `Contents/Frameworks` (an `/Applications` entry pointing into Downloads, say) makes the
/// bundle untrusted. `isSymbolicLink` is asked for each of those paths in order, stopping at the first link, so only
/// paths inside the trusted root are ever examined.
func bundleIsUnderTrustedRoot(_ bundleURL: URL, roots: [String], isSymbolicLink: (String) -> Bool) -> Bool {
    let path = bundleURL.standardizedFileURL.path
    guard let rootPrefix = roots.map({ $0.hasSuffix("/") ? $0 : $0 + "/" }).first(where: { path.hasPrefix($0) }) else {
        return false
    }
    var current = String(rootPrefix.dropLast())
    for component in (path.dropFirst(rootPrefix.count) + "/Contents/Frameworks").split(separator: "/") {
        current += "/" + component
        if isSymbolicLink(current) {
            return false
        }
    }
    return true
}

/// Whether `path` is a symbolic link, read with `lstat` so the link is never followed. A path that cannot be read
/// counts as a link: the caller then treats the bundle as untrusted, which only skips a framework listing.
func pathIsSymbolicLinkOrUnreadable(_ path: String) -> Bool {
    var status = stat()
    guard lstat(path, &status) == 0 else {
        return true
    }
    return (status.st_mode & S_IFMT) == S_IFLNK
}

func lazyWebProbeTrustedRoots() -> [String] {
    ["/Applications", "/System/Applications", FileManager.default.homeDirectoryForCurrentUser.path + "/Applications"]
}

/// Whether the app at `bundleURL` ships a lazy web engine, read once per bundle path.
final class LazyWebEngineDetector: @unchecked Sendable {
    static let shared = LazyWebEngineDetector(trustedRoots: lazyWebProbeTrustedRoots())

    private let trustedRoots: [String]
    private let lock = NSLock()
    private var cache: [String: Bool] = [:]

    init(trustedRoots: [String]) {
        self.trustedRoots = trustedRoots
    }

    func appHasLazyWebAccessibility(bundleURL: URL?) -> Bool {
        guard let bundleURL else {
            return false
        }
        let key = bundleURL.standardizedFileURL.path
        lock.lock()
        if let cached = cache[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        guard bundleIsUnderTrustedRoot(bundleURL, roots: trustedRoots, isSymbolicLink: pathIsSymbolicLinkOrUnreadable) else {
            return false
        }

        let frameworks = bundleURL.appendingPathComponent("Contents/Frameworks", isDirectory: true)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: frameworks.path)) ?? []
        let result = frameworkNamesIndicateLazyWebEngine(names)

        lock.lock()
        cache[key] = result
        lock.unlock()
        return result
    }
}
