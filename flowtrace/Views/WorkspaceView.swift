import SwiftUI

struct WorkspaceView: View {
    @Bindable var store: ProjectStore
    @State private var showSnapshotPrompt = false

    var body: some View {
        NavigationSplitView {
            // Left: Outline
            OutlineView(store: store)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } content: {
            // Center: Tab content
            centerContent
                .navigationSplitViewColumnWidth(min: 400, ideal: 600)
                .toolbar {
                    centerToolbar
                }
        } detail: {
            // Right: Node detail
            if let nodeId = store.selectedNodeId {
                NodeDetailView(nodeId: nodeId, store: store)
                    .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 400)
            } else {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "sidebar.right")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("Select a node to see details")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 400)
            }
        }
        .navigationTitle(store.projectName)
        .focusedValue(\.projectStore, store)
        .sheet(isPresented: $store.showProjectSettings) {
            NavigationStack {
                ProjectSettingsSheet(store: store)
            }
        }
    }

    @ViewBuilder
    private var centerContent: some View {
        switch store.activeTab {
        case .graph:
            GraphView(store: store)
        case .timeline:
            TimelineView(store: store)
        case .inbox:
            InboxView(store: store)
        case .history:
            HistoryView(store: store)
        case .stats:
            StatisticsView(store: store)
        }
    }

    @ToolbarContentBuilder
    private var centerToolbar: some ToolbarContent {
        // Tab picker
        ToolbarItem(placement: .principal) {
            Picker("Tab", selection: Binding(
                get: { store.activeTab },
                set: { store.activeTab = $0 }
            )) {
                ForEach(AppTab.allCases, id: \.self) { tab in
                    Label(tab.label, systemImage: tab.icon).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 420)
        }

        // Add node button — creates child of selected node (or root child if none selected)
        ToolbarItem(placement: .primaryAction) {
            Button {
                if store.state.rootNodeId == nil {
                    store.createNode(title: "Project Root", type: .group)
                } else {
                    let parentId = store.selectedNodeId
                        ?? store.state.rootNodeId.flatMap { UUID(uuidString: $0) }
                    store.createNode(title: "New Task", type: .task, parentId: parentId)
                }
            } label: {
                Label("Add Node", systemImage: "plus")
            }
            .keyboardShortcut("n", modifiers: [.command])
            .help("Add new task (⌘N)")
        }

        // Snapshot button
        ToolbarItem(placement: .automatic) {
            Button {
                store.createSnapshot(description: "quick save")
            } label: {
                Label("Snapshot", systemImage: "camera")
            }
            .help("Save snapshot")
        }

        // Project settings
        ToolbarItem(placement: .automatic) {
            Button {
                store.showProjectSettings = true
            } label: {
                Label("Settings", systemImage: "gear")
            }
            .help("Project Settings (⌘⇧,)")
        }
    }
}

private struct ProjectSettingsSheet: View {
    @Bindable var store: ProjectStore

    var body: some View {
        Form {
            Section("Team") {
                Stepper(
                    "Workers: \(store.state.settings.workerCount)",
                    value: Binding(
                        get: { store.state.settings.workerCount },
                        set: { val in store.updateSettings { $0.workerCount = max(1, val) } }
                    ),
                    in: 1...20
                )
                if store.state.settings.workerCount == 1 {
                    Text("Sequential mode: tasks in a group run one after another")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Description") {
                TextEditor(text: Binding(
                    get: { store.state.settings.projectDescription },
                    set: { val in store.updateSettings { $0.projectDescription = val } }
                ))
                .frame(height: 80)
            }
        }
        .formStyle(.grouped)
        .frame(width: 380, height: 280)
        .navigationTitle("Project Settings")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { store.showProjectSettings = false }
            }
        }
    }
}
