import CoreGraphics
import Foundation
import XCTest
@testable import OpenComputerUseKit

final class SkyLightWindowServerSPITests: XCTestCase {
    func testFeatureAvailabilityNeedsSymbolsAndAVerifiedVersion() {
        XCTAssertEqual(
            windowServerFeatureAvailability(
                feature: "occlusion", missingSymbols: ["SLSMainConnectionID"], majorVersion: 27, requiresVerifiedVersion: true
            ).unavailableReason,
            "missing private occlusion symbols: SLSMainConnectionID"
        )
        let unverified = windowServerFeatureAvailability(
            feature: "occlusion", missingSymbols: [], majorVersion: 26, requiresVerifiedVersion: true, verifiedMajorVersions: [27]
        )
        XCTAssertFalse(unverified.isAvailable)
        XCTAssertEqual(unverified.unavailableReason, "the private occlusion call has not been verified on macOS 26")
        XCTAssertTrue(windowServerFeatureAvailability(
            feature: "occlusion", missingSymbols: [], majorVersion: 27, requiresVerifiedVersion: true, verifiedMajorVersions: [27]
        ).isAvailable)
        XCTAssertTrue(windowServerFeatureAvailability(
            feature: "Space", missingSymbols: [], majorVersion: 14, requiresVerifiedVersion: false, verifiedMajorVersions: [27]
        ).isAvailable)
    }

    func testPreviousStateIsFalseOnlyForAnExplicitZero() {
        XCTAssertEqual(occlusionPreviousState(rawByte: 0), false)
        XCTAssertEqual(occlusionPreviousState(rawByte: 1), true)
        XCTAssertNil(occlusionPreviousState(rawByte: occlusionPreviousStateSentinel))
        XCTAssertNil(occlusionPreviousState(rawByte: 7))
    }

    func testWindowSpaceParsing() {
        XCTAssertEqual(windowSpaceIDs(fromCopyResult: [NSNumber(value: 5), NSNumber(value: 9)]), [5, 9])
        XCTAssertNil(windowSpaceIDs(fromCopyResult: []))
        XCTAssertNil(windowSpaceIDs(fromCopyResult: ["x"]))
        XCTAssertNil(windowSpaceIDs(fromCopyResult: "not a list"))
        XCTAssertNil(windowSpaceIDs(fromCopyResult: nil))
    }

    func testCurrentSpaceParsing() {
        let displays: [Any] = [
            ["Display Identifier": "Main", "Current Space": ["id64": NSNumber(value: 3), "type": NSNumber(value: 0)]],
            ["Display Identifier": "Side", "Current Space": ["ManagedSpaceID": NSNumber(value: 8)]],
            ["Display Identifier": "Broken"],
            "garbage",
        ]
        XCTAssertEqual(currentSpaceIDs(fromManagedDisplaySpaces: displays), [3, 8])
        XCTAssertNil(currentSpaceIDs(fromManagedDisplaySpaces: [["Display Identifier": "Broken"]]))
        XCTAssertNil(currentSpaceIDs(fromManagedDisplaySpaces: NSNumber(value: 1)))
    }

