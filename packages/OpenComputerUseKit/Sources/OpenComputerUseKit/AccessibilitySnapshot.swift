import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import ScreenCaptureKit

final class ElementRecord {
    let index: Int
    let identifier: String?
    let element: AXUIElement?
    let localFrame: CGRect?
    let role: String?
    let rawActions: [String]
    let prettyActions: [String]
    let isSyntheticText: Bool

    init(
        index: Int,
        identifier: String?,
        element: AXUIElement?,
        localFrame: CGRect?,
        role: String? = nil,
        rawActions: [String],
        prettyActions: [String],
        isSyntheticText: Bool = false
    ) {
        self.index = index
        self.identifier = identifier
        self.element = element
        self.localFrame = localFrame
        self.role = role
        self.rawActions = rawActions
        self.prettyActions = prettyActions
        self.isSyntheticText = isSyntheticText
    }
}

enum SnapshotMode {
    case accessibility
    case fixture
}

enum SnapshotRecoveryPolicy: Equatable {
    /// May unhide a hidden app to find its window. The name predates the rule that recovery never activates the app.
    case allowActivation
    case readOnly
}

public struct AccessibilityTreeLimits: Equatable, Sendable {
    public static let defaultMaxNodeCount = 1200
    public static let defaultMaxDepth = 64
    public static let defaults = AccessibilityTreeLimits(
        maxNodeCount: defaultMaxNodeCount,
        maxDepth: defaultMaxDepth
    )

    public let maxNodeCount: Int
    public let maxDepth: Int

    public init(maxNodeCount: Int = defaultMaxNodeCount, maxDepth: Int = defaultMaxDepth) {
        self.maxNodeCount = maxNodeCount
        self.maxDepth = maxDepth
    }

    public func replacing(maxNodeCount: Int? = nil, maxDepth: Int? = nil) -> AccessibilityTreeLimits {
        AccessibilityTreeLimits(
            maxNodeCount: maxNodeCount ?? self.maxNodeCount,
            maxDepth: maxDepth ?? self.maxDepth
        )
    }
}

@usableFromInline
let defaultTextLimit = 500

public struct SnapshotTextLimit: Equatable, Sendable {
    public static let maxKeyword = "max"
    public static let defaults = SnapshotTextLimit(maxCount: defaultTextLimit)
    public static let max = SnapshotTextLimit(maxCount: nil)

    public let maxCount: Int?

    public init(maxCount: Int = defaultTextLimit) {
        precondition(maxCount > 0, "text limit must be positive")
        self.maxCount = maxCount
    }

    private init(maxCount: Int?) {
        self.maxCount = maxCount
    }
}

let accessibilityTreeMaxNodeCount = AccessibilityTreeLimits.defaultMaxNodeCount
let accessibilityTreeMaxDepth = AccessibilityTreeLimits.defaultMaxDepth
let screenshotCaptureTimeout: TimeInterval = 5
let screenshotResultMaxPNGBytes = 900_000
let screenshotResultMaxDimension: CGFloat = 1280
let screenshotResultMinScale: CGFloat = 0.25
private let windowVisibilityRecoveryDelay: TimeInterval = 0.7
private let axWebAreaRole = "AXWebArea"
private let axContentsAttribute = "AXContents"
private let axVisibleChildrenAttribute = "AXVisibleChildren"
private let axPlaceholderValueAttribute = "AXPlaceholderValue"
private let axPlaceholderAttribute = "AXPlaceholder"
private let compactGenericActionTargetMaxWidth: CGFloat = 240
private let compactGenericActionTargetMaxHeight: CGFloat = 120

public struct AppSnapshot {
    public let app: RunningAppDescriptor
    public let windowTitle: String?
    public let windowBounds: CGRect?
    let targetWindowID: CGWindowID?
    let targetWindowLayer: Int?
    public let screenshotPNGData: Data?
    let mode: SnapshotMode
    let treeLines: [String]
    /// Position of each element's own row inside `treeLines`, keyed by element index.
    /// Lets the compact view reuse the exact rendered row instead of re-deriving it.
    let treeLineOffsets: [Int: Int]
    let focusedSummary: String?
    let focusedElement: AXUIElement?
    let selectedText: String?

    let elements: [Int: ElementRecord]
    /// True when the window walk found nothing below the window root. Menu-bar items do not count,
    /// so a window whose content exposes no accessibility elements still reads as empty.
    let windowContentIsEmpty: Bool
    /// True when Stage Manager holds the window off stage: no screenshot, and x/y coordinates are refused.
    var isOffStage: Bool = false

    public var renderedText: String {
        renderedText(style: .fullState)
    }

    public func renderedText(style: SnapshotTextStyle) -> String {
        var lines: [String] = []
        let displayTitle = displayWindowTitle(windowTitle, appName: app.name)
        let appReference = app.bundleIdentifier ?? app.name

        lines.append("App=\(appReference) (pid \(app.pid))")
        lines.append("Window: \(quoted(displayTitle)), App: \(app.name).")
        if isOffStage {
            lines.append(offStageWindowNote)
        }
        if style == .compactActionable {
            lines.append(contentsOf: compactActionableLines())
        } else {
            lines.append(contentsOf: treeLines)
        }

        if let selectedText, !selectedText.isEmpty {
            lines.append("")
            lines.append("Selected text: [\(selectedText)]")
        } else if let focusedSummary {
            lines.append("")
            lines.append("The focused UI element is \(focusedSummary).")
        }

        return lines.joined(separator: "\n")
    }

    /// Rows for elements that expose at least one accessibility action, flattened and with the
    /// focused element first. Element indices are the ones the full tree assigned, so every
    /// `element_index` printed here stays valid for `click`, `set_value`, `scroll` and the rest.
    ///
    /// Deliberately does not de-duplicate rows that render identically: two "Delete" buttons in a
    /// list are distinct targets, and dropping the correct one is a worse failure than printing a
    /// near-duplicate.
    func compactActionableLines() -> [String] {
        let actionable = elements.values
            .filter { isActionableForCompactView($0) && treeLineOffsets[$0.index] != nil }
            .map(\.index)

        guard !actionable.isEmpty else {
            return ["(no actionable elements found; re-run without compact for the full tree)"]
        }

        // Focused element first, then ascending index. Built by partitioning rather than with a
        // custom comparator: a predicate answering `true` for two equal focused indices is not a
        // strict weak ordering, and the standard library is entitled to trap on one.
        let focusedIndex = focusedElementIndex()
        let ordered: [Int]
        if let focusedIndex, actionable.contains(focusedIndex) {
            ordered = [focusedIndex] + actionable.filter { $0 != focusedIndex }.sorted()
        } else {
            ordered = actionable.sorted()
        }

        let addressable = elements.values.filter { !$0.isSyntheticText }.count
        var lines = [
            "Compact actionable view: \(ordered.count) of \(addressable) elements, screenshot omitted."
                + " element_index values match the full tree; re-run without compact for full context."
        ]
        // Rows that carry no index of their own belong to the element above them, so they are the
        // element's span rather than separate entries.
        let rowStarts = treeLineOffsets.values.sorted()
        for index in ordered {
            guard let offset = treeLineOffsets[index], treeLines.indices.contains(offset) else {
                continue
            }
            let end = rowStarts.first { $0 > offset } ?? treeLines.count
            let span = treeLines[offset..<min(end, treeLines.count)]
                .map(Self.stripLeadingIndent)
                .filter { !$0.isEmpty }
            guard var line = span.first else { continue }
            // Trailing rows are an element's own label/columns; joining them keeps the row
            // distinguishable from its siblings, which is the whole point of printing it.
            if span.count > 1 {
                line += " — " + span.dropFirst().joined(separator: " | ")
            }
            lines.append(index == focusedIndex ? "\(line) (focused)" : line)
        }
        return lines
    }

    private static func stripLeadingIndent(_ text: String) -> String {
        var line = Substring(text)
        while line.first == "\t" || line.first == " " {
            line = line.dropFirst()
        }
        return String(line)
    }

    /// Whether an element is worth keeping in the compact view.
    ///
    /// Exposing an accessibility action is the common case, but not the only one. `set_value` only
    /// requires `AXValue` to be settable, and macOS text fields routinely advertise no actions at
    /// all — filtering on actions alone would delete exactly the elements an agent means to type
    /// into, and the compact header would claim nothing was there. Settability itself cannot be
    /// used as the test: it is a live AX query, and running one per element would add a round trip
    /// per node to every snapshot. Text-entry roles stand in for it, which over-includes a
    /// read-only text field but never hides a writable one.
    ///
    /// In fixture mode every element is addressable: `click` and `set_value` dispatch by
    /// identifier, which `FixtureElementState` always carries, and `rawActions` holds only the
    /// fixture's *secondary* actions. So compact genuinely has nothing to filter there — it keeps
    /// the whole tree and only drops the screenshot. Stated outright rather than written as a
    /// condition, because a guard that can never be false reads like a real one.
    private func isActionableForCompactView(_ record: ElementRecord) -> Bool {
        if record.isSyntheticText {
            return false
        }
        if mode == .fixture {
            return true
        }
        if let role = record.role, Self.textEntryRoles.contains(role) {
            return true
        }
        let actuating = record.rawActions.filter { !Self.nonActuatingActions.contains($0) }
        guard !actuating.isEmpty else {
            return false
        }
        // Web content stamps the ubiquitous actions — `AXPress`, and on this page `AXShowMenu`
        // too — onto the static text inside a clickable region as well as onto the region itself,
        // so a page of prose arrives as hundreds of apparently actionable labels. A label is not
        // the target: whatever handles the click carries its own press, and that ancestor is kept.
        // Static text therefore earns a row only by advertising an action that is *not* one every
        // node has, which is what separates a real control mislabelled as text from a paragraph.
        // `meaningfulRawActions` already defines that set for rendering, and reusing it keeps the
        // two from drifting apart. Measured on one Chrome page: 280 rows down to 210.
        //
        // Deliberately NOT applied to generic containers: the snapshot already treats
        // `AXGroup`/`AXUnknown` plus a press as a genuine click target (see
        // `isGenericPrimaryActionSummaryBoundary`), and a clickable div is often the only target a
        // web app offers. Nor to scroll areas: `scroll` resolves by `element_index` and prefers
        // the element's own `AXScroll*ByPage` action, so dropping them would leave it no target.
        if let role = record.role, role == kAXStaticTextRole as String {
            return !meaningfulRawActions(record.rawActions, role: role).isEmpty
        }
        return true
    }

    /// Actions that do not actuate anything. WebKit and Electron advertise `AXScrollToVisible` on
    /// nearly every node, so treating "has any action" as actionable would keep the whole tree and
    /// make the compact view pointless on exactly the apps it exists for.
    private static let nonActuatingActions: Set<String> = [
        "AXScrollToVisible",
        "AXShowDefaultUI",
        "AXShowAlternateUI",
    ]

