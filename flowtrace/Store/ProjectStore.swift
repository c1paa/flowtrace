import Foundation
import SwiftUI
import Combine

enum AppTab: String, CaseIterable {
    case graph, timeline, inbox, history, stats

    var label: String {
        switch self {
        case .graph: return "Graph"
        case .timeline: return "Timeline"
        case .inbox: return "Inbox"
        case .history: return "History"
        case .stats: return "Statistics"
        }
    }

    var icon: String {
        switch self {
        case .graph: return "circle.grid.2x2"
        case .timeline: return "timeline.selection"
        case .inbox: return "tray"
        case .history: return "clock.arrow.circlepath"
        case .stats: return "chart.bar"
        }
    }
}

@Observable
class ProjectStore {
    var state: ProjectState
    var projectURL: URL
    var projectName: String
    var selectedNodeId: UUID?
    var activeTab: AppTab = .graph
    var activeTimerNodeId: UUID?
    var timerStartTime: Date?
    var events: [Event] = []
    var timelineHoursPerPoint: Double = 0.5
    var showProjectSettings: Bool = false

    private var saveTask: Task<Void, Never>?
    private var undoStack: [ProjectState] = []
    private var redoStack: [ProjectState] = []
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    // MARK: - Derived URLs
    var projectStateURL: URL { projectURL.appendingPathComponent("project.json") }
    var eventsLogURL: URL { projectURL.appendingPathComponent("events.log") }
    var snapshotsURL: URL { projectURL.appendingPathComponent("snapshots") }

    // MARK: - Init

    init(state: ProjectState, projectURL: URL, projectName: String) {
        self.state = state
        self.projectURL = projectURL
        self.projectName = projectName
        self.events = (try? PersistenceManager.loadEvents(logURL: projectURL.appendingPathComponent("events.log"))) ?? []
    }

    // MARK: - Computed

    var rootNode: ProjectNode? {
        guard let id = state.rootNodeId else { return nil }
        return state.nodes[id]
    }

    var selectedNode: ProjectNode? {
        guard let id = selectedNodeId else { return nil }
        return state.nodes[id.uuidString]
    }

    func node(for id: UUID) -> ProjectNode? {
        state.nodes[id.uuidString]
    }

    func resolvedColor(for nodeId: UUID) -> Color {
        var current: UUID? = nodeId
        let defaultColors: [Color] = [.blue, .green, .orange, .purple, .pink, .teal]
        while let cid = current {
            if let n = state.nodes[cid.uuidString] {
                if let hex = n.colorHex {
                    return Color(hex: hex)
                }
                // If this node is a direct root child, cycle color by its index
                if let rootId = state.rootNodeId,
                   let root = state.nodes[rootId],
                   let idx = root.childrenIds.firstIndex(of: cid) {
                    return defaultColors[idx % defaultColors.count]
                }
                current = n.parentId
            } else { break }
        }
        return .blue
    }

    func pathToRoot(from nodeId: UUID) -> [UUID] {
        var path: [UUID] = []
        var current: UUID? = nodeId
        while let cid = current {
            path.append(cid)
            current = state.nodes[cid.uuidString]?.parentId
        }
        return path
    }

    func allTransitivePredecessors(of nodeId: UUID) -> Set<UUID> {
        var result = Set<UUID>()
        var queue = [nodeId]
        while !queue.isEmpty {
            let current = queue.removeFirst()
            guard let node = state.nodes[current.uuidString] else { continue }
            if let pid = node.parentId, !result.contains(pid) {
                result.insert(pid); queue.append(pid)
            }
            for depId in node.dependencyIds where !result.contains(depId) {
                result.insert(depId); queue.append(depId)
            }
        }
        return result
    }

    func dependents(of nodeId: UUID) -> Set<UUID> {
        var result = Set<UUID>()
        for (_, node) in state.nodes {
            if node.dependencyIds.contains(nodeId) {
                result.insert(node.id)
            }
        }
        return result
    }

    func children(of nodeId: UUID) -> [ProjectNode] {
        guard let node = state.nodes[nodeId.uuidString] else { return [] }
        return node.childrenIds.compactMap { state.nodes[$0.uuidString] }
    }

