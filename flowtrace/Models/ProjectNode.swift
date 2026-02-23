import Foundation

enum NodeType: String, Codable, CaseIterable {
    case task, group, milestone, decision

    var icon: String {
        switch self {
        case .task: return "circle"
        case .group: return "folder"
        case .milestone: return "diamond"
        case .decision: return "arrow.triangle.branch"
        }
    }

    var label: String {
        switch self {
        case .task: return "Task"
        case .group: return "Group"
        case .milestone: return "Milestone"
        case .decision: return "Decision"
        }
    }
}

enum NodeStatus: String, Codable, CaseIterable {
    case todo, doing, done

    var label: String {
        switch self {
        case .todo: return "To Do"
        case .doing: return "In Progress"
        case .done: return "Done"
        }
    }

    var icon: String {
        switch self {
        case .todo: return "circle"
        case .doing: return "circle.lefthalf.filled"
        case .done: return "checkmark.circle.fill"
        }
    }
}

struct ChecklistItem: Codable, Identifiable {
    let id: UUID
    var text: String
    var isCompleted: Bool
    let createdAt: Date

    init(text: String) {
        self.id = UUID()
        self.text = text
        self.isCompleted = false
        self.createdAt = Date()
    }
}

struct ProjectNode: Codable, Identifiable {
    let id: UUID
    var title: String
    var description: String
    var type: NodeType
    var parentId: UUID?
    var childrenIds: [UUID]
    var dependencyIds: [UUID]
    var activeBranchId: UUID?
    var status: NodeStatus
    var colorHex: String?
    var category: String?
    var complexity: Int?
    var timeEstimate: Double?
    var timeActual: Double
    var isExpanded: Bool
    var checklistItems: [ChecklistItem]
    var notes: String
    let createdAt: Date
    var updatedAt: Date

    init(title: String, type: NodeType = .task, parentId: UUID? = nil) {
        self.id = UUID()
        self.title = title
        self.description = ""
        self.type = type
        self.parentId = parentId
        self.childrenIds = []
        self.dependencyIds = []
        self.activeBranchId = nil
        self.status = .todo
        self.colorHex = nil
        self.category = nil
        self.complexity = nil
        self.timeEstimate = nil
        self.timeActual = 0
        self.isExpanded = true
        self.checklistItems = []
        self.notes = ""
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
