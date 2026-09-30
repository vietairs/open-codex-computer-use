import AppKit
import ApplicationServices
import Foundation
import ImageIO

struct VisualCursorTarget: Equatable {
    let point: CGPoint
    let window: CursorTargetWindow?
}

/// The validated, backend-specific destination for one `decideNextAction` call: the endpoint/config only, not yet
/// the `DecisionReadoutProviding` instance, so the deadline can be captured just before the model calls start.
/// Internal (not `private`) so `@testable import` can exercise `ComputerUseService.resolveValidatedDecisionBackend`
/// / `buildDecisionProvider` directly — the backend-selection and provider-construction seam of `decideNextAction`
/// — without needing a live AX-resolved app for the snapshot step in between.
enum ValidatedDecisionBackend {
    case llama(DecisionModelEndpoint)
    case remote(DecisionRemoteBackendConfig)
}

public enum ClickMethod: String, CaseIterable, Sendable {
    case auto
    case accessibility
    case appPost = "app_post"
    case skyClick = "sky_click"
    case global
}

func clickActionSnapshotRecoveryPolicy(for method: ClickMethod) -> SnapshotRecoveryPolicy {
    method == .skyClick ? .readOnly : .allowActivation
}

/// What a core action needs to know about the call it runs in. A single action carries only the screenshot
/// choice. A batch step also carries the snapshot pinned at batch start, which resolves `element_index` only.
struct ActionContext {
    let includeScreenshot: Bool
    let pinnedSnapshot: AppSnapshot?

    var isBatchStep: Bool { pinnedSnapshot != nil }

    static func single(includeScreenshot: Bool) -> ActionContext {
        ActionContext(includeScreenshot: includeScreenshot, pinnedSnapshot: nil)
    }

    static func batchStep(pinned: AppSnapshot) -> ActionContext {
        ActionContext(includeScreenshot: false, pinnedSnapshot: pinned)
    }
}

/// The element `type_text` writes to. A batch reads focus live because an earlier step may have moved it; a single
/// action keeps using the focus its snapshot recorded (`liveFocus` is not called).
func typingTargetElement(
    context: ActionContext,
    snapshotFocus: AXUIElement?,
    liveFocus: () -> AXUIElement?
) -> AXUIElement? {
    context.isBatchStep ? liveFocus() : snapshotFocus
}

/// Geometry for one batch step, taken from the live window and the live element frame and never from the pinned
/// snapshot: the pinned values may be stale after an earlier step, and a stale frame would click the wrong place.
/// When x/y coordinates are scaled by the screenshot pinned at batch start, that image only describes the window
/// at its pinned size; after a resize the step fails closed with the same error a single x/y click gives.
func batchStepGeometry(
    pinnedWindowBounds: CGRect?,
    liveWindowBounds: CGRect?,
    liveLocalFrame: CGRect?,
    needsElementFrame: Bool,
    elementIndex: String?,
    scalesByPinnedScreenshot: Bool = false
) throws -> (windowBounds: CGRect?, localFrame: CGRect?) {
    if liveWindowBounds == nil, pinnedWindowBounds != nil {
        throw ComputerUseError.stateUnavailable("the target window is no longer on screen; call get_app_state")
    }

    if scalesByPinnedScreenshot, liveWindowBounds?.size != pinnedWindowBounds?.size {
        throw ComputerUseError.stateUnavailable(screenshotFrameMismatchMessage)
    }

    guard needsElementFrame else {
        return (liveWindowBounds, nil)
    }

    guard let liveLocalFrame else {
        throw ComputerUseError.stateUnavailable(
            "element_index \(elementIndex ?? "") is no longer on screen; call get_app_state"
        )
    }

    return (liveWindowBounds, liveLocalFrame)
}

func parseClickMethod(_ rawValue: String?) throws -> ClickMethod {
    let normalized = rawValue?
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased() ?? ClickMethod.auto.rawValue

    guard let method = ClickMethod(rawValue: normalized) else {
        let expected = ClickMethod.allCases.map(\.rawValue).joined(separator: ", ")
        throw ComputerUseError.message(
            "Invalid click_method '\(rawValue ?? "")'. Expected one of: \(expected)"
        )
    }

    return method
}

func validateClickMethod(
    _ method: ClickMethod,
    hasElementIndex: Bool,
    environment: [String: String]
) throws {
    if method == .accessibility, !hasElementIndex {
        throw ComputerUseError.message("click_method 'accessibility' requires element_index")
    }

    if method == .global, !globalPointerFallbacksEnabled(environment: environment) {
        throw ComputerUseError.message(
            "click_method 'global' requires OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS=1 because it may move the system pointer and change foreground focus"
        )
    }
}

func validateSkyClickArguments(
    method: ClickMethod,
    mouseButton: String,
    clickCount: Int
) throws {
    guard method == .skyClick else {
        return
    }

    guard mouseButton.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == MouseButtonKind.left.rawValue else {
        throw ComputerUseError.message(
            "click_method 'sky_click' only supports mouse_button 'left'"
        )
    }

    guard (1...2).contains(clickCount) else {
        throw ComputerUseError.message(
            "click_method 'sky_click' supports click_count 1 or 2"
        )
    }
}

struct VisualCursorScreenMapping: Equatable {
    let screenStateFrame: CGRect
    let appKitFrame: CGRect
}

func currentVisualCursorScreenMappings() -> [VisualCursorScreenMapping] {
    NSScreen.screens.compactMap { screen in
        guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }

        return VisualCursorScreenMapping(
            screenStateFrame: CGDisplayBounds(CGDirectDisplayID(screenNumber.uint32Value)),
            appKitFrame: screen.frame
        )
    }
}

func screenStatePointToAppKitGlobalPoint(
    fromScreenStatePoint point: CGPoint,
    screenMappings: [VisualCursorScreenMapping] = currentVisualCursorScreenMappings()
) -> CGPoint {
    guard let mapping = screenMappings.first(where: { $0.screenStateFrame.contains(point) }) else {
        return point
    }

    let localX = point.x - mapping.screenStateFrame.minX
    let localY = point.y - mapping.screenStateFrame.minY

    return CGPoint(
        x: mapping.appKitFrame.minX + localX,
        y: mapping.appKitFrame.maxY - localY
    )
}

func visualCursorAppKitPoint(
    fromScreenStatePoint point: CGPoint,
    screenMappings: [VisualCursorScreenMapping] = currentVisualCursorScreenMappings()
) -> CGPoint {
    screenStatePointToAppKitGlobalPoint(
        fromScreenStatePoint: point,
        screenMappings: screenMappings
    )
}

func inputEventPoint(
    fromScreenStatePoint point: CGPoint,
    screenMappings: [VisualCursorScreenMapping] = currentVisualCursorScreenMappings()
) -> CGPoint {
    point
}

func makeVisualCursorTarget(
    at point: CGPoint,
    targetWindowID: CGWindowID?,
    targetWindowLayer: Int?,
    screenMappings: [VisualCursorScreenMapping] = currentVisualCursorScreenMappings()
) -> VisualCursorTarget {
    VisualCursorTarget(
        point: screenStatePointToAppKitGlobalPoint(
            fromScreenStatePoint: point,
            screenMappings: screenMappings
        ),
        window: targetWindowID.map { CursorTargetWindow(windowID: $0, layer: targetWindowLayer ?? 0) }
    )
}

func makeVisualCursorTarget(
    localFrame: CGRect?,
    windowBounds: CGRect?,
    targetWindowID: CGWindowID?,
    targetWindowLayer: Int?,
    screenMappings: [VisualCursorScreenMapping] = currentVisualCursorScreenMappings()
) -> VisualCursorTarget? {
    guard let localFrame, let windowBounds else {
        return nil
    }

    let point = CGPoint(
        x: windowBounds.minX + localFrame.midX,
        y: windowBounds.minY + localFrame.midY
    )
    return makeVisualCursorTarget(
        at: point,
        targetWindowID: targetWindowID,
        targetWindowLayer: targetWindowLayer,
        screenMappings: screenMappings
    )
}

func inputFallbackDebugEnabled(environment: [String: String]) -> Bool {
    guard let rawValue = environment["OPEN_COMPUTER_USE_DEBUG_INPUT_FALLBACKS"]?
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
    else {
        return false
    }

    return ["1", "true", "yes", "on"].contains(rawValue)
}

func globalPointerFallbacksEnabled(environment: [String: String]) -> Bool {
    guard let rawValue = environment["OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS"]?
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
    else {
        return false
    }

    return ["1", "true", "yes", "on"].contains(rawValue)
}

/// How a `drag` is delivered. `drag` has no method argument; the path is decided
/// by the same process-level gate that authorizes `click_method=global`.
enum DragDeliveryPath: String, CaseIterable {
    /// `CGEvent.postToPid`: never moves the system pointer, but the events do not
    /// pass through the window server, so window-server drag sessions (window
    /// moves, text selection, Finder drag-and-drop) are not driven.
    case appPost = "app_post"
    /// `.cghidEventTap`: drives window-server drag sessions and may move the
    /// real pointer or change foreground focus.
    case global
}

func dragDeliveryPath(environment: [String: String]) -> DragDeliveryPath {
    globalPointerFallbacksEnabled(environment: environment) ? .global : .appPost
}

func dragDeliveryNote(for path: DragDeliveryPath) -> String {
    switch path {
    case .appPost:
        return "Drag delivered via app_post: mouse events were posted directly to the target process and the system pointer did not move. This path cannot drive window-server drag sessions such as window moves, text selection, or Finder drag-and-drop. If the drag had no effect, set OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS=1 in the server process environment to use the global pointer path, which may move the real pointer and change foreground focus."
    case .global:
        return "Drag delivered via global pointer path: OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS is enabled, so the real pointer may have moved and foreground focus may have changed."
    }
}

/// Inserts the delivery note after the snapshot text and before any screenshot,
/// so `primaryText` remains the snapshot for existing consumers.
func appendingDragDeliveryNote(to result: ToolCallResult, path: DragDeliveryPath) -> ToolCallResult {
    var content = result.content
    let insertIndex = content.firstIndex { $0.dictionary["type"] as? String == "image" } ?? content.endIndex
    content.insert(.text(dragDeliveryNote(for: path)), at: insertIndex)
    return ToolCallResult(content: content, isError: result.isError)
}

/// The screenshot most recently returned to the caller for an app. Text-only action results carry no
/// image, so x/y coordinates keep referring to this frame until a new screenshot is returned.
struct ReturnedScreenshotFrame: Equatable {
    let windowID: CGWindowID?
    let windowSize: CGSize
    let pixelSize: CGSize
}

/// Settle time after an action before its result is read, and between steps of a perform_actions batch.
let postActionSettleInterval: TimeInterval = 0.15

let screenshotFrameMismatchMessage =
    "x/y coordinates refer to a screenshot of a different window or window size. Call get_app_state, or repeat the action with include_screenshot=true, and read coordinates from the new screenshot."

