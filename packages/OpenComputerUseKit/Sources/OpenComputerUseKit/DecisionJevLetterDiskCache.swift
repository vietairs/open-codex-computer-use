import CryptoKit
import Foundation

/// The jev letter table persisted per (base_url, model), so a fresh process does not pay 27 `/tokenize` requests again
/// and a resolution cut short by the deadline keeps the letters it already has.
///
/// One JSON file per key in an owner-only directory. It shares its trust root with `remote-backend.json`: every load
/// goes through `readOwnerOnlyRegularFile`, and every problem (missing, symlink, wrong owner, group/other bits,
/// oversize, bad JSON, another version, another key, a stale template, an expired entry) is a plain miss, never an
/// error. The file holds token ids and token strings only; it never holds the api key.
struct DecisionJevLetterDiskCache: Sendable {
    static let formatVersion = 1
    /// An entry resolved longer ago than this is a miss, so a tokenizer redeploy that nothing else flags heals itself.
    static let maxEntryAge: TimeInterval = 7 * 24 * 60 * 60
    static let maxFileBytes = 64 * 1024
    /// How the shared owner-only reader names this file in its errors.
    static let fileDescription = "jev letter cache file"
    private static let expectedLetterCount = 26
    /// Tolerated clock skew for an entry stamped slightly in the future.
    private static let maxFutureSkew: TimeInterval = 5 * 60

    /// ~/Library/Application Support/OpenComputerUse/decision-model/jev-letters. Production only; tests pass a temp dir.
    static var productionDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/OpenComputerUse/decision-model/jev-letters")
    }

    struct Entry: Codable, Equatable, Sendable {
        struct Letter: Codable, Equatable, Sendable {
            let id: Int
            let tokenStr: String

            enum CodingKeys: String, CodingKey {
                case id
                case tokenStr = "token_str"
            }
        }

        let version: Int
        let baseURL: String
        let model: String
        let samplePromptSHA256: String
        let resolvedAt: Date
        /// `/tokenize` ids of the sample prompt: what a resumed resolution compares its fresh base ids against.
        let baseTokenIDs: [Int]
        /// The letters resolved so far.
        let letters: [String: Letter]

        enum CodingKeys: String, CodingKey {
            case version
            case baseURL = "base_url"
            case model
            case samplePromptSHA256 = "sample_prompt_sha256"
            case resolvedAt = "resolved_at"
            case baseTokenIDs = "base_ids"
            case letters
        }

        /// Every letter A-Z resolved, to 26 distinct ids and 26 distinct token strings.
        var isComplete: Bool {
            letters.count == DecisionJevLetterDiskCache.expectedLetterCount
                && Set(letters.values.map(\.id)).count == DecisionJevLetterDiskCache.expectedLetterCount
                && Set(letters.values.map(\.tokenStr)).count == DecisionJevLetterDiskCache.expectedLetterCount
        }
    }

    let directory: URL
    let now: @Sendable () -> Date

    init(directory: URL, now: @escaping @Sendable () -> Date = Date.init) {
        self.directory = directory
        self.now = now
    }

    /// directory/<lowercase hex sha256("<base_url>|<model>")>.json
    func fileURL(baseURL: URL, model: String) -> URL {
        let digest = SHA256.hash(data: Data("\(baseURL.absoluteString)|\(model)".utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent("\(name).json", isDirectory: false)
    }

    /// nil on any problem. Never throws.
    func load(baseURL: URL, model: String, samplePromptSHA256: String) -> Entry? {
        let url = fileURL(baseURL: baseURL, model: model)
        guard let data = try? readOwnerOnlyRegularFile(
            path: url.path, maxBytes: Self.maxFileBytes, fileDescription: Self.fileDescription
        ) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let entry = try? decoder.decode(Entry.self, from: data),
              entry.version == Self.formatVersion,
              entry.baseURL == baseURL.absoluteString,
              entry.model == model,
              entry.samplePromptSHA256 == samplePromptSHA256,
              entry.letters.keys.allSatisfy(Self.isLetterKey)
        else { return nil }
        let age = now().timeIntervalSince(entry.resolvedAt)
        guard age <= Self.maxEntryAge, age >= -Self.maxFutureSkew else { return nil }
        return entry
    }

    /// Best effort, never throws. Writes a 0600 temp file in the directory and renames it over the target, so a reader
    /// never sees half a file and a symlink at the target path is replaced, not followed.
    func store(_ entry: Entry, baseURL: URL, model: String) {
        guard ensureOwnerOnlyDirectory() else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(entry) else { return }

        let target = fileURL(baseURL: baseURL, model: model)
        let temporary = directory.appendingPathComponent(".tmp-\(UUID().uuidString)", isDirectory: false)
        let fd = temporary.path.withCString {
            open($0, O_CREAT | O_EXCL | O_NOFOLLOW | O_WRONLY | O_CLOEXEC, 0o600)
        }
        guard fd >= 0 else { return }
        // The mode passed to open(2) is masked by umask; pin it so the file is always exactly owner-only.
        var wrote = fchmod(fd, 0o600) == 0
        if wrote {
            wrote = data.withUnsafeBytes { buffer -> Bool in
                var offset = 0
                while offset < buffer.count {
                    let written = write(fd, buffer.baseAddress! + offset, buffer.count - offset)
                    if written < 0 {
                        if errno == EINTR { continue }
                        return false
                    }
                    offset += written
                }
                return true
            }
        }
        let closed = close(fd) == 0
        if wrote, closed, rename(temporary.path, target.path) == 0 { return }
        unlink(temporary.path)
    }

    func remove(baseURL: URL, model: String) {
        unlink(fileURL(baseURL: baseURL, model: model).path)
    }

    private static func isLetterKey(_ key: String) -> Bool {
        key.utf8.count == 1 && (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(key.utf8.first!)
    }

    /// Creates the directory 0700 when absent; refuses one that is not a real directory, is owned by someone else, or
    /// is writable by group or other.
    private func ensureOwnerOnlyDirectory() -> Bool {
        var status = stat()
        if lstat(directory.path, &status) != 0 {
            guard errno == ENOENT else { return false }
            let parent = directory.deletingLastPathComponent()
            try? FileManager.default.createDirectory(
                at: parent, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
            )
            guard mkdir(directory.path, 0o700) == 0 || errno == EEXIST else { return false }
            guard lstat(directory.path, &status) == 0 else { return false }
            if status.st_uid == getuid() { _ = chmod(directory.path, 0o700); _ = lstat(directory.path, &status) }
        }
        return status.st_mode & S_IFMT == S_IFDIR
            && status.st_uid == getuid()
            && status.st_mode & 0o022 == 0
    }
}
