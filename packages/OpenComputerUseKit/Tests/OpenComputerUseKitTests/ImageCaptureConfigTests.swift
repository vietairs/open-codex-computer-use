import AppKit
import XCTest

@testable import OpenComputerUseKit

final class ImageCaptureConfigTests: XCTestCase {
    private var scratch: URL!

    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("ocu-image-config-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratch)
    }

    // MARK: - Resolution

    func testDefaultsKeepPngAndTheCurrentLimits() {
        let config = ImageCaptureConfig.resolve(image: [:], environment: [:])
        XCTAssertEqual(config, ImageCaptureConfig.defaults)
        XCTAssertEqual(config.format, .png)
        XCTAssertEqual(config.maxDimension, 1280)
        XCTAssertEqual(config.captureTimeout, 5)
        XCTAssertEqual(config.discardBelowPixelCount, 64)
        XCTAssertTrue(config.scaleDownAfterMaxSize)
    }

    func testFileValuesApplyAndEnvironmentOverridesThem() {
        let image: [String: Any] = ["format": "jpg", "maxLongEdgePixels": 640, "jpegQuality": 0.5]
        let fromFile = ImageCaptureConfig.resolve(image: image, environment: [:])
        XCTAssertEqual(fromFile.format, .jpg)
        XCTAssertEqual(fromFile.maxDimension, 640)
        XCTAssertEqual(fromFile.jpegQuality, 0.5)

        let overridden = ImageCaptureConfig.resolve(image: image, environment: [
            "OPEN_COMPUTER_USE_IMAGE_FORMAT": "png",
            "OPEN_COMPUTER_USE_IMAGE_MAX_DIMENSION": "800",
        ])
        XCTAssertEqual(overridden.format, .png)
        XCTAssertEqual(overridden.maxDimension, 800)
        XCTAssertEqual(overridden.jpegQuality, 0.5)
    }

    func testJpegIsAnAliasAndWebpIsRejected() {
        XCTAssertEqual(ImageCaptureConfig.resolve(image: ["format": "jpeg"], environment: [:]).format, .jpg)

        var warnings: [String] = []
        let config = ImageCaptureConfig.resolve(
            image: ["format": "webp"],
            environment: ["OPEN_COMPUTER_USE_IMAGE_FORMAT": "gif"],
            warning: { warnings.append($0) }
        )
        XCTAssertEqual(config.format, .png)
        XCTAssertEqual(warnings.count, 2)
    }

    func testInvalidValuesFallBackToTheLowerLayerWithAWarning() {
        var warnings: [String] = []
        let config = ImageCaptureConfig.resolve(
            image: [
                "jpegQuality": 3,
                "maxLongEdgePixels": 0,
                "captureTimeout": "soon",
                "discardBelowPixelCount": -4,
                "scaleDownAfterMaxSize": "yes",
            ],
            environment: [
                "OPEN_COMPUTER_USE_IMAGE_CAPTURE_TIMEOUT": "9999",
                "OPEN_COMPUTER_USE_IMAGE_DISCARD_BELOW_PIXEL_COUNT": "1.5",
                "OPEN_COMPUTER_USE_IMAGE_SCALE_DOWN_AFTER_MAX_SIZE": "1",
            ],
            warning: { warnings.append($0) }
        )
        XCTAssertEqual(config, ImageCaptureConfig.defaults)
        XCTAssertEqual(warnings.count, 8)
    }

    func testBooleanJsonValuesAreNotAcceptedAsNumbers() {
        let config = ImageCaptureConfig.resolve(image: ["maxLongEdgePixels": true, "jpegQuality": false], environment: [:])
        XCTAssertEqual(config.maxDimension, 1280)
        XCTAssertEqual(config.jpegQuality, 0.8)
    }

    func testLongEdgeLimitCanBeSwitchedOffByFileOrEnvironment() {
        XCTAssertNil(ImageCaptureConfig.resolve(image: ["maxLongEdgePixels": NSNull()], environment: [:]).maxDimension)
        XCTAssertNil(ImageCaptureConfig.resolve(image: [:], environment: ["OPEN_COMPUTER_USE_IMAGE_MAX_DIMENSION": "null"]).maxDimension)
        XCTAssertEqual(
            ImageCaptureConfig.resolve(
                image: ["maxLongEdgePixels": NSNull()],
                environment: ["OPEN_COMPUTER_USE_IMAGE_MAX_DIMENSION": "900"]
            ).maxDimension,
            900
        )
    }

    // MARK: - File loading

