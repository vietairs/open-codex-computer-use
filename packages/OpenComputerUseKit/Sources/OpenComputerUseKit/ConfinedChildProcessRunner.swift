import Darwin
import Dispatch
import Foundation

public struct ConfinedChildProcessRequest: Sendable {
    public let executablePath: String
    public let arguments: [String]
    public let standardInput: Data
    public let environment: [String: String]
    public let timeout: TimeInterval
    public let outputByteLimit: Int

    public init(
        executablePath: String,
        arguments: [String],
        standardInput: Data = Data(),
        environment: [String: String],
        timeout: TimeInterval,
        outputByteLimit: Int = ConfinedChildProcessRunner.defaultOutputByteLimit
    ) {
        self.executablePath = executablePath
        self.arguments = arguments
        self.standardInput = standardInput
        self.environment = environment
        self.timeout = timeout
        self.outputByteLimit = outputByteLimit
    }
}

public struct ConfinedChildProcessResult: Equatable, Sendable {
    public let exitStatus: Int32?
    public let terminatingSignal: Int32?
    public let timedOut: Bool
    public let standardOutput: Data
    public let standardError: Data
    public let standardOutputTruncated: Bool
    public let standardErrorTruncated: Bool
    public let duration: TimeInterval
}

public enum ConfinedChildProcessError: Error, Equatable {
    case executablePathNotAbsolute(String)
    case pipeFailed(errno: Int32)
    case spawnFailed(errno: Int32)
}

/// Runs one child with only fds 0-2 (fresh pipes), its own process group, cwd `/` and an explicit environment.
///
/// It deliberately avoids `Foundation.Process`: `posix_spawn` with `POSIX_SPAWN_CLOEXEC_DEFAULT` guarantees the
/// child inherits none of the relay's descriptors (notably the app-agent socket), and the separate process group
/// lets a timeout or a lingering descendant be cleared with one group signal.
///
/// One absolute deadline governs spawn, reap and drain, so a descendant that keeps an output pipe open can never
/// wedge the caller. Worst-case return time is `timeout + killGracePeriod + reapGracePeriod + drainGracePeriod`.
public enum ConfinedChildProcessRunner {
    public static let defaultOutputByteLimit = 65_536
    public static let killGracePeriod: TimeInterval = 1.0
    public static let reapGracePeriod: TimeInterval = 2.0
    public static let drainGracePeriod: TimeInterval = 0.5
    public static let fixedSearchPath = "/usr/bin:/bin:/usr/sbin:/sbin"

    /// The only variables a script child receives: a fixed `PATH`, an absolute `HOME`, and `LANG`.
    public static func scrubbedEnvironment(from environment: [String: String]) -> [String: String] {
        let home = environment["HOME"].flatMap { $0.hasPrefix("/") ? $0 : nil } ?? NSHomeDirectory()
        return [
            "PATH": fixedSearchPath,
            "HOME": home,
            "LANG": environment["LANG"] ?? "en_US.UTF-8",
        ]
    }