    func allDescendants(of nodeId: UUID) -> Set<UUID> {
        var result = Set<UUID>()
        var queue = [nodeId]
        while !queue.isEmpty {
            let current = queue.removeFirst()
            if let node = state.nodes[current.uuidString] {
                for childId in node.childrenIds {
                    if !result.contains(childId) {
                        result.insert(childId)
                        queue.append(childId)
                    }
                }
            }
        }
        return result
    }

    func effectiveTimeEstimate(for nodeId: UUID) -> Double? {
        guard let node = state.nodes[nodeId.uuidString] else { return nil }
        if node.type == .group {
            let sums = node.childrenIds.compactMap { effectiveTimeEstimate(for: $0) }
            return sums.isEmpty ? nil : sums.reduce(0, +)
        }
        return node.timeEstimate
    }

    func groupProgress(for nodeId: UUID) -> (completed: Int, total: Int) {
        let descs = allDescendants(of: nodeId)
        let tasks = descs.compactMap { state.nodes[$0.uuidString] }.filter { $0.type == .task }
        return (tasks.filter { $0.status == .done }.count, tasks.count)
    }

    var availableNextTasks: [ProjectNode] {
        state.nodes.values.filter { node in
            guard node.status == .todo || node.status == .doing else { return false }
            return node.dependencyIds.allSatisfy { depId in
                state.nodes[depId.uuidString]?.status == .done
            }
        }.sorted { $0.createdAt < $1.createdAt }
    }

    // MARK: - Timer (live time)

    var liveTimerSeconds: Double {
        guard let start = timerStartTime else { return 0 }
        return Date().timeIntervalSince(start)
    }