    /// Roles whose value is typically settable through `set_value` even with no advertised action.
    /// Mirrors `canUseKeyboardTextFallback`'s role list rather than inventing a second one, plus
    /// the secure and combo-box forms: a password field that reports role `AXSecureTextField`
    /// rather than the subrole would otherwise vanish from a login sheet.
    private static let textEntryRoles: Set<String> = [
        kAXTextFieldRole as String,
        kAXTextAreaRole as String,
        "AXTextView",
        "AXSecureTextField",
        kAXComboBoxRole as String,
    ]

    /// Index of the focused element, or nil when nothing is focused.
    ///
    /// Two records can carry the same `AXUIElement`: the element's own row, and the synthetic text
    /// row rendered for it. The synthetic row exposes no actions and so never reaches the compact
    /// view, meaning a match against it would silently drop the focused marker. Synthetic records
    /// are therefore skipped, and the lowest matching index wins: `Dictionary.values` has no
    /// defined order, so an arbitrary pick would order the same UI differently between runs.
    private func focusedElementIndex() -> Int? {
        guard let focusedElement else {
            return nil
        }
        return elements.values
            .filter { record in
                guard !record.isSyntheticText, let element = record.element else { return false }
                return CFEqual(element, focusedElement)
            }
            .map(\.index)
            .min()
    }
}

public enum SnapshotTextStyle {
    case fullState
    case actionResult
    /// Actionable rows only, no screenshot. The token-cheap view for agents that already
    /// know what they are looking for.
    case compactActionable
}

/// Decides when a snapshot build captures the window image.
enum SnapshotCapturePolicy: Equatable, Sendable {
    /// Capture before the walk: get_app_state and cache-miss builds.
    case always
    /// The window image is never requested, so SCScreenshotManager is never called.
    case never
    /// Walk first; capture only if the window has no content elements (see `windowHasContentElements`).
    case whenTreeEmpty
}

/// Whether the window walk recorded any element other than the window root itself. Call it with the
/// records produced by the window walk only, before the menu bar is walked.
func windowHasContentElements(_ windowWalkRecords: some Collection<ElementRecord>, windowRoot: AXUIElement) -> Bool {
    windowWalkRecords.contains { record in
        guard let element = record.element else {
            return true
        }
        return !CFEqual(element, windowRoot)
    }
}

enum WindowImageCaptureTiming: Equatable {
    case beforeWalk
    case afterWalkIfTreeEmpty
    case skip
}

/// Off-screen windows are never captured (the capture API cannot see them), whatever the policy. Neither are
/// off-stage Stage Manager windows: every capture API returns only their strip thumbnail.
func windowImageCaptureTiming(
    policy: SnapshotCapturePolicy,
    isOnscreen: Bool,
    isOffStage: Bool = false
) -> WindowImageCaptureTiming {
    guard isOnscreen, !isOffStage else {
        return .skip
    }

    switch policy {
    case .always:
        return .beforeWalk
    case .whenTreeEmpty:
        return .afterWalkIfTreeEmpty
    case .never:
        return .skip
    }
}

enum SnapshotBuilder {
    static func build(
        for app: RunningAppDescriptor,
        textLimit: SnapshotTextLimit = .defaults,
        treeLimits: AccessibilityTreeLimits = .defaults,
        recoveryPolicy: SnapshotRecoveryPolicy = .allowActivation,
        capture: SnapshotCapturePolicy = .always
    ) throws -> AppSnapshot {
        if app.name == FixtureBridge.appName, let fixtureState = try FixtureBridge.readState() {
            return buildFixtureSnapshot(app: app, state: fixtureState)
        }

        let permissions = PermissionDiagnostics.current()
        guard permissions.accessibilityTrusted else {
            throw ComputerUseError.permissionDenied("Accessibility permission is required. Run `open-computer-use doctor` and grant access to Open Computer Use.")
        }

        let appElement = AXUIElementCreateApplication(app.pid)
        enableBestEffortAccessibilityModes(appElement)
        let systemWide = AXUIElementCreateSystemWide()
        var focusedApplication = copyElement(systemWide, attribute: kAXFocusedApplicationAttribute)
        var focusedWindow = preferredFocusedWindow(appElement: appElement, appPID: app.pid, focusedApplication: focusedApplication, systemWide: systemWide)
        // AX tree is accessible for Stage Manager background apps without focus steal,
        // so this fallback runs regardless of the recovery policy.
        if focusedWindow == nil {
            focusedWindow = firstAnyWindow(for: appElement)
        }
        if focusedWindow == nil,
           recoveryPolicy == .allowActivation,
           recoverVisibleWindow(for: app) {
            focusedApplication = copyElement(systemWide, attribute: kAXFocusedApplicationAttribute)
            focusedWindow = preferredFocusedWindow(appElement: appElement, appPID: app.pid, focusedApplication: focusedApplication, systemWide: systemWide)
        }

        var rootWindow: AXUIElement
        guard let resolvedFocusedWindow = focusedWindow else {
            throw ComputerUseError.stateUnavailable(noBackgroundWindowMessage(appName: app.name))
        }
        rootWindow = resolvedFocusedWindow

        var windowTitle = stringValue(of: rootWindow, attribute: kAXTitleAttribute)
        // An off-stage window is located by its own id and AX frame; the window-server entry is only the strip
        // thumbnail, so it is neither matched by size nor captured.
        var windowCapture = liveOffStageWindow(for: rootWindow).map(WindowCapture.offStage(_:))
            ?? WindowCapture.resolve(
                for: app.pid,
                titleHint: windowTitle,
                accessibilityWindowID: accessibilityWindowID(of: rootWindow),
                captureImage: capture == .always
            )
        if windowCapture == nil,
           recoveryPolicy == .allowActivation,
           recoverVisibleWindow(for: app) {
            focusedApplication = copyElement(systemWide, attribute: kAXFocusedApplicationAttribute)
            if let recoveredWindow = preferredFocusedWindow(appElement: appElement, appPID: app.pid, focusedApplication: focusedApplication, systemWide: systemWide) {
                rootWindow = recoveredWindow
                windowTitle = stringValue(of: recoveredWindow, attribute: kAXTitleAttribute)
                windowCapture = WindowCapture.resolve(
                    for: app.pid,
                    titleHint: windowTitle,
                    accessibilityWindowID: accessibilityWindowID(of: recoveredWindow),
                    captureImage: capture == .always
                )
            }
        }

        guard let windowCapture else {
            throw ComputerUseError.stateUnavailable(noBackgroundWindowMessage(appName: app.name))
        }

        return buildAccessibilitySnapshot(
            app: app,
            appElement: appElement,
            rootElement: rootWindow,
            windowTitle: windowTitle,
            windowCapture: windowCapture,
            focusedApplication: focusedApplication,
            systemWide: systemWide,
            textLimit: textLimit,
            treeLimits: treeLimits,
            capture: capture
        )
    }

    private static func buildAccessibilitySnapshot(
        app: RunningAppDescriptor,
        appElement: AXUIElement,
        rootElement: AXUIElement,
        windowTitle: String?,
        windowCapture: WindowCapture,
        focusedApplication: AXUIElement?,
        systemWide: AXUIElement,
        textLimit: SnapshotTextLimit,
        treeLimits: AccessibilityTreeLimits,
        capture: SnapshotCapturePolicy
    ) -> AppSnapshot {
        let windowBounds = windowCapture.bounds
        let captureTiming = windowImageCaptureTiming(
            policy: capture,
            isOnscreen: windowCapture.isOnscreen,
            isOffStage: windowCapture.isOffStage
        )
        let appLevelFocus = preferredFocusedElement(appElement: appElement, appPID: app.pid, focusedApplication: focusedApplication, systemWide: systemWide)
        let context = RenderContext(
            windowBounds: windowBounds,
            focusedElement: appLevelFocus,
            textLimit: textLimit,
            treeLimits: treeLimits
        )

        var renderer = TreeRenderer(context: context)
        renderer.render(rootElement)
        let windowContentIsEmpty = !windowHasContentElements(renderer.records.values, windowRoot: rootElement)

        // A background app usually reports no app-level focus; its window's first responder can still carry AXFocused.
        var focusedElement = appLevelFocus
        var focusedSummary = renderer.focusedSummary
        if appLevelFocus == nil,
           let fallback = selectBackgroundFocus(renderer.focusCandidates, role: { $0.role }, depth: { $0.depth }) {
            focusedElement = fallback.element
            focusedSummary = fallback.lineBody
        }
        renderer.collectsFocusCandidates = false
        let selectedText = focusedElement.flatMap { copySelectedText($0, textLimit: textLimit) }

        if let menuBar = copyElement(appElement, attribute: kAXMenuBarAttribute),
           !CFEqual(menuBar, rootElement)
        {
            renderer.render(menuBar)
        }

        // The image was captured before the walk for .beforeWalk; for .afterWalkIfTreeEmpty it is
        // taken now, only when the window itself had nothing to act on (menu-bar items do not count).
        let screenshotPNGData: Data?
        if captureTiming == .afterWalkIfTreeEmpty, windowContentIsEmpty, !windowCapture.isOffStage {
            screenshotPNGData = windowCapture.capturingImage().pngDataIfAvailable()
        } else {
            screenshotPNGData = windowCapture.pngDataIfAvailable()
        }

        return AppSnapshot(
            app: app,
            windowTitle: windowTitle,
            windowBounds: windowBounds,
            targetWindowID: windowCapture.windowID,
            targetWindowLayer: windowCapture.layer,
            screenshotPNGData: screenshotPNGData,
            mode: .accessibility,
            treeLines: renderer.buffer.lines,
            treeLineOffsets: renderer.buffer.offsets,
            focusedSummary: focusedSummary,
            focusedElement: focusedElement,
            selectedText: selectedText,
            elements: renderer.records,
            windowContentIsEmpty: windowContentIsEmpty,
            isOffStage: windowCapture.isOffStage
        )
    }

    /// Brings back a window only by unhiding a hidden app, which shows its windows without activating it. It never
    /// activates the app, runs `open -b`, raises, unminimizes, or makes a window main or focused: each of those can
    /// put the target in front of the app the user is working in. When unhiding is not enough, the snapshot fails
    /// with `noBackgroundWindowMessage` and the user decides whether to show a window.
    private static func recoverVisibleWindow(for app: RunningAppDescriptor) -> Bool {
        guard let runningApplication = NSRunningApplication(processIdentifier: app.pid),
              runningApplication.isHidden,
              runningApplication.unhide()
        else {
            return false
        }

        Thread.sleep(forTimeInterval: windowVisibilityRecoveryDelay)
        return true
    }

    private static func firstWindow(for appElement: AXUIElement) -> AXUIElement? {
        guard let windows = copyArray(appElement, attribute: kAXWindowsAttribute) else {
            return nil
        }

        return windows.first(where: isUsableWindowElement(_:))
    }

    private static func firstAnyWindow(for appElement: AXUIElement) -> AXUIElement? {
        copyElement(appElement, attribute: kAXFocusedWindowAttribute)
            ?? copyArray(appElement, attribute: kAXWindowsAttribute)?.first(where: { stringValue(of: $0, attribute: kAXRoleAttribute) == kAXWindowRole as String })
    }

