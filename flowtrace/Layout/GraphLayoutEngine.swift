import Foundation
import CoreGraphics

class GraphLayoutEngine {
    let nodeW: CGFloat = 200
    let nodeH: CGFloat = 64
    let hGap: CGFloat = 32
    let vGap: CGFloat = 80

    struct LayoutResult {
        var positions: [UUID: CGPoint]
        var canvasSize: CGSize
    }

    func layout(nodes: [String: ProjectNode], rootId: UUID, expandedNodeH: CGFloat = 64) -> LayoutResult {
        guard nodes[rootId.uuidString] != nil else {
            return LayoutResult(positions: [:], canvasSize: .zero)
        }

        var subtreeWidths: [UUID: CGFloat] = [:]
        var positions: [UUID: CGPoint] = [:]

        // Post-order: compute subtree widths
        computeSubtreeWidths(nodeId: rootId, nodes: nodes, widths: &subtreeWidths)

        // Pre-order: assign positions
        assignPositions(nodeId: rootId, nodes: nodes,
                        widths: subtreeWidths,
                        x: 0, y: 0,
                        expandedNodeH: expandedNodeH,
                        positions: &positions)

        // Normalize so minimum x and y are at margin
        let margin: CGFloat = 40
        let minX = positions.values.map { $0.x }.min() ?? 0
        let minY = positions.values.map { $0.y }.min() ?? 0

        var normalizedPositions: [UUID: CGPoint] = [:]
        for (id, pt) in positions {
            normalizedPositions[id] = CGPoint(x: pt.x - minX + margin,
                                              y: pt.y - minY + margin)
        }

        let maxX = normalizedPositions.values.map { $0.x + nodeW }.max() ?? 0
        let maxY = normalizedPositions.values.map { $0.y + expandedNodeH }.max() ?? 0
        let canvasSize = CGSize(width: maxX + margin, height: maxY + margin)

        return LayoutResult(positions: normalizedPositions, canvasSize: canvasSize)
    }

    /// Returns the Y of the top of the deepest node in the subtree rooted at nodeId.
    private func maxDescendantY(nodeId: UUID, nodes: [String: ProjectNode],
                                positions: [UUID: CGPoint]) -> CGFloat {
        guard let pos = positions[nodeId] else { return 0 }
        guard let node = nodes[nodeId.uuidString], !node.childrenIds.isEmpty else {
            return pos.y
        }
        return node.childrenIds.map {
            maxDescendantY(nodeId: $0, nodes: nodes, positions: positions)
        }.max() ?? pos.y
    }

    @discardableResult
    private func computeSubtreeWidths(nodeId: UUID, nodes: [String: ProjectNode],
                                      widths: inout [UUID: CGFloat]) -> CGFloat {
        guard let node = nodes[nodeId.uuidString] else {
            widths[nodeId] = nodeW
            return nodeW
        }

        if node.childrenIds.isEmpty {
            widths[nodeId] = nodeW
            return nodeW
        }

        // For groups with output milestone, exclude milestone from horizontal layout
        let milestoneId: UUID? = (node.type == .group) ? node.outputMilestoneId : nil
        let horizontalChildren = node.childrenIds.filter { $0 != milestoneId }

        // Still compute milestone subtree width
        if let msId = milestoneId {
            computeSubtreeWidths(nodeId: msId, nodes: nodes, widths: &widths)
        }

        var childrenTotalWidth: CGFloat = 0
        for (idx, childId) in horizontalChildren.enumerated() {
            let w = computeSubtreeWidths(nodeId: childId, nodes: nodes, widths: &widths)
            childrenTotalWidth += w
            if idx < horizontalChildren.count - 1 {
                childrenTotalWidth += hGap
            }
        }

        let width = max(nodeW, childrenTotalWidth)
        widths[nodeId] = width
        return width
    }

    private func assignPositions(nodeId: UUID, nodes: [String: ProjectNode],
                                 widths: [UUID: CGFloat],
                                 x: CGFloat, y: CGFloat,
                                 expandedNodeH: CGFloat,
                                 positions: inout [UUID: CGPoint]) {
        guard let node = nodes[nodeId.uuidString] else { return }

        let subtreeW = widths[nodeId] ?? nodeW
        // Center node over its subtree
        let nodeX = x + (subtreeW - nodeW) / 2
        positions[nodeId] = CGPoint(x: nodeX, y: y)

        guard !node.childrenIds.isEmpty else { return }

        // For groups with output milestone, exclude milestone from horizontal layout
        let milestoneId: UUID? = (node.type == .group) ? node.outputMilestoneId : nil
        let horizontalChildren = node.childrenIds.filter { $0 != milestoneId }

        // Lay out non-milestone children side by side at childY
        var childX = x
        let childY = y + expandedNodeH + vGap

        for childId in horizontalChildren {
            let childW = widths[childId] ?? nodeW
            assignPositions(nodeId: childId, nodes: nodes,
                            widths: widths,
                            x: childX, y: childY,
                            expandedNodeH: expandedNodeH,
                            positions: &positions)
            childX += childW + hGap
        }

        // Place output milestone below the deepest descendant, centered over the group
        if let msId = milestoneId {
            let deepestY = horizontalChildren.isEmpty ? childY :
                horizontalChildren.map { maxDescendantY(nodeId: $0, nodes: nodes, positions: positions) }.max() ?? childY
            let msY = deepestY + expandedNodeH + vGap
            let msNodeX = x + (subtreeW - nodeW) / 2
            positions[msId] = CGPoint(x: msNodeX, y: msY)
            // Handle milestone's own children if any
            if let msNode = nodes[msId.uuidString], !msNode.childrenIds.isEmpty {
                var msChildX = msNodeX
                let msChildY = msY + expandedNodeH + vGap
                for childId in msNode.childrenIds {
                    let childW = widths[childId] ?? nodeW
                    assignPositions(nodeId: childId, nodes: nodes,
                                    widths: widths,
                                    x: msChildX, y: msChildY,
                                    expandedNodeH: expandedNodeH,
                                    positions: &positions)
                    msChildX += childW + hGap
                }
            }
        }
    }
}
