import Foundation

enum IdeaStatus: String, Codable, CaseIterable {
    case inbox, attached, discarded

    var label: String {
        switch self {
        case .inbox: return "Inbox"
        case .attached: return "Attached"
        case .discarded: return "Discarded"
        }
    }
}

struct Idea: Codable, Identifiable {
    let id: UUID
    var text: String
    var tags: [String]
    var status: IdeaStatus
    var attachedNodeId: UUID?
    let createdAt: Date
    var updatedAt: Date

    init(text: String, tags: [String] = [], attachedNodeId: UUID? = nil) {
        self.id = UUID()
        self.text = text
        self.tags = tags
        self.status = attachedNodeId != nil ? .attached : .inbox
        self.attachedNodeId = attachedNodeId
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
