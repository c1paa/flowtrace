import SwiftUI

private struct TimelineItem: Identifiable {
    let id: UUID
    let node: ProjectNode
    let startHour: Double
    let durationHour: Double
    let depth: Int
    let color: Color
}

struct TimelineView: View {
    @Bindable var store: ProjectStore
    @State private var hoursPerPoint: Double = 0.5 // 1 point = 0.5 hours → 2pts/hr
    @State private var items: [TimelineItem] = []

    private let rowHeight: CGFloat = 48
    private let rowSpacing: CGFloat = 8
    private let labelWidth: CGFloat = 160

    var body: some View {
        VStack(spacing: 0) {
            // Zoom controls
            HStack {
                Text("Timeline")
                    .font(.headline)
                Spacer()
                Label("Scale", systemImage: "arrow.left.and.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button { hoursPerPoint = min(2.0, hoursPerPoint * 1.5) } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Button { hoursPerPoint = max(0.05, hoursPerPoint / 1.5) } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            if items.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "timeline.selection")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("No tasks with time estimates")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                ScrollView([.horizontal, .vertical]) {
                    timelineContent
                }
            }
        }
        .onAppear { buildTimeline() }
        .onChange(of: store.state.nodes.count) { buildTimeline() }
        .onChange(of: store.state.updatedAt) { buildTimeline() }
    }

    private var timelineContent: some View {
        let totalDuration = items.map { $0.startHour + $0.durationHour }.max() ?? 1.0
        let ptsPerHour = 1.0 / hoursPerPoint
        let contentWidth = labelWidth + CGFloat(totalDuration) * ptsPerHour + 40
        let contentHeight = CGFloat(items.count) * (rowHeight + rowSpacing) + 40

        return ZStack(alignment: .topLeading) {
            // Hour grid lines
            Canvas { ctx, size in
                let stride = ptsPerHour >= 20 ? 1.0 : (ptsPerHour >= 4 ? 4.0 : 8.0)
                var h = 0.0
                while h <= totalDuration {
                    let x = labelWidth + CGFloat(h) * ptsPerHour
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                    ctx.stroke(path, with: .color(Color.secondary.opacity(0.15)), lineWidth: 1)
                    // Label
                    if ptsPerHour > 2 {
                        ctx.draw(Text("\(Int(h))h").font(.system(size: 9)).foregroundStyle(.secondary),
                                 at: CGPoint(x: x + 2, y: 4))
                    }
                    h += stride
                }
            }
            .frame(width: contentWidth, height: contentHeight)

            // Rows
            VStack(alignment: .leading, spacing: rowSpacing) {
                ForEach(items) { item in
                    HStack(spacing: 0) {
                        // Label
                        HStack(spacing: 6) {
                            Image(systemName: item.node.type.icon)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            Text(item.node.title)
                                .font(.system(size: 12))
                                .lineLimit(1)
                        }
                        .frame(width: labelWidth - 8, alignment: .leading)
                        .padding(.leading, CGFloat(item.depth) * 12)

                        // Spacer for start offset
                        Spacer(minLength: CGFloat(item.startHour) * ptsPerHour)

                        // Bar
                        let barWidth = max(4, CGFloat(item.durationHour) * ptsPerHour)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(item.color.opacity(item.node.status == .done ? 0.5 : 0.85))
                            .overlay(
                                HStack {
                                    Text(String(format: "%.1fh", item.durationHour))
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(.white)
                                        .padding(.leading, 6)
                                    Spacer()
                                }
                            )
                            .frame(width: barWidth, height: rowHeight - 8)
                            .overlay(
                                item.node.status == .done ?
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.green.opacity(0.3)) : nil
                            )
                            .onTapGesture { store.selectedNodeId = item.id }

                        Spacer()
                    }
                    .frame(height: rowHeight)
                }
            }
            .padding(.top, 20)
        }
        .frame(width: contentWidth, height: contentHeight)
    }

    private func buildTimeline() {
        guard let rootIdStr = store.state.rootNodeId,
              let rootId = UUID(uuidString: rootIdStr) else {
            items = []
            return
        }

        var result: [TimelineItem] = []
        var nodeEndTimes: [UUID: Double] = [:]

        func process(nodeId: UUID, depth: Int) {
            guard let node = store.state.nodes[nodeId.uuidString] else { return }

            // Start = max end time of dependencies
            let depEnd = node.dependencyIds.compactMap { nodeEndTimes[$0] }.max() ?? 0

            // Also consider parent end time (start not before parent starts)
            let start = depEnd

            let duration = node.timeEstimate ?? node.timeActual

            if duration > 0 || node.checklistItems.count > 0 {
                let dur = max(duration, 0.25) // minimum 15min for visibility
                let color = store.resolvedColor(for: nodeId)
                result.append(TimelineItem(id: nodeId, node: node, startHour: start,
                                           durationHour: dur, depth: depth, color: color))
                nodeEndTimes[nodeId] = start + dur
            } else {
                nodeEndTimes[nodeId] = start
            }

            for childId in node.childrenIds {
                process(nodeId: childId, depth: depth + 1)
            }
        }

        process(nodeId: rootId, depth: 0)
        items = result
    }
}
