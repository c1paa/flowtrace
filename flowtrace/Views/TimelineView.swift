import SwiftUI
import Combine

private struct TimelineItem: Identifiable {
    let id: UUID
    let node: ProjectNode
    let startHour: Double
    let durationHour: Double
    let depth: Int
    let color: Color
    // Change 7: color of direct parent group for accent stripe
    let groupColor: Color?
    let isGroup: Bool

    var hasExpandContent: Bool {
        !isGroup && (!node.description.isEmpty || !node.checklistItems.isEmpty)
    }
}

struct TimelineView: View {
    @Bindable var store: ProjectStore
    @State private var items: [TimelineItem] = []
    // Change 10: expandable rows
    @State private var expandedItems: Set<UUID> = []
    // Change 8: real-time tick for active timer progress
    @State private var tick = Date()
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

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
                Button { store.timelineHoursPerPoint = min(5.0, store.timelineHoursPerPoint * 1.5) } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Button { store.timelineHoursPerPoint = max(1.0 / 200.0, store.timelineHoursPerPoint / 1.5) } label: {
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
        // Change 8: update tick every second to drive active timer progress
        .onReceive(ticker) { tick = $0 }
    }

    // Change 6: adaptive grid stride based on zoom level
    private func gridStride(ptsPerHour: Double) -> Double {
        switch ptsPerHour {
        case 150...: return 1.0 / 12.0  // 5 min
        case 60...:  return 1.0 / 6.0   // 10 min
        case 30...:  return 0.25         // 15 min
        case 10...:  return 0.5          // 30 min
        case 4...:   return 1.0          // 1 hr
        default:     return 4.0
        }
    }

    private func gridLabel(for hour: Double, stride: Double) -> String {
        if stride < 1.0 {
            let totalMinutes = Int(round(hour * 60))
            let h = totalMinutes / 60
            let m = totalMinutes % 60
            return String(format: "%d:%02d", h, m)
        }
        return "\(Int(hour))h"
    }