    public static func run(_ request: ConfinedChildProcessRequest) throws -> ConfinedChildProcessResult {
        guard request.executablePath.hasPrefix("/") else {
            throw ConfinedChildProcessError.executablePathNotAbsolute(request.executablePath)
        }

        let start = ProcessInfo.processInfo.systemUptime
        let deadline = start + max(request.timeout, 0)

        var standardInputPipe = try makePipe()
        let standardOutputPipe: (read: Int32, write: Int32)
        let standardErrorPipe: (read: Int32, write: Int32)
        do {
            standardOutputPipe = try makePipe()
        } catch {
            closeAll([standardInputPipe.read, standardInputPipe.write])
            throw error
        }
        do {
            standardErrorPipe = try makePipe()
        } catch {
            closeAll([
                standardInputPipe.read, standardInputPipe.write,
                standardOutputPipe.read, standardOutputPipe.write,
            ])
            throw error
        }
        let parentEnds = [standardInputPipe.write, standardOutputPipe.read, standardErrorPipe.read]
        let childEnds = [standardInputPipe.read, standardOutputPipe.write, standardErrorPipe.write]
        for descriptor in parentEnds {
            _ = fcntl(descriptor, F_SETFD, FD_CLOEXEC)
        }
        for descriptor in [standardOutputPipe.read, standardErrorPipe.read] {
            _ = fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL) | O_NONBLOCK)
        }
        // A child that exits early must surface as EPIPE on the write, never as SIGPIPE in the caller.
        _ = fcntl(standardInputPipe.write, F_SETNOSIGPIPE, 1)

        let spawnedPID: pid_t
        do {
            spawnedPID = try spawnChild(request, childEnds: childEnds)
        } catch {
            closeAll(parentEnds + childEnds)
            throw error
        }
        closeAll(childEnds)
        standardInputPipe.read = -1

        let shared = SharedChildState()
        let exited = DispatchSemaphore(value: 0)
        let goAhead = DispatchSemaphore(value: 0)
        let reaped = DispatchSemaphore(value: 0)
        let drainFinished = DispatchSemaphore(value: 0)

        // Writer thread owns the stdin write end: it writes, then closes.
        let stdinWriteEnd = standardInputPipe.write
        let stdinBytes = request.standardInput
        Thread.detachNewThread {
            writeAll(stdinBytes, to: stdinWriteEnd)
            close(stdinWriteEnd)
        }

        // Exactly one reaper owns the child. It observes the exit without reaping so the zombie keeps the pid and
        // process group pinned while the controller clears the group, then reaps once on the controller's go-ahead.
        Thread.detachNewThread {
            var info = siginfo_t()
            var observedWithoutReaping = false
            while true {
                let result = waitid(P_PID, id_t(spawnedPID), &info, WEXITED | WNOWAIT)
                if result == 0 {
                    observedWithoutReaping = true
                    break
                }
                if errno == EINTR { continue }
                break
            }
            if observedWithoutReaping {
                shared.markLeaderObserved(reapedAlready: false)
                exited.signal()
                goAhead.wait()
            }
            var status: Int32 = 0
            var waitResult: pid_t
            repeat {
                waitResult = waitpid(spawnedPID, &status, 0)
            } while waitResult < 0 && errno == EINTR
            if !observedWithoutReaping {
                // waitid could not be used; the direct reap is the observation and the group kill is skipped.
                shared.markLeaderObserved(reapedAlready: true)
                exited.signal()
            }
            shared.setStatus(waitResult == spawnedPID ? status : nil)
            reaped.signal()
        }

        let outputLimit = max(request.outputByteLimit, 0)
        let outputRead = standardOutputPipe.read
        let errorRead = standardErrorPipe.read
        Thread.detachNewThread {
            drain(outputRead: outputRead, errorRead: errorRead, byteLimit: outputLimit, shared: shared)
            drainFinished.signal()
        }

        // Controller.
        var timedOut = false
        var leaderObserved = exited.wait(timeout: dispatchTime(atUptime: deadline)) == .success
        if !leaderObserved {
            timedOut = true
            _ = kill(-spawnedPID, SIGTERM)
            leaderObserved = exited.wait(timeout: .now() + killGracePeriod) == .success
            if !leaderObserved {
                _ = kill(-spawnedPID, SIGKILL)
                leaderObserved = exited.wait(timeout: .now() + reapGracePeriod) == .success
            }
        }

        var status: Int32?
        if leaderObserved {
            if !shared.leaderWasReapedAlready {
                // Clear any descendant left in the group while the zombie leader still pins the pid.
                _ = kill(-spawnedPID, SIGKILL)
            }
            goAhead.signal()
            if reaped.wait(timeout: .now() + reapGracePeriod) == .success {
                status = shared.status
            }
        } else {
            // Leader never observed: let the detached reaper finish whenever the kernel allows it.
            goAhead.signal()
            shared.abandonDrain()
        }

        if drainFinished.wait(timeout: .now() + drainGracePeriod + 1.0) != .success {
            shared.abandonDrain()
            _ = drainFinished.wait(timeout: .now() + 1.0)
        }
        let drained = shared.drainResult
        close(outputRead)
        close(errorRead)

        var exitStatus: Int32?
        var terminatingSignal: Int32?
        if let status {
            let signalBits = status & 0x7f
            if signalBits == 0 {
                exitStatus = (status >> 8) & 0xff
            } else if signalBits != 0x7f {
                terminatingSignal = signalBits
            }
        }

        return ConfinedChildProcessResult(
            exitStatus: exitStatus,
            terminatingSignal: terminatingSignal,
            timedOut: timedOut,
            standardOutput: drained.standardOutput,
            standardError: drained.standardError,
            standardOutputTruncated: drained.standardOutputTruncated,
            standardErrorTruncated: drained.standardErrorTruncated,
            duration: ProcessInfo.processInfo.systemUptime - start
        )
    }

    // MARK: - Spawn

    private static func makePipe() throws -> (read: Int32, write: Int32) {
        var descriptors: [Int32] = [-1, -1]
        guard pipe(&descriptors) == 0 else {
            throw ConfinedChildProcessError.pipeFailed(errno: errno)
        }
        return (descriptors[0], descriptors[1])
    }

    private static func closeAll(_ descriptors: [Int32]) {
        for descriptor in descriptors where descriptor >= 0 {
            close(descriptor)
        }
    }

    /// `childEnds` is `[stdin read, stdout write, stderr write]`.
    private static func spawnChild(_ request: ConfinedChildProcessRequest, childEnds: [Int32]) throws -> pid_t {
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        var fileActions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&fileActions)
        defer { posix_spawn_file_actions_destroy(&fileActions) }

        var allSignals = sigset_t()
        sigfillset(&allSignals)
        var noSignals = sigset_t()
        sigemptyset(&noSignals)
        posix_spawnattr_setsigdefault(&attributes, &allSignals)
        posix_spawnattr_setsigmask(&attributes, &noSignals)
        posix_spawnattr_setpgroup(&attributes, 0)
        let flags = POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK
        posix_spawnattr_setflags(&attributes, Int16(flags))

        for (target, source) in childEnds.enumerated() {
            let result = posix_spawn_file_actions_adddup2(&fileActions, source, Int32(target))
            if result != 0 { throw ConfinedChildProcessError.spawnFailed(errno: result) }
        }
        let chdirResult = posix_spawn_file_actions_addchdir_np(&fileActions, "/")
        if chdirResult != 0 { throw ConfinedChildProcessError.spawnFailed(errno: chdirResult) }

        let argv = ([request.executablePath] + request.arguments).map { strdup($0) } + [nil]
        let envp = request.environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer {
            argv.forEach { free($0) }
            envp.forEach { free($0) }
        }

        var pid: pid_t = 0
        let result = posix_spawn(&pid, request.executablePath, &fileActions, &attributes, argv, envp)
        guard result == 0 else {
            throw ConfinedChildProcessError.spawnFailed(errno: result)
        }
        return pid
    }

    // MARK: - IO

    private static func writeAll(_ data: Data, to descriptor: Int32) {
        data.withUnsafeBytes { buffer in
            guard var cursor = buffer.baseAddress else { return }
            var remaining = buffer.count
            while remaining > 0 {
                let written = write(descriptor, cursor, remaining)
                if written < 0 {
                    if errno == EINTR { continue }
                    return
                }
                cursor += written
                remaining -= written
            }
        }
    }

    /// Drains both read ends on one thread. Stops at EOF on both, at `leaderObservedTime + drainGracePeriod`, or when
    /// the controller abandons the drain. A stream cut short by the deadline is marked truncated.
    private static func drain(outputRead: Int32, errorRead: Int32, byteLimit: Int, shared: SharedChildState) {
        var descriptors = [
            pollfd(fd: outputRead, events: Int16(POLLIN), revents: 0),
            pollfd(fd: errorRead, events: Int16(POLLIN), revents: 0),
        ]
        var collected = [Data(), Data()]
        var truncated = [false, false]
        var open = [true, true]
        var chunk = [UInt8](repeating: 0, count: 8_192)

        while open[0] || open[1] {
            if shared.drainAbandoned { break }
            if let observed = shared.leaderObservedUptime,
               ProcessInfo.processInfo.systemUptime >= observed + drainGracePeriod {
                break
            }
            let ready = poll(&descriptors, nfds_t(descriptors.count), 50)
            if ready < 0 {
                if errno == EINTR { continue }
                break
            }
            for index in 0..<descriptors.count where open[index] && descriptors[index].revents != 0 {
                let count = read(descriptors[index].fd, &chunk, chunk.count)
                if count > 0 {
                    let room = max(byteLimit - collected[index].count, 0)
                    if room > 0 {
                        collected[index].append(contentsOf: chunk[0..<min(count, room)])
                    }
                    if count > room { truncated[index] = true }
                } else if count == 0 || (errno != EAGAIN && errno != EINTR) {
                    open[index] = false
                    descriptors[index].fd = -1
                }
            }
        }
        for index in 0..<2 where open[index] {
            truncated[index] = true
        }
        shared.setDrainResult(
            DrainResult(
                standardOutput: collected[0],
                standardError: collected[1],
                standardOutputTruncated: truncated[0],
                standardErrorTruncated: truncated[1]
            )
        )
    }

    private static func dispatchTime(atUptime uptime: TimeInterval) -> DispatchTime {
        let remaining = max(uptime - ProcessInfo.processInfo.systemUptime, 0)
        return .now() + remaining
    }
}

