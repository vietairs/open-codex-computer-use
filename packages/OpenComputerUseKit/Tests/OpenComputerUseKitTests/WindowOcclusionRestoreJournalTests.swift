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
