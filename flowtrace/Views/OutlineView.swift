import SwiftUI

struct OutlineView: View {
    @Bindable var store: ProjectStore
    @State private var editingNodeId: UUID?
    @State private var editingTitle = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Outline")
                    .font(.headline)
                Spacer()
                Button {
                    addRootSibling()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
                .help("Add task")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Tree
            if let rootId = store.state.rootNodeId.flatMap({ UUID(uuidString: $0) }) {
                List(selection: Binding(
                    get: { store.selectedNodeId },
                    set: { store.selectedNodeId = $0 }
                )) {
                    OutlineNodeRow(nodeId: rootId, store: store, depth: 0,
                                  editingNodeId: $editingNodeId,
                                  editingTitle: $editingTitle)
                }
                .listStyle(.sidebar)
                .onDeleteCommand {
                    if let id = store.selectedNodeId { store.deleteNode(id: id) }
                }
            } else {
                VStack {
                    Spacer()
                    Button("Create Root Node") {
                        store.createNode(title: "Project Root", type: .group)
                    }
                    .buttonStyle(.borderedProminent)
                    Spacer()
                }
            }
        }
    }

    private func addRootSibling() {
        if let rootId = store.state.rootNodeId.flatMap({ UUID(uuidString: $0) }) {
            store.createNode(title: "New Task", type: .task, parentId: rootId)
        } else {
            store.createNode(title: "Project Root", type: .group)
        }
    }
}

struct OutlineNodeRow: View {
    let nodeId: UUID
    @Bindable var store: ProjectStore
    let depth: Int
    @Binding var editingNodeId: UUID?
    @Binding var editingTitle: String

    var node: ProjectNode? { store.node(for: nodeId) }

    var body: some View {
        if let node = node {
            Group {
                if !node.childrenIds.isEmpty {
                    DisclosureGroup(
                        isExpanded: Binding(
                            get: { node.isExpanded },
                            set: { expanded in
                                store.updateNode(id: nodeId) { $0.isExpanded = expanded }
                            }
                        )
                    ) {
                        ForEach(node.childrenIds, id: \.self) { childId in
                            OutlineNodeRow(nodeId: childId, store: store, depth: depth + 1,
                                          editingNodeId: $editingNodeId,
                                          editingTitle: $editingTitle)
                        }
                    } label: {
                        rowContent(for: node)
                    }
                } else {
                    rowContent(for: node)
                        .tag(node.id)
                }
            }
            .contextMenu {
                contextMenuItems(for: node)
            }
        }
    }

    @ViewBuilder
    private func rowContent(for node: ProjectNode) -> some View {
        HStack(spacing: 6) {
            // Status checkbox
            Button {
                let next: NodeStatus = node.status == .done ? .todo : (node.status == .todo ? .doing : .done)
                store.setStatus(nodeId: node.id, status: next)
            } label: {
                Image(systemName: node.status.icon)
                    .foregroundStyle(statusColor(node.status))
                    .font(.system(size: 14))
            }
            .buttonStyle(.plain)

            // Type icon
            Image(systemName: node.type.icon)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            // Title (editable)
            if editingNodeId == node.id {
                TextField("Title", text: $editingTitle)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .onSubmit {
                        commitEdit(node: node)
                    }
                    .onExitCommand {
                        editingNodeId = nil
                    }
            } else {
                Text(node.title)
                    .font(.body)
                    .lineLimit(1)
                    .onTapGesture(count: 2) {
                        editingNodeId = node.id
                        editingTitle = node.title
                    }
            }

            Spacer()

            // Time estimate badge
            if let est = node.timeEstimate {
                Text(String(format: "%.1fh", est))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.1), in: Capsule())
            }
        }
        .tag(node.id)
        .padding(.leading, CGFloat(depth) * 4)
        .onTapGesture {
            store.selectedNodeId = node.id
        }
    }

    @ViewBuilder
    private func contextMenuItems(for node: ProjectNode) -> some View {
        Button("Add Child Task") {
            store.createNode(title: "New Task", type: .task, parentId: node.id)
            store.updateNode(id: node.id) { $0.isExpanded = true }
        }
        Button("Add Child Group") {
            store.createNode(title: "New Group", type: .group, parentId: node.id)
            store.updateNode(id: node.id) { $0.isExpanded = true }
        }
        Button("Add Sibling") {
            store.createNode(title: "New Task", type: .task, parentId: node.parentId)
        }
        Divider()
        Menu("Change Type") {
            ForEach(NodeType.allCases, id: \.self) { type in
                Button(type.label) {
                    store.updateNode(id: node.id) { $0.type = type }
                }
            }
        }
        Divider()
        Menu("Set Status") {
            ForEach(NodeStatus.allCases, id: \.self) { status in
                Button(status.label) {
                    store.setStatus(nodeId: node.id, status: status)
                }
            }
        }
        Divider()
        Button("Rename") {
            editingNodeId = node.id
            editingTitle = node.title
        }
        Divider()
        Button("Delete", role: .destructive) {
            store.deleteNode(id: node.id)
        }
    }

    private func commitEdit(node: ProjectNode) {
        let title = editingTitle.trimmingCharacters(in: .whitespaces)
        if !title.isEmpty {
            store.updateNode(id: node.id) { $0.title = title }
        }
        editingNodeId = nil
    }

    private func statusColor(_ status: NodeStatus) -> Color {
        switch status {
        case .todo: return .secondary
        case .doing: return .orange
        case .done: return .green
        }
    }
}
