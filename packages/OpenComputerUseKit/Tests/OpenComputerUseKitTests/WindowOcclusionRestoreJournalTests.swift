import CoreGraphics
import Darwin
import Foundation
import XCTest
@testable import OpenComputerUseKit

final class WindowOcclusionRestoreJournalTests: XCTestCase {
    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ocu-occlusion-journal-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }

    private func journalFiles(in directory: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).sorted()
    }

    func testParseSkipsMalformedLines() {
        let text = "10 500\n\ngarbage\n11 abc\n0 500\n12 -3\n13 600 extra\n14 700"
        XCTAssertEqual(parseOcclusionRestoreJournal(text), [
            OcclusionRestoreEntry(windowID: 10, ownerPID: 500),
            OcclusionRestoreEntry(windowID: 14, ownerPID: 700),
        ])
    }

    func testRenderIsSortedAndRoundTrips() {
        let entries = [
            OcclusionRestoreEntry(windowID: 20, ownerPID: 1),
            OcclusionRestoreEntry(windowID: 3, ownerPID: 2),
        ]
        let text = renderOcclusionRestoreJournal(entries)
        XCTAssertEqual(text, "3 2\n20 1\n")
        XCTAssertEqual(parseOcclusionRestoreJournal(text), entries.sorted { $0.windowID < $1.windowID })
    }

    func testWriteCreatesAPrivateFileAndDiscardRemovesIt() throws {
        let directory = try makeDirectory()
        let journal = FileOcclusionRestoreJournal(directory: directory, processID: 101)

        try journal.write([OcclusionRestoreEntry(windowID: 10, ownerPID: 500)])
        try journal.write([
            OcclusionRestoreEntry(windowID: 11, ownerPID: 500),
            OcclusionRestoreEntry(windowID: 12, ownerPID: 600),
        ])

        let file = directory.appendingPathComponent("101.journal")
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "11 500\n12 600\n", "each write replaces the file")
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)

        journal.discard()
        XCTAssertEqual(journalFiles(in: directory), [])
    }

    func testLiveWritersJournalIsNotTaken() throws {
        let directory = try makeDirectory()
        let live = FileOcclusionRestoreJournal(directory: directory, processID: 101)
        try live.write([OcclusionRestoreEntry(windowID: 10, ownerPID: 500)])

        let other = FileOcclusionRestoreJournal(directory: directory, processID: 202)
        XCTAssertEqual(other.takeAbandonedEntries(), [])
        XCTAssertEqual(journalFiles(in: directory), ["101.journal"])
        live.discard()
    }

    func testEndedWritersJournalIsTakenOnceAndRemoved() throws {
        let directory = try makeDirectory()
        let ended = FileOcclusionRestoreJournal(directory: directory, processID: 101)
        try ended.write([OcclusionRestoreEntry(windowID: 10, ownerPID: 500)])
        ended.abandonForTesting()

        let other = FileOcclusionRestoreJournal(directory: directory, processID: 202)
        try other.write([OcclusionRestoreEntry(windowID: 99, ownerPID: 1)])
        XCTAssertEqual(other.takeAbandonedEntries(), [OcclusionRestoreEntry(windowID: 10, ownerPID: 500)])
        XCTAssertEqual(other.takeAbandonedEntries(), [])
        XCTAssertEqual(journalFiles(in: directory), ["202.journal"], "the reader's own journal is never taken")
        other.discard()
    }

    func testStaleJournalUnderTheOwnPidIsTakenBeforeTheFirstWrite() throws {
        let directory = try makeDirectory()
        let ended = FileOcclusionRestoreJournal(directory: directory, processID: 101)
        try ended.write([OcclusionRestoreEntry(windowID: 10, ownerPID: 500)])
        ended.abandonForTesting()

        // A new process that was given the same pid.
        let reused = FileOcclusionRestoreJournal(directory: directory, processID: 101)
        XCTAssertEqual(reused.takeAbandonedEntries(), [OcclusionRestoreEntry(windowID: 10, ownerPID: 500)])
        try reused.write([OcclusionRestoreEntry(windowID: 20, ownerPID: 700)])
        XCTAssertEqual(reused.takeAbandonedEntries(), [], "once written, the own journal is never taken")
        XCTAssertEqual(
            try String(contentsOf: directory.appendingPathComponent("101.journal"), encoding: .utf8),
            "20 700\n"
        )
        reused.discard()
    }

    func testShorterWriteLeavesNoTailOfTheOldContent() throws {
        let directory = try makeDirectory()
        let journal = FileOcclusionRestoreJournal(directory: directory, processID: 101)
        try journal.write([
            OcclusionRestoreEntry(windowID: 1_234, ownerPID: 500),
            OcclusionRestoreEntry(windowID: 5_678, ownerPID: 600),
        ])
        try journal.write([OcclusionRestoreEntry(windowID: 9, ownerPID: 7)])
        XCTAssertEqual(try String(contentsOf: directory.appendingPathComponent("101.journal"), encoding: .utf8), "9 7\n")
        try journal.write([])
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("101.journal")).count, 0)
        journal.discard()
    }

    func testPaddingFromAnInterruptedWriteParsesToTheNewEntriesOnly() {
        // What a process killed between the padded write and the truncate leaves behind.
        XCTAssertEqual(
            parseOcclusionRestoreJournal("9 7\n" + String(repeating: " ", count: 14)),
            [OcclusionRestoreEntry(windowID: 9, ownerPID: 7)]
        )
    }

    func testWriteFailsWhileAnotherHolderKeepsTheFileLocked() throws {
        let directory = try makeDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent("101.journal").path
        let holder = open(path, O_RDWR | O_CREAT | O_CLOEXEC | O_EXLOCK, 0o600)
        XCTAssertGreaterThanOrEqual(holder, 0)

        let journal = FileOcclusionRestoreJournal(directory: directory, processID: 101)
        XCTAssertThrowsError(try journal.write([OcclusionRestoreEntry(windowID: 10, ownerPID: 500)])) { error in
            XCTAssertTrue((error as? ComputerUseError)?.errorDescription?.contains("stayed busy") == true)
        }

        close(holder)
        XCTAssertNoThrow(try journal.write([OcclusionRestoreEntry(windowID: 10, ownerPID: 500)]))
        journal.discard()
    }

    func testMissingDirectoryHasNothingAbandoned() throws {
        let directory = try makeDirectory()
        XCTAssertEqual(FileOcclusionRestoreJournal(directory: directory, processID: 1).takeAbandonedEntries(), [])
    }

    func testSymlinkedJournalIsNotFollowed() throws {
        let directory = try makeDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = directory.appendingPathComponent("target.txt")
        try "keep".write(to: target, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            at: directory.appendingPathComponent("101.journal"),
            withDestinationURL: target
        )

        let journal = FileOcclusionRestoreJournal(directory: directory, processID: 101)
        XCTAssertThrowsError(try journal.write([OcclusionRestoreEntry(windowID: 10, ownerPID: 500)]))
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "keep")
    }
}
