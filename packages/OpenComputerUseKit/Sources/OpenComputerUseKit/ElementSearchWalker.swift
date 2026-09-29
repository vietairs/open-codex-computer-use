import Foundation

/// A validated `find_elements` request: which elements to look for and how much of the tree may be read.
public struct ElementSearchQuery: Equatable, Sendable {
    public enum MatchMode: String, Sendable {
        case exact
        case contains

        /// `nil` selects `.contains`; any other unknown spelling is rejected.
        public init(argument: String?) throws {
            guard let argument else {
                self = .contains
                return
            }
            guard let mode = MatchMode(rawValue: argument.lowercased()) else {
                throw ComputerUseError.invalidArguments("match must be one of: exact, contains")
            }
            self = mode
        }
    }

    public static let defaultMaxResults = 5
    public static let maximumMaxResults = 20
    public static let defaultMaxNodes = 1200
    public static let maximumMaxNodes = 10_000

    public let role: String?
    public let label: String?
    public let identifier: String?
    public let matchMode: MatchMode
    public let maxResults: Int
    public let maxNodes: Int

    public init(
        role: String?,
        label: String?,
        identifier: String?,
        matchMode: MatchMode = .contains,
        maxResults: Int = ElementSearchQuery.defaultMaxResults,
        maxNodes: Int = ElementSearchQuery.defaultMaxNodes
    ) throws {
        let role = Self.nonEmpty(role)
        let label = Self.nonEmpty(label)
        let identifier = Self.nonEmpty(identifier)
        guard role != nil || label != nil || identifier != nil else {
            throw ComputerUseError.invalidArguments("find_elements needs at least one of role, label or identifier")
        }
        guard (1...Self.maximumMaxResults).contains(maxResults) else {
            throw ComputerUseError.invalidArguments("max_results must be between 1 and \(Self.maximumMaxResults)")
        }
        guard (1...Self.maximumMaxNodes).contains(maxNodes) else {
            throw ComputerUseError.invalidArguments("max_nodes must be between 1 and \(Self.maximumMaxNodes)")
        }

        self.role = role
        self.label = label
        self.identifier = identifier
        self.matchMode = matchMode
        self.maxResults = maxResults
        self.maxNodes = maxNodes
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else {
            return nil
        }
        return value
    }

    /// Every provided criterion must hold. Role ignores case and a leading `AX`; label is compared with the title
    /// or the description; identifier with the identifier.
    func matches(_ attributes: ElementSearchNodeAttributes) -> Bool {
        if let role {
            guard let nodeRole = attributes.role,
                  Self.strippingAXPrefix(role).lowercased() == Self.strippingAXPrefix(nodeRole).lowercased()
            else {
                return false
            }
        }

        if let label {
            let candidates = [attributes.title, attributes.description].compactMap { $0 }
            guard candidates.contains(where: { textMatches($0, against: label) }) else {
                return false
            }
        }

        if let identifier {
            guard let nodeIdentifier = attributes.identifier, textMatches(nodeIdentifier, against: identifier) else {
                return false
            }
        }

        return true
    }

    private func textMatches(_ text: String, against needle: String) -> Bool {
        switch matchMode {
        case .exact:
            return text.caseInsensitiveCompare(needle) == .orderedSame
        case .contains:
            return text.range(of: needle, options: .caseInsensitive) != nil
        }
    }

    private static func strippingAXPrefix(_ role: String) -> String {
        role.hasPrefix("AX") ? String(role.dropFirst(2)) : role
    }
}

/// The attributes the search needs from one node, already decoded to plain values.
struct ElementSearchNodeAttributes: Equatable {
    var role: String?
    var subrole: String?
    var title: String?
    var description: String?
    var identifier: String?
    var enabled: Bool?
}

/// Where the walker gets nodes from. The live implementation reads accessibility elements; tests use an in-memory
/// tree. `read` returns a node's attributes and its children in one call.
protocol ElementSearchNodeSource {
    associatedtype Node
    func read(_ node: Node) -> (attributes: ElementSearchNodeAttributes, children: [Node])
    func isSameNode(_ lhs: Node, _ rhs: Node) -> Bool
}

struct ElementSearchHit<Node> {
    let node: Node
    let attributes: ElementSearchNodeAttributes
}

struct ElementSearchOutcome<Node> {
    let hits: [ElementSearchHit<Node>]
    let nodesVisited: Int
    /// The node budget ran out while nodes were still waiting to be read.
    let truncated: Bool
    let stoppedAtMaxResults: Bool
}

enum ElementSearchWalker {
    private struct Pending<Node> {
        let node: Node
        /// Nodes from the root down to (excluding) `node`; a child equal to any of them is a cycle.
        let ancestors: [Node]
    }

    /// Iterative pre-order depth-first search. Reads each visited node exactly once and stops as soon as
    /// `maxResults` hits are found or `maxNodes` nodes have been read.
    static func search<Source: ElementSearchNodeSource>(
        root: Source.Node,
        source: Source,
        query: ElementSearchQuery,
        maxDepth: Int = AccessibilityTreeLimits.defaultMaxDepth
    ) -> ElementSearchOutcome<Source.Node> {
        var stack = [Pending(node: root, ancestors: [])]
        var hits: [ElementSearchHit<Source.Node>] = []
        var nodesVisited = 0
        var truncated = false
        var stoppedAtMaxResults = false

        while let pending = stack.popLast() {
            if nodesVisited >= query.maxNodes {
                truncated = true
                break
            }

            let (attributes, children) = source.read(pending.node)
            nodesVisited += 1

            if query.matches(attributes) {
                hits.append(ElementSearchHit(node: pending.node, attributes: attributes))
                if hits.count >= query.maxResults {
                    stoppedAtMaxResults = true
                    break
                }
            }

            guard pending.ancestors.count < maxDepth else {
                continue
            }

            let path = pending.ancestors + [pending.node]
            // Pushed in reverse so the first child is read next.
            for child in children.reversed() {
                if path.contains(where: { source.isSameNode($0, child) }) {
                    continue
                }
                stack.append(Pending(node: child, ancestors: path))
            }
        }

        return ElementSearchOutcome(
            hits: hits,
            nodesVisited: nodesVisited,
            truncated: truncated,
            stoppedAtMaxResults: stoppedAtMaxResults
        )
    }
}
