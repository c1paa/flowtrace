import SwiftUI

struct ProjectListView: View {
    @Binding var store: ProjectStore?
    @State private var showNewProject = false
    @State private var newProjectName = ""
    @State private var errorMessage: String?
    @State private var recentProjects: [(name: String, url: URL)] = []

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "point.3.filled.connected.trianglepath.dotted")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)
                Text("flowtrace")
                    .font(.largeTitle.bold())
                Text("Project management like git for progress")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 60)
            .padding(.bottom, 40)

            // New Project
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text("New Project").font(.headline)
                    HStack {
                        TextField("Project name", text: $newProjectName)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { createProject() }
                        Button("Create", action: createProject)
                            .buttonStyle(.borderedProminent)
                            .disabled(newProjectName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    if let err = errorMessage {
                        Text(err).font(.caption).foregroundStyle(.red)
                    }
                }
                .padding(8)
            }
            .padding(.horizontal, 60)

            // Recent Projects
            if !recentProjects.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recent Projects")
                        .font(.headline)
                        .padding(.leading, 60)
                        .padding(.top, 24)

                    List(recentProjects, id: \.url) { project in
                        HStack {
                            Image(systemName: "folder")
                                .foregroundStyle(.blue)
                            VStack(alignment: .leading) {
                                Text(project.name).font(.body)
                                Text(project.url.path)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Button("Open") { openProject(at: project.url, name: project.name) }
                                .buttonStyle(.bordered)
                        }
                        .padding(.vertical, 4)
                    }
                    .listStyle(.plain)
                    .frame(maxHeight: 280)
                    .padding(.horizontal, 48)
                }
            }

            Spacer()

            // Open existing
            Button("Open Existing Project Folder...") {
                openExisting()
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .padding(.bottom, 24)
        }
        .frame(minWidth: 500, minHeight: 500)
        .onAppear { recentProjects = PersistenceManager.allProjects() }
    }

    private func createProject() {
        let name = newProjectName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        let projectURL = PersistenceManager.projectURL(named: name)
        do {
            try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
            var state = ProjectState()
            let root = ProjectNode(title: name, type: .group, parentId: nil)
            state.nodes[root.id.uuidString] = root
            state.rootNodeId = root.id.uuidString
            try PersistenceManager.save(state, to: projectURL.appendingPathComponent("project.json"))
            let newStore = ProjectStore(state: state, projectURL: projectURL, projectName: name)
            store = newStore
            newProjectName = ""
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func openProject(at url: URL, name: String) {
        do {
            let state = try PersistenceManager.load(from: url.appendingPathComponent("project.json"))
            store = ProjectStore(state: state, projectURL: url, projectName: name)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func openExisting() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Select a Flowtrace project folder"
        if panel.runModal() == .OK, let url = panel.url {
            let name = url.lastPathComponent
            openProject(at: url, name: name)
        }
    }
}