    private func pushUndo() {
        undoStack.append(state)
        if undoStack.count > 50 { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    func undo() {
        guard let prev = undoStack.popLast() else { return }
        redoStack.append(state)
        if redoStack.count > 50 { redoStack.removeFirst() }
        state = prev
        scheduleSave()
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(state)
        if undoStack.count > 50 { undoStack.removeFirst() }
        state = next
        scheduleSave()
    }

    func updateSettings(_ block: (inout ProjectSettings) -> Void) {
        block(&state.settings)
        state.updatedAt = Date()
        scheduleSave()
    }

    // MARK: - Mutations

    /// Follows the last task-typed child recursively to find the tail of a sequential chain.
    private func chainTail(of nodeId: UUID) -> UUID {
        guard let node = state.nodes[nodeId.uuidString] else { return nodeId }
        let taskChildren = node.childrenIds.filter { state.nodes[$0.uuidString]?.type == .task }
        guard let lastChildId = taskChildren.last else { return nodeId }
        return chainTail(of: lastChildId)
    }

    // MARK: - Insert node after (smart gap or leaf insertion)

    /// Inserts a new node after `nodeId`:
    /// - Has non-milestone children + inserting Task → task goes between nodeId and its children (children move into new task).
    /// - Has non-milestone children + inserting Group → empty group inserted after nodeId; old children continue AFTER group done (as children of M_G, not inside the group).
    /// - No non-milestone children → creates as a direct child of nodeId (leaf; milestone dep updates handled by createNode).
    @discardableResult
    func insertNodeAfter(nodeId: UUID, title: String, type: NodeType) -> ProjectNode {
        guard let targetNode = state.nodes[nodeId.uuidString] else {
            return createNode(title: title, type: type, parentId: nodeId)
        }

        let childrenToMove = targetNode.childrenIds.filter {
            state.nodes[$0.uuidString]?.type != .milestone
        }

        guard !childrenToMove.isEmpty else {
            // Leaf: createNode handles milestone dep updates (removes nodeId from ancestor deps, adds new node/milestone)
            return createNode(title: title, type: type, parentId: nodeId)
        }

        // Gap insertion
        pushUndo()
        let newNode = ProjectNode(title: title, type: type, parentId: nodeId)
        state.nodes[newNode.id.uuidString] = newNode
        let newNodeId = newNode.id

        if type == .group {
            // Group is created EMPTY. Old children continue AFTER group done (as children of M_G).
            // Bypasses createNode to avoid incorrect ancestor-milestone dep updates — the chain tail is
            // unchanged (it is still reachable through M_G → old children), so no dep rewiring is needed.
            let ms = ProjectNode(title: "\(title) Done", type: .milestone, parentId: newNodeId)
            state.nodes[ms.id.uuidString] = ms
            state.nodes[newNodeId.uuidString]?.childrenIds = [ms.id]
            state.nodes[newNodeId.uuidString]?.outputMilestoneId = ms.id
            let msId = ms.id

            // Detach old children from target, reparent to M_G (they come after group done)
            state.nodes[nodeId.uuidString]?.childrenIds.removeAll { childrenToMove.contains($0) }
            for childId in childrenToMove {
                state.nodes[childId.uuidString]?.parentId = msId
            }
            state.nodes[msId.uuidString]?.childrenIds.append(contentsOf: childrenToMove)

            // Attach new group to target
            state.nodes[nodeId.uuidString]?.childrenIds.append(newNodeId)

        } else {
            // Task (or other): insert in gap — old children move into the new node
            state.nodes[nodeId.uuidString]?.childrenIds.removeAll { childrenToMove.contains($0) }
            for childId in childrenToMove {
                state.nodes[childId.uuidString]?.parentId = newNodeId
            }
            state.nodes[newNodeId.uuidString]?.childrenIds.append(contentsOf: childrenToMove)

            // Attach new node to target (keep target's own milestone last if present)
            if let milestoneId = state.nodes[nodeId.uuidString]?.outputMilestoneId {
                state.nodes[nodeId.uuidString]?.childrenIds.removeAll { $0 == milestoneId }
                state.nodes[nodeId.uuidString]?.childrenIds.append(newNodeId)
                state.nodes[nodeId.uuidString]?.childrenIds.append(milestoneId)
            } else {
                state.nodes[nodeId.uuidString]?.childrenIds.append(newNodeId)
            }
        }

        state.updatedAt = Date()
        let event = Event(type: .nodeCreated, nodeId: newNodeId.uuidString,
                         summary: "Created \(type.rawValue): \(title)")
        appendEventAndSave(event)
        return state.nodes[newNodeId.uuidString]!
    }

    @discardableResult
    func createNode(title: String, type: NodeType = .task, parentId: UUID? = nil) -> ProjectNode {
        pushUndo()

        // Sequential chain: if parent is a task that already has task children,
        // follow the chain tail so the new node comes after existing ones, not parallel.
        let effectiveParentId: UUID?
        if let pid = parentId,
           let parent = state.nodes[pid.uuidString],
           parent.type == .task,
           parent.childrenIds.contains(where: { state.nodes[$0.uuidString]?.type == .task }) {
            effectiveParentId = chainTail(of: pid)
        } else {
            effectiveParentId = parentId
        }

        let node = ProjectNode(title: title, type: type, parentId: effectiveParentId)
        state.nodes[node.id.uuidString] = node

        if let pid = effectiveParentId {
            state.nodes[pid.uuidString]?.childrenIds.append(node.id)
        } else if state.rootNodeId == nil {
            state.rootNodeId = node.id.uuidString
        }

        // Auto-milestone: when a group is created, add a "Done" milestone as its output
        if type == .group {
            let ms = ProjectNode(title: "\(title) Done", type: .milestone, parentId: node.id)
            state.nodes[ms.id.uuidString] = ms
            state.nodes[node.id.uuidString]?.childrenIds.append(ms.id)
            state.nodes[node.id.uuidString]?.outputMilestoneId = ms.id
        }

        // Non-milestone child of a group with outputMilestoneId → keep milestone last
        // For group children, the parent milestone depends on the CHILD'S milestone (not the child group itself)
        if type != .milestone, let pid = effectiveParentId,
           let milestoneId = state.nodes[pid.uuidString]?.outputMilestoneId {
            state.nodes[pid.uuidString]?.childrenIds.removeAll { $0 == milestoneId }
            state.nodes[pid.uuidString]?.childrenIds.append(milestoneId)
            let depTarget: UUID
            if type == .group, let childMilestoneId = state.nodes[node.id.uuidString]?.outputMilestoneId {
                depTarget = childMilestoneId
            } else {
                depTarget = node.id
            }
            if !(state.nodes[milestoneId.uuidString]?.dependencyIds.contains(depTarget) ?? false) {
                state.nodes[milestoneId.uuidString]?.dependencyIds.append(depTarget)
                state.nodes[milestoneId.uuidString]?.updatedAt = Date()
            }
        }

        // Auto-detect: if a milestone is manually added to a group, mark it as the group's output milestone
        if type == .milestone, let pid = effectiveParentId,
           let parentNode = state.nodes[pid.uuidString], parentNode.type == .group {
            state.nodes[pid.uuidString]?.outputMilestoneId = node.id
        }

        // Nested milestone: if parent is a non-group node inside a group, update that group's milestone
        // so the new node (not the parent) is what the milestone waits on.
        if type != .milestone, let pid = effectiveParentId,
           let parent = state.nodes[pid.uuidString], parent.type != .group {
            var ancestor: UUID? = parent.parentId
            while let aid = ancestor {
                if let anc = state.nodes[aid.uuidString], anc.type == .group {
                    if let msId = anc.outputMilestoneId {
                        // Parent is no longer a leaf — remove it from milestone's deps
                        state.nodes[msId.uuidString]?.dependencyIds.removeAll { $0 == pid }
                        // For a new group, use its milestone as the dep target
                        let depTarget: UUID
                        if type == .group,
                           let childMsId = state.nodes[node.id.uuidString]?.outputMilestoneId {
                            depTarget = childMsId
                        } else {
                            depTarget = node.id
                        }
                        if !(state.nodes[msId.uuidString]?.dependencyIds.contains(depTarget) ?? false) {
                            state.nodes[msId.uuidString]?.dependencyIds.append(depTarget)
                            state.nodes[msId.uuidString]?.updatedAt = Date()
                        }
                    }
                    break
                }
                ancestor = state.nodes[aid.uuidString]?.parentId
            }
        }

        // Parent is no longer a leaf — update ALL group output milestones across the tree
        // that depended on it. This handles ancestor groups, sibling groups, etc.
        // (The nested milestone block above only updates the first enclosing group.)
        if type != .milestone, let pid = effectiveParentId {
            let depTarget: UUID
            if type == .group,
               let childMsId = state.nodes[node.id.uuidString]?.outputMilestoneId {
                depTarget = childMsId
            } else {
                depTarget = node.id
            }
            for key in state.nodes.keys {
                guard let n = state.nodes[key], n.type == .milestone,
                      let mParentId = n.parentId,
                      let mParent = state.nodes[mParentId.uuidString],
                      mParent.type == .group,
                      mParent.outputMilestoneId == n.id else { continue }
                if state.nodes[key]?.dependencyIds.contains(pid) == true {
                    state.nodes[key]?.dependencyIds.removeAll { $0 == pid }
                    if !(state.nodes[key]?.dependencyIds.contains(depTarget) ?? false) {
                        state.nodes[key]?.dependencyIds.append(depTarget)
                        state.nodes[key]?.updatedAt = Date()
                    }
                }
            }
        }

        state.updatedAt = Date()
        let summary = "Created \(type.label.lowercased()): \(title)"
        let event = Event(type: .nodeCreated, nodeId: node.id.uuidString, summary: summary)
        appendEventAndSave(event)
        return node
    }

    func updateNode(id: UUID, _ block: (inout ProjectNode) -> Void) {
        guard var node = state.nodes[id.uuidString] else { return }
        block(&node)
        node.updatedAt = Date()
        state.nodes[id.uuidString] = node
        state.updatedAt = Date()
        let event = Event(type: .nodeUpdated, nodeId: id.uuidString,
                         summary: "Updated: \(node.title)")
        appendEventAndSave(event)
    }

    func deleteNode(id: UUID) {
        guard let node = state.nodes[id.uuidString] else { return }
        pushUndo()
        let title = node.title

        // Remove from parent's children
        if let pid = node.parentId {
            state.nodes[pid.uuidString]?.childrenIds.removeAll { $0 == id }
        }
        if state.rootNodeId == id.uuidString {
            state.rootNodeId = nil
        }

        // Recursively delete descendants
        let descendants = allDescendants(of: id)
        for descId in descendants {
            state.nodes.removeValue(forKey: descId.uuidString)
        }
        state.nodes.removeValue(forKey: id.uuidString)

        // Remove dependencies referencing deleted node
        for key in state.nodes.keys {
            state.nodes[key]?.dependencyIds.removeAll { $0 == id }
        }

        if selectedNodeId == id { selectedNodeId = nil }
        if activeTimerNodeId == id { activeTimerNodeId = nil; timerStartTime = nil }

        state.updatedAt = Date()
        let event = Event(type: .nodeDeleted, nodeId: id.uuidString,
                         summary: "Deleted: \(title) (and subtree)")
        appendEventAndSave(event)
    }

    func setStatus(nodeId: UUID, status: NodeStatus) {
        guard let node = state.nodes[nodeId.uuidString] else { return }
        pushUndo()
        let old = node.status
        state.nodes[nodeId.uuidString]?.status = status
        state.nodes[nodeId.uuidString]?.updatedAt = Date()
        state.updatedAt = Date()
        let event = Event(type: .statusChanged, nodeId: nodeId.uuidString,
                         summary: "\(node.title): \(old.label) -> \(status.label)",
                         previousValue: old.rawValue, newValue: status.rawValue)
        appendEventAndSave(event)
        // Propagate status upward through parent groups
        if let parentId = state.nodes[nodeId.uuidString]?.parentId {
            propagateGroupStatus(groupId: parentId)
        }
    }

    func cycleStatus(nodeId: UUID) {
        guard let node = state.nodes[nodeId.uuidString] else { return }
        let next: NodeStatus
        switch node.status {
        case .todo: next = .doing
        case .doing: next = .done
        case .done: next = .todo
        }
        setStatus(nodeId: nodeId, status: next)
    }

    private func propagateGroupStatus(groupId: UUID) {
        guard let group = state.nodes[groupId.uuidString], group.type == .group else { return }
        let milestoneId = group.outputMilestoneId
        let nonMilestoneChildren = group.childrenIds
            .compactMap { state.nodes[$0.uuidString] }
            .filter { $0.type != .milestone }
        guard !nonMilestoneChildren.isEmpty else { return }

        let newStatus: NodeStatus
        if nonMilestoneChildren.allSatisfy({ $0.status == .done }) {
            newStatus = .done
        } else if nonMilestoneChildren.contains(where: { $0.status == .doing || $0.status == .done }) {
            newStatus = .doing
        } else {
            newStatus = .todo
        }

        state.nodes[groupId.uuidString]?.status = newStatus
        state.nodes[groupId.uuidString]?.updatedAt = Date()
        if let msId = milestoneId {
            state.nodes[msId.uuidString]?.status = newStatus
            state.nodes[msId.uuidString]?.updatedAt = Date()
        }
        state.updatedAt = Date()

        // Continue upward
        if let parentId = group.parentId, let parent = state.nodes[parentId.uuidString], parent.type == .group {
            propagateGroupStatus(groupId: parentId)
        }
    }

    func toggleChecklistItem(nodeId: UUID, itemId: UUID) {
        guard let nodeVal = state.nodes[nodeId.uuidString],
              let itemIdx = state.nodes[nodeId.uuidString]?.checklistItems.firstIndex(where: { $0.id == itemId }) else { return }
        state.nodes[nodeId.uuidString]?.checklistItems[itemIdx].isCompleted.toggle()
        state.nodes[nodeId.uuidString]?.updatedAt = Date()
        let isNowCompleted = state.nodes[nodeId.uuidString]?.checklistItems[itemIdx].isCompleted ?? false
        let completedStr = isNowCompleted ? "completed" : "uncompleted"
        state.updatedAt = Date()
        let event = Event(type: .checklistToggled, nodeId: nodeId.uuidString,
                         summary: "Checklist item \(completedStr) in \(nodeVal.title)")
        appendEventAndSave(event)
    }

    func addChecklistItem(nodeId: UUID, text: String) {
        guard state.nodes[nodeId.uuidString] != nil else { return }
        let item = ChecklistItem(text: text)
        state.nodes[nodeId.uuidString]?.checklistItems.append(item)
        state.nodes[nodeId.uuidString]?.updatedAt = Date()
        state.updatedAt = Date()
        let event = Event(type: .checklistItemAdded, nodeId: nodeId.uuidString,
                         summary: "Added checklist item: \(text)")
        appendEventAndSave(event)
    }

    func deleteChecklistItem(nodeId: UUID, itemId: UUID) {
        guard let node = state.nodes[nodeId.uuidString],
              let item = node.checklistItems.first(where: { $0.id == itemId }) else { return }
        state.nodes[nodeId.uuidString]?.checklistItems.removeAll { $0.id == itemId }
        state.nodes[nodeId.uuidString]?.updatedAt = Date()
        state.updatedAt = Date()
        let event = Event(type: .checklistItemDeleted, nodeId: nodeId.uuidString,
                         summary: "Deleted checklist item: \(item.text)")
        appendEventAndSave(event)
    }

    func startTimer(nodeId: UUID) {
        if let prev = activeTimerNodeId, prev != nodeId {
            stopTimer()
        }
        activeTimerNodeId = nodeId
        timerStartTime = Date()
        let title = state.nodes[nodeId.uuidString]?.title ?? nodeId.uuidString
        let event = Event(type: .timerStarted, nodeId: nodeId.uuidString,
                         summary: "Timer started on: \(title)")
        appendEventAndSave(event)
    }

    func stopTimer() {
        guard let nodeId = activeTimerNodeId, let start = timerStartTime else { return }
        let elapsed = Date().timeIntervalSince(start) / 3600.0
        state.nodes[nodeId.uuidString]?.timeActual += elapsed
        state.nodes[nodeId.uuidString]?.updatedAt = Date()
        state.updatedAt = Date()
        let title = state.nodes[nodeId.uuidString]?.title ?? nodeId.uuidString
        activeTimerNodeId = nil
        timerStartTime = nil
        let summary = String(format: "Timer stopped (+%.2fh): %@", elapsed, title)
        let event = Event(type: .timerStopped, nodeId: nodeId.uuidString, summary: summary)
        appendEventAndSave(event)
    }

    func setTimeManual(nodeId: UUID, hours: Double) {
        guard state.nodes[nodeId.uuidString] != nil else { return }
        state.nodes[nodeId.uuidString]?.timeActual = hours
        state.nodes[nodeId.uuidString]?.updatedAt = Date()
        state.updatedAt = Date()
        let title = state.nodes[nodeId.uuidString]?.title ?? nodeId.uuidString
        let summary = String(format: "Set manual time %.2fh on: %@", hours, title)
        let event = Event(type: .timeManualSet, nodeId: nodeId.uuidString, summary: summary)
        appendEventAndSave(event)
    }

    @discardableResult
    func addIdea(text: String, tags: [String] = [], attachedNodeId: UUID? = nil) -> Idea {
        let idea = Idea(text: text, tags: tags, attachedNodeId: attachedNodeId)
        state.ideas[idea.id.uuidString] = idea
        state.updatedAt = Date()
        let event = Event(type: .ideaAdded, nodeId: attachedNodeId?.uuidString,
                         summary: "Added idea: \(text)")
        appendEventAndSave(event)
        return idea
    }

    func updateIdea(id: UUID, _ block: (inout Idea) -> Void) {
        guard var idea = state.ideas[id.uuidString] else { return }
        block(&idea)
        idea.updatedAt = Date()
        state.ideas[id.uuidString] = idea
        state.updatedAt = Date()
        scheduleSave()
    }

    func setIdeaStatus(id: UUID, status: IdeaStatus, attachedNodeId: UUID? = nil) {
        guard var idea = state.ideas[id.uuidString] else { return }
        let old = idea.status
        idea.status = status
        idea.attachedNodeId = attachedNodeId
        idea.updatedAt = Date()
        state.ideas[id.uuidString] = idea
        state.updatedAt = Date()
        let event = Event(type: .ideaStatusChanged,
                         summary: "Idea status: \(old.label) -> \(status.label)")
        appendEventAndSave(event)
    }

    func createSnapshot(description: String) {
        do {
            try PersistenceManager.saveSnapshot(state, description: description, dir: snapshotsURL)
            let event = Event(type: .snapshotCreated, summary: "Snapshot: \(description)")
            appendEventAndSave(event)
        } catch {
            print("Snapshot error: \(error)")
        }
    }

    func restoreSnapshot(from url: URL) {
        do {
            let restored = try PersistenceManager.loadSnapshot(from: url)
            state = restored
            scheduleSave()
        } catch {
            print("Restore error: \(error)")
        }
    }

    func moveNode(id: UUID, newParentId: UUID?) {
        guard var node = state.nodes[id.uuidString] else { return }
        pushUndo()

        // Remove from old parent
        if let oldPid = node.parentId {
            state.nodes[oldPid.uuidString]?.childrenIds.removeAll { $0 == id }
        }

        // Add to new parent
        node.parentId = newParentId
        if let newPid = newParentId {
            state.nodes[newPid.uuidString]?.childrenIds.append(id)
        }
        node.updatedAt = Date()
        state.nodes[id.uuidString] = node
        state.updatedAt = Date()
        let event = Event(type: .nodeUpdated, nodeId: id.uuidString,
                         summary: "Moved: \(node.title)")
        appendEventAndSave(event)
    }

    func reorderChildren(parentId: UUID, newOrder: [UUID]) {
        state.nodes[parentId.uuidString]?.childrenIds = newOrder
        state.updatedAt = Date()
        let title = state.nodes[parentId.uuidString]?.title ?? ""
        let event = Event(type: .nodeUpdated, nodeId: parentId.uuidString,
                         summary: "Reordered children of: \(title)")
        appendEventAndSave(event)
    }

    func addDependency(nodeId: UUID, dependsOn depId: UUID) {
        guard state.nodes[nodeId.uuidString] != nil,
              state.nodes[depId.uuidString] != nil,
              !state.nodes[nodeId.uuidString]!.dependencyIds.contains(depId) else { return }
        pushUndo()
        state.nodes[nodeId.uuidString]?.dependencyIds.append(depId)
        state.nodes[nodeId.uuidString]?.updatedAt = Date()
        state.updatedAt = Date()
        let depTitle = state.nodes[depId.uuidString]?.title ?? ""
        let event = Event(type: .nodeUpdated, nodeId: nodeId.uuidString,
                         summary: "Added dependency on: \(depTitle)")
        appendEventAndSave(event)
    }

    func removeDependency(nodeId: UUID, depId: UUID) {
        pushUndo()
        state.nodes[nodeId.uuidString]?.dependencyIds.removeAll { $0 == depId }
        state.nodes[nodeId.uuidString]?.updatedAt = Date()
        state.updatedAt = Date()
        scheduleSave()
    }

    // MARK: - Persistence

    private func appendEventAndSave(_ event: Event) {
        events.append(event)
        try? PersistenceManager.appendEvent(event, logURL: eventsLogURL)
        scheduleSave()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s debounce
            if !Task.isCancelled {
                try? PersistenceManager.save(self.state, to: self.projectStateURL)
            }
        }
    }

    func forceSave() {
        try? PersistenceManager.save(state, to: projectStateURL)
    }
}

// MARK: - FocusedValue support

private struct ProjectStoreFocusedKey: FocusedValueKey {
    typealias Value = ProjectStore
}

extension FocusedValues {
    var projectStore: ProjectStore? {
        get { self[ProjectStoreFocusedKey.self] }
        set { self[ProjectStoreFocusedKey.self] = newValue }
    }
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB,
                  red: Double(r) / 255,
                  green: Double(g) / 255,
                  blue: Double(b) / 255,
                  opacity: Double(a) / 255)
    }

    var hexString: String {
        let components = NSColor(self).cgColor.components ?? [0, 0, 0, 1]
        let r = Int(components[0] * 255)
        let g = Int(components[1] * 255)
        let b = Int(components[2] * 255)
        return String(format: "%02X%02X%02X", r, g, b)
    }
}