    private func makeImage(width: Int, height: Int) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        return try XCTUnwrap(context.makeImage())
    }

    func testCapturedImageIsTypeCheckedAndOutlivesTheArray() throws {
        var image: CGImage?
        do {
            let array = [try makeImage(width: 4, height: 3)] as CFArray
            image = firstCapturedImage(fromCaptureResult: array)
        }
        XCTAssertEqual(image?.width, 4)
        XCTAssertEqual(image?.height, 3)

        XCTAssertNil(firstCapturedImage(fromCaptureResult: ["not an image"] as CFArray))
        XCTAssertNil(firstCapturedImage(fromCaptureResult: [] as CFArray))
        XCTAssertNil(firstCapturedImage(fromCaptureResult: "not an array" as CFString))
        XCTAssertNil(firstCapturedImage(fromCaptureResult: ["key": "value"] as CFDictionary))
    }

    func testHardwareCaptureSizeMustMatchBoundsTimesScale() {
        let bounds = CGRect(x: 10, y: 20, width: 300, height: 200)
        XCTAssertTrue(hardwareCaptureSizeMatches(imageWidth: 600, imageHeight: 400, bounds: bounds, scale: 2))
        XCTAssertTrue(hardwareCaptureSizeMatches(imageWidth: 602, imageHeight: 398, bounds: bounds, scale: 2))
        XCTAssertFalse(hardwareCaptureSizeMatches(imageWidth: 640, imageHeight: 440, bounds: bounds, scale: 2), "shadow margin")
        XCTAssertFalse(hardwareCaptureSizeMatches(imageWidth: 300, imageHeight: 200, bounds: bounds, scale: 2))
        XCTAssertFalse(hardwareCaptureSizeMatches(imageWidth: 600, imageHeight: 400, bounds: bounds, scale: .nan))
        XCTAssertFalse(hardwareCaptureSizeMatches(imageWidth: 600, imageHeight: 400, bounds: bounds, scale: .infinity))
        XCTAssertFalse(hardwareCaptureSizeMatches(imageWidth: 600, imageHeight: 400, bounds: bounds, scale: 0))
        XCTAssertFalse(hardwareCaptureSizeMatches(
            imageWidth: 600, imageHeight: 400, bounds: CGRect(x: 0, y: 0, width: CGFloat.nan, height: 200), scale: 2
        ))
        XCTAssertFalse(hardwareCaptureSizeMatches(imageWidth: 0, imageHeight: 0, bounds: .zero, scale: 2))
    }

    func testHardwareCaptureNeedsSharingPermissionAndUnlockedSession() {
        XCTAssertTrue(hardwareWindowCaptureAllowed(sharingState: 1, screenRecordingGranted: true, sessionIsUnlocked: true))
        XCTAssertFalse(hardwareWindowCaptureAllowed(sharingState: 0, screenRecordingGranted: true, sessionIsUnlocked: true))
        XCTAssertFalse(hardwareWindowCaptureAllowed(sharingState: nil, screenRecordingGranted: true, sessionIsUnlocked: true))
        XCTAssertFalse(hardwareWindowCaptureAllowed(sharingState: 1, screenRecordingGranted: false, sessionIsUnlocked: true))
        XCTAssertFalse(hardwareWindowCaptureAllowed(sharingState: 1, screenRecordingGranted: true, sessionIsUnlocked: false))
    }

    private func capturable(
        isOnscreen: Bool,
        isOffStage: Bool = false,
        unlocked: Bool = true,
        currentSpace: Bool? = true,
        offscreenAllowed: Bool = true,
        asked: ((String) -> Void)? = nil
    ) -> Bool {
        windowIsCapturable(
            isOnscreen: isOnscreen,
            isOffStage: isOffStage,
            probes: WindowCaptureProbes(
                sessionIsStrictlyUnlocked: { asked?("unlocked"); return unlocked },
                isOnCurrentSpace: { asked?("space"); return currentSpace },
                offscreenCaptureAllowed: { asked?("offscreen"); return offscreenAllowed }
            )
        )
    }

    func testCaptureEligibility() {
        var asked: [String] = []
        XCTAssertTrue(capturable(isOnscreen: true, offscreenAllowed: false, asked: { asked.append($0) }))
        XCTAssertFalse(asked.contains("offscreen"), "an on-screen window needs no off-screen check")
        XCTAssertFalse(capturable(isOnscreen: true, isOffStage: true))
        XCTAssertFalse(capturable(isOnscreen: false, isOffStage: true))
        XCTAssertTrue(capturable(isOnscreen: false, offscreenAllowed: true))
        XCTAssertFalse(capturable(isOnscreen: false, offscreenAllowed: false))
    }

    func testOnscreenWindowOnAnotherSpaceNeedsAStrictUnlock() {
        // Windows on another Desktop report kCGWindowIsOnscreen too. With the Mac locked and
        // OPEN_COMPUTER_USE_ALLOW_LOCKED set, the session is still not strictly unlocked, so such a window is not captured.
        let lockedWithOptIn = sessionIsStrictlyUnlocked(MacSessionSnapshot(isLocked: true, isUnknown: false, rawKeysSeen: []))
        XCTAssertFalse(capturable(isOnscreen: true, unlocked: lockedWithOptIn, currentSpace: false))
        XCTAssertFalse(capturable(isOnscreen: true, unlocked: false, currentSpace: nil), "an unreadable Space fails closed")
        XCTAssertTrue(capturable(isOnscreen: true, unlocked: false, currentSpace: true), "the current Space keeps the lock opt-in")
        XCTAssertTrue(capturable(isOnscreen: true, unlocked: true, currentSpace: false))
        XCTAssertTrue(capturable(isOnscreen: true, unlocked: true, currentSpace: nil))

        var asked: [String] = []
        _ = capturable(isOnscreen: true, unlocked: true, currentSpace: false, asked: { asked.append($0) })
        XCTAssertEqual(asked, ["unlocked"], "the Space is not read while the session is unlocked")
    }

    func testOffscreenCaptureNeedsTheTreeWindowVisibleAppAndUnlockedSession() {
        XCTAssertTrue(offscreenWindowCaptureAllowed(isAccessibilityRoot: true, isMinimized: false, appIsHidden: false, sessionIsUnlocked: true))
        XCTAssertFalse(offscreenWindowCaptureAllowed(isAccessibilityRoot: false, isMinimized: false, appIsHidden: false, sessionIsUnlocked: true))
        XCTAssertFalse(offscreenWindowCaptureAllowed(isAccessibilityRoot: true, isMinimized: true, appIsHidden: false, sessionIsUnlocked: true))
        XCTAssertFalse(offscreenWindowCaptureAllowed(isAccessibilityRoot: true, isMinimized: false, appIsHidden: true, sessionIsUnlocked: true))
        XCTAssertFalse(offscreenWindowCaptureAllowed(isAccessibilityRoot: true, isMinimized: false, appIsHidden: false, sessionIsUnlocked: false))
    }

    func testStrictUnlockIgnoresTheLockedOptIn() {
        XCTAssertTrue(sessionIsStrictlyUnlocked(MacSessionSnapshot(isLocked: false, isUnknown: false, rawKeysSeen: [])))
        XCTAssertFalse(sessionIsStrictlyUnlocked(MacSessionSnapshot(isLocked: true, isUnknown: false, rawKeysSeen: [])))
        XCTAssertFalse(sessionIsStrictlyUnlocked(MacSessionSnapshot(isLocked: true, isUnknown: true, rawKeysSeen: [])))
        XCTAssertFalse(sessionIsStrictlyUnlocked(MacSessionSnapshot(isLocked: false, isUnknown: true, rawKeysSeen: [])))
        XCTAssertThrowsError(
            try requireStrictlyUnlocked(MacSessionSnapshot(isLocked: true, isUnknown: false, rawKeysSeen: []), subject: "x")
        ) { error in
            XCTAssertEqual(
                (error as? ComputerUseError)?.errorDescription,
                "x cannot run while macOS is locked or its lock state is unknown, even when OPEN_COMPUTER_USE_ALLOW_LOCKED is set. Unlock the Mac and retry."
            )
        }
    }
}
