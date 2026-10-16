import CoreGraphics
import Darwin
import Foundation

/// One window whose occlusion notifications this process turned off, with the pid that owned the window then. A
/// replay restores the window only while the same pid still owns it, so a reused window id is never touched.
struct OcclusionRestoreEntry: Equatable, Hashable, Sendable {
    let windowID: CGWindowID
    let ownerPID: pid_t
}

/// Pure. Parses a journal: one `windowID ownerPID` pair per line. Malformed lines (a write cut short by a crash) are
/// skipped rather than failing the whole replay.
func parseOcclusionRestoreJournal(_ text: String) -> [OcclusionRestoreEntry] {
    text.split(whereSeparator: \.isNewline).compactMap { line in
        let fields = line.split(separator: " ")
        guard fields.count == 2,
              let windowID = CGWindowID(fields[0]), windowID != 0,
              let ownerPID = pid_t(fields[1]), ownerPID > 0
        else {
            return nil
        }
        return OcclusionRestoreEntry(windowID: windowID, ownerPID: ownerPID)
    }
}

/// Pure. The journal text for `entries`, sorted so the file content is stable.
func renderOcclusionRestoreJournal(_ entries: some Collection<OcclusionRestoreEntry>) -> String {
    entries
        .sorted { ($0.windowID, $0.ownerPID) < ($1.windowID, $1.ownerPID) }
        .map { "\($0.windowID) \($0.ownerPID)\n" }
        .joined()
}

/// Write-ahead record of the windows this process pinned, so a process that dies without restoring them (SIGKILL, a
/// crash) does not leave other apps' windows pinned for their whole lifetime.
protocol OcclusionRestoreJournaling: AnyObject {
    /// Replaces this process's journal with `entries`. Throws when it cannot be written; the caller then pins nothing.
    func write(_ entries: [OcclusionRestoreEntry]) throws

    /// Entries from journals whose writing process has ended, including a file under this process's own name that an
    /// ended process with the same pid left before this process wrote anything. Their files are removed once read.
    func takeAbandonedEntries() -> [OcclusionRestoreEntry]

    /// Removes this process's journal at a clean exit with nothing left to restore.
    func discard()
}

/// One file per process in a private directory, holding an exclusive `flock` for as long as the process lives. The
/// kernel drops the lock when the process ends however it ends, so another process that can take the lock knows the
/// writer is gone, and pid reuse cannot make a live writer look dead or the reverse. The file is created and locked in
/// one `open` (`O_EXLOCK`), and a writer that finds its locked file already unlinked by a reader opens a new one, so a
/// reader can never take a live writer's journal.
///
/// A replay only ever turns notifications back on, which is the system default, so a journal planted by another
/// same-user process cannot make the agent hide anything.
final class FileOcclusionRestoreJournal: OcclusionRestoreJournaling {
    static let fileExtension = "journal"

    /// ~/Library/Application Support/OpenComputerUse/occlusion-restore. Production only; tests pass a temp dir.
    static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/OpenComputerUse/occlusion-restore", isDirectory: true)
    }

    private let directory: URL
    private let processID: pid_t
    private var fileDescriptor: Int32 = -1

    init(directory: URL = FileOcclusionRestoreJournal.defaultDirectory, processID: pid_t = getpid()) {
        self.directory = directory
        self.processID = processID
    }

    deinit {
        if fileDescriptor >= 0 {
            close(fileDescriptor)
        }
    }

    private var ownFileName: String {
        "\(processID).\(Self.fileExtension)"
    }

    /// Writes before truncating, so a process killed in between leaves the new entries, never an empty journal. A
    /// shorter journal is padded with spaces over the old content first, so no tail of an old line survives to be
    /// parsed as an entry.
    func write(_ entries: [OcclusionRestoreEntry]) throws {
        let descriptor = try openOwnFile()
        let data = Data(renderOcclusionRestoreJournal(entries).utf8)
        var status = stat()
        guard fstat(descriptor, &status) == 0 else {
            throw journalError("stat")
        }
        let padded = data + Data(repeating: UInt8(ascii: " "), count: max(0, Int(status.st_size) - data.count))
        let written = padded.withUnsafeBytes { bytes -> Int in
            guard let base = bytes.baseAddress else {
                return 0
            }
            return pwrite(descriptor, base, bytes.count, 0)
        }
        guard written == padded.count else {
            throw journalError("write")
        }
        guard ftruncate(descriptor, off_t(data.count)) == 0 else {
            throw journalError("truncate")
        }
    }

    func takeAbandonedEntries() -> [OcclusionRestoreEntry] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else {
            return []
        }
        var entries: [OcclusionRestoreEntry] = []
        // The own file is skipped only once this process holds it; before that, a file under its name was left by an
        // ended process with the same pid.
        for name in names where name.hasSuffix(".\(Self.fileExtension)") && (name != ownFileName || fileDescriptor < 0) {
            let path = directory.appendingPathComponent(name).path
            let descriptor = open(path, O_RDWR | O_NOFOLLOW | O_CLOEXEC)
            guard descriptor >= 0 else {
                continue
            }
            defer {
                close(descriptor)
            }
            // A live writer still holds the lock.
            guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
                continue
            }
            entries.append(contentsOf: parseOcclusionRestoreJournal(readAll(descriptor)))
            unlink(path)
        }
        return entries
    }

    func discard() {
        guard fileDescriptor >= 0 else {
            return
        }
        unlink(directory.appendingPathComponent(ownFileName).path)
        close(fileDescriptor)
        fileDescriptor = -1
    }

    /// Closes the file without removing it, as a process that is killed would. Tests only.
    func abandonForTesting() {
        guard fileDescriptor >= 0 else {
            return
        }
        close(fileDescriptor)
        fileDescriptor = -1
    }

    private func openOwnFile() throws -> Int32 {
        if fileDescriptor >= 0 {
            return fileDescriptor
        }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let path = directory.appendingPathComponent(ownFileName).path
        // A reader holds a file's lock only while it reads and removes it, so a busy or just-removed file is retried
        // a few times before the write fails (and the caller pins nothing).
        for attempt in 0..<Self.openAttempts {
            if attempt > 0 {
                usleep(Self.openRetryDelayMicroseconds)
            }
            let descriptor = open(path, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC | O_EXLOCK | O_NONBLOCK, 0o600)
            guard descriptor >= 0 else {
                if errno == EWOULDBLOCK {
                    continue
                }
                throw journalError("open")
            }
            // Removed by a reader between its read and our lock: the lock would protect a file nobody can find.
            var status = stat()
            guard fstat(descriptor, &status) == 0, status.st_nlink > 0 else {
                close(descriptor)
                continue
            }
            fileDescriptor = descriptor
            return descriptor
        }
        throw ComputerUseError.message("occlusion restore journal lock failed: the journal file stayed busy")
    }

    private static let openAttempts = 5
    private static let openRetryDelayMicroseconds: useconds_t = 10_000

    private func readAll(_ descriptor: Int32) -> String {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        var offset: off_t = 0
        while true {
            let count = buffer.withUnsafeMutableBytes { pread(descriptor, $0.baseAddress, $0.count, offset) }
            guard count > 0 else {
                break
            }
            data.append(contentsOf: buffer[0..<count])
            offset += off_t(count)
        }
        return String(decoding: data, as: UTF8.self)
    }

    private func journalError(_ operation: String) -> ComputerUseError {
        ComputerUseError.message(
            "occlusion restore journal \(operation) failed: \(String(cString: strerror(errno)))"
        )
    }
}
