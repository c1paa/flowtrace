import Foundation

struct ProjectSettings: Codable {
    var workerCount: Int = 1
    var projectDescription: String = ""
}

struct ProjectState: Codable {
    var nodes: [String: ProjectNode]
    var rootNodeId: String?
    var ideas: [String: Idea]
    var version: Int
    let createdAt: Date
    var updatedAt: Date
    var settings: ProjectSettings = ProjectSettings()

    init() {
        self.nodes = [:]
        self.rootNodeId = nil
        self.ideas = [:]
        self.version = 1
        self.createdAt = Date()
        self.updatedAt = Date()
        self.settings = ProjectSettings()
    }
}