    private static func preferredFocusedWindow(appElement: AXUIElement, appPID: pid_t, focusedApplication: AXUIElement?, systemWide: AXUIElement) -> AXUIElement? {
        if let focusedApplication, pid(of: focusedApplication) == appPID {
            return usableWindowElement(from: copyElement(systemWide, attribute: kAXFocusedWindowAttribute))
                ?? usableWindowElement(from: copyElement(focusedApplication, attribute: kAXFocusedWindowAttribute))
                ?? firstWindow(for: focusedApplication)
                ?? usableWindowElement(from: copyElement(appElement, attribute: kAXFocusedWindowAttribute))
                ?? firstWindow(for: appElement)
        }

        return usableWindowElement(from: copyElement(appElement, attribute: kAXFocusedWindowAttribute)) ?? firstWindow(for: appElement)
    }

    private static func usableWindowElement(from element: AXUIElement?) -> AXUIElement? {
        guard let element, isUsableWindowElement(element) else {
            return nil
        }

        return element
    }

    private static func isUsableWindowElement(_ element: AXUIElement) -> Bool {
        stringValue(of: element, attribute: kAXRoleAttribute) == kAXWindowRole as String
            && boolValue(of: element, attribute: kAXMinimizedAttribute) != true
    }

    private static func preferredFocusedElement(appElement: AXUIElement, appPID: pid_t, focusedApplication: AXUIElement?, systemWide: AXUIElement) -> AXUIElement? {
        if let focusedApplication, pid(of: focusedApplication) == appPID {
            return copyElement(systemWide, attribute: kAXFocusedUIElementAttribute)
                ?? copyElement(focusedApplication, attribute: kAXFocusedUIElementAttribute)
                ?? copyElement(appElement, attribute: kAXFocusedUIElementAttribute)
        }

        return copyElement(appElement, attribute: kAXFocusedUIElementAttribute)
    }

    static func buildFixtureSnapshot(app: RunningAppDescriptor, state: FixtureAppState) -> AppSnapshot {
        var buffer = IndexedLineBuffer()

        var records: [Int: ElementRecord] = [:]
        let focusedIdentifier = state.focusedIdentifier
        var focusedSummary: String?

        for element in state.elements.sorted(by: { $0.index < $1.index }) {
            let titleSegment = element.title.map { " \($0)" } ?? ""
            let valueSegment = element.value.map { " Value: \($0)" } ?? ""
            let actionsSegment = element.actions.isEmpty ? "" : " Secondary Actions: \(element.actions.joined(separator: ", "))"
            let focusSegment = focusedIdentifier == element.identifier ? " (focused)" : ""
            buffer.appendIndexedLine(index: element.index, "\(String(repeating: "    ", count: element.index == 0 ? 0 : 1))\(element.index) \(element.role)\(titleSegment)\(focusSegment) ID: \(element.identifier)\(valueSegment)\(actionsSegment) Frame: \(element.frame.cgRect.renderedLocalFrame)")

            let record = ElementRecord(
                index: element.index,
                identifier: element.identifier,
                element: nil,
                localFrame: element.frame.cgRect,
                role: element.role,
                rawActions: element.actions,
                prettyActions: element.actions
            )
            records[element.index] = record

            if focusedIdentifier == element.identifier {
                focusedSummary = "\(element.index) \(element.role)"
            }
        }

        return AppSnapshot(
            app: app,
            windowTitle: state.windowTitle,
            windowBounds: state.windowBounds.cgRect,
            targetWindowID: nil,
            targetWindowLayer: nil,
            screenshotPNGData: nil,
            mode: .fixture,
            treeLines: buffer.lines,
            treeLineOffsets: buffer.offsets,
            focusedSummary: focusedSummary,
            focusedElement: nil,
            selectedText: nil,
            elements: records,
            windowContentIsEmpty: records.isEmpty
        )
    }
}