/// Picks the pixel size that x/y coordinates are scaled by.
/// 1. The snapshot's own screenshot wins.
/// 2. With no screenshot ever returned for the app, there is nothing to scale by (nil, scale 1).
/// 3. A previously returned screenshot still applies while its window identity and size are unchanged.
/// 4. Otherwise the coordinates would be read from a stale frame, so fail closed.
func resolveScreenshotPixelSize(
    snapshotPixelSize: CGSize?,
    windowID: CGWindowID?,
    windowBounds: CGRect?,
    lastReturned: ReturnedScreenshotFrame?
) throws -> CGSize? {
    if let snapshotPixelSize {
        return snapshotPixelSize
    }

    guard let lastReturned else {
        return nil
    }

    if lastReturned.windowID == windowID, lastReturned.windowSize == windowBounds?.size {
        return lastReturned.pixelSize
    }

    throw ComputerUseError.stateUnavailable(screenshotFrameMismatchMessage)
}

func actionCapturePolicy(includeScreenshot: Bool) -> SnapshotCapturePolicy {
    includeScreenshot ? .always : .whenTreeEmpty
}

/// The full state always carries its screenshot, the compact view never does, and an action result
/// carries one only on request or when the window has no content elements (menu-bar items do not count).
func shouldAttachScreenshot(style: SnapshotTextStyle, includeScreenshot: Bool, treeIsEmpty: Bool) -> Bool {
    switch style {
    case .compactActionable:
        return false
    case .fullState:
        return true
    case .actionResult:
        return includeScreenshot || treeIsEmpty
    }
}

/// Pixel dimensions from a PNG header, without decoding the image.
func pngPixelSize(of data: Data) -> CGSize? {
    guard
        let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
        let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
        let pixelWidth = properties[kCGImagePropertyPixelWidth] as? CGFloat,
        let pixelHeight = properties[kCGImagePropertyPixelHeight] as? CGFloat,
        pixelWidth > 0,
        pixelHeight > 0
    else {
        return nil
    }

    return CGSize(width: pixelWidth, height: pixelHeight)
}

func screenshotPixelScale(
    screenshotPixelSize: CGSize?,
    windowBounds: CGRect?
) -> CGSize {
    guard
        let screenshotPixelSize,
        let windowBounds,
        windowBounds.width > 0,
        windowBounds.height > 0,
        screenshotPixelSize.width > 0,
        screenshotPixelSize.height > 0
    else {
        return CGSize(width: 1, height: 1)
    }

    return CGSize(
        width: screenshotPixelSize.width / windowBounds.width,
        height: screenshotPixelSize.height / windowBounds.height
    )
}

func screenshotPixelToWindowPoint(
    _ point: CGPoint,
    screenshotPixelSize: CGSize?,
    windowBounds: CGRect?
) -> CGPoint {
    let scale = screenshotPixelScale(
        screenshotPixelSize: screenshotPixelSize,
        windowBounds: windowBounds
    )
    return CGPoint(
        x: point.x / scale.width,
        y: point.y / scale.height
    )
}

let nonSettableSetValueErrorMessage = "Cannot set a value for an element that is not settable"

func setValueAttributeIsSettable(result: AXError, settable: Bool, attribute: String) throws -> Bool {
    guard result == .success else {
        throw ComputerUseError.message("AXUIElementIsAttributeSettable(\(attribute)) failed with \(result.rawValue)")
    }

    return settable
}

func invalidSecondaryActionErrorMessage(action: String, elementIndex: Int) -> String {
    "\(action) is not a valid secondary action for \(elementIndex)"
}

func localClickActionPoints(frame: CGRect, isSyntheticText: Bool) -> [CGPoint] {
    let center = CGPoint(x: frame.midX, y: frame.midY)
    let leading = CGPoint(
        x: frame.minX + min(max(frame.width * 0.3, 20), max(frame.width - 4, 20)),
        y: frame.midY
    )

    if isSyntheticText {
        return [leading]
    }

    if abs(leading.x - center.x) < 1 {
        return [center]
    }

    return [center, leading]
}

/// Subroles of a window's title-bar buttons. Pressing one closes, minimizes, zooms or full-screens the window.
private let windowTitleBarButtonSubroles: Set<String> = [
    "AXCloseButton",
    "AXMinimizeButton",
    "AXZoomButton",
    "AXFullScreenButton",
]

/// Pure. Drops window title-bar buttons from the descendants an `auto` click may press on the target's behalf.
/// On a window target they are often the smallest pressable children, so they would otherwise win the ranking.
/// A click aimed at such a button by its own element_index never goes through this filter and still works.
func excludingWindowTitleBarButtons(_ candidates: [ElementRecord]) -> [ElementRecord] {
    candidates.filter { candidate in
        guard let subrole = candidate.subrole else {
            return true
        }
        return !windowTitleBarButtonSubroles.contains(subrole)
    }
}

/// Pure. True for a tab bar's close button, which apps keep in the tree even while it is hidden.
func isTabCloseButton(_ candidate: ElementRecord, labels: [String]) -> Bool {
    if candidate.subrole == "AXCloseButton" {
        return true
    }
    return labels.contains { label in
        label.localizedCaseInsensitiveContains("_closeButton") || label.caseInsensitiveCompare("Close tab") == .orderedSame
    }
}

/// Pure. Drops descendants an `auto` click must not press on the target's behalf: tab close buttons, and controls
/// that are not on screen inside the target (a zero-width or zero-height frame, or a frame outside the target's).
/// `labels` reads a candidate's title, description and identifier; it is only asked for actionable candidates.
func excludingHiddenAndTabCloseCandidates(
    _ candidates: [ElementRecord],
    targetFrame: CGRect?,
    labels: (ElementRecord) -> [String]
) -> [ElementRecord] {
    candidates.filter { candidate in
        if let frame = candidate.localFrame {
            if frame.width <= 0 || frame.height <= 0 {
                return false
            }
            if let targetFrame, !frame.intersects(targetFrame) {
                return false
            }
        }
        return !isTabCloseButton(candidate, labels: candidate.rawActions.isEmpty ? [] : labels(candidate))
    }
}

/// Pure. The refusal text for an element_index click that targets a window itself, or nil when the click may go on.
/// A window has no press of its own, so an `auto` or `accessibility` click would land on whichever control happens
/// to sit inside it. Explicit posting methods are the caller's own choice and stay allowed.
func windowElementClickRefusal(role: String?, method: ClickMethod, elementIndex: String) -> String? {
    guard role == kAXWindowRole as String, method == .auto || method == .accessibility else {
        return nil
    }
    return "element \(elementIndex) is the window itself; click a control inside it by element_index. "
        + "Open Computer Use does not raise or select windows."
}

func isLikelySyntheticSideActionCandidate(
    parentFrame: CGRect?,
    candidateFrame: CGRect?,
    hasPrimaryAction: Bool,
    labels: [String]
) -> Bool {
    let hasSideActionLabel = labels.contains { label in
        let normalized = label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else {
            return false
        }

        if normalized == "完成" || normalized == "done" || normalized == "complete" || normalized == "archive" {
            return true
        }

        if normalized.count <= 24 {
            if normalized.contains("完成") {
                return true
            }

            if normalized.contains("mark") && (normalized.contains("done") || normalized.contains("complete")) {
                return true
            }
        }

        return false
    }

    guard let parentFrame, let candidateFrame else {
        return false
    }

    let trailingBandWidth = min(max(parentFrame.width * 0.22, 56), 140)
    let isTrailing = candidateFrame.midX >= parentFrame.maxX - trailingBandWidth
    let compactWidth = candidateFrame.width <= max(88, parentFrame.width * 0.18)
    let compactHeight = candidateFrame.height <= max(44, parentFrame.height * 1.2)
    let isCompact = compactWidth && compactHeight

    if hasSideActionLabel && hasPrimaryAction && isCompact {
        return true
    }

    return isTrailing && isCompact && (hasPrimaryAction || hasSideActionLabel)
}

func shouldScanDescendantsOfHitRecord(originalFrame: CGRect?, hitFrame: CGRect?) -> Bool {
    guard let originalFrame, let hitFrame else {
        return true
    }

    let originalArea = max(originalFrame.width * originalFrame.height, 1)
    let hitArea = hitFrame.width * hitFrame.height
    if hitArea > max(originalArea * 12, 20_000) {
        return false
    }

    if hitFrame.height > max(originalFrame.height * 4, 96),
       hitFrame.width > max(originalFrame.width * 2, 240)
    {
        return false
    }

    return true
}

func isLikelyContainingRowActionFrame(
    targetFrame: CGRect,
    candidateFrame: CGRect?,
    hasPrimaryAction: Bool
) -> Bool {
    let targetCenter = CGPoint(x: targetFrame.midX, y: targetFrame.midY)
    guard
        hasPrimaryAction,
        let candidateFrame,
        candidateFrame.insetBy(dx: -2, dy: -2).contains(targetCenter),
        candidateFrame.width >= targetFrame.width,
        candidateFrame.height >= targetFrame.height,
        candidateFrame.height <= max(targetFrame.height + 32, targetFrame.height * 2)
    else {
        return false
    }

    return true
}

/// Pure. Whether the element is a text-entry control, judged by role, subrole and role description only.
///
/// Value settability is deliberately not a signal: sliders, steppers and some lists and tables expose a settable
/// AXValue, and typing into them would move a selection or a setting instead of entering text.
func canUseKeyboardTextFallback(role: String?, subrole: String?, roleDescription: String?) -> Bool {
    if isClickFocusTextEntry(role: role, subrole: subrole) {
        return true
    }

    guard role != nil, let roleDescription = roleDescription?.lowercased() else {
        return false
    }

    return roleDescription.contains("text field")
        || roleDescription.contains("text area")
        || roleDescription.contains("text entry")
}

func isElectronScopedWebRowClickOptimizationTarget(appName: String, bundleIdentifier: String?) -> Bool {
    let normalizedBundleIdentifier = bundleIdentifier?
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
    let normalizedName = appName
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()

    if let normalizedBundleIdentifier,
       normalizedBundleIdentifier.hasPrefix("com.electron.")
            || normalizedBundleIdentifier.contains(".electron.")
            || normalizedBundleIdentifier.contains("lark")
            || normalizedBundleIdentifier.contains("feishu")
    {
        return true
    }

    return normalizedName == "lark" || normalizedName == "feishu" || normalizedName == "飞书"
}

func shouldPreferContainingWebRowAXClickCandidate(
    role: String?,
    isSyntheticText: Bool,
    hasWebAreaAncestor: Bool,
    appName: String,
    bundleIdentifier: String?
) -> Bool {
    guard hasWebAreaAncestor,
          isElectronScopedWebRowClickOptimizationTarget(
            appName: appName,
            bundleIdentifier: bundleIdentifier
          )
    else {
        return false
    }

    guard let role else {
        return isSyntheticText
    }

    return role == kAXStaticTextRole as String || role == kAXGroupRole as String || isSyntheticText
}

public final class ComputerUseService {
    private var snapshotsByApp: [String: AppSnapshot] = [:]
    private var lastReturnedScreenshotFrames: [pid_t: ReturnedScreenshotFrame] = [:]

    public init() {}

    public func listApps() -> ToolCallResult {
        ToolCallResult.text(
            AppDiscovery.listCatalog()
                .map(\.renderedLine)
                .joined(separator: "\n")
        )
    }

    public func getAppState(
        app query: String,
        textLimit: SnapshotTextLimit = .defaults,
        treeLimits: AccessibilityTreeLimits = .defaults,
        compact: Bool = false
    ) throws -> ToolCallResult {
        snapshotResult(
            for: try refreshSnapshot(for: query, textLimit: textLimit, treeLimits: treeLimits),
            style: compact ? .compactActionable : .fullState
        )
    }

