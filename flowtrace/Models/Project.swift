import Foundation

struct ProjectState: Codable {
    var nodes: [String: ProjectNode]
    var rootNodeId: String?
    var ideas: [String: Idea]
    var version: Int
    let createdAt: Date
    var updatedAt: Date

    init() {
        self.nodes = [:]
        self.rootNodeId = nil
        self.ideas = [:]
        self.version = 1
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
