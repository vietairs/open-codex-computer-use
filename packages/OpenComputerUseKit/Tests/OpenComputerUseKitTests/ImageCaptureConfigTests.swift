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

    func testLoadRefusesAFifoWithoutBlocking() throws {
        let fifo = scratch.appendingPathComponent("config.fifo")
        XCTAssertEqual(mkfifo(fifo.path, 0o600), 0)
        var warnings: [String] = []
        let config = ImageCaptureConfig.load(
            environment: ["OPEN_COMPUTER_USE_CONFIG_FILE": fifo.path],
            warning: { warnings.append($0) }
        )
        XCTAssertEqual(config, ImageCaptureConfig.defaults)
        XCTAssertEqual(warnings.count, 1)
        XCTAssertTrue(warnings.first?.contains("notRegularFile") ?? false)
    }

    func testLoadFollowsASymlinkToARegularFile() throws {
        let target = try writeConfig(#"{"image":{"format":"jpg"}}"#)
        let link = scratch.appendingPathComponent("link.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        XCTAssertEqual(ImageCaptureConfig.load(environment: ["OPEN_COMPUTER_USE_CONFIG_FILE": link.path]).format, .jpg)
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

    func testCaptureTimeoutIsCappedAtThirtySeconds() {
        XCTAssertEqual(
            ImageCaptureConfig.resolve(image: [:], environment: ["OPEN_COMPUTER_USE_IMAGE_CAPTURE_TIMEOUT": "30"]).captureTimeout,
            30
        )
        var warnings: [String] = []
        let config = ImageCaptureConfig.resolve(
            image: ["captureTimeout": 31],
            environment: [:],
            warning: { warnings.append($0) }
        )
        XCTAssertEqual(config.captureTimeout, ImageCaptureConfig.defaults.captureTimeout)
        XCTAssertEqual(warnings.count, 1)
    }

    // MARK: - Settings relayed to the app agent

    func testForwardedSettingsReadNoConfigFileAndNoAgentEnvironment() throws {
        let file = try writeConfig(#"{"image":{"format":"jpg","maxLongEdgePixels":512}}"#)
        setenv("OPEN_COMPUTER_USE_IMAGE_MAX_DIMENSION", "555", 1)
        addTeardownBlock { unsetenv("OPEN_COMPUTER_USE_IMAGE_MAX_DIMENSION") }

        // A path in the call and a value in the agent's own environment both have no effect.
        let config = ImageCaptureConfig.forwarded(environment: [
            "OPEN_COMPUTER_USE_CONFIG_FILE": file.path,
            "HOME": scratch.path,
        ])
        XCTAssertEqual(config, ImageCaptureConfig.defaults)
    }

    func testForwardedSettingsApplyOnlyValidValues() {
        var expected = ImageCaptureConfig.defaults
        expected.format = .jpg
        let config = ImageCaptureConfig.forwarded(environment: [
            "OPEN_COMPUTER_USE_IMAGE_FORMAT": "jpg",
            "OPEN_COMPUTER_USE_IMAGE_JPEG_QUALITY": "not a number",
            "OPEN_COMPUTER_USE_IMAGE_CAPTURE_TIMEOUT": "9000",
            "OPEN_COMPUTER_USE_ALLOW_LOCKED": "1",
        ])
        XCTAssertEqual(config, expected)
    }

    func testResolvedSettingsRoundTripThroughTheForwardedForm() throws {
        let file = try writeConfig(
            #"{"image":{"format":"jpg","jpegQuality":0.35,"captureTimeout":7.5,"scaleDownAfterMaxSize":false,"discardBelowPixelCount":12}}"#
        )
        for maxDimension in ["640", "null"] {
            let resolved = ImageCaptureConfig.load(environment: [
                "OPEN_COMPUTER_USE_CONFIG_FILE": file.path,
                "OPEN_COMPUTER_USE_IMAGE_MAX_DIMENSION": maxDimension,
            ])
            let values = resolved.environmentValues
            XCTAssertEqual(Set(values.keys), OCUConfiguration.imageEnvironmentKeys)
            XCTAssertEqual(ImageCaptureConfig.forwarded(environment: values), resolved, maxDimension)
        }
        // An invalid file value is replaced by a valid one before it is forwarded.
        let invalid = try writeConfig(#"{"image":{"format":"webp"}}"#)
        let values = ImageCaptureConfig.load(environment: ["OPEN_COMPUTER_USE_CONFIG_FILE": invalid.path]).environmentValues
        XCTAssertEqual(values["OPEN_COMPUTER_USE_IMAGE_FORMAT"], "png")
    }

    func testProcessOverridesDropEveryScreenshotKeyAndKeepTheRest() {
        var environment = Dictionary(uniqueKeysWithValues: OCUConfiguration.environmentKeys.map { ($0, "x") })
        // Image settings alone leave nothing to set on the shared process, so such a call takes no lock.
        XCTAssertTrue(OCUConfiguration.processOverrides(from: environment).isEmpty)

        environment["OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS"] = "1"
        XCTAssertEqual(
            OCUConfiguration.processOverrides(from: environment),
            ["OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS": "1"]
        )
    }

    func testRelayedEnvironmentCarriesValidatedSettingsInPlaceOfRawOnes() {
        let process = [
            "OPEN_COMPUTER_USE_CONFIG_FILE": "/tmp/config.json",
            "OPEN_COMPUTER_USE_IMAGE_FORMAT": "webp",
            "OPEN_COMPUTER_USE_ALLOW_LOCKED": "1",
            "OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS": "1",
            "PATH": "/usr/bin",
        ]
        // A call that takes no screenshot carries no screenshot setting and no path.
        XCTAssertEqual(
            OCUConfiguration.relayedEnvironment(processEnvironment: process, imageSettings: nil),
            ["OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS": "1"]
        )
        var validated = ImageCaptureConfig.defaults.environmentValues
        validated["OPEN_COMPUTER_USE_ALLOW_LOCKED"] = "1"
        validated["OPEN_COMPUTER_USE_CONFIG_FILE"] = "/tmp/other.json"
        let relayed = OCUConfiguration.relayedEnvironment(processEnvironment: process, imageSettings: validated)
        XCTAssertEqual(relayed["OPEN_COMPUTER_USE_IMAGE_FORMAT"], "png")
        XCTAssertEqual(relayed["OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS"], "1")
        XCTAssertNil(relayed["OPEN_COMPUTER_USE_CONFIG_FILE"])
        XCTAssertNil(relayed["OPEN_COMPUTER_USE_ALLOW_LOCKED"])
        XCTAssertNil(relayed["PATH"])
        XCTAssertEqual(relayed.count, OCUConfiguration.imageEnvironmentKeys.count + 1)
    }

    func testPeerEnvironmentNeverCarriesTheConfigFilePath() {
        let sanitized = MacSessionLockPolicy.sanitizePeerEnvironment([
            "OPEN_COMPUTER_USE_CONFIG_FILE": "/tmp/chosen-by-a-peer.json",
            "OPEN_COMPUTER_USE_IMAGE_FORMAT": "jpg",
        ])
        XCTAssertEqual(sanitized, ["OPEN_COMPUTER_USE_IMAGE_FORMAT": "jpg"])
    }

    func testCallSettingsReplaceTheProcessSettingsForOneCallOnly() {
        let service = ComputerUseService()
        let outside = service.effectiveImageConfig
        XCTAssertEqual(outside, ImageCaptureConfig.current)

        service.withForwardedImageSettings(environment: ["OPEN_COMPUTER_USE_IMAGE_MAX_DIMENSION": "777"]) {
            XCTAssertEqual(service.effectiveImageConfig.maxDimension, 777)
        }
        XCTAssertEqual(service.effectiveImageConfig, outside)
    }

    /// The settings the agent applies come from the dispatcher: it must wrap the call in the forwarded settings, so a
    /// relayed host gets its own values instead of the agent's launch environment or config file.
    func testDispatcherAppliesTheForwardedSettingsToTheCallAndOnlyToIt() {
        struct StopBeforeAnyApp: Error {}
        struct Unlocked: MacSessionStateProvider {
            func currentSnapshot() -> MacSessionSnapshot {
                MacSessionSnapshot(isLocked: false, isUnknown: false, rawKeysSeen: ["CGSSessionScreenIsLocked"])
            }
        }
        var seenDuringCall: [ImageCaptureConfig] = []
        var service: ComputerUseService!
        service = ComputerUseService(appResolver: { _ in
            seenDuringCall.append(service.effectiveImageConfig)
            throw StopBeforeAnyApp()
        })
        let dispatcher = ComputerUseToolDispatcher(service: service, guard: MacSessionGuard(provider: Unlocked()))
        let processSettings = ImageCaptureConfig.current
        XCTAssertNotEqual(processSettings.maxDimension, 777)

        XCTAssertThrowsError(
            try dispatcher.callTool(
                name: "get_app_state",
                arguments: ["app": "Anything"],
                environment: [
                    "OPEN_COMPUTER_USE_IMAGE_MAX_DIMENSION": "777",
                    "OPEN_COMPUTER_USE_IMAGE_FORMAT": "jpg",
                ]
            )
        )
        XCTAssertEqual(seenDuringCall.count, 1)
        XCTAssertEqual(seenDuringCall.first?.maxDimension, 777)
        XCTAssertEqual(seenDuringCall.first?.format, .jpg)

        // A call that carries no per-call environment uses the process's own settings, and the previous call's
        // values did not stay behind.
        XCTAssertThrowsError(try dispatcher.callTool(name: "get_app_state", arguments: ["app": "Anything"]))
        XCTAssertEqual(seenDuringCall.count, 2)
        XCTAssertEqual(seenDuringCall.last, processSettings)
    }

    func testOnlyScreenshotTakingRequestsCarryTheSettings() {
        func line(_ tool: String) -> String {
            #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"\#(tool)","arguments":{}}}"#
        }
        XCTAssertTrue(StdioMCPServer.mayCaptureScreenshot(line: line("get_app_state")))
        XCTAssertTrue(StdioMCPServer.mayCaptureScreenshot(line: line("click")))
        XCTAssertFalse(StdioMCPServer.mayCaptureScreenshot(line: line("list_apps")))
        XCTAssertFalse(StdioMCPServer.mayCaptureScreenshot(line: line(ToolDefinitions.decideNextAction.name)))
        XCTAssertFalse(StdioMCPServer.mayCaptureScreenshot(line: #"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"#))
        XCTAssertFalse(StdioMCPServer.mayCaptureScreenshot(line: "not json"))

        XCTAssertTrue(openComputerUseCLIMayCaptureScreenshot(arguments: ["snapshot", "Mail"]))
        XCTAssertTrue(openComputerUseCLIMayCaptureScreenshot(arguments: ["call", "get_app_state", "--args", #"{"app":"Mail"}"#]))
        XCTAssertFalse(openComputerUseCLIMayCaptureScreenshot(arguments: ["list-apps"]))
        XCTAssertFalse(openComputerUseCLIMayCaptureScreenshot(arguments: ["call", ToolDefinitions.decideNextAction.name, "--args", #"{"app":"Mail","goal":"x"}"#]))
        XCTAssertFalse(openComputerUseCLIMayCaptureScreenshot(arguments: []))
    }

    func testSnapshotWithoutAScreenshotNeverReadsTheConfiguration() {
        var reads = 0
        let resolve = { () -> ImageCaptureConfig in reads += 1; return .defaults }

        XCTAssertNil(imageConfigForCapture(shouldCapture: false, isOnscreen: true, resolve: resolve))
        XCTAssertNil(imageConfigForCapture(shouldCapture: true, isOnscreen: false, resolve: resolve))
        XCTAssertEqual(reads, 0)
        XCTAssertNotNil(imageConfigForCapture(shouldCapture: true, isOnscreen: true, resolve: resolve))
        XCTAssertEqual(reads, 1)
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

    func testProductionByteCapAppliesToPngAndJpegByDefault() throws {
        XCTAssertEqual(screenshotResultMaxBytes, 900_000)
        let image = try makeRandomImage(width: 1200, height: 900)
        for format in [ScreenshotFormat.png, .jpg] {
            var config = ImageCaptureConfig.defaults
            config.format = format
            config.jpegQuality = 1
            config.maxDimension = nil
            let unbounded = try XCTUnwrap(encodeScreenshot(for: image, config: config, maxBytes: Int.max).data)
            XCTAssertGreaterThan(unbounded.count, screenshotResultMaxBytes, format.rawValue)

            // Default parameters: the cap comes from the production constant, not from the test.
            let bounded = try XCTUnwrap(encodeScreenshot(for: image, config: config).data)
            XCTAssertLessThanOrEqual(bounded.count, screenshotResultMaxBytes, format.rawValue)
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

    func testServiceRefusesCoordinateClickAndDragBeforeAnyInputWhenTheScreenshotWasOmitted() {
        let omitted = makeSnapshot(data: nil, note: "Screenshot omitted: 7×9 has fewer than 64 pixels")
        let service = ComputerUseService()
        service.storeSnapshot(omitted, query: "Mail", app: omitted.app)

        func assertRefused(_ body: () throws -> ToolCallResult, _ label: String) {
            XCTAssertThrowsError(try body(), label) { error in
                guard case ComputerUseError.stateUnavailable(let message) = error else {
                    return XCTFail("\(label): unexpected error \(error)")
                }
                XCTAssertTrue(message.contains("coordinate input requires a delivered screenshot"), label)
            }
        }
        assertRefused({
            try service.click(app: "Mail", elementIndex: nil, x: 10, y: 10, clickCount: 1, mouseButton: "left")
        }, "click")
        assertRefused({
            try service.drag(app: "Mail", fromX: 1, fromY: 1, toX: 20, toY: 20)
        }, "drag")
    }

    func testSearchMergeKeepsTheOmittedScreenshotNote() throws {
        let note = "Screenshot omitted: long edge 2000 exceeds maxLongEdgePixels 1280; scaleDownAfterMaxSize is false"
        let cached = makeSnapshot(data: nil, note: note)
        let window: ElementSearchWindowInfo = (
            windowID: 1, layer: 0, bounds: CGRect(x: 0, y: 0, width: 400, height: 300), title: "Inbox",
            focusedElement: nil, isOffStage: false
        )
        let merged = mergeElementSearchHits([], rows: [], into: cached, window: window, app: cached.app)
        XCTAssertEqual(merged.screenshotNote, note)
        XCTAssertThrowsError(try rejectCoordinateInputWhenScreenshotOmitted(merged))
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

    /// Incompressible pixels from a fixed seed, so the encoded size does not depend on a lucky pattern.
    private func makeRandomImage(width: Int, height: Int) throws -> CGImage {
        var state: UInt64 = 0x9E37_79B9_7F4A_7C15
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            pixels[offset] = UInt8(truncatingIfNeeded: state)
            pixels[offset + 1] = UInt8(truncatingIfNeeded: state >> 16)
            pixels[offset + 2] = UInt8(truncatingIfNeeded: state >> 32)
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
