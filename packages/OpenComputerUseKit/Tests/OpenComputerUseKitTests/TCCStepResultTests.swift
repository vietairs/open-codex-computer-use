import SQLite3
import XCTest
@testable import OpenComputerUseKit

final class TCCStepResultTests: XCTestCase {
    func testRowAndNoRecordAreDistinguishedFromErrors() {
        XCTAssertEqual(tccStepFoundRow(SQLITE_ROW), true)
        XCTAssertEqual(tccStepFoundRow(SQLITE_DONE), false)
    }

    func testStepErrorsLeaveTheGrantUnknown() {
        for code in [SQLITE_BUSY, SQLITE_LOCKED, SQLITE_CORRUPT, SQLITE_IOERR, SQLITE_NOTADB, SQLITE_ERROR] {
            XCTAssertNil(tccStepFoundRow(code), "result code \(code) must not read as a missing record")
        }
    }

    func testDoctorHelpExplainsSourceAndTheUnreadableExit() {
        let help = openComputerUseHelpText(command: "doctor")

        XCTAssertTrue(help.contains("source says whose grants were read"))
        XCTAssertTrue(help.contains("exits non-zero"))
    }

    func testUnreadableErrorNamesMoreThanFullDiskAccess() {
        let message = PermissionRecordUnreadableError().errorDescription ?? ""

        XCTAssertTrue(message.contains("Full Disk Access"))
        XCTAssertTrue(message.contains("locked by another process"))
    }
}
