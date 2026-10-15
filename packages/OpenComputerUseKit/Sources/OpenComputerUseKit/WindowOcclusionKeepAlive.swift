import AppKit
import CoreGraphics
import Darwin
import Foundation

/// Pure. True when every coordinate of `rect` is finite.
func rectIsFinite(_ rect: CGRect) -> Bool {
    rect.origin.x.isFinite && rect.origin.y.isFinite && rect.size.width.isFinite && rect.size.height.isFinite
}

/// Pure. True when every coordinate of `rect` is finite and it has a positive size.
func rectIsFiniteAndNonEmpty(_ rect: CGRect) -> Bool {
    rectIsFinite(rect) && rect.size.width > 0 && rect.size.height > 0
}

/// Pure. Samples a grid over `bounds`; the window looks unoccluded when at least one sample point is outside every
/// covering window. Close enough to Chromium's own occlusion check to decide whether pinning the visible state is
/// safe: pinning a window that is already occluded would freeze its page hidden.
///
/// Fails closed on bad geometry: empty or non-finite bounds are never unoccluded, and a non-finite covering rect
/// means the cover cannot be judged, so the answer is false. Nothing here converts a coordinate to an integer.
func windowLooksUnoccluded(bounds: CGRect, coveringBounds: [CGRect], grid: Int = 16) -> Bool {
    guard rectIsFiniteAndNonEmpty(bounds), grid > 0 else {
        return false
    }
    guard coveringBounds.allSatisfy(rectIsFinite) else {
        return false
    }
    let cells = CGFloat(grid)
    for row in 0..<grid {
        for column in 0..<grid {
            let point = CGPoint(
                x: bounds.minX + bounds.width * (CGFloat(column) + 0.5) / cells,
                y: bounds.minY + bounds.height * (CGFloat(row) + 0.5) / cells
            )
            if !coveringBounds.contains(where: { $0.contains(point) }) {
                return true
            }
        }
    }
    return false
}