    /// Read-only advice from a decision model: the loopback llama sidecar by default, or the remote jev backend when
    /// `OPEN_COMPUTER_USE_DECISION_MODEL_BACKEND=remote` (see `DecisionBackendSelection`). The backend, endpoint/
    /// config, and goal are all validated before any AX read or network call; the snapshot goes through
    /// `refreshSnapshot`, so the returned element_index is resolvable later. For the llama backend the listener is
    /// verified to be the recorded sidecar immediately before the first request, so no goal or screen text is sent to
    /// a process that merely holds the port; the remote backend has no equivalent squatting risk (its destination
    /// comes only from the trusted config file), so it skips that check.
    public func decideNextAction(
        app query: String,
        goal: String,
        environment: [String: String],
        transport: DecisionModelTransport = URLSessionDecisionModelTransport(),
        sidecarVerifier: DecisionSidecarVerifier = DecisionSidecarVerifier(),
        remoteBackendConfigURL: URL = DecisionRemoteBackendConfigLoader.defaultConfigFileURL
    ) throws -> ToolCallResult {
        let validated = try Self.resolveValidatedDecisionBackend(
            environment: environment, remoteBackendConfigURL: remoteBackendConfigURL
        )

        guard !goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ComputerUseError.invalidArguments("goal must not be empty")
        }

        let snapshot = try refreshSnapshot(for: query, capture: .never)
        let appName = snapshot.app.name
        let renderedFull = snapshot.renderedText(style: .fullState)
        let renderedCompact = snapshot.renderedText(style: .compactActionable)

        // Captured now, right before the model calls actually start, so the remote backend's letter resolution
        // (up to 27 /tokenize requests) and every /v1/completions request are bounded by the same overall budget
        // `DecisionAdvisor` uses to bound the loopback backend's readouts.
        let deadline = Date().addingTimeInterval(DecisionAdvisor.overallDeadline)
        let built = Self.buildDecisionProvider(validated: validated, transport: transport, deadline: deadline)