    private var timelineContent: some View {
        let totalDuration = items.map { $0.startHour + $0.durationHour }.max() ?? 1.0
        let ptsPerHour = 1.0 / store.timelineHoursPerPoint
        let contentWidth = labelWidth + CGFloat(totalDuration) * ptsPerHour + 40

        // Change 10: account for expanded row extra height
        let expandedExtraHeight: CGFloat = items.reduce(0) { acc, item in
            guard expandedItems.contains(item.id) else { return acc }
            var h: CGFloat = 0
            if !item.node.description.isEmpty { h += 52 }
            h += CGFloat(min(5, item.node.checklistItems.count)) * 18
            if h > 0 { h += 8 }
            return acc + h
        }
        let contentHeight = CGFloat(items.count) * (rowHeight + rowSpacing) + expandedExtraHeight + 40
        let stride = gridStride(ptsPerHour: ptsPerHour)

        return ZStack(alignment: .topLeading) {
            // Hour grid lines
            Canvas { ctx, size in
                var h = 0.0
                while h <= totalDuration {
                    let x = labelWidth + CGFloat(h) * ptsPerHour
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                    ctx.stroke(path, with: .color(Color.secondary.opacity(0.15)), lineWidth: 1)
                    let gapPts = CGFloat(stride) * CGFloat(ptsPerHour)
                    if gapPts > 30 {
                        let label = gridLabel(for: h, stride: stride)
                        ctx.draw(Text(label).font(.system(size: 9)).foregroundStyle(.secondary),
                                 at: CGPoint(x: x + 2, y: 4))
                    }
                    h += stride
                }
            }
            .frame(width: contentWidth, height: contentHeight)

            // Rows
            VStack(alignment: .leading, spacing: rowSpacing) {
                ForEach(items, id: \.id) { item in
                    // Change 10: wrap in VStack to support expandable content
                    VStack(alignment: .leading, spacing: 0) {
                        // Main row
                        HStack(spacing: 0) {
                            // Change 10: disclosure chevron
                            Button {
                                if expandedItems.contains(item.id) {
                                    expandedItems.remove(item.id)
                                } else {
                                    expandedItems.insert(item.id)
                                }
                            } label: {
                                Image(systemName: expandedItems.contains(item.id) ? "chevron.down" : "chevron.right")
                                    .font(.system(size: 9))
                                    .foregroundStyle(item.hasExpandContent ? Color.secondary : .clear)
                            }
                            .buttonStyle(.plain)
                            .frame(width: 16)
                            .disabled(!item.hasExpandContent)

                            // Label
                            HStack(spacing: 6) {
                                Image(systemName: item.node.type.icon)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                Text(item.node.title)
                                    .font(.system(size: 12))
                                    .lineLimit(1)
                            }
                            .frame(width: labelWidth - 24, alignment: .leading)
                            .padding(.leading, CGFloat(item.depth) * 12)

                            // Spacer for start offset
                            Spacer(minLength: CGFloat(item.startHour) * ptsPerHour)

                            // Bar
                            ZStack(alignment: .leading) {
                                // Base fill
                                RoundedRectangle(cornerRadius: item.isGroup ? 2 : 4)
                                    .fill(item.color.opacity(item.isGroup ? 0.35 : (item.node.status == .done ? 0.5 : 0.85)))

                                if !item.isGroup {
                                    // Change 8: active timer progress overlay
                                    if item.id == store.activeTimerNodeId,
                                       let est = item.node.timeEstimate, est > 0,
                                       let startTime = store.timerStartTime {
                                        GeometryReader { geo in
                                            Rectangle()
                                                .fill(Color.white.opacity(0.3))
                                                .frame(width: max(0, geo.size.width * CGFloat(min(1.0, tick.timeIntervalSince(startTime) / 3600.0 / est))))
                                        }
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                    }

                                    // Done overlay
                                    if item.node.status == .done {
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Color.green.opacity(0.3))
                                    }

                                    // Duration label
                                    HStack {
                                        Text(String(format: "%.1fh", item.durationHour))
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundStyle(.white)
                                            .padding(.leading, 6)
                                        Spacer()
                                    }

                                    // Change 7: group color accent stripe on left edge
                                    if let gc = item.groupColor {
                                        HStack(spacing: 0) {
                                            Rectangle()
                                                .fill(gc)
                                                .frame(width: 3)
                                            Spacer()
                                        }
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                    }
                                }
                            }
                            .frame(width: max(4, CGFloat(item.durationHour) * ptsPerHour),
                                   height: item.isGroup ? 4 : (rowHeight - 8))
                            .onTapGesture { store.selectedNodeId = item.id }

                            Spacer()
                        }
                        .frame(height: rowHeight)

                        // Change 10: expanded detail content
                        if expandedItems.contains(item.id) {
                            VStack(alignment: .leading, spacing: 4) {
                                if !item.node.description.isEmpty {
                                    Text(item.node.description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(3)
                                        .padding(.leading, CGFloat(item.depth) * 12 + 16)
                                }
                                ForEach(Array(item.node.checklistItems.prefix(5))) { ci in
                                    HStack(spacing: 4) {
                                        Image(systemName: ci.isCompleted ? "checkmark.circle.fill" : "circle")
                                            .font(.system(size: 10))
                                            .foregroundStyle(ci.isCompleted ? .green : .secondary)
                                        Text(ci.text)
                                            .font(.caption)
                                            .lineLimit(1)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.leading, CGFloat(item.depth) * 12 + 16)
                                }
                            }
                            .padding(.bottom, 4)
                        }
                    }
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
        var nodeStartTimes: [UUID: Double] = [:]

        func process(nodeId: UUID, depth: Int) {
            guard let node = store.state.nodes[nodeId.uuidString] else { return }

            let depEnd = node.dependencyIds.compactMap { nodeEndTimes[$0] }.max() ?? 0
            let start = depEnd
            nodeStartTimes[nodeId] = start

            if node.type == .group {
                // Process children first so we can compute span
                let insertionIdx = result.count
                for childId in node.childrenIds {
                    process(nodeId: childId, depth: depth + 1)
                }
                // Compute spanning bar from all descendants
                let descendants = store.allDescendants(of: nodeId)
                let spanStart = descendants.compactMap { nodeStartTimes[$0] }.min() ?? start
                let spanEnd = descendants.compactMap { nodeEndTimes[$0] }.max() ?? start
                if spanEnd > spanStart {
                    let color = store.resolvedColor(for: nodeId)
                    let item = TimelineItem(id: nodeId, node: node, startHour: spanStart,
                                           durationHour: spanEnd - spanStart, depth: depth,
                                           color: color, groupColor: nil, isGroup: true)
                    result.insert(item, at: insertionIdx)
                }
                nodeEndTimes[nodeId] = spanEnd > spanStart ? spanEnd : start
            } else {
                let duration = node.timeEstimate ?? node.timeActual

                // Change 7: compute group color for accent stripe
                let groupColor: Color? = {
                    guard let pid = node.parentId,
                          let parent = store.state.nodes[pid.uuidString],
                          parent.type == .group else { return nil }
                    return store.resolvedColor(for: pid)
                }()

                if duration > 0 || node.checklistItems.count > 0 {
                    let dur = max(duration, 0.25)
                    let color = store.resolvedColor(for: nodeId)
                    result.append(TimelineItem(id: nodeId, node: node, startHour: start,
                                               durationHour: dur, depth: depth, color: color,
                                               groupColor: groupColor, isGroup: false))
                    nodeEndTimes[nodeId] = start + dur
                } else {
                    nodeEndTimes[nodeId] = start
                }

                for childId in node.childrenIds {
                    process(nodeId: childId, depth: depth + 1)
                }
            }
        }

        process(nodeId: rootId, depth: 0)
        items = result
    }
}