/// Layer-0 windows of other processes ordered above `windowID` on screen. This process's own windows (the visual
/// cursor overlay) do not count as cover.
func coveringWindowBounds(above windowID: CGWindowID) -> [CGRect] {
    let infoList = CGWindowListCopyWindowInfo(
        [.optionOnScreenAboveWindow, .excludeDesktopElements],
        windowID
    ) as? [[String: Any]] ?? []
    let ownPID = ProcessInfo.processInfo.processIdentifier
    return infoList.compactMap { info in
        guard
            let ownerPID = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value, ownerPID != ownPID,
            (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
            let boundsDictionary = info[kCGWindowBounds as String] as? NSDictionary,
            let bounds = CGRect(dictionaryRepresentation: boundsDictionary)
        else {
            return nil
        }
        return bounds
    }
}

/// The live reads behind `windowIsVisibleToItsApp`, each made only when the checks before it passed.
struct WindowVisibilityProbes {
    var isMinimized: () -> Bool
    var appIsHidden: () -> Bool
    var sessionIsUnlocked: () -> Bool
    /// Nil when the Space of the window or the current Space cannot be read.
    var isOnCurrentSpace: () -> Bool?
    var coveringBounds: () -> [CGRect]
}

/// Pure. Whether the window's own app currently sees it as visible, which is the only state the keep-alive may pin.
/// Every unknown answers false: a window pinned while hidden stays hidden to its app until the pin is released.
/// Windows on another Desktop still report themselves on screen, so the Space check is required.
func windowIsVisibleToItsApp(
    bounds: CGRect,
    isOnscreen: Bool,
    isOffStage: Bool,
    probes: WindowVisibilityProbes
) -> Bool {
    guard isOnscreen, !isOffStage, rectIsFiniteAndNonEmpty(bounds) else {
        return false
    }
    guard !probes.isMinimized(), !probes.appIsHidden(), probes.sessionIsUnlocked() else {
        return false
    }
    guard probes.isOnCurrentSpace() == true else {
        return false
    }
    return windowLooksUnoccluded(bounds: bounds, coveringBounds: probes.coveringBounds())
}

/// The window-server owner of `windowID`, or nil when the window no longer exists.
func liveWindowOwnerPID(_ windowID: CGWindowID) -> pid_t? {
    let infoList = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
    for info in infoList where (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value == windowID {
        return (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
    }
    return nil
}

/// Keeps a window "visible" from its own app's point of view while the agent works on it in the background.
///
/// Apps learn that a window is covered only through WindowServer occlusion notifications
/// (`NSWindow.occlusionState`). Web engines react by hiding the page: Chromium, Electron and WebKit drop the web
/// accessibility subtree and stop rendering. Turning those notifications off for one window while it is visible pins
/// the app's notion at "visible", so covering the window later or switching to another Space no longer hides its
/// content. Nothing here activates, raises or moves a window, and it cannot bring back a window that is already
/// hidden when the agent first sees it.
///
/// Pins belong to owners (one per `ComputerUseService`, so one per host session of the shared agent) and are
/// reference counted per window: a session that ends releases only its own pins. Every pin is written to a
/// per-process journal before the WindowServer call, so a later process can turn notifications back on for windows a
/// killed process left pinned. Pins are released at session end, process exit (atexit, SIGTERM, SIGINT, SIGHUP,
/// `applicationWillTerminate`) and when the screen locks.
final class WindowOcclusionKeepAlive: @unchecked Sendable {
    static let shared = WindowOcclusionKeepAlive(installsProcessHooks: true)

    private struct Pin {
        let ownerPID: pid_t
        var owners: Set<UUID>
    }

    private let control: WindowOcclusionControlling
    private let journal: OcclusionRestoreJournaling
    private let sessionState: MacSessionStateProvider
    private let windowOwnerPID: (CGWindowID) -> pid_t?
    private let installsProcessHooks: Bool

    private let lock = NSLock()
    private var pins: [CGWindowID: Pin] = [:]
    /// Windows whose restore failed; retried at every release, dropped once the window is gone.
    private var failedRestores: [CGWindowID: pid_t] = [:]
    private var abandonedJournalsRecovered = false
    private var processHooksInstalled = false

    init(
        control: WindowOcclusionControlling = SkyLightWindowServerSPI.shared,
        journal: OcclusionRestoreJournaling = FileOcclusionRestoreJournal(),
        sessionState: MacSessionStateProvider = SystemMacSessionStateProvider(),
        windowOwnerPID: @escaping (CGWindowID) -> pid_t? = liveWindowOwnerPID,
        installsProcessHooks: Bool = false
    ) {
        self.control = control
        self.journal = journal
        self.sessionState = sessionState
        self.windowOwnerPID = windowOwnerPID
        self.installsProcessHooks = installsProcessHooks
    }

    var isAvailable: Bool {
        control.occlusionAvailability.isAvailable
    }

    /// Adds `owner` to an existing pin. True when the window was already pinned by this process.
    func retainExistingPin(windowID: CGWindowID, owner: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if pins[windowID] != nil {
            pins[windowID]?.owners.insert(owner)
            return true
        }
        return false
    }

    /// Pins a window the caller found visible to its app (see `windowIsVisibleToItsApp`). True when this process
    /// holds the pin for `owner` afterwards. Refuses while the session is locked or its state is unknown, when the
    /// journal cannot be written, and when another holder had already turned the window's notifications off.
    @discardableResult
    func pin(windowID: CGWindowID, windowOwnerPID ownerPID: pid_t, owner: UUID) -> Bool {
        guard control.occlusionAvailability.isAvailable,
              sessionIsStrictlyUnlocked(sessionState.currentSnapshot())
        else {
            return false
        }

        lock.lock()
        defer { lock.unlock() }
        recoverAbandonedJournalsLocked()

        if pins[windowID] != nil {
            pins[windowID]?.owners.insert(owner)
            return true
        }
        // Still off from an earlier pin whose restore failed: it is this process's pin again.
        if let failedOwnerPID = failedRestores.removeValue(forKey: windowID) {
            pins[windowID] = Pin(ownerPID: failedOwnerPID, owners: [owner])
            return true
        }

        do {
            try journal.write(journalEntriesLocked() + [OcclusionRestoreEntry(windowID: windowID, ownerPID: ownerPID)])
        } catch {
            logKeepAlive("not pinning window \(windowID): \(describe(error))")
            return false
        }

        let previous: Bool?
        do {
            previous = try control.setWindowOcclusionNotificationsEnabled(false, windowID: windowID)
        } catch {
            logKeepAlive("could not pin window \(windowID): \(describe(error))")
            writeJournalLocked()
            return false
        }

        if previous == false {
            // Another holder had already turned notifications off. Turning them back on is its job, and doing it
            // here could undo that holder's pin.
            writeJournalLocked()
            return false
        }

        pins[windowID] = Pin(ownerPID: ownerPID, owners: [owner])
        installProcessHooksLocked()
        return true
    }

    func isPinned(windowID: CGWindowID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return pins[windowID] != nil
    }

    func pinnedWindowIDs(owner: UUID) -> Set<CGWindowID> {
        lock.lock()
        defer { lock.unlock() }
        return Set(pins.filter { $0.value.owners.contains(owner) }.keys)
    }

    /// Releases `owner`'s pins. A window stays pinned while another owner holds it.
    func release(owner: UUID) {
        lock.lock()
        defer { lock.unlock() }
        let owned = pins.filter { $0.value.owners.contains(owner) }
        guard !owned.isEmpty || !failedRestores.isEmpty else {
            return
        }
        // Earlier failures first, so a restore that fails now is not tried twice in one release.
        retryFailedRestoresLocked()
        for (windowID, pin) in owned {
            var remaining = pin
            remaining.owners.remove(owner)
            if remaining.owners.isEmpty {
                pins.removeValue(forKey: windowID)
                restoreLocked(windowID: windowID, ownerPID: pin.ownerPID)
            } else {
                pins[windowID] = remaining
            }
        }
        writeJournalLocked()
    }

    /// Releases every pin of every owner.
    func releaseAll() {
        lock.lock()
        defer { lock.unlock() }
        guard !pins.isEmpty || !failedRestores.isEmpty else {
            return
        }
        retryFailedRestoresLocked()
        let all = pins
        pins.removeAll()
        for (windowID, pin) in all {
            restoreLocked(windowID: windowID, ownerPID: pin.ownerPID)
        }
        writeJournalLocked()
    }

    /// Final cleanup at process exit: release everything, and remove the journal when nothing is left to restore. A
    /// journal that still lists a failed restore is kept for the next process to retry.
    func finishAtExit() {
        releaseAll()
        lock.lock()
        defer { lock.unlock() }
        if pins.isEmpty, failedRestores.isEmpty {
            journal.discard()
        }
    }

    /// Turns notifications back on for windows that ended processes left pinned, once per process. Runs before the
    /// first pin, and at app launch through `recoverOpenComputerUseBackgroundWindowState`.
    func recoverAbandonedJournals() {
        lock.lock()
        defer { lock.unlock() }
        recoverAbandonedJournalsLocked()
    }

    // MARK: - Locked helpers

    private func recoverAbandonedJournalsLocked() {
        guard !abandonedJournalsRecovered else {
            return
        }
        abandonedJournalsRecovered = true
        guard control.occlusionAvailability.isAvailable else {
            return
        }
        for entry in Set(journal.takeAbandonedEntries()) where pins[entry.windowID] == nil {
            // Only while the same app still owns the window: a reused window id belongs to someone else.
            guard windowOwnerPID(entry.windowID) == entry.ownerPID else {
                continue
            }
            do {
                _ = try control.setWindowOcclusionNotificationsEnabled(true, windowID: entry.windowID)
            } catch {
                logKeepAlive("could not restore window \(entry.windowID) left by an ended process: \(describe(error))")
            }
        }
    }

    private func restoreLocked(windowID: CGWindowID, ownerPID: pid_t) {
        // A window that is gone, or whose id now belongs to another app, needs nothing.
        guard windowOwnerPID(windowID) == ownerPID else {
            failedRestores.removeValue(forKey: windowID)
            return
        }
        do {
            // Always back on: a pin is only kept when the previous state was on or unknown.
            _ = try control.setWindowOcclusionNotificationsEnabled(true, windowID: windowID)
            failedRestores.removeValue(forKey: windowID)
        } catch {
            failedRestores[windowID] = ownerPID
            logKeepAlive("could not restore window \(windowID); will retry: \(describe(error))")
        }
    }

    private func retryFailedRestoresLocked() {
        for (windowID, ownerPID) in failedRestores {
            restoreLocked(windowID: windowID, ownerPID: ownerPID)
        }
    }

    private func journalEntriesLocked() -> [OcclusionRestoreEntry] {
        pins.map { OcclusionRestoreEntry(windowID: $0.key, ownerPID: $0.value.ownerPID) }
            + failedRestores.map { OcclusionRestoreEntry(windowID: $0.key, ownerPID: $0.value) }
    }

    private func writeJournalLocked() {
        do {
            try journal.write(journalEntriesLocked())
        } catch {
            logKeepAlive("could not update the restore journal: \(describe(error))")
        }
    }

    private func installProcessHooksLocked() {
        guard installsProcessHooks, !processHooksInstalled else {
            return
        }
        processHooksInstalled = true
        WindowOcclusionProcessHooks.install()
    }

    private func describe(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    }

    private func logKeepAlive(_ message: String) {
        fputs("[open-computer-use] occlusion keep-alive: \(message)\n", stderr)
    }
}

/// Process-exit and screen-lock hooks for the shared keep-alive, installed once with the first pin.
private enum WindowOcclusionProcessHooks {
    nonisolated(unsafe) private static var signalSources: [DispatchSourceSignal] = []

    static func install() {
        atexit {
            WindowOcclusionKeepAlive.shared.finishAtExit()
        }
        installTerminationSignalHandlers()
        // Distributed notifications arrive on the main run loop: the app runtimes run one; the plain stdio server
        // does not, and there the lock check before every pin is what applies.
        DispatchQueue.main.async {
            _ = DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name("com.apple.screenIsLocked"),
                object: nil,
                queue: nil
            ) { _ in
                WindowOcclusionKeepAlive.shared.releaseAll()
            }
        }
    }

    /// SIGTERM, SIGINT and SIGHUP terminate without running atexit handlers, so each one that still has its default
    /// action releases the pins first and then ends the process with the same signal. A signal the process already
    /// ignores or handles is left alone. The installed handler is an empty function, not SIG_IGN, because an ignored
    /// signal would be inherited by every child process the agent starts.
    private static func installTerminationSignalHandlers() {
        for signalNumber in [SIGTERM, SIGINT, SIGHUP] {
            var current = sigaction()
            guard sigaction(signalNumber, nil, &current) == 0,
                  current.__sigaction_u.__sa_handler.map({ unsafeBitCast($0, to: Int.self) }) ?? 0 == 0
            else {
                continue
            }

            var action = sigaction()
            action.__sigaction_u.__sa_handler = { _ in }
            action.sa_flags = SA_RESTART
            sigemptyset(&action.sa_mask)
            guard sigaction(signalNumber, &action, nil) == 0 else {
                continue
            }

            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .global(qos: .userInitiated))
            source.setEventHandler {
                WindowOcclusionKeepAlive.shared.finishAtExit()
                signal(signalNumber, SIG_DFL)
                kill(getpid(), signalNumber)
            }
            source.resume()
            signalSources.append(source)
        }
    }
}

/// Releases every window pin this process holds. The app runtimes call it from `applicationWillTerminate`.
public func releaseOpenComputerUseBackgroundWindowState() {
    WindowOcclusionKeepAlive.shared.releaseAll()
}

/// Turns occlusion notifications back on for windows that a killed or crashed Open Computer Use process left pinned.
/// The app runtimes call it at launch; the first pin of any process runs it as well.
public func recoverOpenComputerUseBackgroundWindowState() {
    WindowOcclusionKeepAlive.shared.recoverAbandonedJournals()
}