private func enableBestEffortAccessibilityModes(_ appElement: AXUIElement) {
    // Chromium/Electron apps may withhold parts of their AX tree until manual
    // accessibility is enabled. These private attributes are best-effort and
    // harmlessly fail on apps that do not support them.
    _ = AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    _ = AXUIElementSetAttributeValue(appElement, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
}

private struct WindowCapture {
    let windowID: CGWindowID
    let layer: Int
    let bounds: CGRect
    let image: CGImage?
    let isOnscreen: Bool
    var isOffStage = false

    /// An off-stage window: bounds are its AX frame, so element frames stay window-relative, and there is no image.
    static func offStage(_ window: OffStageWindow) -> WindowCapture {
        WindowCapture(
            windowID: window.windowID,
            layer: 0,
            bounds: window.accessibilityFrame,
            image: nil,
            isOnscreen: false,
            isOffStage: true
        )
    }

    /// `accessibilityWindowID` is the window-server id of the snapshot's AX root window; when it is among the
    /// candidates it is the window captured, so the screenshot and window bounds match the accessibility tree.
    static func resolve(
        for pid: pid_t,
        titleHint: String?,
        accessibilityWindowID: CGWindowID? = nil,
        captureImage shouldCaptureImage: Bool = true
    ) -> WindowCapture? {
        // Query all windows (not just onscreen) so Stage Manager background apps are included.
        guard let infoList = CGWindowListCopyWindowInfo([], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        let candidates = infoList.enumerated().compactMap { offset, info -> WindowCaptureCandidate? in
            guard
                let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
                ownerPID == pid,
                let number = info[kCGWindowNumber as String] as? NSNumber,
                let layer = info[kCGWindowLayer as String] as? Int,
                let boundsDictionary = info[kCGWindowBounds as String] as? NSDictionary,
                let bounds = CGRect(dictionaryRepresentation: boundsDictionary)
            else {
                return nil
            }

            let title = info[kCGWindowName as String] as? String
            let area = Int(bounds.width * bounds.height)
            let isOnscreen = info[kCGWindowIsOnscreen as String] as? Bool ?? false
            return WindowCaptureCandidate(
                windowID: CGWindowID(number.uint32Value),
                layer: layer,
                bounds: bounds,
                title: title,
                area: area,
                frontToBackIndex: offset,
                isOnscreen: isOnscreen
            )
        }

        // Read lazily: only a window in front of the chosen one needs its modal flag.
        var nonModalWindowIDs: Set<CGWindowID>?
        guard let best = preferredWindowCaptureCandidate(
            candidates,
            titleHint: titleHint,
            preferredWindowID: accessibilityWindowID,
            isNonModalAccessibilityWindow: { windowID in
                if nonModalWindowIDs == nil {
                    nonModalWindowIDs = liveNonModalAccessibilityWindowIDs(pid: pid)
                }
                return nonModalWindowIDs?.contains(windowID) ?? false
            }
        ) else {
            return nil
        }

        // Skip screenshot for off-screen windows (Stage Manager background strips):
        // SCShareableContent only returns onscreen windows, so capture would return nil anyway.
        let image = shouldCaptureImage && best.isOnscreen ? captureImage(windowID: best.windowID, bounds: best.bounds) : nil

        return WindowCapture(windowID: best.windowID, layer: best.layer, bounds: best.bounds, image: image, isOnscreen: best.isOnscreen)
    }

    /// Returns this capture with the window image taken now, reusing the already-resolved window
    /// id and bounds. Off-screen windows and captures that already hold an image are unchanged.
    func capturingImage() -> WindowCapture {
        guard isOnscreen, !isOffStage, image == nil else {
            return self
        }

        return WindowCapture(
            windowID: windowID,
            layer: layer,
            bounds: bounds,
            image: Self.captureImage(windowID: windowID, bounds: bounds),
            isOnscreen: isOnscreen
        )
    }

    private static func captureImage(windowID: CGWindowID, bounds: CGRect) -> CGImage? {
        try? BlockingAsyncBridge.run(timeout: screenshotCaptureTimeout) {
            let shareableContent = try await SCShareableContent.current
            guard let window = shareableContent.windows.first(where: { $0.windowID == windowID }) else {
                return nil
            }

            let configuration = SCStreamConfiguration()
            let scaleFactor = bestEffortScaleFactor(for: bounds)
            let captureSize = window.frame.isEmpty ? bounds.size : window.frame.size
            configuration.width = max(1, Int(ceil(captureSize.width * scaleFactor)))
            configuration.height = max(1, Int(ceil(captureSize.height * scaleFactor)))
            configuration.showsCursor = false
            configuration.scalesToFit = false
            configuration.ignoreShadowsSingleWindow = true

            let filter = SCContentFilter(desktopIndependentWindow: window)
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        }
    }

    private static func bestEffortScaleFactor(for bounds: CGRect) -> CGFloat {
        NSScreen.screens.first(where: { $0.frame.intersects(bounds) })?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor
            ?? 1
    }

    func pngDataIfAvailable() -> Data? {
        guard let image else {
            return nil
        }

        return boundedScreenshotPNGData(for: image)
    }
}

struct WindowCaptureCandidate {
    let windowID: CGWindowID
    let layer: Int
    let bounds: CGRect
    let title: String?
    let area: Int
    let frontToBackIndex: Int
    let isOnscreen: Bool
}

/// Picks the window to capture for a snapshot.
///
/// 1. The window whose id is `preferredWindowID` (the AX root window), when it is a usable candidate.
/// 2. Otherwise the title-hinted or frontmost usable window, searched among on-screen windows first: apps such as
///    Mail keep hidden layer-0 windows ahead of the visible one in z-order, and those have no screenshot and
///    unrelated bounds. Off-screen windows are considered only when no usable window is on screen.
///
/// A frontmost window in the same on-screen group that overlaps the chosen window (a modal panel) still wins, so
/// the screenshot shows what covers the target. Windows that `isNonModalAccessibilityWindow` reports as separate
/// non-modal windows of the app (Mail's search suggestions list, shown once its search field has focus) are skipped
/// for that check: they cover only a corner, belong to no modal flow, and are not part of the chosen window's
/// accessibility tree, so capturing them would swap the window identity and size under the caller. The check is
/// consulted only for windows in front of the chosen one.
func preferredWindowCaptureCandidate(
    _ candidates: [WindowCaptureCandidate],
    titleHint: String?,
    preferredWindowID: CGWindowID? = nil,
    isNonModalAccessibilityWindow: (CGWindowID) -> Bool = { _ in false }
) -> WindowCaptureCandidate? {
    let usable = candidates
        .filter { $0.layer == 0 && $0.area >= 20_000 }
        .sorted { lhs, rhs in
            lhs.frontToBackIndex < rhs.frontToBackIndex
        }

    guard !usable.isEmpty else {
        return candidates.sorted { lhs, rhs in
            lhs.area > rhs.area
        }.first
    }

    let onscreen = usable.filter(\.isOnscreen)
    let pool = onscreen.isEmpty ? usable : onscreen

    let accessibilityMatch = preferredWindowID.flatMap { id in usable.first(where: { $0.windowID == id }) }
    let titleMatch: WindowCaptureCandidate?
    if let titleHint, !titleHint.isEmpty {
        titleMatch = pool.first(where: { $0.title == titleHint })
    } else {
        titleMatch = nil
    }

    guard let hinted = accessibilityMatch ?? titleMatch else {
        // `usable` is non-empty, so `pool` is too.
        return pool[0]
    }

    // An off-screen AX root outside the on-screen pool is not covered by anything in that pool.
    guard let hintedPosition = pool.firstIndex(where: { $0.windowID == hinted.windowID }) else {
        return hinted
    }

    let covering = pool[..<hintedPosition].first { !isNonModalAccessibilityWindow($0.windowID) }
    if let covering, covering.bounds.intersects(hinted.bounds) {
        return covering
    }

    return hinted
}

/// Window-server ids of the app's accessibility windows that explicitly report `AXModal == false`. A window whose id
/// or modal flag cannot be read is left out, so it keeps today's "covering window wins" treatment.
func nonModalAccessibilityWindowIDs(_ windows: [(windowID: CGWindowID?, isModal: Bool?)]) -> Set<CGWindowID> {
    Set(windows.compactMap { window in
        window.isModal == false ? window.windowID : nil
    })
}

/// Live reads for `nonModalAccessibilityWindowIDs`: the app's AX windows, their window-server ids, and `AXModal`.
private func liveNonModalAccessibilityWindowIDs(pid: pid_t) -> Set<CGWindowID> {
    let windows = copyArray(AXUIElementCreateApplication(pid), attribute: kAXWindowsAttribute) ?? []
    return nonModalAccessibilityWindowIDs(windows.map { window in
        (windowID: accessibilityWindowID(of: window), isModal: boolValue(of: window, attribute: kAXModalAttribute))
    })
}

func boundedScreenshotPNGData(
    for image: CGImage,
    maxBytes: Int = screenshotResultMaxPNGBytes,
    maxDimension: CGFloat = screenshotResultMaxDimension,
    minScale: CGFloat = screenshotResultMinScale
) -> Data? {
    guard image.width > 0, image.height > 0, maxBytes > 0 else {
        return nil
    }

    let original = pngData(for: image)
    let largestDimension = CGFloat(max(image.width, image.height))
    var scale = min(1, maxDimension / largestDimension)

    if scale >= 1, let original, original.count <= maxBytes {
        return original
    }

    var best = original
    while scale >= minScale {
        guard let resized = resizedCGImage(image, scale: scale),
              let data = pngData(for: resized)
        else {
            break
        }

        best = data
        if data.count <= maxBytes {
            return data
        }

        scale *= 0.85
    }

    return best
}

private func pngData(for image: CGImage) -> Data? {
    let bitmap = NSBitmapImageRep(cgImage: image)
    return bitmap.representation(using: .png, properties: [:])
}

private func resizedCGImage(_ image: CGImage, scale: CGFloat) -> CGImage? {
    let width = max(1, Int((CGFloat(image.width) * scale).rounded()))
    let height = max(1, Int((CGFloat(image.height) * scale).rounded()))
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: bitmapInfo
    ) else {
        return nil
    }

    context.interpolationQuality = .medium
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()
}

private final class AsyncResultBox<T>: @unchecked Sendable {
    var result: Result<T, Error>?
}

enum BlockingAsyncBridge {
    static func run<T>(timeout: TimeInterval? = nil, _ operation: @escaping @Sendable () async throws -> T) throws -> T {
        let semaphore = DispatchSemaphore(value: 0)
        let resultBox = AsyncResultBox<T>()

        let task = Task.detached {
            do {
                resultBox.result = .success(try await operation())
            } catch {
                resultBox.result = .failure(error)
            }

            semaphore.signal()
        }

        guard waitForSignal(semaphore, timeout: timeout) else {
            task.cancel()
            throw ComputerUseError.message("ScreenCaptureKit screenshot task timed out after \(timeout ?? 0) seconds.")
        }

        return try resultBox.result?.get() ?? {
            throw ComputerUseError.message("ScreenCaptureKit screenshot task finished without producing a result.")
        }()
    }

    private static func waitForSignal(_ semaphore: DispatchSemaphore, timeout: TimeInterval?) -> Bool {
        let deadline = timeout.map { Date(timeIntervalSinceNow: $0) }

        if Thread.isMainThread {
            while semaphore.wait(timeout: .now()) == .timedOut {
                if let deadline, Date() >= deadline {
                    return false
                }

                RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
            }
            return true
        }

        if let timeout {
            return semaphore.wait(timeout: .now() + timeout) == .success
        }

        semaphore.wait()
        return true
    }
}

/// A rendered node that reported AXFocused == true, with the row text the focus line reuses.
struct RenderedFocusCandidate {
    let element: AXUIElement
    let role: String
    let depth: Int
    let lineBody: String
}

struct RenderContext {
    let windowBounds: CGRect?
    let focusedElement: AXUIElement?
    let textLimit: SnapshotTextLimit
    let treeLimits: AccessibilityTreeLimits
}

/// Collects rendered tree rows and the index -> row lookup that has to stay in step with them.
///
/// The compact view is only usable because a compact row's leading number is the element's
/// full-tree index, never a renumbering. That holds exactly as long as every indexed row's offset
/// points at the row it was appended as. Recording the offset inside the same call that appends
/// the row is what makes the two impossible to separate: there is no longer a gap between them for
/// a later edit to insert a row into.
struct IndexedLineBuffer {
    private(set) var lines: [String] = []
    private(set) var offsets: [Int: Int] = [:]

    /// Appends a row that owns `index`, and registers that row as the element's line.
    mutating func appendIndexedLine(index: Int, _ text: String) {
        lines.append(text)
        offsets[index] = lines.count - 1
    }

    /// Appends a row that owns no index and belongs to the element above it. Compact folds such
    /// rows into that element's span rather than printing them as entries of their own.
    mutating func appendSpanLine(_ text: String) {
        lines.append(text)
    }
}

struct TreeRenderer {
    let context: RenderContext
    var nextIndex = 0
    var buffer = IndexedLineBuffer()
    var records: [Int: ElementRecord] = [:]
    var identifierIndex: [String: String] = [:]
    var focusedSummary: String?
    /// Rendered nodes reporting AXFocused == true, collected only while the app-level focus is unknown (a background
    /// app). The builder turns collection off before walking the menu bar.
    var focusCandidates: [RenderedFocusCandidate] = []
    var collectsFocusCandidates: Bool

    init(context: RenderContext) {
        self.context = context
        self.collectsFocusCandidates = context.focusedElement == nil
    }

    /// `webAreaAncestorPosition` is the position in `ancestors` of the outermost AXWebArea ancestor, carried down the
    /// walk so no ancestor's role is read again.
    mutating func render(
        _ root: AXUIElement,
        depth: Int = 0,
        ancestors: [AXUIElement] = [],
        webAreaAncestorPosition: Int? = nil
    ) {
        guard shouldContinueRendering(nextIndex: nextIndex, depth: depth, limits: context.treeLimits) else {
            return
        }

        guard !ancestors.contains(where: { CFEqual($0, root) }) else {
            return
        }
        let nextAncestors = ancestors + [root]

        let index = nextIndex

        // One round trip for the attributes every node reads; nil falls back to single reads.
        let prefetch = AXAttributePrefetch.fetch(root)
        let role = stringValue(of: root, attribute: kAXRoleAttribute, prefetch: prefetch) ?? "AXUnknown"
        let subrole = stringValue(of: root, attribute: kAXSubroleAttribute, prefetch: prefetch)
        let baseRoleText = roleDescription(of: root, role: role, subrole: subrole, prefetch: prefetch)
        let label = stringValue(of: root, attribute: kAXDescriptionAttribute, prefetch: prefetch)
            .map { sanitizeText($0, textLimit: context.textLimit) }
        let help = stringValue(of: root, attribute: kAXHelpAttribute, prefetch: prefetch)
            .map { sanitizeText($0, textLimit: context.textLimit) }
        let value = sanitizedValue(of: root, textLimit: context.textLimit, prefetch: prefetch)
        let axIdentifier = displayIdentifier(stringValue(of: root, attribute: kAXIdentifierAttribute, prefetch: prefetch))
        let traits = summarizeTraits(of: root, prefetch: prefetch)
        let actions = copyActions(root) ?? []
        let exposesPrimaryClickAction = hasPrimaryClickAction(actions)
        let prettyActions = meaningfulActions(actions, role: role)
        let placeholder = placeholderValue(of: root, textLimit: context.textLimit, prefetch: prefetch)
        let webAreaDepth = webAreaDepth(role: role, ancestorCount: ancestors.count, webAreaAncestorPosition: webAreaAncestorPosition)
        let childWebAreaAncestorPosition = webAreaAncestorPosition ?? (role == axWebAreaRole ? ancestors.count : nil)
        let localFrame = resolveLocalFrame(of: root, windowBounds: context.windowBounds, prefetch: prefetch)
        let rowTexts = role == kAXRowRole as String
            ? flattenedRowTexts(of: root, textLimit: context.textLimit, prefetch: prefetch)
            : []
        let childElements = children(of: root, prefetch: prefetch)
        let hasActionableLinkDescendant =
            (role == kAXGroupRole as String || role == kAXUnknownRole as String)
            && exposesPrimaryClickAction
            && containsActionableLinkDescendant(
                in: childElements,
                textLimit: context.textLimit
            )
        let rendersCompactGenericActionTarget = shouldRenderCompactGenericActionTarget(
            role: role,
            hasPrimaryClickAction: exposesPrimaryClickAction,
            localFrame: localFrame,
            hasActionableLinkDescendant: hasActionableLinkDescendant
        )
        let genericTextSummary: String?
        if hasActionableLinkDescendant {
            genericTextSummary = nil
        } else {
            genericTextSummary = summarizedGenericText(
                of: root,
                role: role,
                childElements: childElements,
                textLimit: context.textLimit,
                minimumTextCount: rendersCompactGenericActionTarget ? 1 : 2
            )
        }
        let summaryImageChildren = genericTextSummary == nil ? [] : summaryImageDescendants(of: root)
        let rendersSummaryAsChildren = !rendersCompactGenericActionTarget
            && shouldRenderGenericTextSummaryAsChildren(
                genericTextSummary,
                summaryImageCount: summaryImageChildren.count
            )
        let title = preferredDisplayTitle(
            for: root,
            role: role,
            label: label,
            identifier: axIdentifier,
            explicitValue: value,
            rowTexts: rowTexts,
            textLimit: context.textLimit,
            prefetch: prefetch
        )
        let linkText = role == "AXLink" ? markdownLinkText(for: root, title: title, label: label, value: value, textLimit: context.textLimit) : nil
        let displayTitle = linkText ?? title
        let inlineRowSummary = outlineRowSummary(for: root, role: role, prefetch: prefetch)
        let hidesChildren = shouldSuppressChildren(
            role: role,
            title: displayTitle,
            label: label,
            help: help,
            value: value,
            identifier: axIdentifier,
            traits: traits,
            actions: prettyActions,
            children: childElements,
            genericTextSummary: genericTextSummary
        )
        let roleText = displayRoleText(
            baseRoleText: baseRoleText,
            role: role,
            title: displayTitle,
            label: label,
            suppressChildren: hidesChildren
        )

        if shouldElideNode(
            role: role,
            title: displayTitle,
            label: label,
            value: value,
            identifier: axIdentifier,
            traits: traits,
            actions: prettyActions,
            childCount: childElements.count,
            genericTextSummary: genericTextSummary,
            webAreaDepth: webAreaDepth,
            preservesCompactGenericActionTarget: rendersCompactGenericActionTarget
        ) {
            for child in childElements {
                render(child, depth: depth, ancestors: nextAncestors, webAreaAncestorPosition: childWebAreaAncestorPosition)
            }
            return
        }

        nextIndex += 1

        let traitsSegment = traits.isEmpty ? "" : " (\(traits.joined(separator: ", ")))"
        let titleSegment = displayTitle.map { " \($0)" } ?? ""
        let rowSummary = inlineRowSummary ?? (rendersSummaryAsChildren ? nil : genericTextSummary)
        let rowSummarySegment = rowSummary.map { " \($0)" } ?? ""
        let labelSegment = formattedLabelSegment(label, title: displayTitle, linkText: linkText, textLimit: context.textLimit)
        let helpSegment = {
            guard let help else {
                return ""
            }
            if help == displayTitle || help == label {
                return ""
            }
            return " Help: \(help)"
        }()
        let urlSegment = formattedURLSegment(for: root, role: role, title: displayTitle, label: label, textLimit: context.textLimit)
        let identifierSegment = displayIdentifierSegment(for: root, role: role, identifier: axIdentifier, title: displayTitle)
        let rawValueSegment = formattedValueSegment(role: role, roleText: roleText, title: displayTitle, value: value)
        let valueSegment = formattedValueSegmentWithSeparator(
            rawValueSegment,
            precedingSegments: [labelSegment, helpSegment, urlSegment, identifierSegment]
        )
        let placeholderSegment = formattedPlaceholderSegment(
            placeholder,
            title: displayTitle,
            label: label,
            value: value,
            precedingSegments: [labelSegment, helpSegment, urlSegment, identifierSegment, valueSegment]
        )
        let frameSegment = rendersCompactGenericActionTarget
            ? localFrame.map { " Frame: \($0.renderedLocalFrame)" } ?? ""
            : ""
        let actionsPrefix = shouldCommaSeparateActions(
            title: displayTitle,
            inlineRowSummary: inlineRowSummary,
            genericTextSummary: genericTextSummary,
            segments: [labelSegment, helpSegment, urlSegment, identifierSegment, valueSegment, placeholderSegment]
        ) ? ", Secondary Actions: " : " Secondary Actions: "
        let actionsSegment = prettyActions.isEmpty ? "" : "\(actionsPrefix)\(prettyActions.joined(separator: ", "))"
        let renderedRoleText = rendersCompactGenericActionTarget ? "button" : roleText
        let linePrefix = renderedRoleText.isEmpty ? "\(index)" : "\(index) \(renderedRoleText)"

        let lineBody = "\(linePrefix)\(traitsSegment)\(titleSegment)\(rowSummarySegment)\(labelSegment)\(helpSegment)\(urlSegment)\(identifierSegment)\(valueSegment)\(placeholderSegment)\(frameSegment)"
        buffer.appendIndexedLine(index: index, "\(String(repeating: "\t", count: depth))\(lineBody)\(actionsSegment)")

        let record = ElementRecord(
            index: index,
            identifier: axIdentifier,
            element: root,
            localFrame: localFrame,
            role: role,
            rawActions: actions,
            prettyActions: prettyActions
        )
        records[index] = record

        if let axIdentifier, let localFrame {
            identifierIndex[axIdentifier] = "\(axIdentifier) -> \(index) @ \(localFrame.renderedLocalFrame)"
        }

        if let focusedElement = context.focusedElement, CFEqual(focusedElement, root) {
            focusedSummary = lineBody
        } else if collectsFocusCandidates,
                  boolValue(of: root, attribute: kAXFocusedAttribute, prefetch: prefetch) == true {
            focusCandidates.append(RenderedFocusCandidate(element: root, role: role, depth: depth, lineBody: lineBody))
        }

        if role == kAXRowRole as String, boolValue(of: root, attribute: kAXSelectedAttribute, prefetch: prefetch) != true {
            for text in Array(rowTexts.dropFirst()) {
                buffer.appendSpanLine(text)
            }
            return
        }

        if rendersSummaryAsChildren, let genericTextSummary {
            renderSyntheticText(genericTextSummary, representedBy: root, depth: depth + 1)
            for image in summaryImageChildren {
                render(image, depth: depth + 1, ancestors: nextAncestors, webAreaAncestorPosition: childWebAreaAncestorPosition)
            }
            return
        }

        if hidesChildren {
            return
        }

        for child in childElements {
            render(child, depth: depth + 1, ancestors: nextAncestors, webAreaAncestorPosition: childWebAreaAncestorPosition)
        }
    }

    private mutating func renderSyntheticText(_ text: String, representedBy element: AXUIElement, depth: Int) {
        guard shouldContinueRendering(nextIndex: nextIndex, depth: depth, limits: context.treeLimits) else {
            return
        }

        let index = nextIndex
        nextIndex += 1
        // Deliberately a span row even though it prints an index of its own: registering an offset
        // here would terminate the parent's span, and since synthetic text is never ordered into
        // compact on its own, its text would vanish from the compact view entirely. Folding it into
        // the parent keeps it. Behavior preserved from before this buffer existed — see the history
        // note for the inconsistency this leaves with `records`.
        buffer.appendSpanLine("\(String(repeating: "\t", count: depth))\(index) text \(text)")

        records[index] = ElementRecord(
            index: index,
            identifier: nil,
            element: element,
            localFrame: resolveLocalFrame(of: element, windowBounds: context.windowBounds),
            rawActions: [],
            prettyActions: [],
            isSyntheticText: true
        )
    }

    private func opaqueIdentifier(for element: AXUIElement) -> String {
        String(CFHash(element))
    }

    private func webAreaDepth(role: String, ancestorCount: Int, webAreaAncestorPosition: Int?) -> Int? {
        if role == axWebAreaRole {
            return 0
        }

        return webAreaAncestorPosition.map { ancestorCount - $0 }
    }

    /// `prefetch` is the render prefetch, which already holds every attribute read here; without one, the attributes
    /// are fetched in one round trip.
    private func children(of element: AXUIElement, prefetch renderPrefetch: AXAttributePrefetch? = nil) -> [AXUIElement] {
        let prefetch = renderPrefetch ?? AXAttributePrefetch.fetch(element, attributes: AXAttributePrefetch.childListAttributes)
        let role = stringValue(of: element, attribute: kAXRoleAttribute, prefetch: prefetch)
        let rows = copyArray(element, attribute: kAXRowsAttribute, prefetch: prefetch) ?? []
        let visibleChildren = copyArray(element, attribute: axVisibleChildrenAttribute, prefetch: prefetch) ?? []
        let attributes = childTraversalAttributes(
            role: role,
            hasRows: !rows.isEmpty,
            hasVisibleChildren: !visibleChildren.isEmpty
        )
        var children: [AXUIElement] = []

        for attribute in attributes {
            let sourceValues: [AXUIElement]
            if attribute == kAXRowsAttribute {
                sourceValues = rows
            } else if attribute == axVisibleChildrenAttribute {
                sourceValues = visibleChildren
            } else {
                sourceValues = copyArray(element, attribute: attribute, prefetch: prefetch) ?? []
            }

            let values = attribute == kAXRowsAttribute
                ? visibleRows(in: sourceValues, parent: element, parentPrefetch: prefetch)
                : sourceValues

            for child in values {
                if shouldSkipChild(child, parentRole: role) {
                    continue
                }

                if !children.contains(where: { CFEqual($0, child) }) {
                    children.append(child)
                }
            }
        }

        return children
    }

    private func containsActionableLinkDescendant(
        in elements: [AXUIElement],
        textLimit: SnapshotTextLimit,
        ancestors: [AXUIElement] = [],
        depth: Int = 0
    ) -> Bool {
        guard depth < 8 else {
            return false
        }

        for element in elements {
            guard !ancestors.contains(where: { CFEqual($0, element) }) else {
                continue
            }

            let role = stringValue(of: element, attribute: kAXRoleAttribute) ?? ""
            if role == "AXLink",
               let url = urlValue(of: element, attribute: kAXURLAttribute, textLimit: textLimit),
               !url.isEmpty
            {
                return true
            }

            if containsActionableLinkDescendant(
                in: children(of: element),
                textLimit: textLimit,
                ancestors: ancestors + [element],
                depth: depth + 1
            ) {
                return true
            }
        }

        return false
    }
}

func childTraversalAttributes(role: String?, hasRows: Bool, hasVisibleChildren: Bool) -> [String] {
    var attributes: [String] = []
    if !(hasRows && usesRowsAsPrimaryRole(role)) && !(hasVisibleChildren && usesVisibleChildrenAsPrimaryRole(role)) {
        attributes.append(kAXChildrenAttribute)
    }
    attributes.append(kAXRowsAttribute)
    attributes.append(axContentsAttribute)
    attributes.append(axVisibleChildrenAttribute)
    return attributes
}

private func usesRowsAsPrimaryRole(_ role: String?) -> Bool {
    return [
        kAXOutlineRole as String,
        kAXListRole as String,
        kAXTableRole as String,
        "AXBrowser",
    ].contains(role)
}

private func usesVisibleChildrenAsPrimaryRole(_ role: String?) -> Bool {
    role == kAXListRole as String
}

private func shouldSkipChild(_ child: AXUIElement, parentRole: String?) -> Bool {
    guard parentRole == kAXMenuBarRole as String else {
        return false
    }

    return stringValue(of: child, attribute: kAXTitleAttribute) == "Apple"
}

func shouldContinueRendering(
    nextIndex: Int,
    depth: Int,
    limits: AccessibilityTreeLimits = .defaults
) -> Bool {
    nextIndex < limits.maxNodeCount && depth < limits.maxDepth
}

private func summarizeTraits(of element: AXUIElement, prefetch: AXAttributePrefetch?) -> [String] {
    var values: [String] = []

    if boolValue(of: element, attribute: kAXSelectedAttribute, prefetch: prefetch) == true {
        values.append("selected")
    }

    if boolValue(of: element, attribute: kAXExpandedAttribute, prefetch: prefetch) == true {
        values.append("expanded")
    }

    if boolValue(of: element, attribute: kAXEnabledAttribute, prefetch: prefetch) == false {
        values.append("disabled")
    }

    let isValueSettable = isSettable(of: element, attribute: kAXValueAttribute)
    if isValueSettable {
        values.append("settable")
    }

    if let valueType = valueTypeTrait(of: element, isValueSettable: isValueSettable, prefetch: prefetch) {
        values.append(valueType)
    }

    return values
}

private func valueTypeTrait(of element: AXUIElement, isValueSettable: Bool, prefetch: AXAttributePrefetch?) -> String? {
    guard isValueSettable else {
        return nil
    }

    guard let value = attributeValue(of: element, attribute: kAXValueAttribute, prefetch: prefetch) else {
        return nil
    }

    if CFGetTypeID(value) == CFStringGetTypeID() {
        return "string"
    }

    if value is NSNumber {
        if numericValueRepresentsBoolean(for: element, value: value, prefetch: prefetch) {
            return "boolean"
        }

        return "float"
    }

    return nil
}

private func copyElement(_ element: AXUIElement, attribute: String) -> AXUIElement? {
    let (error, value) = AccessibilityReads.backend.copyAttributeValue(element, attribute)
    guard error == .success, let value else {
        return nil
    }

    return (value as! AXUIElement)
}

private func copyArray(_ element: AXUIElement, attribute: String) -> [AXUIElement]? {
    let (error, value) = AccessibilityReads.backend.copyAttributeValue(element, attribute)
    guard error == .success, let value else {
        return nil
    }

    return value as? [AXUIElement]
}

private func copyArray(_ element: AXUIElement, attribute: String, prefetch: AXAttributePrefetch?) -> [AXUIElement]? {
    guard let prefetch, prefetch.covers(attribute) else {
        return copyArray(element, attribute: attribute)
    }

    return prefetch.value(attribute) as? [AXUIElement]
}

private func copyActions(_ element: AXUIElement) -> [String]? {
    let (error, actions) = AccessibilityReads.backend.copyActionNames(element)
    guard error == .success else {
        return nil
    }

    return actions as? [String]
}

private func attributeValue(of element: AXUIElement, attribute: String) -> CFTypeRef? {
    let (error, value) = AccessibilityReads.backend.copyAttributeValue(element, attribute)
    guard error == .success else {
        return nil
    }

    return value
}

private func attributeValue(of element: AXUIElement, attribute: String, prefetch: AXAttributePrefetch?) -> CFTypeRef? {
    prefetchedOrLive(prefetch, attribute) { attributeValue(of: element, attribute: attribute) }
}

private func stringValue(of element: AXUIElement, attribute: String) -> String? {
    stringValue(of: element, attribute: attribute, prefetch: nil)
}

private func stringValue(of element: AXUIElement, attribute: String, prefetch: AXAttributePrefetch?) -> String? {
    guard let value = attributeValue(of: element, attribute: attribute, prefetch: prefetch) else {
        return nil
    }

    if CFGetTypeID(value) == CFStringGetTypeID() {
        guard let string = value as? String else {
            return nil
        }

        return string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : string
    }

    return nil
}

private func copySelectedText(_ element: AXUIElement, textLimit: SnapshotTextLimit = .defaults) -> String? {
    guard let value = stringValue(of: element, attribute: kAXSelectedTextAttribute) else {
        return nil
    }

    let sanitized = sanitizeText(value, textLimit: textLimit)
    return sanitized.isEmpty ? nil : sanitized
}

private func boolValue(of element: AXUIElement, attribute: String) -> Bool? {
    boolValue(of: element, attribute: attribute, prefetch: nil)
}

private func boolValue(of element: AXUIElement, attribute: String, prefetch: AXAttributePrefetch?) -> Bool? {
    guard let value = attributeValue(of: element, attribute: attribute, prefetch: prefetch) else {
        return nil
    }

    return value as? Bool
}

private func pid(of element: AXUIElement) -> pid_t {
    var processIdentifier: pid_t = 0
    AXUIElementGetPid(element, &processIdentifier)
    return processIdentifier
}

private func isSettable(of element: AXUIElement, attribute: String) -> Bool {
    let (error, settable) = AccessibilityReads.backend.isAttributeSettable(element, attribute)
    return error == .success && settable
}

private func sanitizedValue(
    of element: AXUIElement,
    textLimit: SnapshotTextLimit = .defaults,
    prefetch: AXAttributePrefetch? = nil
) -> String? {
    if let string = stringValue(of: element, attribute: kAXValueAttribute, prefetch: prefetch) {
        let sanitized = sanitizeText(string, textLimit: textLimit)
        return sanitized.isEmpty ? nil : sanitized
    }

    guard let value = attributeValue(of: element, attribute: kAXValueAttribute, prefetch: prefetch) else {
        return nil
    }

    if let number = value as? NSNumber {
        if numericValueRepresentsBoolean(for: element, value: value, prefetch: prefetch) {
            return number.boolValue ? "on" : "off"
        }

        return number.stringValue
    }

    return nil
}

private func placeholderValue(
    of element: AXUIElement,
    textLimit: SnapshotTextLimit = .defaults,
    prefetch: AXAttributePrefetch? = nil
) -> String? {
    for attribute in [axPlaceholderValueAttribute, axPlaceholderAttribute] {
        if let string = stringValue(of: element, attribute: attribute, prefetch: prefetch) {
            let sanitized = sanitizeText(string, textLimit: textLimit)
            if !sanitized.isEmpty {
                return sanitized
            }
        }
    }

    return nil
}

private func numericValueRepresentsBoolean(
    for element: AXUIElement,
    value: CFTypeRef,
    prefetch: AXAttributePrefetch? = nil
) -> Bool {
    guard let number = value as? NSNumber else {
        return false
    }

    guard number == 0 || number == 1 else {
        return false
    }

    let role = stringValue(of: element, attribute: kAXRoleAttribute, prefetch: prefetch) ?? ""
    let roleText = roleDescription(
        of: element,
        role: role,
        subrole: stringValue(of: element, attribute: kAXSubroleAttribute, prefetch: prefetch),
        prefetch: prefetch
    )

    return roleText == "tab"
        || role == kAXCheckBoxRole as String
        || role == kAXRadioButtonRole as String
}

private func preferredDisplayTitle(
    for element: AXUIElement,
    role: String,
    label: String?,
    identifier: String?,
    explicitValue: String?,
    rowTexts: [String],
    textLimit: SnapshotTextLimit = .defaults,
    prefetch: AXAttributePrefetch? = nil
) -> String? {
    if let title = stringValue(of: element, attribute: kAXTitleAttribute, prefetch: prefetch), !title.isEmpty {
        return sanitizeText(title, textLimit: textLimit)
    }

    if role == kAXRowRole as String {
        return rowTexts.first
    }

    if (role == kAXOutlineRole as String || role == kAXListRole as String), let identifier {
        return identifier
    }

    if (role == kAXButtonRole as String || role == kAXPopUpButtonRole as String), let label, !label.isEmpty {
        return sanitizeText(label, textLimit: textLimit)
    }

    if role == kAXImageRole as String, let label, !label.isEmpty {
        return sanitizeText(label, textLimit: textLimit)
    }

    if (role == kAXGroupRole as String || role == kAXUnknownRole as String || role == "AXWebArea"),
       let label,
       !label.isEmpty
    {
        return sanitizeText(label, textLimit: textLimit)
    }

    let subrole = stringValue(of: element, attribute: kAXSubroleAttribute, prefetch: prefetch)
    guard roleDescription(of: element, role: role, subrole: subrole, prefetch: prefetch) == "search text field" else {
        return nil
    }

    return explicitValue
}

private func markdownLinkText(
    for element: AXUIElement,
    title: String?,
    label: String?,
    value: String?,
    textLimit: SnapshotTextLimit = .defaults
) -> String? {
    guard let url = urlValue(of: element, attribute: kAXURLAttribute, textLimit: textLimit), !url.isEmpty else {
        return nil
    }

    let text = [label, title, value]
        .compactMap { candidate -> String? in
            guard let candidate else {
                return nil
            }
            let sanitized = sanitizeText(candidate, textLimit: textLimit)
            return sanitized.isEmpty ? nil : sanitized
        }
        .first

    guard let text else {
        return nil
    }

    return "[\(markdownEscapedLinkText(text))](\(url))"
}

private func markdownEscapedLinkText(_ text: String) -> String {
    text
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "[", with: "\\[")
        .replacingOccurrences(of: "]", with: "\\]")
}

