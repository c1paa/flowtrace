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

        // Add node button
        ToolbarItem(placement: .primaryAction) {
            Button {
                if let rootId = store.state.rootNodeId.flatMap({ UUID(uuidString: $0) }) {
                    store.createNode(title: "New Task", type: .task, parentId: rootId)
                } else {
                    store.createNode(title: "Project Root", type: .group)
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
    }
}