        do {
            if let port = built.sidecarPortToVerify {
                try sidecarVerifier.verify(port: port)
            }
            let advice = try DecisionAdvisor.runOffMainThread {
                try DecisionAdvisor.advise(
                    goal: goal, appName: appName, renderedFull: renderedFull, renderedCompact: renderedCompact,
                    client: built.provider, pageSize: built.pageSize, maxPages: built.maxPages
                )
            }
            return .text(try advice.resultJSON(recommendedMinMargin: DecisionAdvisor.recommendedMinMargin))
        } catch let error as DecisionAdvisorError {
            throw ComputerUseError.message("decide_next_action: \(error.errorDescription!)")
        } catch let error as DecisionModelError {
            throw ComputerUseError.message("decide_next_action: \(error.errorDescription!)")
        }
    }

    /// The backend-selection half of `decideNextAction`, factored out so it is independently testable without a
    /// live AX-resolved app: resolves `environment` to a backend, then validates that backend's endpoint (`llama`)
    /// or loads and validates its config file (`remote`). Every failure maps to the same `ComputerUseError` case
    /// `decideNextAction` has always thrown for it — a missing/invalid endpoint or config file becomes
    /// `.invalidArguments`, an absent `llama` endpoint becomes `.stateUnavailable`.
    static func resolveValidatedDecisionBackend(
        environment: [String: String], remoteBackendConfigURL: URL
    ) throws -> ValidatedDecisionBackend {
        let backend: DecisionBackendSelection
        do {
            backend = try DecisionBackendSelection.resolve(environment: environment)
        } catch let error as DecisionModelError {
            throw ComputerUseError.invalidArguments(error.errorDescription!)
        }

        switch backend {
        case .llama:
            let endpoint: DecisionModelEndpoint
            do {
                guard let configured = try DecisionModelEndpoint.fromEnvironment(environment) else {
                    throw ComputerUseError.stateUnavailable(DecisionAdvisorError.disabled.errorDescription!)
                }
                endpoint = configured
            } catch let error as DecisionModelError {
                throw ComputerUseError.invalidArguments("\(DecisionModelEndpoint.environmentKey): \(error.errorDescription!)")
            }
            return .llama(endpoint)
        case .remote:
            let config: DecisionRemoteBackendConfig
            do {
                config = try DecisionRemoteBackendConfigLoader.load(from: remoteBackendConfigURL)
            } catch let error as DecisionModelError {
                throw ComputerUseError.invalidArguments(error.errorDescription!)
            }
            return .remote(config)
        }
    }

    /// The provider-construction half of `decideNextAction`, factored out so it is independently testable: turns a
    /// validated backend into the `DecisionReadoutProviding` instance, page size, max pages, and (for `llama` only)
    /// the sidecar port `decideNextAction` must verify before the first request — `remote` has no equivalent
    /// squatting risk (its destination comes only from the trusted config file), so it always reports `nil` here.
    static func buildDecisionProvider(
        validated: ValidatedDecisionBackend, transport: DecisionModelTransport, deadline: Date
    ) -> (provider: DecisionReadoutProviding, pageSize: Int, maxPages: Int, sidecarPortToVerify: Int?) {
        switch validated {
        case .llama(let endpoint):
            return (
                DecisionModelClient(endpoint: endpoint, transport: transport),
                DecisionCandidateBuilder.pageSize, DecisionCandidateBuilder.defaultMaxPages, endpoint.port
            )
        case .remote(let config):
            return (
                DecisionJevClient(
                    config: config, transport: transport, deadline: deadline, now: Date.init,
                    diskCache: DecisionJevLetterDiskCache(directory: DecisionJevLetterDiskCache.productionDirectory)
                ),
                DecisionJevClient.pageSize, DecisionJevClient.maxPages, nil
            )
        }
    }

    public func click(
        app query: String,
        elementIndex: String?,
        x: Double?,
        y: Double?,
        clickCount: Int,
        mouseButton: String,
        clickMethod: ClickMethod = .auto,
        includeScreenshot: Bool = false
    ) throws -> ToolCallResult {
        try click(
            app: query,
            elementIndex: elementIndex,
            x: x,
            y: y,
            clickCount: clickCount,
            mouseButton: mouseButton,
            clickMethod: clickMethod,
            context: .single(includeScreenshot: includeScreenshot)
        )
    }

    func click(
        app query: String,
        elementIndex: String?,
        x: Double?,
        y: Double?,
        clickCount: Int,
        mouseButton: String,
        clickMethod: ClickMethod,
        context: ActionContext
    ) throws -> ToolCallResult {
        try validateClickMethod(
            clickMethod,
            hasElementIndex: elementIndex != nil,
            environment: ProcessInfo.processInfo.environment
        )
        try validateSkyClickArguments(
            method: clickMethod,
            mouseButton: mouseButton,
            clickCount: clickCount
        )

        let snapshot = try actionSnapshot(for: query, context: context, elementIndex: elementIndex)
        let button = MouseButtonKind(rawValue: mouseButton.lowercased()) ?? .left
        if snapshot.mode == .fixture {
            guard clickMethod == .auto else {
                throw ComputerUseError.message(
                    "click_method '\(clickMethod.rawValue)' is not supported for fixture apps"
                )
            }

            let cursorTarget: VisualCursorTarget?
            if let elementIndex {
                let record = try lookupElement(snapshot: snapshot, index: elementIndex)
                guard let identifier = record.identifier else {
                    throw ComputerUseError.invalidArguments("fixture click requires an identifier-backed element")
                }
                cursorTarget = visualCursorTarget(for: record, snapshot: snapshot)
                moveVisualCursor(to: cursorTarget)
                try FixtureBridge.post(FixtureCommand(kind: "click", identifier: identifier))
            } else if let x, let y {
                let identifier = try fixtureIdentifier(at: CGPoint(x: x, y: y), snapshot: snapshot)
                cursorTarget = fixtureVisualCursorTarget(identifier: identifier, snapshot: snapshot)
                moveVisualCursor(to: cursorTarget)
                try FixtureBridge.post(FixtureCommand(kind: "click", identifier: identifier, x: x, y: y))
            } else {
                throw ComputerUseError.invalidArguments("click requires either element_index or x/y")
            }

            Thread.sleep(forTimeInterval: postActionSettleInterval)
            pulseVisualCursor(at: cursorTarget, clickCount: clickCount, mouseButton: button)
            return try finishAction(query: query, context: context)
        }

        if let elementIndex {
            let record = try lookupElement(snapshot: snapshot, index: elementIndex)
            if let refusal = windowElementClickRefusal(role: record.role, method: clickMethod, elementIndex: elementIndex) {
                throw ComputerUseError.invalidArguments(refusal)
            }
            guard let windowPoint = clickPoint(for: record, snapshot: snapshot) else {
                throw ComputerUseError.stateUnavailable("element \(elementIndex) has no clickable frame")
            }
            let targetPoint = try windowPointToGlobalPoint(snapshot: snapshot, point: windowPoint)
            // An off-stage window is not where its AX frame says, so the software cursor would point at empty space.
            let cursorTarget: VisualCursorTarget? = snapshot.isOffStage ? nil : makeVisualCursorTarget(
                at: targetPoint,
                targetWindowID: snapshot.targetWindowID,
                targetWindowLayer: snapshot.targetWindowLayer
            )

            moveVisualCursor(to: cursorTarget)

            do {
                switch clickMethod {
                case .auto:
                    if !(try performAXClickSequence(
                        on: record,
                        snapshot: snapshot,
                        button: button,
                        clickCount: clickCount,
                        includeNearbyHitTesting: !context.isBatchStep
                    )) {
                        try performNonAXClickFallback(
                            at: targetPoint,
                            button: button,
                            clickCount: clickCount,
                            targetDescription: "element_index=\(elementIndex)",
                            snapshot: snapshot
                        )
                    }
                case .accessibility:
                    guard try performAXClickSequence(
                        on: record,
                        snapshot: snapshot,
                        button: button,
                        clickCount: clickCount,
                        includeNearbyHitTesting: !context.isBatchStep
                    ) else {
                        throw ComputerUseError.message(
                            "click_method 'accessibility' could not click element_index=\(elementIndex)"
                        )
                    }
                case .appPost, .skyClick, .global:
                    try performExplicitMouseClick(
                        method: clickMethod,
                        at: targetPoint,
                        windowPoint: windowPoint,
                        button: button,
                        clickCount: clickCount,
                        targetDescription: "element_index=\(elementIndex)",
                        snapshot: snapshot
                    )
                }
            } catch {
                settleVisualCursor(at: cursorTarget)
                throw error
            }

            // A click on a background app's text field does not move its keyboard focus; an accessibility focus
            // write does, without activating the app. Only a primary click means "put the caret here".
            if button == .left, let element = record.element {
                focusTextEntryAfterClick(
                    role: record.role,
                    readSubrole: { stringValue(of: element, attribute: kAXSubroleAttribute) },
                    isFocusSettable: { isSettable(element: element, attribute: kAXFocusedAttribute) },
                    setFocused: { writeClickedTextEntryFocus(element) }
                )
            }

            pulseVisualCursor(at: cursorTarget, clickCount: clickCount, mouseButton: button)
        } else if let x, let y {
            try rejectCoordinateInputWhenOffStage(snapshot.isOffStage)
            let screenshotPoint = CGPoint(x: x, y: y)
            let point = try screenshotPixelToWindowPointInSnapshot(snapshot: snapshot, point: screenshotPoint)
            let targetPoint = try windowPointToGlobalPoint(snapshot: snapshot, point: point)
            let cursorTarget = makeVisualCursorTarget(
                at: targetPoint,
                targetWindowID: snapshot.targetWindowID,
                targetWindowLayer: snapshot.targetWindowLayer
            )

            moveVisualCursor(to: cursorTarget)

            do {
                switch clickMethod {
                case .auto:
                    let candidates = try clickCandidates(at: point, in: snapshot)
                    var handled = false
                    for record in candidates {
                        if try performAXClickSequence(
                            on: record,
                            snapshot: snapshot,
                            button: button,
                            clickCount: clickCount,
                            includeNearbyHitTesting: false
                        ) {
                            handled = true
                            break
                        }
                    }

                    if !handled {
                        try performNonAXClickFallback(
                            at: targetPoint,
                            button: button,
                            clickCount: clickCount,
                            targetDescription: "x=\(Int(screenshotPoint.x)) y=\(Int(screenshotPoint.y))",
                            snapshot: snapshot
                        )
                    }
                case .accessibility:
                    throw ComputerUseError.message("click_method 'accessibility' requires element_index")
                case .appPost, .skyClick, .global:
                    try performExplicitMouseClick(
                        method: clickMethod,
                        at: targetPoint,
                        windowPoint: point,
                        button: button,
                        clickCount: clickCount,
                        targetDescription: "x=\(Int(screenshotPoint.x)) y=\(Int(screenshotPoint.y))",
                        snapshot: snapshot
                    )
                }
            } catch {
                settleVisualCursor(at: cursorTarget)
                throw error
            }

            pulseVisualCursor(at: cursorTarget, clickCount: clickCount, mouseButton: button)
        } else {
            throw ComputerUseError.invalidArguments("click requires either element_index or x/y")
        }

        return try finishAction(
            query: query,
            context: context,
            recoveryPolicy: clickActionSnapshotRecoveryPolicy(for: clickMethod)
        )
    }

    public func performSecondaryAction(app query: String, elementIndex: String, action: String, includeScreenshot: Bool = false) throws -> ToolCallResult {
        try performSecondaryAction(
            app: query, elementIndex: elementIndex, action: action, context: .single(includeScreenshot: includeScreenshot)
        )
    }

    func performSecondaryAction(app query: String, elementIndex: String, action: String, context: ActionContext) throws -> ToolCallResult {
        let snapshot = try actionSnapshot(for: query, context: context, elementIndex: elementIndex)
        let record = try lookupElement(snapshot: snapshot, index: elementIndex)

        if snapshot.mode == .fixture {
            guard action.caseInsensitiveCompare("Raise") == .orderedSame else {
                throw ComputerUseError.message(invalidSecondaryActionMessage(action: action, record: record))
            }

            return try finishAction(query: query, context: context)
        }

        guard let rawAction = matchingAction(requested: action, record: record) else {
            throw ComputerUseError.message(invalidSecondaryActionMessage(action: action, record: record))
        }

        guard let element = record.element else {
            throw ComputerUseError.stateUnavailable("element \(elementIndex) has no backing accessibility object")
        }

        let result = AXUIElementPerformAction(element, rawAction as CFString)
        guard result == .success else {
            throw ComputerUseError.message("AXUIElementPerformAction failed with \(result.rawValue)")
        }

        Thread.sleep(forTimeInterval: postActionSettleInterval)
        return try finishAction(query: query, context: context)
    }

    public func scroll(app query: String, direction: String, elementIndex: String, pages: Double, includeScreenshot: Bool = false) throws -> ToolCallResult {
        try scroll(
            app: query, direction: direction, elementIndex: elementIndex, pages: pages,
            context: .single(includeScreenshot: includeScreenshot)
        )
    }

    func scroll(app query: String, direction: String, elementIndex: String, pages: Double, context: ActionContext) throws -> ToolCallResult {
        let normalized = direction.lowercased()
        guard ["up", "down", "left", "right"].contains(normalized) else {
            throw ComputerUseError.message("Invalid scroll direction: \(direction)")
        }
        guard pages.isFinite, pages > 0 else {
            throw ComputerUseError.message("pages must be > 0")
        }

        let snapshot = try actionSnapshot(for: query, context: context, elementIndex: elementIndex)
        let record = try lookupElement(snapshot: snapshot, index: elementIndex)

        if snapshot.mode == .fixture {
            guard let identifier = record.identifier else {
                throw ComputerUseError.invalidArguments("fixture scroll requires an identifier-backed element")
            }
            try FixtureBridge.post(FixtureCommand(kind: "scroll", identifier: identifier, direction: normalized, pages: pages))
            Thread.sleep(forTimeInterval: postActionSettleInterval)
            return try finishAction(query: query, context: context)
        }

        if let repeatCount = integralScrollPageCount(pages),
           let rawAction = record.rawActions.first(where: { $0.caseInsensitiveCompare("AXScroll\(normalized.capitalized)ByPage") == .orderedSame }),
           let element = record.element {
            for _ in 0..<repeatCount {
                _ = AXUIElementPerformAction(element, rawAction as CFString)
                Thread.sleep(forTimeInterval: 0.05)
            }
        } else if let point = try globalPoint(for: record, snapshot: snapshot) {
            try performScrollEvent(
                at: point,
                direction: normalized,
                pages: pages,
                targetDescription: "element_index=\(elementIndex)",
                snapshot: snapshot
            )
        } else {
            throw ComputerUseError.stateUnavailable("element \(elementIndex) has no scrollable frame")
        }

        return try finishAction(query: query, context: context)
    }

    public func drag(app query: String, fromX: Double, fromY: Double, toX: Double, toY: Double, includeScreenshot: Bool = false) throws -> ToolCallResult {
        let snapshot = try currentSnapshot(for: query)
        if snapshot.mode == .fixture {
            try FixtureBridge.post(FixtureCommand(kind: "drag", identifier: "fixture-drag-pad", x: fromX, y: fromY, toX: toX, toY: toY))
            Thread.sleep(forTimeInterval: postActionSettleInterval)
            return try finishAction(query: query, context: .single(includeScreenshot: includeScreenshot))
        }

        try rejectCoordinateInputWhenOffStage(snapshot.isOffStage)
        let start = try screenshotToGlobalPoint(snapshot: snapshot, x: fromX, y: fromY)
        let end = try screenshotToGlobalPoint(snapshot: snapshot, x: toX, y: toY)
        let path = try performDragEvent(
            from: start,
            to: end,
            targetDescription: "from=(\(Int(fromX)), \(Int(fromY))) to=(\(Int(toX)), \(Int(toY)))",
            snapshot: snapshot
        )
        return appendingDragDeliveryNote(
            to: try finishAction(query: query, context: .single(includeScreenshot: includeScreenshot)),
            path: path
        )
    }

    public func typeText(app query: String, text: String, includeScreenshot: Bool = false) throws -> ToolCallResult {
        try typeText(app: query, text: text, context: .single(includeScreenshot: includeScreenshot))
    }

    func typeText(app query: String, text: String, context: ActionContext) throws -> ToolCallResult {
        let snapshot = try context.pinnedSnapshot ?? currentSnapshot(for: query)
        if snapshot.mode == .fixture {
            try FixtureBridge.post(FixtureCommand(kind: "type_text", identifier: "fixture-input", value: text))
            Thread.sleep(forTimeInterval: postActionSettleInterval)
            return try finishAction(query: query, context: context)
        }

        // A batch reads focus live: an earlier step may have moved it since the pinned snapshot was built.
        let focusedElement = typingTargetElement(
            context: context,
            snapshotFocus: snapshot.focusedElement,
            liveFocus: { liveFocusedElement(pinned: snapshot) }
        )

        // Never activates the target: without a confirmed text focus the call fails instead of guessing.
        let route = try deliverTypedText(
            focus: try typeTextFocus(of: focusedElement),
            appName: snapshot.app.name,
            setValue: { try typeTextBySettingFocusedValueIfAvailable(text, focusedElement: focusedElement) },
            postKeys: { try InputSimulation.typeText(text, pid: snapshot.app.pid) }
        )
        if route == .setFocusedValue {
            Thread.sleep(forTimeInterval: 0.1)
        }
        return try finishAction(query: query, context: context)
    }

    public func pressKey(app query: String, key: String, includeScreenshot: Bool = false) throws -> ToolCallResult {
        try pressKey(app: query, key: key, context: .single(includeScreenshot: includeScreenshot))
    }

    func pressKey(app query: String, key: String, context: ActionContext) throws -> ToolCallResult {
        let snapshot = try context.pinnedSnapshot ?? currentSnapshot(for: query)
        if snapshot.mode == .fixture {
            try FixtureBridge.post(FixtureCommand(kind: "press_key", identifier: "fixture-key-capture", value: key))
            Thread.sleep(forTimeInterval: postActionSettleInterval)
            return try finishAction(query: query, context: context)
        }

        try InputSimulation.pressKey(key, pid: snapshot.app.pid)
        return try finishAction(query: query, context: context)
    }

    public func setValue(app query: String, elementIndex: String, value: String, includeScreenshot: Bool = false) throws -> ToolCallResult {
        try setValue(
            app: query, elementIndex: elementIndex, value: value, context: .single(includeScreenshot: includeScreenshot)
        )
    }

    func setValue(app query: String, elementIndex: String, value: String, context: ActionContext) throws -> ToolCallResult {
        let snapshot = try actionSnapshot(for: query, context: context, elementIndex: elementIndex)
        let record = try lookupElement(snapshot: snapshot, index: elementIndex)

        if snapshot.mode == .fixture {
            guard let identifier = record.identifier else {
                throw ComputerUseError.invalidArguments("fixture set_value requires a known element identifier")
            }

            let cursorTarget = visualCursorTarget(for: record, snapshot: snapshot)
            moveVisualCursor(to: cursorTarget)
            try FixtureBridge.post(FixtureCommand(kind: "set_value", identifier: identifier, value: value))
            Thread.sleep(forTimeInterval: postActionSettleInterval)
            settleVisualCursor(at: cursorTarget)
            return try finishAction(query: query, context: context)
        }

        guard let element = record.element else {
            throw ComputerUseError.stateUnavailable("element \(elementIndex) has no backing accessibility object")
        }

        guard try isSettableForSetValue(element: element, attribute: kAXValueAttribute) else {
            throw ComputerUseError.message(nonSettableSetValueErrorMessage)
        }

        let cursorTarget = visualCursorTarget(for: record, snapshot: snapshot)
        moveVisualCursor(to: cursorTarget)

        do {
            let result = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, value as CFString)
            guard result == .success else {
                throw ComputerUseError.message("AXUIElementSetAttributeValue failed with \(result.rawValue)")
            }

            Thread.sleep(forTimeInterval: 0.1)
        } catch {
            settleVisualCursor(at: cursorTarget)
            throw error
        }

        settleVisualCursor(at: cursorTarget)
        return try finishAction(query: query, context: context)
    }

    /// Runs a short, fully specified sequence of actions against the snapshot pinned at batch start, then
    /// returns the step lines plus one final state. Nothing is observed between steps.
    func performActions(
        app query: String,
        steps: [ActionStep],
        includeScreenshot: Bool,
        checkLock: () throws -> Void
    ) throws -> ToolCallResult {
        if let message = BatchActionRunner.missingReceivedStateMessage(
            app: query, steps: steps, hasReceivedState: snapshotsByApp[query.lowercased()] != nil
        ) {
            throw ComputerUseError.invalidArguments(message)
        }

        let pinned = try currentSnapshot(for: query)

        // Validate every step before any of them runs, so a bad step never leaves a half-applied batch.
        for (offset, step) in steps.enumerated() {
            guard case let .click(elementIndex, _, _, clickCount, mouseButton, clickMethod) = step else {
                continue
            }

            do {
                try validateClickMethod(
                    clickMethod,
                    hasElementIndex: elementIndex != nil,
                    environment: ProcessInfo.processInfo.environment
                )
                try validateSkyClickArguments(method: clickMethod, mouseButton: mouseButton, clickCount: clickCount)
            } catch {
                throw ComputerUseError.invalidArguments("step \(offset + 1): \(BatchActionRunner.errorText(error))")
            }
        }

        let unknown = BatchActionRunner.unknownElementIndices(in: steps, knownIndices: Set(pinned.elements.keys))
        if let first = unknown.first, let offset = steps.firstIndex(where: { $0.elementIndex == first }) {
            throw ComputerUseError.invalidArguments(
                "step \(offset + 1): element_index \(first) is not in the state you last received for this app; call get_app_state"
            )
        }

        let context = ActionContext.batchStep(pinned: pinned)
        let report = BatchActionRunner.run(
            steps: steps,
            beforeEachStep: { index in
                try checkLock()
                if index > 0 {
                    Thread.sleep(forTimeInterval: postActionSettleInterval)
                }
            },
            perform: { _, step in
                _ = try performBatchStep(step, query: query, context: context)
            }
        )

        do {
            try checkLock()
        } catch {
            return BatchActionRunner.result(
                report: report, finalState: nil, notReadReason: BatchActionRunner.errorText(error)
            )
        }

        let finalState = Result {
            try finishAction(
                query: query,
                context: .single(includeScreenshot: includeScreenshot),
                recoveryPolicy: BatchActionRunner.mostRestrictiveRecoveryPolicy(for: steps)
            )
        }
        return BatchActionRunner.result(report: report, finalState: finalState, notReadReason: nil)
    }

    private func performBatchStep(_ step: ActionStep, query: String, context: ActionContext) throws -> ToolCallResult {
        switch step {
        case let .click(elementIndex, x, y, clickCount, mouseButton, clickMethod):
            return try click(
                app: query, elementIndex: elementIndex, x: x, y: y, clickCount: clickCount,
                mouseButton: mouseButton, clickMethod: clickMethod, context: context
            )
        case let .typeText(text):
            return try typeText(app: query, text: text, context: context)
        case let .pressKey(key):
            return try pressKey(app: query, key: key, context: context)
        case let .setValue(elementIndex, value):
            return try setValue(app: query, elementIndex: elementIndex, value: value, context: context)
        case let .scroll(direction, elementIndex, pages):
            return try scroll(
                app: query, direction: direction, elementIndex: elementIndex, pages: pages, context: context
            )
        case let .performSecondaryAction(elementIndex, action):
            return try performSecondaryAction(
                app: query, elementIndex: elementIndex, action: action, context: context
            )
        }
    }

    /// The pinned snapshot with the window bounds and the target element's frame re-read live. Fixture snapshots
    /// come from the fixture bridge and carry no live geometry, so they are returned unchanged.
    private func liveGeometrySnapshot(from pinned: AppSnapshot, elementIndex: String?) throws -> AppSnapshot {
        if pinned.mode == .fixture {
            return pinned
        }

        // An off-stage window's window-server frame is its strip thumbnail, so its pinned AX frame stays the bounds.
        let liveBounds = pinned.isOffStage
            ? pinned.windowBounds
            : pinned.targetWindowID.flatMap { liveWindowBounds(forWindowID: $0) }
        let record = try elementIndex.map { try lookupElement(snapshot: pinned, index: $0) }
        let liveFrame = record.flatMap { liveLocalFrame(of: $0, windowBounds: liveBounds) }
        let geometry = try batchStepGeometry(
            pinnedWindowBounds: pinned.windowBounds,
            liveWindowBounds: liveBounds,
            liveLocalFrame: liveFrame,
            needsElementFrame: elementIndex != nil,
            elementIndex: elementIndex,
            // Only an x/y click reaches here without an index; it scales by the pinned image when there is one.
            scalesByPinnedScreenshot: elementIndex == nil && pinned.screenshotPNGData != nil
        )

        var elements = pinned.elements
        if let record, let localFrame = geometry.localFrame {
            elements[record.index] = ElementRecord(
                index: record.index,
                identifier: record.identifier,
                element: record.element,
                localFrame: localFrame,
                role: record.role,
                rawActions: record.rawActions,
                prettyActions: record.prettyActions,
                isSyntheticText: record.isSyntheticText
            )
        }

        return AppSnapshot(
            app: pinned.app,
            windowTitle: pinned.windowTitle,
            windowBounds: geometry.windowBounds,
            targetWindowID: pinned.targetWindowID,
            targetWindowLayer: pinned.targetWindowLayer,
            screenshotPNGData: pinned.screenshotPNGData,
            mode: pinned.mode,
            treeLines: pinned.treeLines,
            treeLineOffsets: pinned.treeLineOffsets,
            focusedSummary: pinned.focusedSummary,
            focusedElement: pinned.focusedElement,
            selectedText: pinned.selectedText,
            elements: elements,
            windowContentIsEmpty: pinned.windowContentIsEmpty,
            isOffStage: pinned.isOffStage
        )
    }

    private func liveWindowBounds(forWindowID windowID: CGWindowID) -> CGRect? {
        guard
            let windowInfo = CGWindowListCopyWindowInfo([.optionIncludingWindow], windowID) as? [[String: Any]],
            let entry = windowInfo.first(where: { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == windowID }),
            let boundsDictionary = entry[kCGWindowBounds as String] as? NSDictionary
        else {
            return nil
        }

        return CGRect(dictionaryRepresentation: boundsDictionary)
    }

    /// The element's frame relative to the live window, or in screen space when there is no window.
    private func liveLocalFrame(of record: ElementRecord, windowBounds: CGRect?) -> CGRect? {
        guard
            let element = record.element,
            let positionValue = liveAXValue(of: element, attribute: kAXPositionAttribute),
            let sizeValue = liveAXValue(of: element, attribute: kAXSizeAttribute)
        else {
            return nil
        }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue, .cgPoint, &position), AXValueGetValue(sizeValue, .cgSize, &size) else {
            return nil
        }

        let frame = CGRect(origin: position, size: size)
        guard let windowBounds else {
            return frame
        }

        return windowRelativeFrame(elementFrame: frame, windowBounds: windowBounds)
    }

    private func liveAXValue(of element: AXUIElement, attribute: String) -> AXValue? {
        var raw: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success,
            let raw,
            CFGetTypeID(raw) == AXValueGetTypeID()
        else {
            return nil
        }

        return (raw as! AXValue)
    }

    /// The app's focused element, read live. A background app usually answers nil for its app-level focus, so the
    /// fallback re-reads AXFocused live on the elements the pinned snapshot already holds (see
    /// `backgroundFocusProbeOrder`), which costs one AX read per text-entry element instead of a new tree walk.
    private func liveFocusedElement(pinned: AppSnapshot) -> AXUIElement? {
        var raw: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            AXUIElementCreateApplication(pinned.app.pid), kAXFocusedUIElementAttribute as CFString, &raw
        ) == .success,
            let raw,
            CFGetTypeID(raw) == AXUIElementGetTypeID()
        {
            return (raw as! AXUIElement)
        }

        return backgroundFocusProbeOrder(pinnedFocus: pinned.focusedElement, records: Array(pinned.elements.values))
            .first(where: liveIsFocused(_:))
    }

    private func liveIsFocused(_ element: AXUIElement) -> Bool {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXFocusedAttribute as CFString, &raw) == .success else {
            return false
        }
        return (raw as? Bool) == true
    }

    private func currentSnapshot(for query: String) throws -> AppSnapshot {
        if let snapshot = snapshotsByApp[query.lowercased()] {
            return snapshot
        }

        return try refreshSnapshot(for: query)
    }

    /// The single tail of every action: rebuild the snapshot and return it as a text-only action
    /// result, capturing and attaching the window image only on request or when the window has no content elements.
    /// A batch step observes nothing: the batch takes one final state after its last step instead.
    private func finishAction(
        query: String,
        context: ActionContext,
        recoveryPolicy: SnapshotRecoveryPolicy = .allowActivation
    ) throws -> ToolCallResult {
        if context.isBatchStep {
            return ToolCallResult(content: [])
        }

        let refreshed: AppSnapshot
        do {
            refreshed = try refreshSnapshot(
                for: query,
                recoveryPolicy: recoveryPolicy,
                capture: actionCapturePolicy(includeScreenshot: context.includeScreenshot)
            )
        } catch {
            throw errorAfterPerformedAction(error, appName: query)
        }

        return snapshotResult(
            for: refreshed,
            style: .actionResult,
            includeScreenshot: context.includeScreenshot
        )
    }

    /// The snapshot a core action reads its target from: the cached one for a single action, or the batch's
    /// pinned snapshot with live window bounds and the target's live frame for a batch step.
    private func actionSnapshot(for query: String, context: ActionContext, elementIndex: String?) throws -> AppSnapshot {
        guard let pinned = context.pinnedSnapshot else {
            return try currentSnapshot(for: query)
        }

        return try liveGeometrySnapshot(from: pinned, elementIndex: elementIndex)
    }

    @discardableResult
    private func refreshSnapshot(
        for query: String,
        textLimit: SnapshotTextLimit = .defaults,
        treeLimits: AccessibilityTreeLimits = .defaults,
        recoveryPolicy: SnapshotRecoveryPolicy = .allowActivation,
        capture: SnapshotCapturePolicy = .always
    ) throws -> AppSnapshot {
        let app = try AppDiscovery.resolve(query)
        let snapshot = try SnapshotBuilder.build(
            for: app,
            textLimit: textLimit,
            treeLimits: treeLimits,
            recoveryPolicy: recoveryPolicy,
            capture: capture
        )

        let keys = Set([
            query.lowercased(),
            app.name.lowercased(),
            (app.bundleIdentifier ?? "").lowercased(),
        ].filter { !$0.isEmpty })

        for key in keys {
            snapshotsByApp[key] = snapshot
        }

        return snapshot
    }

    private func lookupElement(snapshot: AppSnapshot, index: String) throws -> ElementRecord {
        guard let parsedIndex = Int(index), let record = snapshot.elements[parsedIndex] else {
            throw ComputerUseError.invalidArguments("unknown element_index '\(index)'")
        }

        return record
    }

    func matchingAction(requested: String, record: ElementRecord) -> String? {
        if let exact = record.rawActions.first(where: { $0.caseInsensitiveCompare(requested) == .orderedSame }) {
            return exact
        }
        let visibleActions = record.role.map { meaningfulRawActions(record.rawActions, role: $0) } ?? record.rawActions
        let matches = visibleActions.filter { rawAction in
            secondaryActionNamesEquivalent(requested, secondaryActionDisplayName(rawAction))
        }
        return matches.count == 1 ? matches[0] : nil
    }

    private func invalidSecondaryActionMessage(action: String, record: ElementRecord) -> String {
        invalidSecondaryActionErrorMessage(action: action, elementIndex: record.index)
    }

    private func performPreferredClick(on record: ElementRecord, button: MouseButtonKind, clickCount: Int) throws -> Bool {
        guard let element = record.element else {
            return false
        }

        switch button {
        case .left:
            if clickCount <= 1,
               !hasAncestorRole("AXWebArea", of: element),
               try selectContainingListItem(for: element)
            {
                return true
            }

            if try performAction(named: kAXPressAction as String, on: element, availableActions: record.rawActions, repeatCount: clickCount) {
                return true
            }

            if try performAction(named: kAXConfirmAction as String, on: element, availableActions: record.rawActions, repeatCount: clickCount) {
                return true
            }

            if try performAction(named: "AXOpen", on: element, availableActions: record.rawActions, repeatCount: clickCount) {
                return true
            }
        case .right:
            if try performAction(named: kAXShowMenuAction as String, on: element, availableActions: record.rawActions, repeatCount: clickCount) {
                return true
            }
        case .middle:
            break
        }

        return false
    }

    private func clickCandidates(at point: CGPoint, in snapshot: AppSnapshot) throws -> [ElementRecord] {
        var candidates: [ElementRecord] = []

        if let bestRecord = bestElement(containing: point, in: snapshot) {
            candidates.append(bestRecord)
        }

        if let hitRecord = try hitTestElement(at: point, in: snapshot) {
            candidates.append(hitRecord)
        }

        return candidates.reduce(into: []) { uniqueCandidates, candidate in
            if !uniqueCandidates.contains(where: { sameElement($0.element, candidate.element) }) {
                uniqueCandidates.append(candidate)
            }
        }
    }

    private func sameElement(_ lhs: AXUIElement?, _ rhs: AXUIElement?) -> Bool {
        guard let lhs, let rhs else {
            return false
        }

        return CFEqual(lhs, rhs)
    }

    private func selectContainingListItem(for element: AXUIElement) throws -> Bool {
        guard let target = selectableListItem(containing: element) else {
            return false
        }

        let result = AXUIElementSetAttributeValue(
            target.list,
            kAXSelectedChildrenAttribute as CFString,
            [target.item] as CFArray
        )

        switch result {
        case .success:
            Thread.sleep(forTimeInterval: 0.15)
            return true
        case .failure, .attributeUnsupported, .actionUnsupported, .cannotComplete, .noValue, .invalidUIElement, .illegalArgument:
            return false
        default:
            throw ComputerUseError.message("AXUIElementSetAttributeValue(\(kAXSelectedChildrenAttribute)) failed with \(result.rawValue)")
        }
    }

    private func selectableListItem(containing element: AXUIElement) -> (list: AXUIElement, item: AXUIElement)? {
        var current = element
        var directChild = element

        for _ in 0..<8 {
            guard let parent = copyParent(of: current) else {
                return nil
            }

            if stringValue(of: parent, attribute: kAXRoleAttribute) == kAXListRole as String,
               isSettable(element: parent, attribute: kAXSelectedChildrenAttribute)
            {
                return (parent, directChild)
            }

            directChild = parent
            current = parent
        }

        return nil
    }

    private func performAXClickSequence(
        on record: ElementRecord,
        snapshot: AppSnapshot,
        button: MouseButtonKind,
        clickCount: Int,
        includeNearbyHitTesting: Bool
    ) throws -> Bool {
        let preferContainingWebRowAXClick = shouldPreferContainingWebRowAXClick(record, in: snapshot)
        debugClickDecision("record=\(clickDebugDescription(record)) preferContainingWebRowAXClick=\(preferContainingWebRowAXClick)")

        if preferContainingWebRowAXClick,
           try performContainingWebRowClick(for: record, snapshot: snapshot, button: button, clickCount: clickCount)
        {
            Thread.sleep(forTimeInterval: 0.15)
            return true
        }

        if !preferContainingWebRowAXClick {
            if try performPreferredClick(on: record, button: button, clickCount: clickCount) {
                debugClickDecision("handled by preferred target \(clickDebugDescription(record))")
                Thread.sleep(forTimeInterval: 0.15)
                return true
            }

            for candidate in descendantClickCandidates(for: record, snapshot: snapshot) {
                if try performPreferredClick(on: candidate, button: button, clickCount: clickCount) {
                    debugClickDecision("handled by descendant \(clickDebugDescription(candidate))")
                    Thread.sleep(forTimeInterval: 0.15)
                    return true
                }
            }

            if includeNearbyHitTesting {
                for localPoint in clickActionPoints(for: record, snapshot: snapshot) {
                    guard let hitRecord = try hitTestElement(at: localPoint, in: snapshot) ?? bestElement(containing: localPoint, in: snapshot) else {
                        continue
                    }

                    if !isLikelySyntheticSideAction(hitRecord, in: record),
                       try performPreferredClick(on: hitRecord, button: button, clickCount: clickCount)
                    {
                        debugClickDecision("handled by hit record \(clickDebugDescription(hitRecord))")
                        Thread.sleep(forTimeInterval: 0.15)
                        return true
                    }

                    if shouldScanDescendantsOfHitRecord(
                        originalFrame: clickFrame(for: record, snapshot: snapshot),
                        hitFrame: hitRecord.localFrame
                    ) {
                        for candidate in descendantClickCandidates(
                            for: hitRecord,
                            snapshot: snapshot,
                            sideActionScope: record
                        ) {
                            if try performPreferredClick(on: candidate, button: button, clickCount: clickCount) {
                                debugClickDecision("handled by hit descendant \(clickDebugDescription(candidate))")
                                Thread.sleep(forTimeInterval: 0.15)
                                return true
                            }
                        }
                    }
                }
            }
        }

        return false
    }

    private func performAction(named action: String, on element: AXUIElement, availableActions: [String], repeatCount: Int = 1) throws -> Bool {
        guard availableActions.contains(where: { $0.caseInsensitiveCompare(action) == .orderedSame }) else {
            return false
        }

        let attempts = max(repeatCount, 1)
        for index in 0..<attempts {
            let result = AXUIElementPerformAction(element, action as CFString)
            switch result {
            case .success:
                if index < attempts - 1 {
                    Thread.sleep(forTimeInterval: 0.05)
                }
            case .attributeUnsupported where action.caseInsensitiveCompare("AXOpen") == .orderedSame:
                return true
            case .failure, .actionUnsupported, .attributeUnsupported, .cannotComplete, .noValue, .invalidUIElement, .illegalArgument:
                return false
            default:
                throw ComputerUseError.message("AXUIElementPerformAction(\(action)) failed with \(result.rawValue)")
            }
        }

        return true
    }

    private func isSettable(element: AXUIElement, attribute: String) -> Bool {
        var settable: DarwinBoolean = false
        let result = AXUIElementIsAttributeSettable(element, attribute as CFString, &settable)
        return result == .success && settable.boolValue
    }

    private func isSettableForSetValue(element: AXUIElement, attribute: String) throws -> Bool {
        var settable = DarwinBoolean(false)
        let result = AXUIElementIsAttributeSettable(element, attribute as CFString, &settable)
        return try setValueAttributeIsSettable(
            result: result,
            settable: settable.boolValue,
            attribute: attribute
        )
    }

    private func bestElement(containing point: CGPoint, in snapshot: AppSnapshot) -> ElementRecord? {
        snapshot.elements.values
            .filter { $0.localFrame?.contains(point) ?? false }
            .sorted { lhs, rhs in
                let lhsPriority = clickPriority(for: lhs)
                let rhsPriority = clickPriority(for: rhs)
                if lhsPriority != rhsPriority {
                    return lhsPriority < rhsPriority
                }

                return frameArea(of: lhs) < frameArea(of: rhs)
            }
            .first
    }

    private func hitTestElement(at point: CGPoint, in snapshot: AppSnapshot) throws -> ElementRecord? {
        let appElement = AXUIElementCreateApplication(snapshot.app.pid)
        let globalPoint = try windowPointToGlobalPoint(snapshot: snapshot, point: point)
        var hitElement: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(appElement, Float(globalPoint.x), Float(globalPoint.y), &hitElement)
        guard result == .success, let hitElement else {
            return nil
        }

        let rawActions = copyActions(for: hitElement) ?? []
        return ElementRecord(
            index: -1,
            identifier: nil,
            element: hitElement,
            localFrame: localFrame(of: hitElement, windowBounds: snapshot.windowBounds),
            rawActions: rawActions,
            prettyActions: rawActions
        )
    }

    private func clickPriority(for record: ElementRecord) -> Int {
        if record.rawActions.contains(where: {
            $0.caseInsensitiveCompare(kAXPressAction as String) == .orderedSame ||
            $0.caseInsensitiveCompare(kAXConfirmAction as String) == .orderedSame ||
            $0.caseInsensitiveCompare(kAXShowMenuAction as String) == .orderedSame ||
            $0.caseInsensitiveCompare(kAXRaiseAction as String) == .orderedSame
        }) {
            return 0
        }

        if let element = record.element,
           isSettable(element: element, attribute: kAXMainAttribute) ||
           isSettable(element: element, attribute: kAXFocusedAttribute) {
            return 1
        }

        return 2
    }

    private func frameArea(of record: ElementRecord) -> CGFloat {
        guard let frame = record.localFrame else {
            return .greatestFiniteMagnitude
        }

        return frame.width * frame.height
    }

    private func localCenter(for record: ElementRecord) -> CGPoint? {
        guard let frame = record.localFrame else {
            return nil
        }

        return CGPoint(x: frame.midX, y: frame.midY)
    }

    private func clickActionPoints(for record: ElementRecord, snapshot: AppSnapshot) -> [CGPoint] {
        guard let frame = clickFrame(for: record, snapshot: snapshot) else {
            return []
        }

        return localClickActionPoints(frame: frame, isSyntheticText: record.isSyntheticText)
    }

    private func descendantClickCandidates(
        for record: ElementRecord,
        snapshot: AppSnapshot,
        sideActionScope: ElementRecord? = nil
    ) -> [ElementRecord] {
        guard let element = record.element else {
            return []
        }

        let sideActionParent = sideActionScope ?? record
        return excludingHiddenAndTabCloseCandidates(
            excludingWindowTitleBarButtons(descendantClickCandidates(of: element, windowBounds: snapshot.windowBounds)),
            targetFrame: record.localFrame,
            labels: { accessibilityLabels(for: $0.element) }
        )
            .filter { candidate in
                !isLikelySyntheticSideAction(candidate, in: sideActionParent)
            }
            .sorted { lhs, rhs in
                let lhsPriority = clickPriority(for: lhs)
                let rhsPriority = clickPriority(for: rhs)
                if lhsPriority != rhsPriority {
                    return lhsPriority < rhsPriority
                }

                return frameArea(of: lhs) < frameArea(of: rhs)
            }
    }

    private func descendantClickCandidates(of element: AXUIElement, windowBounds: CGRect?, depth: Int = 0) -> [ElementRecord] {
        guard depth < 3 else {
            return []
        }

        var results: [ElementRecord] = []
        for child in copyChildren(of: element) {
            let rawActions = copyActions(for: child) ?? []
            results.append(
                ElementRecord(
                    index: -1,
                    identifier: nil,
                    element: child,
                    localFrame: localFrame(of: child, windowBounds: windowBounds),
                    // Only an actionable child can be pressed, so only its subrole is worth a read.
                    subrole: rawActions.isEmpty ? nil : stringValue(of: child, attribute: kAXSubroleAttribute),
                    rawActions: rawActions,
                    prettyActions: rawActions
                )
            )
            results.append(contentsOf: descendantClickCandidates(of: child, windowBounds: windowBounds, depth: depth + 1))
        }

        return results
    }

    private func isLikelySyntheticSideAction(_ candidate: ElementRecord, in parent: ElementRecord) -> Bool {
        isLikelySyntheticSideActionCandidate(
            parentFrame: parent.localFrame,
            candidateFrame: candidate.localFrame,
            hasPrimaryAction: hasPrimaryClickAction(candidate),
            labels: accessibilityLabels(for: candidate.element)
        )
    }

    private func hasPrimaryClickAction(_ record: ElementRecord) -> Bool {
        record.rawActions.contains { action in
            action.caseInsensitiveCompare(kAXPressAction as String) == .orderedSame ||
                action.caseInsensitiveCompare(kAXConfirmAction as String) == .orderedSame ||
                action.caseInsensitiveCompare("AXOpen") == .orderedSame ||
                action.caseInsensitiveCompare(kAXShowMenuAction as String) == .orderedSame
        }
    }

    private func shouldPreferContainingWebRowAXClick(_ record: ElementRecord, in snapshot: AppSnapshot) -> Bool {
        guard
            let element = record.element
        else {
            return false
        }

        return shouldPreferContainingWebRowAXClickCandidate(
            role: stringValue(of: element, attribute: kAXRoleAttribute),
            isSyntheticText: record.isSyntheticText,
            hasWebAreaAncestor: hasAncestorRole("AXWebArea", of: element),
            appName: snapshot.app.name,
            bundleIdentifier: snapshot.app.bundleIdentifier
        )
    }

    private func performContainingWebRowClick(
        for record: ElementRecord,
        snapshot: AppSnapshot,
        button: MouseButtonKind,
        clickCount: Int
    ) throws -> Bool {
        guard
            button == .left,
            clickCount <= 1,
            let element = record.element,
            let targetFrame = record.localFrame
        else {
            return false
        }

        var current = element

        for _ in 0..<6 {
            guard let parent = copyParent(of: current) else {
                return false
            }

            let rawActions = copyActions(for: parent) ?? []
            let candidate = ElementRecord(
                index: -1,
                identifier: nil,
                element: parent,
                localFrame: localFrame(of: parent, windowBounds: snapshot.windowBounds),
                rawActions: rawActions,
                prettyActions: rawActions
            )

            if isLikelyContainingWebRowAction(targetFrame: targetFrame, candidate: candidate),
               !isLikelySyntheticSideAction(candidate, in: record),
               try performAction(named: kAXPressAction as String, on: parent, availableActions: rawActions)
            {
                debugClickDecision("handled by containing web row \(clickDebugDescription(candidate))")
                return true
            }

            current = parent
        }

        return false
    }

    private func isLikelyContainingWebRowAction(
        targetFrame: CGRect,
        candidate: ElementRecord
    ) -> Bool {
        isLikelyContainingRowActionFrame(
            targetFrame: targetFrame,
            candidateFrame: candidate.localFrame,
            hasPrimaryAction: hasPrimaryClickAction(candidate)
        )
    }

    private func hasAncestorRole(_ role: String, of element: AXUIElement) -> Bool {
        var current = element

        for _ in 0..<12 {
            guard let parent = copyParent(of: current) else {
                return false
            }

            if stringValue(of: parent, attribute: kAXRoleAttribute) == role {
                return true
            }

            current = parent
        }

        return false
    }

    private func accessibilityLabels(for element: AXUIElement?) -> [String] {
        guard let element else {
            return []
        }

        return [
            kAXTitleAttribute as String,
            kAXDescriptionAttribute as String,
            kAXHelpAttribute as String,
            kAXValueAttribute as String,
            "AXIdentifier"
        ].compactMap { attribute in
            stringValue(of: element, attribute: attribute)
        }
    }

    private func typeTextBySettingFocusedValueIfAvailable(_ text: String, focusedElement: AXUIElement?) throws -> Bool {
        guard let element = focusedElement else {
            return false
        }

        guard try isSettableForSetValue(element: element, attribute: kAXValueAttribute) else {
            return false
        }

        let baseValue = editableBaseValue(for: element)
        let result = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, (baseValue + text) as CFString)
        switch result {
        case .success:
            return true
        case .failure, .attributeUnsupported, .actionUnsupported, .cannotComplete, .noValue, .invalidUIElement, .illegalArgument:
            return false
        default:
            throw ComputerUseError.message("AXUIElementSetAttributeValue failed with \(result.rawValue)")
        }
    }

    private func typeTextFocus(of focusedElement: AXUIElement?) throws -> TypeTextFocus? {
        guard let element = focusedElement else {
            return nil
        }

        let role = stringValue(of: element, attribute: kAXRoleAttribute)
        let roleDescription = role.flatMap {
            stringValue(of: element, attribute: kAXRoleDescriptionAttribute) ?? humanizedRoleDescription(for: $0)
        }
        let subrole = stringValue(of: element, attribute: kAXSubroleAttribute)
        return makeTypeTextFocus(
            role: role,
            subrole: subrole,
            roleDescription: roleDescription,
            isValueSettable: try isSettableForSetValue(element: element, attribute: kAXValueAttribute)
        )
    }

    private func humanizedRoleDescription(for role: String) -> String {
        if role == kAXTextFieldRole as String {
            return "text field"
        }

        switch role {
        case "AXTextArea", "AXTextView":
            return "text entry area"
        default:
            return ""
        }
    }

    private func editableBaseValue(for element: AXUIElement) -> String {
        let childTextValues = editableDescendantTextValues(in: element)
            .filter { !looksLikeEditablePlaceholder($0) }
        if !childTextValues.isEmpty {
            return childTextValues.joined()
        }

        guard let currentValue = stringValue(of: element, attribute: kAXValueAttribute) else {
            return ""
        }

        let normalizedValue = normalizeEditablePlaceholderText(currentValue)
        if normalizedValue.isEmpty || looksLikeEditablePlaceholder(normalizedValue) {
            return ""
        }

        for attribute in ["AXPlaceholderValue", "AXPlaceholder"] {
            guard let placeholder = stringValue(of: element, attribute: attribute) else {
                continue
            }

            if normalizedValue == normalizeEditablePlaceholderText(placeholder) {
                return ""
            }
        }

        return currentValue
    }

    private func editableDescendantTextValues(in element: AXUIElement, depth: Int = 0) -> [String] {
        guard depth < 4 else {
            return []
        }

        var values: [String] = []
        for child in copyChildren(of: element) {
            if stringValue(of: child, attribute: kAXRoleAttribute) == kAXStaticTextRole as String,
               let value = stringValue(of: child, attribute: kAXValueAttribute)
                    ?? stringValue(of: child, attribute: kAXTitleAttribute)
            {
                let normalized = normalizeEditablePlaceholderText(value)
                if !normalized.isEmpty {
                    values.append(normalized)
                }
            }

            values.append(contentsOf: editableDescendantTextValues(in: child, depth: depth + 1))
        }

        return values
    }

    private func looksLikeEditablePlaceholder(_ value: String) -> Bool {
        let normalized = normalizeEditablePlaceholderText(value)
        return normalized == "沟通时请保持“公开可接受”"
    }

    private func normalizeEditablePlaceholderText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\u{200B}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func clickFrame(for record: ElementRecord, snapshot: AppSnapshot) -> CGRect? {
        guard let frame = record.localFrame else {
            return nil
        }

        guard
            !record.isSyntheticText,
            let element = record.element,
            stringValue(of: element, attribute: kAXRoleAttribute) == kAXStaticTextRole as String,
            let rowFrame = containingRowFrame(for: element, textFrame: frame, windowBounds: snapshot.windowBounds)
        else {
            return frame
        }

        return rowFrame
    }

    private func containingRowFrame(for element: AXUIElement, textFrame: CGRect, windowBounds: CGRect?) -> CGRect? {
        let textCenter = CGPoint(x: textFrame.midX, y: textFrame.midY)
        var current = element

        for _ in 0..<4 {
            guard let parent = copyParent(of: current) else {
                return nil
            }

            if let frame = localFrame(of: parent, windowBounds: windowBounds),
               frame.insetBy(dx: -2, dy: -2).contains(textCenter),
               frame.width >= textFrame.width + 40,
               frame.height >= textFrame.height,
               frame.height <= max(textFrame.height * 4, 96)
            {
                return frame
            }

            current = parent
        }

        return nil
    }

    private func copyActions(for element: AXUIElement) -> [String]? {
        var actions: CFArray?
        let result = AXUIElementCopyActionNames(element, &actions)
        guard result == .success else {
            return nil
        }

        return actions as? [String]
    }

    private func copyChildren(of element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
        guard result == .success, let value else {
            return []
        }

        return value as? [AXUIElement] ?? []
    }

    private func copyParent(of element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &value)
        guard result == .success, let value else {
            return nil
        }

        return (value as! AXUIElement)
    }

    private func stringValue(of element: AXUIElement, attribute: String) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success, let value else {
            return nil
        }

        return value as? String
    }

    private func localFrame(of element: AXUIElement, windowBounds: CGRect?) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        let positionResult = AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue)
        let sizeResult = AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue)

        guard
            positionResult == .success,
            sizeResult == .success,
            let positionValue,
            let sizeValue
        else {
            return nil
        }

        let positionAXValue = positionValue as! AXValue
        let sizeAXValue = sizeValue as! AXValue
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionAXValue, .cgPoint, &position), AXValueGetValue(sizeAXValue, .cgSize, &size) else {
            return nil
        }

        let frame = CGRect(origin: position, size: size)
        guard let windowBounds else {
            return frame
        }

        return windowRelativeFrame(elementFrame: frame, windowBounds: windowBounds)
    }

    private func globalPoint(for record: ElementRecord, snapshot: AppSnapshot) throws -> CGPoint? {
        guard let frame = record.localFrame else {
            return nil
        }

        return try windowPointToGlobalPoint(
            snapshot: snapshot,
            point: CGPoint(x: frame.midX, y: frame.midY)
        )
    }

    private func clickPoint(for record: ElementRecord, snapshot: AppSnapshot) -> CGPoint? {
        clickActionPoints(for: record, snapshot: snapshot).first ?? localCenter(for: record)
    }

    private func screenshotToGlobalPoint(snapshot: AppSnapshot, x: Double, y: Double) throws -> CGPoint {
        try windowPointToGlobalPoint(
            snapshot: snapshot,
            point: try screenshotPixelToWindowPointInSnapshot(
                snapshot: snapshot,
                point: CGPoint(x: x, y: y)
            )
        )
    }

    private func screenshotPixelToWindowPointInSnapshot(snapshot: AppSnapshot, point: CGPoint) throws -> CGPoint {
        screenshotPixelToWindowPoint(
            point,
            screenshotPixelSize: try screenshotPixelSize(snapshot: snapshot),
            windowBounds: snapshot.windowBounds
        )
    }

    private func screenshotPixelSize(snapshot: AppSnapshot) throws -> CGSize? {
        try resolveScreenshotPixelSize(
            snapshotPixelSize: snapshot.screenshotPNGData.flatMap { pngPixelSize(of: $0) },
            windowID: snapshot.targetWindowID,
            windowBounds: snapshot.windowBounds,
            lastReturned: lastReturnedScreenshotFrames[snapshot.app.pid]
        )
    }

    private func windowPointToGlobalPoint(snapshot: AppSnapshot, point: CGPoint) throws -> CGPoint {
        guard let windowBounds = snapshot.windowBounds else {
            let appReference = snapshot.app.bundleIdentifier ?? snapshot.app.name
            throw ComputerUseError.stateUnavailable("No window bounds are available for \(appReference). Run get_app_state after bringing the app on screen.")
        }

        return CGPoint(x: windowBounds.minX + point.x, y: windowBounds.minY + point.y)
    }

    private func fixtureIdentifier(at point: CGPoint, snapshot: AppSnapshot) throws -> String {
        let candidates = snapshot.elements.values
            .filter { $0.identifier != nil && ($0.localFrame?.contains(point) ?? false) }
            .sorted { lhs, rhs in
                let lhsArea = (lhs.localFrame?.width ?? 0) * (lhs.localFrame?.height ?? 0)
                let rhsArea = (rhs.localFrame?.width ?? 0) * (rhs.localFrame?.height ?? 0)
                return lhsArea < rhsArea
            }

        guard let identifier = candidates.first?.identifier else {
            throw ComputerUseError.invalidArguments("No fixture element contains coordinate (\(Int(point.x)), \(Int(point.y)))")
        }

        return identifier
    }

    private func visualCursorTarget(for record: ElementRecord, snapshot: AppSnapshot) -> VisualCursorTarget? {
        makeVisualCursorTarget(
            localFrame: record.localFrame,
            windowBounds: snapshot.windowBounds,
            targetWindowID: snapshot.targetWindowID,
            targetWindowLayer: snapshot.targetWindowLayer
        )
    }

    private func fixtureVisualCursorTarget(identifier: String, snapshot: AppSnapshot) -> VisualCursorTarget? {
        let record = snapshot.elements.values.first { $0.identifier == identifier }
        return record.flatMap { visualCursorTarget(for: $0, snapshot: snapshot) }
    }

    private func moveVisualCursor(to target: VisualCursorTarget?) {
        guard let target else {
            return
        }

        VisualCursorSupport.performOnMain {
            SoftwareCursorOverlay.moveCursor(to: target.point, in: target.window)
        }
    }

    private func settleVisualCursor(at target: VisualCursorTarget?) {
        guard let target else {
            return
        }

        VisualCursorSupport.performOnMain {
            SoftwareCursorOverlay.settle(at: target.point, in: target.window)
        }
    }

    private func pulseVisualCursor(at target: VisualCursorTarget?, clickCount: Int, mouseButton: MouseButtonKind) {
        guard let target else {
            return
        }

        VisualCursorSupport.performOnMain {
            SoftwareCursorOverlay.pulseClick(
                at: target.point,
                clickCount: clickCount,
                mouseButton: mouseButton,
                in: target.window
            )
        }
    }

    private func debugInputFallback(tool: String, targetDescription: String, snapshot: AppSnapshot) {
        guard inputFallbackDebugEnabled(environment: ProcessInfo.processInfo.environment) else {
            return
        }

        let appReference = snapshot.app.bundleIdentifier ?? snapshot.app.name
        fputs(
            "[open-computer-use] global pointer fallback tool=\(tool) app=\(appReference) target=\(targetDescription)\n",
            stderr
        )
    }

    private func debugClickDecision(_ message: String) {
        guard inputFallbackDebugEnabled(environment: ProcessInfo.processInfo.environment) else {
            return
        }

        fputs("[open-computer-use] click decision \(message)\n", stderr)
    }

    private func clickDebugDescription(_ record: ElementRecord) -> String {
        let role = record.element.flatMap { stringValue(of: $0, attribute: kAXRoleAttribute) } ?? "nil"
        let actions = record.rawActions.joined(separator: ",")
        let frame = record.localFrame.map { "x=\(Int($0.minX)) y=\(Int($0.minY)) w=\(Int($0.width)) h=\(Int($0.height))" } ?? "nil"
        return "index=\(record.index) role=\(role) synthetic=\(record.isSyntheticText) actions=[\(actions)] frame=\(frame)"
    }

    private func integralScrollPageCount(_ pages: Double) -> Int? {
        let rounded = pages.rounded(.toNearestOrAwayFromZero)
        guard abs(pages - rounded) < 0.000001 else {
            return nil
        }
        return max(Int(rounded), 1)
    }

    private func performScrollEvent(
        at point: CGPoint,
        direction: String,
        pages: Double,
        targetDescription: String,
        snapshot: AppSnapshot
    ) throws {
        try rejectCoordinateInputWhenOffStage(snapshot.isOffStage)
        let eventPoint = inputEventPoint(fromScreenStatePoint: point)

        if globalPointerFallbacksEnabled(environment: ProcessInfo.processInfo.environment) {
            debugInputFallback(
                tool: "scroll",
                targetDescription: targetDescription,
                snapshot: snapshot
            )
            InputSimulation.prepareAppForGlobalPointerInput(snapshot.app)
            try InputSimulation.scrollGlobally(at: eventPoint, direction: direction, pages: pages)
            return
        }

        try InputSimulation.scrollTargeted(at: eventPoint, direction: direction, pages: pages, pid: snapshot.app.pid)
    }

    private func performDragEvent(
        from start: CGPoint,
        to end: CGPoint,
        targetDescription: String,
        snapshot: AppSnapshot
    ) throws -> DragDeliveryPath {
        try rejectCoordinateInputWhenOffStage(snapshot.isOffStage)
        let eventStart = inputEventPoint(fromScreenStatePoint: start)
        let eventEnd = inputEventPoint(fromScreenStatePoint: end)
        let path = dragDeliveryPath(environment: ProcessInfo.processInfo.environment)

        switch path {
        case .global:
            debugInputFallback(
                tool: "drag",
                targetDescription: targetDescription,
                snapshot: snapshot
            )
            InputSimulation.prepareAppForGlobalPointerInput(snapshot.app)
            try InputSimulation.dragGlobally(from: eventStart, to: eventEnd)
        case .appPost:
            try InputSimulation.dragTargeted(from: eventStart, to: eventEnd, pid: snapshot.app.pid)
        }

        return path
    }

    private func performNonAXClickFallback(
        at point: CGPoint,
        button: MouseButtonKind,
        clickCount: Int,
        targetDescription: String,
        snapshot: AppSnapshot
    ) throws {
        try rejectCoordinateInputWhenOffStage(snapshot.isOffStage)
        let eventPoint = inputEventPoint(fromScreenStatePoint: point)

        if globalPointerFallbacksEnabled(environment: ProcessInfo.processInfo.environment) {
            debugInputFallback(
                tool: "click",
                targetDescription: targetDescription,
                snapshot: snapshot
            )
            InputSimulation.prepareAppForGlobalPointerInput(snapshot.app)
            try InputSimulation.clickGlobally(at: eventPoint, button: button, clickCount: clickCount)
            return
        }

        do {
            if let windowID = snapshot.targetWindowID, let windowBounds = snapshot.windowBounds {
                try InputSimulation.clickBackgrounded(
                    at: eventPoint,
                    windowID: windowID,
                    windowBounds: windowBounds,
                    button: button,
                    clickCount: clickCount,
                    pid: snapshot.app.pid
                )
            } else {
                try InputSimulation.clickTargeted(
                    at: eventPoint,
                    button: button,
                    clickCount: clickCount,
                    pid: snapshot.app.pid
                )
            }
            return
        } catch {
            guard globalPointerFallbacksEnabled(environment: ProcessInfo.processInfo.environment) else {
                throw ComputerUseError.message(
                    "click could not be handled through accessibility, and global pointer fallback is disabled. Set OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS=1 to allow physical-pointer fallback for this process."
                )
            }
        }
    }

    private func performExplicitMouseClick(
        method: ClickMethod,
        at point: CGPoint,
        windowPoint: CGPoint,
        button: MouseButtonKind,
        clickCount: Int,
        targetDescription: String,
        snapshot: AppSnapshot
    ) throws {
        try rejectCoordinateInputWhenOffStage(snapshot.isOffStage)
        let eventPoint = inputEventPoint(fromScreenStatePoint: point)

        switch method {
        case .appPost:
            debugClickDecision("requested=app_post executed=pid_post target=\(targetDescription)")
            try InputSimulation.clickTargeted(
                at: eventPoint,
                button: button,
                clickCount: clickCount,
                pid: snapshot.app.pid
            )
        case .skyClick:
            guard let windowBounds = snapshot.windowBounds, let windowID = snapshot.targetWindowID else {
                throw ComputerUseError.stateUnavailable(
                    "click_method 'sky_click' requires a current on-screen target window. Run get_app_state again."
                )
            }
            debugClickDecision("requested=sky_click executed=skylight_pid_post target=\(targetDescription)")
            try InputSimulation.clickWithSkyLight(
                at: eventPoint,
                windowPoint: windowPoint,
                windowBounds: windowBounds,
                windowID: windowID,
                clickCount: clickCount,
                pid: snapshot.app.pid
            )
        case .global:
            guard globalPointerFallbacksEnabled(environment: ProcessInfo.processInfo.environment) else {
                throw ComputerUseError.message(
                    "click_method 'global' requires OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS=1 because it may move the system pointer and change foreground focus"
                )
            }
            debugClickDecision("requested=global executed=global_hid target=\(targetDescription)")
            InputSimulation.prepareAppForGlobalPointerInput(snapshot.app)
            try InputSimulation.clickGlobally(at: eventPoint, button: button, clickCount: clickCount)
        case .auto, .accessibility:
            throw ComputerUseError.message(
                "click_method '\(method.rawValue)' is not a direct mouse event method"
            )
        }
    }

    private func snapshotResult(
        for snapshot: AppSnapshot,
        style: SnapshotTextStyle,
        includeScreenshot: Bool = false
    ) -> ToolCallResult {
        var content = [ToolResultContentItem.text(snapshot.renderedText(style: style))]
        // The compact view exists to cut tokens; attaching the screenshot would defeat it.
        if shouldAttachScreenshot(style: style, includeScreenshot: includeScreenshot, treeIsEmpty: snapshot.windowContentIsEmpty),
           let screenshotPNGData = snapshot.screenshotPNGData {
            content.append(.pngImage(screenshotPNGData))
            rememberReturnedScreenshotFrame(for: snapshot, pngData: screenshotPNGData)
        }
        return ToolCallResult(content: content)
    }

    /// Records the frame of a screenshot handed to the caller so later x/y coordinates, read from
    /// that image, are scaled against it even when a text-only result replaced the cached snapshot.
    private func rememberReturnedScreenshotFrame(for snapshot: AppSnapshot, pngData: Data) {
        guard let windowBounds = snapshot.windowBounds, let pixelSize = pngPixelSize(of: pngData) else {
            return
        }

        lastReturnedScreenshotFrames[snapshot.app.pid] = ReturnedScreenshotFrame(
            windowID: snapshot.targetWindowID,
            windowSize: windowBounds.size,
            pixelSize: pixelSize
        )
    }
}