private func outlineRowSummary(for element: AXUIElement, role: String, prefetch: AXAttributePrefetch? = nil) -> String? {
    guard role == kAXOutlineRole as String || role == kAXListRole as String else {
        return nil
    }

    guard let allRows = copyArray(element, attribute: kAXRowsAttribute, prefetch: prefetch), !allRows.isEmpty else {
        return nil
    }

    let visibleRows = visibleRows(in: allRows, parent: element, parentPrefetch: prefetch)
    guard !visibleRows.isEmpty, visibleRows.count < allRows.count else {
        return nil
    }

    return "(showing 0-\(visibleRows.count - 1) of \(allRows.count) items)"
}

private func formattedValueSegment(role: String, roleText: String, title: String?, value: String?) -> String {
    guard let value, !value.isEmpty else {
        return ""
    }

    if roleText == "search text field", title == value {
        return ""
    }

    if title == nil, role == kAXStaticTextRole as String {
        return " \(value)"
    }

    if ["scroll bar", "value indicator"].contains(roleText) {
        return " \(value)"
    }

    if roleText == "text entry area" {
        return " \(value)"
    }

    return " Value: \(value)"
}

func formattedLabelSegment(
    _ label: String?,
    title: String?,
    linkText: String?,
    textLimit: SnapshotTextLimit = .defaults
) -> String {
    guard let label, label != title else {
        return ""
    }

    let sanitizedLabel = sanitizeText(label, textLimit: textLimit)
    guard !sanitizedLabel.isEmpty, sanitizedLabel != title else {
        return ""
    }

    let comparableLabel = markdownEscapedLinkText(sanitizedLabel)
    if let linkText, linkText.hasPrefix("[\(comparableLabel)](") {
        return ""
    }

    return " Description: \(sanitizedLabel)"
}

