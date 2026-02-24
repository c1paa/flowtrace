import SwiftUI
import Combine

private struct TimelineItem: Identifiable {
    let id: UUID
    let node: ProjectNode
    let startHour: Double
    let durationHour: Double
    let depth: Int
    let color: Color
    let groupColor: Color?
    let isGroup: Bool

    var hasExpandContent: Bool {
        !isGroup && (!node.description.isEmpty || !node.checklistItems.isEmpty)
    }
}

struct TimelineView: View {
    @Bindable var store: ProjectStore
    @State private var items: [TimelineItem] = []
    @State private var expandedItems: Set<UUID> = []
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
        .onReceive(ticker) { tick = $0 }
    }

    private func gridStride(ptsPerHour: Double) -> Double {
        switch ptsPerHour {
        case 150...: return 1.0 / 12.0
        case 60...:  return 1.0 / 6.0
        case 30...:  return 0.25
        case 10...:  return 0.5
        case 4...:   return 1.0
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
                    VStack(alignment: .leading, spacing: 0) {
                        // Main row
                        HStack(spacing: 0) {
                            // Label — no expand chevron here; expand triggered by clicking the bar
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

                            // Fixed-width offset so bar starts at the exact position (not centered)
                            Color.clear.frame(width: CGFloat(item.startHour) * ptsPerHour, height: 1)

                            // Bar
                            ZStack(alignment: .leading) {
                                // Base fill
                                RoundedRectangle(cornerRadius: item.isGroup ? 2 : 4)
                                    .fill(item.color.opacity(item.isGroup ? 0.35 : (item.node.status == .done ? 0.5 : 0.85)))

                                if item.isGroup {
                                    let prog = store.groupProgress(for: item.id)
                                    if prog.total > 0 {
                                        VStack(alignment: .leading, spacing: 2) {
                                            ProgressView(value: Double(prog.completed), total: Double(prog.total))
                                                .progressViewStyle(.linear)
                                                .padding(.horizontal, 4)
                                            Text("\(prog.completed)/\(prog.total) tasks")
                                                .font(.system(size: 8))
                                                .foregroundStyle(.white.opacity(0.8))
                                                .padding(.leading, 6)
                                        }
                                    }
                                } else {
                                    let liveActual: Double = {
                                        var a = item.node.timeActual
                                        if item.id == store.activeTimerNodeId,
                                           let startTime = store.timerStartTime {
                                            a += tick.timeIntervalSince(startTime) / 3600.0
                                        }
                                        return a
                                    }()
                                    if let est = item.node.timeEstimate, est > 0, liveActual > 0 {
                                        GeometryReader { geo in
                                            Rectangle()
                                                .fill(Color.white.opacity(0.3))
                                                .frame(width: max(0, geo.size.width * CGFloat(min(1.0, liveActual / est))))
                                        }
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                    }

                                    if item.node.status == .done {
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Color.green.opacity(0.3))
                                    }

                                    // Bar label with expand indicator
                                    HStack(spacing: 4) {
                                        if item.hasExpandContent {
                                            Image(systemName: expandedItems.contains(item.id) ? "chevron.down" : "chevron.right")
                                                .font(.system(size: 8))
                                                .foregroundStyle(.white.opacity(0.7))
                                        }
                                        Text(item.node.title)
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundStyle(.white)
                                            .lineLimit(1)
                                        Spacer()
                                        Text(String(format: "%.1fh", item.durationHour))
                                            .font(.system(size: 9))
                                            .foregroundStyle(.white.opacity(0.75))
                                    }
                                    .padding(.horizontal, 6)

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
                                   height: item.isGroup ? 20 : (rowHeight - 8))
                            .onTapGesture {
                                store.selectedNodeId = item.id
                                if item.hasExpandContent {
                                    if expandedItems.contains(item.id) {
                                        expandedItems.remove(item.id)
                                    } else {
                                        expandedItems.insert(item.id)
                                    }
                                }
                            }

                            Spacer()
                        }
                        .frame(height: rowHeight)

                        // Expanded detail content — aligned with bar start
                        if expandedItems.contains(item.id) && !item.isGroup {
                            HStack(spacing: 0) {
                                Color.clear.frame(width: labelWidth + CGFloat(item.startHour * ptsPerHour))
                                VStack(alignment: .leading, spacing: 4) {
                                    if !item.node.description.isEmpty {
                                        Text(item.node.description)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(3)
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
                                    }
                                }
                                Spacer()
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
        var builder = TLBuilder(store: store)
        builder.run(rootId: rootId)
        items = builder.result
    }
}

// MARK: - Timeline Builder

private struct TLBuilder {
    let store: ProjectStore
    var result: [TimelineItem] = []
    var nodeEndTimes: [UUID: Double] = [:]
    var nodeStartTimes: [UUID: Double] = [:]

    var workerCount: Int { max(1, store.state.settings.workerCount) }
    var sequential: Bool { workerCount == 1 }

    mutating func run(rootId: UUID) {
        processNode(nodeId: rootId, depth: 0, minStart: 0)
    }

    mutating func processNode(nodeId: UUID, depth: Int, minStart: Double) {
        guard let node = store.state.nodes[nodeId.uuidString] else { return }
        let depEnd = node.dependencyIds.compactMap { nodeEndTimes[$0] }.max() ?? 0
        let start = max(depEnd, minStart)
        nodeStartTimes[nodeId] = start

        if node.type == .group {
            processGroup(nodeId: nodeId, node: node, depth: depth, groupStart: start)
        } else {
            processLeaf(nodeId: nodeId, node: node, depth: depth, start: start)
        }
    }

    mutating func processGroup(nodeId: UUID, node: ProjectNode, depth: Int, groupStart: Double) {
        let insertionIdx = result.count

        // Milestone runs after all non-milestone children finish
        let milestoneId = node.outputMilestoneId
        let nonMilestoneChildren = node.childrenIds.filter { $0 != milestoneId }

        // Sequential cursor or parallel slots, starting at groupStart
        var cursor = groupStart
        var slots = Array(repeating: groupStart, count: workerCount)

        for childId in nonMilestoneChildren {
            let childMinStart: Double = sequential ? cursor : (slots.min() ?? groupStart)
            processNode(nodeId: childId, depth: depth + 1, minStart: childMinStart)

            let childEnd = nodeEndTimes[childId] ?? groupStart
            if sequential {
                cursor = childEnd
            } else {
                if let slotIdx = slots.indices.min(by: { slots[$0] < slots[$1] }) {
                    slots[slotIdx] = childEnd
                }
            }
        }

        // Milestone starts after all children are done
        let allChildrenEnd = sequential ? cursor : (slots.max() ?? groupStart)
        if let msId = milestoneId {
            processNode(nodeId: msId, depth: depth + 1, minStart: allChildrenEnd)
        }

        // Compute group span from all descendants
        let descendants = store.allDescendants(of: nodeId)
        let spanStart = descendants.compactMap { nodeStartTimes[$0] }.min() ?? groupStart
        let spanEnd = descendants.compactMap { nodeEndTimes[$0] }.max() ?? groupStart

        let color = store.resolvedColor(for: nodeId)
        if spanEnd > spanStart {
            let item = TimelineItem(id: nodeId, node: node, startHour: spanStart,
                                   durationHour: spanEnd - spanStart, depth: depth,
                                   color: color, groupColor: nil, isGroup: true)
            result.insert(item, at: insertionIdx)
        }
        nodeEndTimes[nodeId] = spanEnd > spanStart ? spanEnd : groupStart
        nodeStartTimes[nodeId] = spanStart
    }

    mutating func processLeaf(nodeId: UUID, node: ProjectNode, depth: Int, start: Double) {
        let duration = node.timeEstimate ?? node.timeActual

        let groupColor: Color? = {
            guard let pid = node.parentId,
                  let parent = store.state.nodes[pid.uuidString],
                  parent.type == .group else { return nil }
            return store.resolvedColor(for: pid)
        }()

        if duration > 0 || !node.checklistItems.isEmpty {
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
            processNode(nodeId: childId, depth: depth + 1, minStart: start)
        }
    }
}
