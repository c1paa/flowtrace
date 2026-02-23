import Foundation

enum EventType: String, Codable {
    case nodeCreated, nodeUpdated, nodeDeleted, statusChanged
    case checklistToggled, checklistItemAdded, checklistItemDeleted
    case timerStarted, timerStopped, timeManualSet
    case ideaAdded, ideaStatusChanged, ideaAttached
    case snapshotCreated, projectRenamed

    var icon: String {
        switch self {
        case .nodeCreated: return "plus.circle"
        case .nodeUpdated: return "pencil.circle"
        case .nodeDeleted: return "minus.circle"
        case .statusChanged: return "arrow.triangle.2.circlepath"
        case .checklistToggled: return "checkmark.square"
        case .checklistItemAdded: return "square.and.pencil"
        case .checklistItemDeleted: return "trash"
        case .timerStarted: return "play.circle"
        case .timerStopped: return "stop.circle"
        case .timeManualSet: return "clock"
        case .ideaAdded: return "lightbulb"
        case .ideaStatusChanged: return "lightbulb.fill"
        case .ideaAttached: return "link"
        case .snapshotCreated: return "camera"
        case .projectRenamed: return "textformat"
        }
    }
}

struct Event: Codable {
    let id: UUID
    let timestamp: Date
    let type: EventType
    let nodeId: String?
    let summary: String
    let previousValue: String?
    let newValue: String?

    init(type: EventType, nodeId: String? = nil, summary: String,
         previousValue: String? = nil, newValue: String? = nil) {
        self.id = UUID()
        self.timestamp = Date()
        self.type = type
        self.nodeId = nodeId
        self.summary = summary
        self.previousValue = previousValue
        self.newValue = newValue
    }
}
