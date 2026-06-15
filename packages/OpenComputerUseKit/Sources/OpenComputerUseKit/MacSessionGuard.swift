import Foundation
import ApplicationServices

// macOS CGSession lock state keys — verified on macOS 12–15 (Monterey–Sequoia) and macOS 26
// CGSSessionScreenIsLocked: Bool — true when session is locked
// Key absent or dict nil/empty → treat as locked (fail-closed)
let cgSessionScreenIsLockedKey = "CGSSessionScreenIsLocked"

public protocol MacSessionStateProvider {
    func currentSnapshot() -> MacSessionSnapshot
}

public struct MacSessionSnapshot {
    public let isLocked: Bool
    public let isUnknown: Bool   // true when dict was nil/empty/parse-failed
    public let rawKeysSeen: Set<String>

    public init(isLocked: Bool, isUnknown: Bool, rawKeysSeen: Set<String>) {
        self.isLocked = isLocked
        self.isUnknown = isUnknown
        self.rawKeysSeen = rawKeysSeen
    }
}

// TTL for CGSessionCopyCurrentDictionary cache — 200ms balances IPC cost vs responsiveness
private let sessionStateCacheTTL: TimeInterval = 0.200

public final class SystemMacSessionStateProvider: MacSessionStateProvider {
    private var cachedSnapshot: MacSessionSnapshot?
    private var cacheTimestamp: TimeInterval = 0
    // Lock for thread-safe cache access
    private let lock = NSLock()

    public init() {}

    public func currentSnapshot() -> MacSessionSnapshot {
        let now = ProcessInfo.processInfo.systemUptime
        lock.lock()
        if let cached = cachedSnapshot, (now - cacheTimestamp) < sessionStateCacheTTL {
            lock.unlock()
            return cached
        }
        lock.unlock()
        let fresh = Self.fetchFromSystem()
        lock.lock()
        cachedSnapshot = fresh
        cacheTimestamp = now
        lock.unlock()
        return fresh
    }

    private static func fetchFromSystem() -> MacSessionSnapshot {
        guard let dict = CGSessionCopyCurrentDictionary() as? [String: Any], !dict.isEmpty else {
            return MacSessionSnapshot(isLocked: true, isUnknown: true, rawKeysSeen: [])
        }
        let rawKeys = Set(dict.keys)
        #if DEBUG
        if ProcessInfo.processInfo.environment["OPEN_COMPUTER_USE_LOCK_FAIL_OPEN"] == "1" {
            return MacSessionSnapshot(isLocked: false, isUnknown: false, rawKeysSeen: rawKeys)
        }
        #endif
        guard let lockedValue = dict[cgSessionScreenIsLockedKey] else {
            return MacSessionSnapshot(isLocked: true, isUnknown: true, rawKeysSeen: rawKeys)
        }
        let isLocked: Bool
        if let boolVal = lockedValue as? Bool {
            isLocked = boolVal
        } else if let numVal = lockedValue as? NSNumber {
            isLocked = numVal.boolValue
        } else {
            return MacSessionSnapshot(isLocked: true, isUnknown: true, rawKeysSeen: rawKeys)
        }
        return MacSessionSnapshot(isLocked: isLocked, isUnknown: false, rawKeysSeen: rawKeys)
    }
}

public struct MacSessionGuard {
    private let provider: MacSessionStateProvider

    public init(provider: MacSessionStateProvider = SystemMacSessionStateProvider()) {
        self.provider = provider
    }

    public func requireUnlocked(for toolName: String) throws {
        let snapshot = provider.currentSnapshot()
        if snapshot.isLocked {
            if snapshot.isUnknown {
                fputs("[open-computer-use] Lock state unknown — CGSessionCopyCurrentDictionary returned nil/empty/parse-failed (keys: \(snapshot.rawKeysSeen.sorted().joined(separator: ","))). Treating as locked.\n", stderr)
            }
            throw ComputerUseError.stateUnavailable("Computer Use cannot run while macOS is locked. Unlock the Mac or run open-computer-use inside a dedicated logged-in desktop session.")
        }
    }

    // Current snapshot for menu bar status display (never throws)
    public func currentState() -> MacSessionSnapshot {
        return provider.currentSnapshot()
    }
}