    func testLoadReadsTheConfiguredFile() throws {
        let file = try writeConfig(#"{"image":{"format":"jpg","maxLongEdgePixels":512}}"#)
        let config = ImageCaptureConfig.load(environment: ["OPEN_COMPUTER_USE_CONFIG_FILE": file.path])
        XCTAssertEqual(config.format, .jpg)
        XCTAssertEqual(config.maxDimension, 512)
    }

    func testLoadFallsBackToDefaultsForMalformedOrWronglyShapedFiles() throws {
        for body in ["not json", "[]", #"{"image":[1]}"#] {
            let file = try writeConfig(body)
            var warnings: [String] = []
            let config = ImageCaptureConfig.load(
                environment: ["OPEN_COMPUTER_USE_CONFIG_FILE": file.path],
                warning: { warnings.append($0) }
            )
            XCTAssertEqual(config, ImageCaptureConfig.defaults, body)
            XCTAssertFalse(warnings.isEmpty, body)
        }
    }

    func testLoadStillAppliesEnvironmentWhenTheFileIsMalformed() throws {
        let file = try writeConfig("not json")
        let config = ImageCaptureConfig.load(environment: [
            "OPEN_COMPUTER_USE_CONFIG_FILE": file.path,
            "OPEN_COMPUTER_USE_IMAGE_FORMAT": "jpg",
        ])
        XCTAssertEqual(config.format, .jpg)
    }

    func testLoadRefusesANonRegularFileAndAnOversizedFile() throws {
        // A directory and a character device stand in for any non-regular path such as a fifo.
        for path in [scratch.path, "/dev/null"] {
            var warnings: [String] = []
            let config = ImageCaptureConfig.load(
                environment: ["OPEN_COMPUTER_USE_CONFIG_FILE": path],
                warning: { warnings.append($0) }
            )
            XCTAssertEqual(config, ImageCaptureConfig.defaults, path)
            XCTAssertEqual(warnings.count, 1, path)
            XCTAssertTrue(warnings.first?.contains("notRegularFile") ?? false, path)
        }

        let padding = String(repeating: "x", count: Int(OCUConfiguration.maxFileBytes) + 1)
        let large = try writeConfig(#"{"image":{"format":"jpg"},"padding":"\#(padding)"}"#)
        var warnings: [String] = []
        XCTAssertEqual(
            ImageCaptureConfig.load(environment: ["OPEN_COMPUTER_USE_CONFIG_FILE": large.path], warning: { warnings.append($0) }),
            ImageCaptureConfig.defaults
        )
        XCTAssertEqual(warnings.count, 1)
        XCTAssertTrue(warnings.first?.contains("tooLarge") ?? false)
    }

    func testMissingFileIsSilentlyTheDefaults() {
        var warnings: [String] = []
        let config = ImageCaptureConfig.load(
            environment: ["OPEN_COMPUTER_USE_CONFIG_FILE": scratch.appendingPathComponent("absent.json").path],
            warning: { warnings.append($0) }
        )
        XCTAssertEqual(config, ImageCaptureConfig.defaults)
        XCTAssertTrue(warnings.isEmpty)
    }

    func testConfigPathResolutionRequiresAbsolutePaths() throws {
        XCTAssertThrowsError(try OCUConfiguration.fileURL(environment: ["OPEN_COMPUTER_USE_CONFIG_FILE": "relative.json"]))
        XCTAssertThrowsError(try OCUConfiguration.fileURL(environment: ["XDG_CONFIG_HOME": "relative"]))
        XCTAssertEqual(
            try OCUConfiguration.fileURL(environment: ["HOME": "/Users/test"]).path,
            "/Users/test/.config/ocu/config.json"
        )
        XCTAssertEqual(
            try OCUConfiguration.fileURL(environment: ["XDG_CONFIG_HOME": "/settings"]).path,
            "/settings/ocu/config.json"
        )
    }

    // MARK: - Safety boundary

    func testConfigurationCarriesNoPermissionOrSafetyKey() throws {
        let forbidden = [
            MacSessionLockPolicy.environmentKey,
            LocalChannelPolicy.environmentKey,
            "OPEN_COMPUTER_USE_DECISION_MODEL_BACKEND",
        ]
        for key in forbidden {
            XCTAssertFalse(OCUConfiguration.environmentKeys.contains(key), key)
        }
        for key in OCUConfiguration.environmentKeys {
            XCTAssertTrue(key == "OPEN_COMPUTER_USE_CONFIG_FILE" || key.hasPrefix("OPEN_COMPUTER_USE_IMAGE_"), key)
        }
    }

    func testFileKeysThatAreNotImageSettingsHaveNoEffect() throws {
        let file = try writeConfig(#"{"allowLocked":true,"lock":{"allow":true},"image":{"allowLocked":true,"format":"jpg"}}"#)
        let config = ImageCaptureConfig.load(environment: ["OPEN_COMPUTER_USE_CONFIG_FILE": file.path])
        var expected = ImageCaptureConfig.defaults
        expected.format = .jpg
        XCTAssertEqual(config, expected)
    }

    // MARK: - Encoding

    func testPngIsTheDefaultOutput() throws {
        let result = encodeScreenshot(for: try makeImage(width: 200, height: 100), config: .defaults)
        let data = try XCTUnwrap(result.data)
        XCTAssertTrue(data.starts(with: [0x89, 0x50, 0x4e, 0x47]))
        XCTAssertNil(result.note)
    }

    func testJpegOutputCarriesJpegBytesAndMimeType() throws {
        var config = ImageCaptureConfig.defaults
        config.format = .jpg
        let data = try XCTUnwrap(encodeScreenshot(for: try makeImage(width: 200, height: 100), config: config).data)
        XCTAssertTrue(data.starts(with: [0xff, 0xd8, 0xff]))
        XCTAssertEqual(try imageSize(of: data).width, 200)

        let item = ToolResultContentItem.screenshotImage(data)
        XCTAssertEqual(item.dictionary["mimeType"] as? String, "image/jpeg")
        XCTAssertEqual(item.dictionary["data"] as? String, data.base64EncodedString())
        let png = try XCTUnwrap(encodeScreenshot(for: try makeImage(width: 50, height: 50), config: .defaults).data)
        XCTAssertEqual(ToolResultContentItem.screenshotImage(png).dictionary["mimeType"] as? String, "image/png")
    }

    func testJpegQualityChangesTheEncodedSize() throws {
        let image = try makeNoisyImage(width: 300, height: 200)
        var low = ImageCaptureConfig.defaults
        low.format = .jpg
        low.jpegQuality = 0.1
        var high = low
        high.jpegQuality = 0.95
        let lowData = try XCTUnwrap(encodeScreenshot(for: image, config: low).data)
        let highData = try XCTUnwrap(encodeScreenshot(for: image, config: high).data)
        XCTAssertLessThan(lowData.count, highData.count)
    }

    func testLongEdgeLimitIsHonouredEvenFarBelowTheByteCapFloor() throws {
        var config = ImageCaptureConfig.defaults
        config.maxDimension = 100
        let data = try XCTUnwrap(encodeScreenshot(for: try makeImage(width: 2000, height: 1000), config: config).data)
        let size = try imageSize(of: data)
        XCTAssertEqual(size.width, 100)
        XCTAssertEqual(size.height, 50)
    }

    func testCustomLongEdgeLimitMapsCoordinatesAgainstTheReturnedPixels() throws {
        var config = ImageCaptureConfig.defaults
        config.maxDimension = 320
        let data = try XCTUnwrap(encodeScreenshot(for: try makeImage(width: 800, height: 600), config: config).data)
        let size = try XCTUnwrap(pngPixelSize(of: data))
        XCTAssertEqual(size.width, 320)
        XCTAssertEqual(size.height, 240)

        let windowBounds = CGRect(x: 0, y: 0, width: 400, height: 300)
        let point = screenshotPixelToWindowPoint(CGPoint(x: 160, y: 120), screenshotPixelSize: size, windowBounds: windowBounds)
        XCTAssertEqual(point.x, 200, accuracy: 0.001)
        XCTAssertEqual(point.y, 150, accuracy: 0.001)
    }

    func testDisabledLongEdgeLimitKeepsTheCapturedSize() throws {
        var config = ImageCaptureConfig.defaults
        config.maxDimension = nil
        let data = try XCTUnwrap(encodeScreenshot(for: try makeImage(width: 1600, height: 900), config: config).data)
        XCTAssertEqual(try imageSize(of: data).width, 1600)
    }

    func testOversizeImageIsOmittedWithAReasonWhenScalingIsOff() throws {
        var config = ImageCaptureConfig.defaults
        config.maxDimension = 500
        config.scaleDownAfterMaxSize = false
        let result = encodeScreenshot(for: try makeImage(width: 800, height: 400), config: config)
        XCTAssertNil(result.data)
        XCTAssertTrue(try XCTUnwrap(result.note).contains("scaleDownAfterMaxSize is false"))

        let fits = encodeScreenshot(for: try makeImage(width: 500, height: 400), config: config)
        XCTAssertNotNil(fits.data)
    }

    func testPixelCountThresholdKeepsEqualityAndDropsBelow() throws {
        let config = ImageCaptureConfig.defaults
        XCTAssertNotNil(encodeScreenshot(for: try makeImage(width: 8, height: 8), config: config).data)
        let tiny = encodeScreenshot(for: try makeImage(width: 7, height: 9), config: config)
        XCTAssertNil(tiny.data)
        XCTAssertTrue(try XCTUnwrap(tiny.note).contains("fewer than 64 pixels"))

        var disabled = config
        disabled.discardBelowPixelCount = 0
        XCTAssertNotNil(encodeScreenshot(for: try makeImage(width: 1, height: 1), config: disabled).data)
    }

    func testResizingBelowThePixelThresholdOmitsTheScreenshot() throws {
        var config = ImageCaptureConfig.defaults
        config.maxDimension = 10
        config.discardBelowPixelCount = 4096
        let result = encodeScreenshot(for: try makeImage(width: 2000, height: 1000), config: config)
        XCTAssertNil(result.data)
        XCTAssertTrue(try XCTUnwrap(result.note).contains("resizing would fall below"))
    }

    func testByteCeilingStillShrinksPngAndJpegOutput() throws {
        let image = try makeNoisyImage(width: 800, height: 600)
        for format in [ScreenshotFormat.png, .jpg] {
            var config = ImageCaptureConfig.defaults
            config.format = format
            config.jpegQuality = 1
            let unbounded = try XCTUnwrap(encodeScreenshot(for: image, config: config, maxBytes: Int.max).data)
            let ceiling = unbounded.count / 3
            let bounded = try XCTUnwrap(encodeScreenshot(for: image, config: config, maxBytes: ceiling, minScale: 0.05).data)
            XCTAssertLessThanOrEqual(bounded.count, ceiling, format.rawValue)
            XCTAssertLessThan(try imageSize(of: bounded).width, 800, format.rawValue)
        }
    }

    func testInvalidLongEdgeConfigurationOmitsInsteadOfEncoding() throws {
        var config = ImageCaptureConfig.defaults
        config.maxDimension = 0
        XCTAssertNil(encodeScreenshot(for: try makeImage(width: 100, height: 100), config: config).data)
        config.maxDimension = 12.5
        XCTAssertNil(encodeScreenshot(for: try makeImage(width: 100, height: 100), config: config).data)
    }

    // MARK: - Coordinate input without an image

    func testCoordinateInputIsRefusedOnlyWhenTheConfigOmittedTheScreenshot() throws {
        let omitted = makeSnapshot(data: nil, note: "Screenshot omitted: 7×9 has fewer than 64 pixels")
        XCTAssertThrowsError(try rejectCoordinateInputWhenScreenshotOmitted(omitted)) { error in
            XCTAssertTrue("\(error)".contains("coordinate input requires a delivered screenshot"))
        }
        // Never captured (no note): the existing carried-frame fallback still decides.
        XCTAssertNoThrow(try rejectCoordinateInputWhenScreenshotOmitted(makeSnapshot(data: nil, note: nil)))
        let delivered = try XCTUnwrap(encodeScreenshot(for: try makeImage(width: 20, height: 20), config: .defaults).data)
        XCTAssertNoThrow(try rejectCoordinateInputWhenScreenshotOmitted(makeSnapshot(data: delivered, note: nil)))
    }

    // MARK: - Helpers

    @discardableResult
    private func writeConfig(_ body: String) throws -> URL {
        let file = scratch.appendingPathComponent("config-\(UUID().uuidString).json")
        try Data(body.utf8).write(to: file)
        return file
    }

    private func imageSize(of data: Data) throws -> (width: Int, height: Int) {
        let size = try XCTUnwrap(pngPixelSize(of: data))
        return (Int(size.width), Int(size.height))
    }

    private func makeImage(width: Int, height: Int) throws -> CGImage {
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            pixels[index] = 80
            pixels[index + 1] = 140
            pixels[index + 2] = 220
        }
        return try makeCGImage(width: width, height: height, pixels: pixels)
    }

    private func makeNoisyImage(width: Int, height: Int) throws -> CGImage {
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                pixels[offset] = UInt8((x * 37 + y * 17) & 0xFF)
                pixels[offset + 1] = UInt8((x * 11 + y * 43) & 0xFF)
                pixels[offset + 2] = UInt8((x * 71 + y * 5) & 0xFF)
            }
        }
        return try makeCGImage(width: width, height: height, pixels: pixels)
    }

    private func makeCGImage(width: Int, height: Int, pixels: [UInt8]) throws -> CGImage {
        let provider = try XCTUnwrap(CGDataProvider(data: Data(pixels) as CFData))
        return try XCTUnwrap(CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ))
    }

    private func makeSnapshot(data: Data?, note: String?) -> AppSnapshot {
        AppSnapshot(
            app: RunningAppDescriptor(
                name: "Mail",
                bundleIdentifier: "com.apple.mail",
                pid: 4242,
                runningApplication: NSRunningApplication.current
            ),
            windowTitle: "Inbox",
            windowBounds: CGRect(x: 0, y: 0, width: 400, height: 300),
            targetWindowID: 1,
            targetWindowLayer: 0,
            screenshotData: data,
            mode: .accessibility,
            treeLines: [],
            treeLineOffsets: [:],
            focusedSummary: nil,
            focusedElement: nil,
            selectedText: nil,
            elements: [:],
            windowContentIsEmpty: false,
            screenshotNote: note
        )
    }
}