private func formattedValueSegmentWithSeparator(_ valueSegment: String, precedingSegments: [String]) -> String {
    guard valueSegment.hasPrefix(" Value:"), precedingSegments.contains(where: { !$0.isEmpty }) else {
        return valueSegment
    }

    return ",\(valueSegment)"
}

func formattedPlaceholderSegment(_ placeholder: String?, title: String?, label: String?, value: String?, precedingSegments: [String]) -> String {
    guard let placeholder, !placeholder.isEmpty else {
        return ""
    }

    if placeholder == title || placeholder == label || placeholder == value {
        return ""
    }

    let prefix = precedingSegments.contains(where: { !$0.isEmpty }) || title != nil ? ", Placeholder: " : " Placeholder: "
    return "\(prefix)\(placeholder)"
}

private func shouldCommaSeparateActions(
    title: String?,
    inlineRowSummary: String?,
    genericTextSummary: String?,
    segments: [String]
) -> Bool {
    title != nil
        || inlineRowSummary != nil
        || genericTextSummary != nil
        || segments.contains(where: { !$0.isEmpty })
}

private func formattedURLSegment(
    for element: AXUIElement,
    role: String,
    title: String?,
    label: String?,
    textLimit: SnapshotTextLimit = .defaults
) -> String {
    guard role == "AXWebArea" else {
        return ""
    }

    guard let url = urlValue(of: element, attribute: kAXURLAttribute, textLimit: textLimit), !url.isEmpty else {
        return ""
    }

    if url == title || url == label {
        return ""
    }

    return ", URL: \(url)"
}