// MARK: - Shared state

private struct DrainResult {
    var standardOutput = Data()
    var standardError = Data()
    var standardOutputTruncated = false
    var standardErrorTruncated = false
}

/// Lock-protected state shared by the controller, reaper and drain threads.
private final class SharedChildState: @unchecked Sendable {
    private let lock = NSLock()
    private var observedUptime: TimeInterval?
    private var reapedAlready = false
    private var storedStatus: Int32?
    private var abandoned = false
    private var storedDrain = DrainResult()

    func markLeaderObserved(reapedAlready: Bool) {
        lock.lock()
        observedUptime = ProcessInfo.processInfo.systemUptime
        self.reapedAlready = reapedAlready
        lock.unlock()
    }

    var leaderObservedUptime: TimeInterval? {
        lock.lock(); defer { lock.unlock() }
        return observedUptime
    }

    var leaderWasReapedAlready: Bool {
        lock.lock(); defer { lock.unlock() }
        return reapedAlready
    }

    func setStatus(_ status: Int32?) {
        lock.lock()
        storedStatus = status
        lock.unlock()
    }

    var status: Int32? {
        lock.lock(); defer { lock.unlock() }
        return storedStatus
    }

    func abandonDrain() {
        lock.lock()
        abandoned = true
        lock.unlock()
    }

    var drainAbandoned: Bool {
        lock.lock(); defer { lock.unlock() }
        return abandoned
    }

    func setDrainResult(_ result: DrainResult) {
        lock.lock()
        storedDrain = result
        lock.unlock()
    }

    var drainResult: DrainResult {
        lock.lock(); defer { lock.unlock() }
        return storedDrain
    }
}
