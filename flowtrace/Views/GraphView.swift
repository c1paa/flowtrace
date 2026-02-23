import SwiftUI

struct GraphView: View {
    @Bindable var store: ProjectStore

    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var layout: GraphLayoutEngine.LayoutResult = .init(positions: [:], canvasSize: .zero)
    private let engine = GraphLayoutEngine()

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if store.state.rootNodeId == nil {
                    emptyState
                } else {
                    ScrollView([.horizontal, .vertical]) {
                        ZStack(alignment: .topLeading) {
                            // Edge layer
                            Canvas { ctx, size in
                                drawEdges(ctx: ctx, size: size)
                            }
                            .frame(width: layout.canvasSize.width,
                                   height: layout.canvasSize.height)

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
                        Spacer()
                        HStack {
                            Spacer()
                            zoomControls
                        }
                        .padding()
                    }
                }
            }
        }
        .onAppear { recomputeLayout() }
        .onChange(of: store.state.nodes.count) { recomputeLayout() }
        .onChange(of: store.state.rootNodeId) { recomputeLayout() }
    }

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
        }
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func nodeCard(for node: ProjectNode) -> some View {
        if let pos = layout.positions[node.id] {
            let color = store.resolvedColor(for: node.id)
            let isSelected = store.selectedNodeId == node.id
            let highlighted = highlightedNodes
            let isHighlighted = highlighted.contains(node.id)
            let isDimmed = !highlighted.isEmpty && !isHighlighted && !isSelected
            let isTimerActive = store.activeTimerNodeId == node.id

            NodeCardView(node: node,
                        color: color,
                        isSelected: isSelected,
                        isHighlighted: isHighlighted,
                        isDimmed: isDimmed,
                        isTimerActive: isTimerActive)
                .position(x: pos.x + 100, y: pos.y + 32) // offset by half card size
                .onTapGesture {
                    store.selectedNodeId = node.id
                }
                .contextMenu {
                    nodeContextMenu(for: node)
                }
        }
    }

    @ViewBuilder
    private func nodeContextMenu(for node: ProjectNode) -> some View {
        Button("Add Child Task") {
            store.createNode(title: "New Task", type: .task, parentId: node.id)
            recomputeLayout()
        }
        Button("Add Child Group") {
            store.createNode(title: "New Group", type: .group, parentId: node.id)
            recomputeLayout()
        }
        Button("Add Milestone") {
            store.createNode(title: "Milestone", type: .milestone, parentId: node.id)
            recomputeLayout()
        }
        Divider()
        Button("Mark Done") { store.setStatus(nodeId: node.id, status: .done) }
        Button("Mark In Progress") { store.setStatus(nodeId: node.id, status: .doing) }
        Button("Mark To Do") { store.setStatus(nodeId: node.id, status: .todo) }
        Divider()
        Button("Delete", role: .destructive) {
            store.deleteNode(id: node.id)
            recomputeLayout()
        }
    }

    private var visibleNodes: [ProjectNode] {
        Array(store.state.nodes.values)
    }

    private var highlightedNodes: Set<UUID> {
        guard let selectedId = store.selectedNodeId else { return [] }
        var nodes = Set<UUID>()
        nodes.formUnion(store.pathToRoot(from: selectedId))
        nodes.formUnion(store.dependents(of: selectedId))
        return nodes
    }

    private func recomputeLayout() {
        guard let rootIdStr = store.state.rootNodeId,
              let rootId = UUID(uuidString: rootIdStr) else {
            layout = .init(positions: [:], canvasSize: .zero)
            return
        }
        layout = engine.layout(nodes: store.state.nodes, rootId: rootId)
    }

    private func drawEdges(ctx: GraphicsContext, size: CGSize) {
        // Parent → child edges (straight)
        for (_, node) in store.state.nodes {
            guard let parentPos = layout.positions[node.id] else { continue }
            let parentCenter = CGPoint(x: parentPos.x + 100, y: parentPos.y + 64)

            for childId in node.childrenIds {
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

                // Arrow head
                drawArrowHead(ctx: ctx, at: childTop, from: parentCenter, color: color)
            }
        }

        // Dependency edges (curved, different color)
        for (_, node) in store.state.nodes {
            for depId in node.dependencyIds {
                guard let fromPos = layout.positions[depId],
                      let toPos = layout.positions[node.id] else { continue }

                let fromCenter = CGPoint(x: fromPos.x + 200, y: fromPos.y + 32)
                let toCenter = CGPoint(x: toPos.x, y: toPos.y + 32)

                var path = Path()
                path.move(to: fromCenter)
                let cp1 = CGPoint(x: fromCenter.x + 40, y: fromCenter.y)
                let cp2 = CGPoint(x: toCenter.x - 40, y: toCenter.y)
                path.addCurve(to: toCenter, control1: cp1, control2: cp2)

                let isDependentHighlighted = store.selectedNodeId == depId || store.selectedNodeId == node.id
                let color: Color = isDependentHighlighted ? .orange : Color(nsColor: .systemOrange).opacity(0.4)
                ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
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