private func urlValue(
    of element: AXUIElement,
    attribute: String,
    textLimit: SnapshotTextLimit = .defaults
) -> String? {
    guard let value = attributeValue(of: element, attribute: attribute) else {
        return nil
    }

    if CFGetTypeID(value) == CFStringGetTypeID(), let string = value as? String {
        let sanitized = sanitizeText(string, textLimit: textLimit)
        return sanitized.isEmpty ? nil : sanitized
    }

    if CFGetTypeID(value) == CFURLGetTypeID(), let url = value as? URL {
        let sanitized = sanitizeText(url.absoluteString, textLimit: textLimit)
        return sanitized.isEmpty ? nil : sanitized
    }

    return nil
}

private func displayIdentifierSegment(for element: AXUIElement, role: String, identifier: String?, title: String?) -> String {
    guard let identifier else {
        return ""
    }

    if (role == kAXOutlineRole as String || role == kAXListRole as String), title == identifier {
        return ""
    }

    return " ID: \(identifier)"
}

private func resolveLocalFrame(
    of element: AXUIElement,
    windowBounds: CGRect?,
    prefetch: AXAttributePrefetch? = nil
) -> CGRect? {
    // Absent prefetched values (error sentinel or null) resolve to nil here, so they never reach the AXValue cast.
    let positionValue = attributeValue(of: element, attribute: kAXPositionAttribute, prefetch: prefetch)
    let sizeValue = attributeValue(of: element, attribute: kAXSizeAttribute, prefetch: prefetch)
    guard let positionValue, let sizeValue else {
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

func shouldElideNode(
    role: String,
    title: String?,
    label: String?,
    value: String?,
    identifier: String?,
    traits: [String],
    actions: [String],
    childCount: Int,
    genericTextSummary: String? = nil,
    webAreaDepth: Int? = nil,
    preservesCompactGenericActionTarget: Bool = false
) -> Bool {
    let genericRoles = [kAXGroupRole as String, kAXUnknownRole as String]
    guard genericRoles.contains(role) else {
        return false
    }

    if preservesCompactGenericActionTarget {
        return false
    }

    if genericTextSummary != nil {
        return false
    }

    if shouldPreserveWebAreaGenericContainer(childCount: childCount, webAreaDepth: webAreaDepth) {
        return false
    }

    if childCount == 1,
       title == nil,
       label == nil,
       value == nil,
       identifier == nil,
       actions.isEmpty,
       traitsAreNonDescriptiveWrapperTraits(traits)
    {
        return true
    }

    return title == nil
        && label == nil
        && value == nil
        && identifier == nil
        && traits.isEmpty
        && actions.isEmpty
}

func shouldPreserveWebAreaGenericContainer(childCount: Int, webAreaDepth: Int?) -> Bool {
    guard childCount > 0, webAreaDepth != nil else {
        return false
    }

    return childCount > 1
}

private func traitsAreNonDescriptiveWrapperTraits(_ traits: [String]) -> Bool {
    traits.isEmpty || traits == ["settable", "string"]
}

func hasPrimaryClickAction(_ actions: [String]) -> Bool {
    let primaryActions = [
        kAXPressAction as String,
        kAXConfirmAction as String,
        "AXOpen",
    ]

    return actions.contains { action in
        primaryActions.contains { $0.caseInsensitiveCompare(action) == .orderedSame }
    }
}

func shouldRenderCompactGenericActionTarget(
    role: String,
    hasPrimaryClickAction: Bool,
    localFrame: CGRect?,
    hasActionableLinkDescendant: Bool = false
) -> Bool {
    guard hasPrimaryClickAction else {
        return false
    }

    // A URL-bearing AXLink is the navigation target. Do not hide it behind a
    // generic action wrapper that happens to expose AXPress as well.
    guard !hasActionableLinkDescendant else {
        return false
    }

    guard role == kAXGroupRole as String || role == kAXUnknownRole as String else {
        return false
    }

    guard let localFrame,
          localFrame.width > 0,
          localFrame.height > 0,
          localFrame.width <= compactGenericActionTargetMaxWidth,
          localFrame.height <= compactGenericActionTargetMaxHeight
    else {
        return false
    }

    return true
}

private func shouldSuppressChildren(
    role: String,
    title: String?,
    label: String?,
    help: String?,
    value: String?,
    identifier: String?,
    traits: [String],
    actions: [String],
    children: [AXUIElement],
    genericTextSummary: String?
) -> Bool {
    if role == kAXMenuBarItemRole as String {
        return true
    }

    if role == "AXLink", title?.hasPrefix("[") == true {
        return true
    }

    return genericTextSummary != nil
}

private func summarizedGenericText(
    of element: AXUIElement,
    role: String,
    childElements: [AXUIElement],
    textLimit: SnapshotTextLimit = .defaults,
    minimumTextCount: Int = 2
) -> String? {
    guard role == kAXGroupRole as String || role == kAXUnknownRole as String else {
        return nil
    }

    guard !childElements.isEmpty else {
        return nil
    }

    guard isPlainGenericTextContainer(element, children: childElements) else {
        return nil
    }

    let texts = descendantTextsForSummary(of: element, textLimit: textLimit)
    guard texts.count >= minimumTextCount else {
        return nil
    }

    guard shouldMergeTextOnlySiblings(texts) else {
        return nil
    }

    let joined = sanitizeText(texts.joined(separator: " "), textLimit: textLimit)
        .replacingOccurrences(of: " : ", with: " :  ")
    return joined.isEmpty ? nil : joined
}

private func summaryImageDescendants(of element: AXUIElement, depth: Int = 0) -> [AXUIElement] {
    guard depth < 4 else {
        return []
    }

    let children = copyArray(element, attribute: kAXChildrenAttribute) ?? []
    var images: [AXUIElement] = []

    for child in children {
        let role = stringValue(of: child, attribute: kAXRoleAttribute) ?? ""
        if role == kAXImageRole as String {
            if !images.contains(where: { CFEqual($0, child) }) {
                images.append(child)
            }
        } else {
            for image in summaryImageDescendants(of: child, depth: depth + 1) {
                if !images.contains(where: { CFEqual($0, image) }) {
                    images.append(image)
                }
            }
        }

        if images.count >= 4 {
            return Array(images.prefix(4))
        }
    }

    return images
}

func shouldRenderGenericTextSummaryAsChildren(_ genericTextSummary: String?, summaryImageCount: Int) -> Bool {
    genericTextSummary != nil && summaryImageCount > 0
}

func shouldMergeTextOnlySiblings(_ texts: [String]) -> Bool {
    if texts.contains("日期") && texts.contains("时间") {
        return false
    }

    if texts.contains(where: isSiblingCounterText(_:)) {
        return false
    }

    if texts.contains(where: isStandaloneTimeRangeText(_:)) {
        return false
    }

    let totalLength = texts.reduce(0) { $0 + $1.count }
    return texts.count <= 8 && totalLength <= 220
}

private func isSiblingCounterText(_ text: String) -> Bool {
    text.range(of: #"^\d+\s*/\s*\d+$"#, options: .regularExpression) != nil
}

private func isStandaloneTimeRangeText(_ text: String) -> Bool {
    text.range(of: #"^\d{1,2}:\d{2}\s*-\s*\d{1,2}:\d{2}$"#, options: .regularExpression) != nil
}

private func isPlainGenericTextContainer(_ element: AXUIElement, children: [AXUIElement], depth: Int = 0) -> Bool {
    for child in children {
        let childRole = stringValue(of: child, attribute: kAXRoleAttribute) ?? ""

        if childRole == kAXStaticTextRole as String || childRole == kAXImageRole as String {
            continue
        }

        if childRole == "AXLink", summaryTextForLink(child) != nil {
            continue
        }

        if childRole == kAXGroupRole as String || childRole == kAXUnknownRole as String {
            // Crossing this boundary would collapse the actionable child into its parent's text summary.
            if isGenericPrimaryActionSummaryBoundary(
                role: childRole,
                actions: copyActions(child) ?? []
            ) {
                return false
            }

            guard depth < 3 else {
                return false
            }

            if isPlainGenericTextContainer(child, children: copyArray(child, attribute: kAXChildrenAttribute) ?? [], depth: depth + 1) {
                continue
            }
        }

        return false
    }

    return true
}

func isGenericPrimaryActionSummaryBoundary(role: String, actions: [String]) -> Bool {
    let genericRoles = [kAXGroupRole as String, kAXUnknownRole as String]
    return genericRoles.contains(role) && hasPrimaryClickAction(actions)
}

func displayRoleText(
    baseRoleText: String,
    role: String,
    title: String?,
    label: String?,
    suppressChildren: Bool
) -> String {
    if role == kAXMenuBarItemRole as String {
        return ""
    }

    if role == "AXLink" {
        return baseRoleText
    }

    if suppressChildren {
        return "container"
    }

    if baseRoleText == "radio group", role == kAXRadioGroupRole as String, title == nil, label != nil {
        return ""
    }

    return baseRoleText
}

func windowRelativeFrame(elementFrame: CGRect, windowBounds: CGRect) -> CGRect {
    CGRect(
        x: elementFrame.minX - windowBounds.minX,
        y: elementFrame.minY - windowBounds.minY,
        width: elementFrame.width,
        height: elementFrame.height
    )
}

private func roleDescription(
    of element: AXUIElement,
    role: String,
    subrole: String?,
    prefetch: AXAttributePrefetch? = nil
) -> String {
    if role == kAXRowRole as String {
        return "row"
    }

    if role == kAXGroupRole as String {
        return "container"
    }

    if role == kAXMenuBarItemRole as String {
        return ""
    }

    if role == "AXLink" {
        return "link"
    }

    if role == "AXWebArea" {
        return stringValue(of: element, attribute: kAXRoleDescriptionAttribute, prefetch: prefetch) ?? "HTML 内容"
    }

    if let roleDescription = stringValue(of: element, attribute: kAXRoleDescriptionAttribute, prefetch: prefetch),
       !roleDescription.isEmpty
    {
        return roleDescription.lowercased()
    }

    if let subrole, subrole == kAXStandardWindowSubrole as String {
        return "standard window"
    }

    return humanizeAXToken(role)
}

func meaningfulActions(_ values: [String], role: String) -> [String] {
    let rawActions = meaningfulRawActions(values, role: role)
    let names = rawActions.map(secondaryActionDisplayName(_:))
    return names.indices.map { index in
        let collides = names.indices.contains { other in
            other != index && secondaryActionNamesEquivalent(names[index], names[other])
        }
        // Exact raw-action lookup takes precedence over display-name lookup,
        // including actions omitted from the rendered list.
        let shadowsRawAction = values.contains { rawAction in
            rawAction != rawActions[index]
                && rawAction.caseInsensitiveCompare(names[index]) == .orderedSame
        }
        return collides || shadowsRawAction ? rawActions[index] : names[index]
    }
}

func meaningfulRawActions(_ values: [String], role: String) -> [String] {
    values
        .filter {
            var ignored = [
                kAXPressAction as String,
                "AXShowDefaultUI",
                "AXShowAlternateUI",
                "AXShowMenu",
                "AXConfirm",
                "AXScrollToVisible",
            ]

            if [
                kAXMenuBarRole as String,
                kAXMenuBarItemRole as String,
                kAXMenuRole as String,
                kAXMenuItemRole as String,
            ].contains(role) {
                ignored.append(contentsOf: ["AXCancel", "AXPick"])
            }

            return !ignored.contains($0)
        }
        .filter {
            guard role == kAXScrollAreaRole as String else {
                return true
            }

            if values.contains("AXScrollUpByPage") || values.contains("AXScrollDownByPage") {
                return $0 != "AXScrollLeftByPage" && $0 != "AXScrollRightByPage"
            }

            return true
        }
}

func secondaryActionDisplayName(_ value: String) -> String {
    if let name = accessibilityActionDescriptionName(value) {
        return name
    }

    if value == "AXZoomWindow" {
        return "zoom the window"
    }

    let stripped = value.hasPrefix("AX") ? String(value.dropFirst(2)) : value
    let withoutPage = stripped.replacingOccurrences(of: "ByPage", with: "")
    return splitCamelCase(withoutPage)
}

func secondaryActionNamesEquivalent(_ lhs: String, _ rhs: String) -> Bool {
    !normalizedSecondaryActionCandidates(lhs).isDisjoint(with: normalizedSecondaryActionCandidates(rhs))
}

func accessibilityActionDescriptionName(_ value: String) -> String? {
    guard let nameStart = actionDescriptionValueStart(label: "name", in: value) else {
        return nil
    }

    let nameEnd = ["target", "selector", "button clicked"]
        .compactMap { actionDescriptionLabelStart(label: $0, in: value, from: nameStart) }
        .min() ?? value.endIndex
    let name = value[nameStart..<nameEnd].trimmingCharacters(in: .whitespacesAndNewlines)
    return name.isEmpty ? nil : name
}

private func actionDescriptionValueStart(label: String, in value: String) -> String.Index? {
    var searchStart = value.startIndex
    while let range = value.range(of: label, options: .caseInsensitive, range: searchStart..<value.endIndex) {
        if range.lowerBound != value.startIndex, !value[value.index(before: range.lowerBound)].isWhitespace {
            searchStart = range.upperBound
            continue
        }

        var cursor = range.upperBound
        while cursor < value.endIndex, value[cursor].isWhitespace {
            cursor = value.index(after: cursor)
        }
        guard cursor < value.endIndex, value[cursor] == ":" else {
            searchStart = range.upperBound
            continue
        }
        cursor = value.index(after: cursor)
        while cursor < value.endIndex, value[cursor].isWhitespace {
            cursor = value.index(after: cursor)
        }
        return cursor
    }
    return nil
}

private func actionDescriptionLabelStart(label: String, in value: String, from start: String.Index) -> String.Index? {
    var searchStart = start
    while let range = value.range(of: label, options: .caseInsensitive, range: searchStart..<value.endIndex) {
        if range.lowerBound != value.startIndex, !value[value.index(before: range.lowerBound)].isWhitespace {
            searchStart = range.upperBound
            continue
        }

        var cursor = range.upperBound
        while cursor < value.endIndex, value[cursor].isWhitespace {
            cursor = value.index(after: cursor)
        }
        guard cursor < value.endIndex, value[cursor] == ":" else {
            searchStart = range.upperBound
            continue
        }
        return range.lowerBound
    }
    return nil
}

private func normalizedSecondaryActionCandidates(_ value: String) -> Set<String> {
    var candidates = Set<String>()
    let normalized = normalizedSecondaryActionName(value)
    if !normalized.isEmpty {
        candidates.insert(normalized)
    }
    if let descriptionName = accessibilityActionDescriptionName(value) {
        candidates.insert(normalizedSecondaryActionName(descriptionName))
    }
    return candidates
}

private func normalizedSecondaryActionName(_ value: String) -> String {
    value
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "_", with: " ")
        .replacingOccurrences(of: "-", with: " ")
        .split(whereSeparator: { $0.isWhitespace })
        .joined(separator: " ")
        .lowercased()
}

private func humanizeAXToken(_ value: String) -> String {
    let stripped = value.hasPrefix("AX") ? String(value.dropFirst(2)) : value
    return splitCamelCase(stripped).lowercased()
}

private func splitCamelCase(_ value: String) -> String {
    var result = ""
    for character in value {
        if character.isUppercase, !result.isEmpty {
            result.append(" ")
        }
        result.append(character)
    }
    return result
}

func sanitizeText(_ value: String, textLimit: SnapshotTextLimit = .defaults) -> String {
    let collapsed = value
        .replacingOccurrences(of: "\n", with: "\\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)

    if let maxCount = textLimit.maxCount, collapsed.count > maxCount {
        return String(collapsed.prefix(maxCount)) + "..."
    }

    return collapsed
}

private func flattenedRowTexts(
    of element: AXUIElement,
    textLimit: SnapshotTextLimit = .defaults,
    prefetch: AXAttributePrefetch? = nil
) -> [String] {
    let cells = copyArray(element, attribute: kAXChildrenAttribute, prefetch: prefetch) ?? []
    let texts = cells
        .flatMap { descendantTexts(of: $0, textLimit: textLimit) }
        .map { sanitizeText($0, textLimit: textLimit) }
        .filter { !$0.isEmpty }

    var unique: [String] = []
    var seen: Set<String> = []
    for text in texts {
        if seen.insert(text).inserted {
            unique.append(text)
        }
    }

    return unique
}

private func descendantTexts(
    of element: AXUIElement,
    depth: Int = 0,
    textLimit: SnapshotTextLimit = .defaults
) -> [String] {
    guard depth < 4 else {
        return []
    }

    var values: [String] = []
    let prefetch = AXAttributePrefetch.fetch(element, attributes: AXAttributePrefetch.textWalkAttributes)
    let role = stringValue(of: element, attribute: kAXRoleAttribute, prefetch: prefetch) ?? ""
    if role == kAXStaticTextRole as String || role == kAXTextFieldRole as String {
        if let value = sanitizedValue(of: element, textLimit: textLimit, prefetch: prefetch) {
            values.append(value)
        } else if let title = stringValue(of: element, attribute: kAXTitleAttribute, prefetch: prefetch) {
            values.append(sanitizeText(title, textLimit: textLimit))
        }
    }

    for child in copyArray(element, attribute: kAXChildrenAttribute, prefetch: prefetch) ?? [] {
        values.append(contentsOf: descendantTexts(of: child, depth: depth + 1, textLimit: textLimit))
    }

    return values
}

private func descendantTextsForSummary(
    of element: AXUIElement,
    depth: Int = 0,
    textLimit: SnapshotTextLimit = .defaults
) -> [String] {
    guard depth < 8 else {
        return []
    }

    let prefetch = AXAttributePrefetch.fetch(element, attributes: AXAttributePrefetch.textWalkAttributes)
    let role = stringValue(of: element, attribute: kAXRoleAttribute, prefetch: prefetch) ?? ""
    if role == "AXLink", let linkText = summaryTextForLink(element, textLimit: textLimit, prefetch: prefetch) {
        return [linkText]
    }

    if role == kAXStaticTextRole as String || role == kAXTextFieldRole as String {
        if let value = sanitizedValue(of: element, textLimit: textLimit, prefetch: prefetch), !value.isEmpty {
            return [value]
        }

        if let title = stringValue(of: element, attribute: kAXTitleAttribute, prefetch: prefetch) {
            let sanitized = sanitizeText(title, textLimit: textLimit)
            return sanitized.isEmpty ? [] : [sanitized]
        }
    }

    return (copyArray(element, attribute: kAXChildrenAttribute, prefetch: prefetch) ?? [])
        .flatMap { descendantTextsForSummary(of: $0, depth: depth + 1, textLimit: textLimit) }
}

private func summaryTextForLink(
    _ element: AXUIElement,
    textLimit: SnapshotTextLimit = .defaults,
    prefetch: AXAttributePrefetch? = nil
) -> String? {
    guard let url = urlValue(of: element, attribute: kAXURLAttribute, textLimit: textLimit), !url.isEmpty else {
        return nil
    }

    let childText = (copyArray(element, attribute: kAXChildrenAttribute, prefetch: prefetch) ?? [])
        .flatMap { descendantTextsForSummary(of: $0, textLimit: textLimit) }
        .joined(separator: " ")
    let sanitized = sanitizeText(childText, textLimit: textLimit)
    guard !sanitized.isEmpty else {
        return nil
    }

    return summaryMarkdownLinkText(text: sanitized, url: url)
}

func summaryMarkdownLinkText(text: String, url: String) -> String {
    "[\(markdownEscapedLinkText(text))](\(url))"
}

private let visibleRowLimit = 20

/// The first `visibleRowLimit` rows whose frame intersects the parent's, in row order; the first rows when none does.
/// Each row's frame is one round trip, and rows after the last kept one are never read.
private func visibleRows(in rows: [AXUIElement], parent: AXUIElement, parentPrefetch: AXAttributePrefetch? = nil) -> [AXUIElement] {
    guard let parentFrame = resolveLocalFrame(of: parent, windowBounds: nil, prefetch: parentPrefetch) else {
        return Array(rows.prefix(visibleRowLimit))
    }

    var visible: [AXUIElement] = []
    for row in rows {
        let rowPrefetch = AXAttributePrefetch.fetch(row, attributes: AXAttributePrefetch.frameAttributes)
        guard let rowFrame = resolveLocalFrame(of: row, windowBounds: nil, prefetch: rowPrefetch),
              rowFrame.intersects(parentFrame)
        else {
            continue
        }

        visible.append(row)
        if visible.count == visibleRowLimit {
            break
        }
    }

    if visible.isEmpty {
        return Array(rows.prefix(visibleRowLimit))
    }

    return visible
}

private func displayIdentifier(_ value: String?) -> String? {
    guard let value, !value.isEmpty, !value.hasPrefix("_NS:") else {
        return nil
    }

    return value
}

private func displayWindowTitle(_ value: String?, appName: String) -> String {
    guard let value, !value.isEmpty else {
        return appName
    }

    if value.hasPrefix("\(appName) –") {
        return appName
    }

    return value
}

private func quoted(_ value: String) -> String {
    "\"\(value)\""
}

private extension CGRect {
    var renderedLocalFrame: String {
        "x=\(Int(origin.x)), y=\(Int(origin.y)), w=\(Int(width)), h=\(Int(height))"
    }
}
