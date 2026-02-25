import SwiftUI

private struct DepEdgeInfo: Identifiable {
    let id: String // "fromUUID->toUUID"
    let fromId: UUID
    let toId: UUID
    let path: Path
}

struct GraphView: View {
    @Bindable var store: ProjectStore

    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var layout: GraphLayoutEngine.LayoutResult = .init(positions: [:], canvasSize: .zero)
    @State private var graphExpandedMode = false
    @State private var inlineEditingNodeId: UUID?
    // Link mode: click source then destination to create a dependency edge
    @State private var isLinkMode = false
    @State private var linkSourceId: UUID?
    // Selected dep edge for deletion
    @State private var selectedEdge: (from: UUID, to: UUID)?
    @FocusState private var graphFocused: Bool
    private let engine = GraphLayoutEngine()

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if store.state.rootNodeId == nil {
                    emptyState
                } else {
                    ScrollView([.horizontal, .vertical]) {
                        ZStack(alignment: .topLeading) {
                            // Edge drawing layer
                            Canvas { ctx, size in
                                drawEdges(ctx: ctx, size: size)
                            }
                            .frame(width: layout.canvasSize.width,
                                   height: layout.canvasSize.height)

                            // Dep edge hit areas (invisible, for tap detection)
                            depEdgeHitAreas

                            // Node layer
                            ForEach(visibleNodes) { node in
                                nodeCard(for: node)
                            }
                        }
                        .frame(width: max(layout.canvasSize.width, geo.size.width),
                               height: max(layout.canvasSize.height, geo.size.height))
                        .scaleEffect(scale)
                        .animation(.spring(duration: 0.3), value: scale)
                    }
                    .gesture(
                        MagnifyGesture()
                            .onChanged { val in
                                scale = max(0.3, min(3.0, val.magnification))
                            }
                    )

                    // Controls
                    VStack {
                        // Link mode hint
                        if isLinkMode {
                            HStack(spacing: 8) {
                                Image(systemName: linkSourceId == nil ? "cursorarrow.click" : "arrow.forward.circle")
                                    .foregroundStyle(.orange)
                                Text(linkSourceId == nil ? "Click source node" : "Click target node")
                                    .font(.caption.bold())
                                    .foregroundStyle(.orange)
                                Button("Cancel") {
                                    isLinkMode = false; linkSourceId = nil
                                }
                                .font(.caption)
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(.top, 8)
                        }
                        Spacer()
                        HStack {
                            Spacer()
                            zoomControls
                        }
                        .padding()
                    }
                }
            }
            .focusable()
            .focused($graphFocused)
            .focusEffectDisabled()
            .onDeleteCommand {
                if let edge = selectedEdge {
                    store.removeDependency(nodeId: edge.to, depId: edge.from)
                    selectedEdge = nil
                    recomputeLayout()
                } else if let id = store.selectedNodeId {
                    store.deleteNode(id: id)
                    recomputeLayout()
                }
            }
            .onExitCommand {
                selectedEdge = nil
                store.selectedNodeId = nil
                if isLinkMode {
                    isLinkMode = false
                    linkSourceId = nil
                }
            }
        }
        .onAppear { recomputeLayout() }
        .onChange(of: store.state.nodes.count) { recomputeLayout() }
        .onChange(of: store.state.rootNodeId) { recomputeLayout() }
        .onChange(of: graphExpandedMode) { recomputeLayout() }
    }

    // MARK: - Dep edge hit areas

    private var depEdgeHitAreas: some View {
        let edges = computeDepEdges()
        return ForEach(edges) { edge in
            edge.path
                .stroke(Color.clear, lineWidth: 20)
                .contentShape(edge.path.strokedPath(StrokeStyle(lineWidth: 20)))
                .onTapGesture {
                    guard !isLinkMode else { return }
                    graphFocused = true
                    let key = (from: edge.fromId, to: edge.toId)
                    if selectedEdge?.from == key.from && selectedEdge?.to == key.to {
                        selectedEdge = nil
                    } else {
                        selectedEdge = key
                        store.selectedNodeId = nil
                    }
                }
        }
    }

    // MARK: - Dep edge computation (matches drawEdges bezier logic exactly)

    private func computeDepEdges() -> [DepEdgeInfo] {
        var edges: [DepEdgeInfo] = []
        for (_, node) in store.state.nodes {
            for depId in node.dependencyIds {
                // Skip auto-created deps to group output milestones
                if node.type == .milestone,
                   let parentId = node.parentId,
                   let parent = store.state.nodes[parentId.uuidString],
                   parent.type == .group,
                   parent.outputMilestoneId == node.id {
                    continue
                }
                guard let fromPos = layout.positions[depId],
                      let toPos = layout.positions[node.id] else { continue }

                let endpoints = smartEndpoints(fromPos: fromPos, toPos: toPos)
                let dx = toPos.x - fromPos.x
                let dy = toPos.y - fromPos.y
                let bezierOffset: CGFloat = 40.0

                let cp1: CGPoint
                let cp2: CGPoint
                if abs(dx) >= abs(dy) {
                    let sign: CGFloat = dx >= 0 ? 1 : -1
                    cp1 = CGPoint(x: endpoints.exit.x + bezierOffset * sign, y: endpoints.exit.y)
                    cp2 = CGPoint(x: endpoints.entry.x - bezierOffset * sign, y: endpoints.entry.y)
                } else {
                    let sign: CGFloat = dy >= 0 ? 1 : -1
                    cp1 = CGPoint(x: endpoints.exit.x, y: endpoints.exit.y + bezierOffset * sign)
                    cp2 = CGPoint(x: endpoints.entry.x, y: endpoints.entry.y - bezierOffset * sign)
                }

                var path = Path()
                path.move(to: endpoints.exit)
                path.addCurve(to: endpoints.entry, control1: cp1, control2: cp2)

                edges.append(DepEdgeInfo(
                    id: "\(depId.uuidString)->\(node.id.uuidString)",
                    fromId: depId,
                    toId: node.id,
                    path: path
                ))
            }
        }
        return edges
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "circle.grid.2x2")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No nodes yet")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Use the outline or click + to add your first node")
                .font(.body)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Zoom controls

    private var zoomControls: some View {
        HStack(spacing: 8) {
            Button { scale = max(0.3, scale - 0.1) } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .buttonStyle(.bordered)
            Text(String(format: "%.0f%%", scale * 100))
                .font(.caption)
                .frame(width: 40)
            Button { scale = min(3.0, scale + 0.1) } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .buttonStyle(.bordered)
            Button { scale = 1.0 } label: {
                Image(systemName: "arrow.up.left.and.down.right.magnifyingglass")
            }
            .buttonStyle(.bordered)
            Button { graphExpandedMode.toggle() } label: {
                Image(systemName: "rectangle.expand.vertical")
            }
            .buttonStyle(.bordered)
            .tint(graphExpandedMode ? .blue : nil)
            // Link mode toggle
            Button {
                isLinkMode.toggle()
                if !isLinkMode { linkSourceId = nil }
            } label: {
                Image(systemName: "arrow.triangle.branch")
            }
            .buttonStyle(.bordered)
            .tint(isLinkMode ? .orange : nil)
            .help("Link mode: click source then target to add dependency arrow")
        }
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Node card

    @ViewBuilder
    private func nodeCard(for node: ProjectNode) -> some View {
        if let pos = layout.positions[node.id] {
            let color = store.resolvedColor(for: node.id)
            let isSelected = store.selectedNodeId == node.id
            let highlighted = highlightedNodes
            let isHighlighted = highlighted.contains(node.id)
            let isDimmed = !highlighted.isEmpty && !isHighlighted && !isSelected
            let isTimerActive = store.activeTimerNodeId == node.id
            let progress = store.groupProgress(for: node.id)
            let isLinkSource = isLinkMode && linkSourceId == node.id

            NodeCardView(node: node,
                        color: color,
                        isSelected: isSelected,
                        isHighlighted: isHighlighted,
                        isDimmed: isDimmed,
                        isTimerActive: isTimerActive,
                        showDetails: graphExpandedMode,
                        groupCompleted: progress.completed,
                        groupTotal: progress.total,
                        isInlineEditing: inlineEditingNodeId == node.id,
                        onInlineCommit: { newTitle in
                            store.updateNode(id: node.id) { $0.title = newTitle.isEmpty ? node.title : newTitle }
                            inlineEditingNodeId = nil
                        },
                        onInlineCancel: { inlineEditingNodeId = nil },
                        onStatusTap: { store.cycleStatus(nodeId: node.id) })
                .overlay(
                    isLinkSource ? RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.orange, lineWidth: 3)
                        .opacity(0.9) : nil
                )
                .position(x: pos.x + 100, y: pos.y + 32)
                .onTapGesture {
                    graphFocused = true
                    if isLinkMode {
                        if let sourceId = linkSourceId {
                            if sourceId != node.id {
                                store.addDependency(nodeId: node.id, dependsOn: sourceId)
                                recomputeLayout()
                            }
                            linkSourceId = nil
                            isLinkMode = false
                        } else {
                            linkSourceId = node.id
                        }
                    } else {
                        selectedEdge = nil
                        store.selectedNodeId = node.id
                    }
                }
                .contextMenu {
                    nodeContextMenu(for: node)
                }
        }
    }

    // MARK: - Context menu

    @ViewBuilder
    private func nodeContextMenu(for node: ProjectNode) -> some View {
        Button("Add Child Task") {
            let newNode = store.createNode(title: "New Task", type: .task, parentId: node.id)
            recomputeLayout()
            inlineEditingNodeId = newNode.id
        }
        Button("Add Child Group") {
            let newNode = store.createNode(title: "New Group", type: .group, parentId: node.id)
            recomputeLayout()
            inlineEditingNodeId = newNode.id
        }
        Button("Add Milestone") {
            let newNode = store.createNode(title: "Milestone", type: .milestone, parentId: node.id)
            recomputeLayout()
            inlineEditingNodeId = newNode.id
        }
        Divider()
        Button("Link from this node (add out-arrow)") {
            isLinkMode = true
            linkSourceId = node.id
        }
        Button("Link to this node (add in-arrow)") {
            isLinkMode = true
            linkSourceId = nil
            store.selectedNodeId = node.id
        }
        Divider()
        Button("Mark Done") { store.setStatus(nodeId: node.id, status: .done) }
        Button("Mark In Progress") { store.setStatus(nodeId: node.id, status: .doing) }
        Button("Mark To Do") { store.setStatus(nodeId: node.id, status: .todo) }
        Divider()
        Button("Set Color...") {
            store.selectedNodeId = node.id
        }
        Divider()
        Button("Delete", role: .destructive) {
            store.deleteNode(id: node.id)
            recomputeLayout()
        }
    }

    // MARK: - Helpers

    private var visibleNodes: [ProjectNode] {
        Array(store.state.nodes.values)
    }

    private var highlightedNodes: Set<UUID> {
        guard let selectedId = store.selectedNodeId else { return [] }
        var nodes = store.allTransitivePredecessors(of: selectedId)
        nodes.insert(selectedId)
        return nodes
    }

    private func recomputeLayout() {
        guard let rootIdStr = store.state.rootNodeId,
              let rootId = UUID(uuidString: rootIdStr) else {
            layout = .init(positions: [:], canvasSize: .zero)
            return
        }
        layout = engine.layout(nodes: store.state.nodes, rootId: rootId,
                               expandedNodeH: graphExpandedMode ? 160 : 64)
    }

    // Smart endpoint routing for dependency edges
    private func smartEndpoints(fromPos: CGPoint, toPos: CGPoint) -> (exit: CGPoint, entry: CGPoint) {
        let nodeW: CGFloat = 200
        let nodeH: CGFloat = 64
        let dx = toPos.x - fromPos.x
        let dy = toPos.y - fromPos.y
        if abs(dx) >= abs(dy) {
            if dx >= 0 {
                return (CGPoint(x: fromPos.x + nodeW, y: fromPos.y + nodeH / 2),
                        CGPoint(x: toPos.x, y: toPos.y + nodeH / 2))
            } else {
                return (CGPoint(x: fromPos.x, y: fromPos.y + nodeH / 2),
                        CGPoint(x: toPos.x + nodeW, y: toPos.y + nodeH / 2))
            }
        } else {
            if dy >= 0 {
                return (CGPoint(x: fromPos.x + nodeW / 2, y: fromPos.y + nodeH),
                        CGPoint(x: toPos.x + nodeW / 2, y: toPos.y))
            } else {
                return (CGPoint(x: fromPos.x + nodeW / 2, y: fromPos.y),
                        CGPoint(x: toPos.x + nodeW / 2, y: toPos.y + nodeH))
            }
        }
    }

    // MARK: - Edge drawing

    private func drawEdges(ctx: GraphicsContext, size: CGSize) {
        // Parent → child edges (straight lines, arrowhead at child)
        for (_, node) in store.state.nodes {
            guard let parentPos = layout.positions[node.id] else { continue }
            let parentCenter = CGPoint(x: parentPos.x + 100, y: parentPos.y + 64)

            for childId in node.childrenIds {
                // Skip group→milestone parent-child edge if group has non-milestone children
                if node.type == .group,
                   let childNode = store.state.nodes[childId.uuidString],
                   childNode.type == .milestone,
                   node.childrenIds.contains(where: { store.state.nodes[$0.uuidString]?.type != .milestone }) {
                    continue
                }

                guard let childPos = layout.positions[childId] else { continue }
                let childTop = CGPoint(x: childPos.x + 100, y: childPos.y)

                var path = Path()
                path.move(to: parentCenter)
                path.addLine(to: childTop)

                let color: Color = {
                    if let selId = store.selectedNodeId {
                        let pathIds = Set(store.pathToRoot(from: selId))
                        if pathIds.contains(node.id) && pathIds.contains(childId) {
                            return .blue
                        }
                    }
                    return Color(nsColor: .separatorColor)
                }()

                ctx.stroke(path, with: .color(color), lineWidth: 1.5)
                drawArrowHead(ctx: ctx, at: childTop, from: parentCenter, color: color)
            }
        }

        // Dependency edges: A→B means "B depends on A, do A before B"
        // Arrow points FROM prerequisite (depId) TO dependent (node)
        for (_, node) in store.state.nodes {
            for depId in node.dependencyIds {
                // Auto-created deps to group output milestones are drawn gray in convergence section
                if node.type == .milestone,
                   let parentId = node.parentId,
                   let parent = store.state.nodes[parentId.uuidString],
                   parent.type == .group,
                   parent.outputMilestoneId == node.id {
                    continue
                }
                guard let fromPos = layout.positions[depId],
                      let toPos = layout.positions[node.id] else { continue }

                let endpoints = smartEndpoints(fromPos: fromPos, toPos: toPos)
                let dx = toPos.x - fromPos.x
                let dy = toPos.y - fromPos.y
                let bezierOffset: CGFloat = 40.0

                let cp1: CGPoint
                let cp2: CGPoint
                if abs(dx) >= abs(dy) {
                    let sign: CGFloat = dx >= 0 ? 1 : -1
                    cp1 = CGPoint(x: endpoints.exit.x + bezierOffset * sign, y: endpoints.exit.y)
                    cp2 = CGPoint(x: endpoints.entry.x - bezierOffset * sign, y: endpoints.entry.y)
                } else {
                    let sign: CGFloat = dy >= 0 ? 1 : -1
                    cp1 = CGPoint(x: endpoints.exit.x, y: endpoints.exit.y + bezierOffset * sign)
                    cp2 = CGPoint(x: endpoints.entry.x, y: endpoints.entry.y - bezierOffset * sign)
                }

                var path = Path()
                path.move(to: endpoints.exit)
                path.addCurve(to: endpoints.entry, control1: cp1, control2: cp2)

                let isEdgeSelected = selectedEdge?.from == depId && selectedEdge?.to == node.id
                let isDependentHighlighted = store.selectedNodeId == depId
                    || store.selectedNodeId == node.id
                    || isEdgeSelected
                let color: Color = isDependentHighlighted ? .orange : Color(nsColor: .systemOrange).opacity(0.4)
                let lineWidth: CGFloat = isEdgeSelected ? 2.5 : 1.5
                ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: lineWidth, dash: [4, 3]))
                drawArrowHead(ctx: ctx, at: endpoints.entry, from: cp2, color: color)
            }
        }

        // Milestone convergence: draw from the milestone's actual leaf dependants (auto-maintained by createNode)
        for (_, node) in store.state.nodes {
            guard node.type == .group, let milestoneId = node.outputMilestoneId else { continue }
            guard let milestoneNode = store.state.nodes[milestoneId.uuidString] else { continue }
            guard let milestonePos = layout.positions[milestoneId] else { continue }

            // Leaf filter: only deps not relied upon by another dep in the same list
            let depIds = milestoneNode.dependencyIds
            let leafDepIds = depIds.filter { depId in
                !depIds.contains { otherId in
                    otherId != depId &&
                    (store.state.nodes[otherId.uuidString]?.dependencyIds.contains(depId) ?? false)
                }
            }
            for childId in leafDepIds {
                guard let childNode = store.state.nodes[childId.uuidString] else { continue }

                // If the dep is itself a group, draw from its output milestone
                let sourceId: UUID
                if childNode.type == .group,
                   let childMsId = childNode.outputMilestoneId,
                   layout.positions[childMsId] != nil {
                    sourceId = childMsId
                } else {
                    sourceId = childId
                }

                guard let sourcePos = layout.positions[sourceId] else { continue }

                let endpoints = smartEndpoints(fromPos: sourcePos, toPos: milestonePos)
                let dx = milestonePos.x - sourcePos.x
                let dy = milestonePos.y - sourcePos.y
                let bezierOffset: CGFloat = 30.0

                let cp1: CGPoint
                let cp2: CGPoint
                if abs(dx) >= abs(dy) {
                    let sign: CGFloat = dx >= 0 ? 1 : -1
                    cp1 = CGPoint(x: endpoints.exit.x + bezierOffset * sign, y: endpoints.exit.y)
                    cp2 = CGPoint(x: endpoints.entry.x - bezierOffset * sign, y: endpoints.entry.y)
                } else {
                    let sign: CGFloat = dy >= 0 ? 1 : -1
                    cp1 = CGPoint(x: endpoints.exit.x, y: endpoints.exit.y + bezierOffset * sign)
                    cp2 = CGPoint(x: endpoints.entry.x, y: endpoints.entry.y - bezierOffset * sign)
                }

                var path = Path()
                path.move(to: endpoints.exit)
                path.addCurve(to: endpoints.entry, control1: cp1, control2: cp2)
                ctx.stroke(path, with: .color(Color.gray.opacity(0.3)),
                           style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                drawArrowHead(ctx: ctx, at: endpoints.entry, from: cp2, color: Color.gray.opacity(0.3))
            }
        }
    }

    private func drawArrowHead(ctx: GraphicsContext, at tip: CGPoint, from: CGPoint, color: Color) {
        let angle = atan2(tip.y - from.y, tip.x - from.x)
        let len: CGFloat = 8
        let spread: CGFloat = 0.5
        let left = CGPoint(x: tip.x - len * cos(angle - spread),
                           y: tip.y - len * sin(angle - spread))
        let right = CGPoint(x: tip.x - len * cos(angle + spread),
                            y: tip.y - len * sin(angle + spread))
        var path = Path()
        path.move(to: tip)
        path.addLine(to: left)
        path.move(to: tip)
        path.addLine(to: right)
        ctx.stroke(path, with: .color(color), lineWidth: 1.5)
    }
}
