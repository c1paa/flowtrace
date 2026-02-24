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

        var childrenTotalWidth: CGFloat = 0
        for (idx, childId) in node.childrenIds.enumerated() {
            let w = computeSubtreeWidths(nodeId: childId, nodes: nodes, widths: &widths)
            childrenTotalWidth += w
            if idx < node.childrenIds.count - 1 {
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

        // Lay out children side by side
        var childX = x
        let childY = y + expandedNodeH + vGap

        for childId in node.childrenIds {
            let childW = widths[childId] ?? nodeW
            assignPositions(nodeId: childId, nodes: nodes,
                            widths: widths,
                            x: childX, y: childY,
                            expandedNodeH: expandedNodeH,
                            positions: &positions)
            childX += childW + hGap
        }
    }
}
