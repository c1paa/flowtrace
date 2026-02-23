import SwiftUI

struct InboxView: View {
    @Bindable var store: ProjectStore
    @State private var newIdeaText = ""
    @State private var filterStatus: IdeaStatus? = nil
    @State private var showAttachPicker: UUID? = nil
    @FocusState private var captureFieldFocused: Bool

    var filteredIdeas: [Idea] {
        let all = store.state.ideas.values.sorted { $0.createdAt > $1.createdAt }
        guard let filter = filterStatus else { return Array(all) }
        return all.filter { $0.status == filter }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Capture bar
            HStack(spacing: 8) {
                Image(systemName: "lightbulb")
                    .foregroundStyle(.yellow)
                TextField("Capture idea... (Return to add)", text: $newIdeaText)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .focused($captureFieldFocused)
                    .onSubmit { addIdea() }
                if !newIdeaText.isEmpty {
                    Button("Add", action: addIdea)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            }
            .padding(12)
            .background(Color.yellow.opacity(0.08))

            Divider()

            // Filter tabs
            HStack(spacing: 0) {
                filterTab("All", status: nil)
                filterTab("Inbox", status: .inbox)
                filterTab("Attached", status: .attached)
                filterTab("Discarded", status: .discarded)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            Divider()

            // Ideas list
            if filteredIdeas.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "tray")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text(filterStatus == nil ? "No ideas yet" : "No \(filterStatus!.label.lowercased()) ideas")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                List {
                    ForEach(filteredIdeas) { idea in
                        IdeaRowView(idea: idea, store: store, showAttachPicker: $showAttachPicker)
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private func filterTab(_ label: String, status: IdeaStatus?) -> some View {
        Button {
            filterStatus = status
        } label: {
            Text(label)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(filterStatus == status ? Color.accentColor : Color.clear,
                            in: Capsule())
                .foregroundStyle(filterStatus == status ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    private func addIdea() {
        let text = newIdeaText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        store.addIdea(text: text)
        newIdeaText = ""
        captureFieldFocused = true
    }
}

struct IdeaRowView: View {
    let idea: Idea
    @Bindable var store: ProjectStore
    @Binding var showAttachPicker: UUID?
    @State private var nodeSearchText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(idea.text)
                    .font(.body)
                Spacer()
                statusBadge
            }

            HStack {
                Text(idea.createdAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !idea.tags.isEmpty {
                    ForEach(idea.tags, id: \.self) { tag in
                        Text(tag)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.15), in: Capsule())
                    }
                }

                Spacer()

                // Actions
                if idea.status == .inbox {
                    Button("Attach") {
                        showAttachPicker = showAttachPicker == idea.id ? nil : idea.id
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)

                    Button("Discard") {
                        store.setIdeaStatus(id: idea.id, status: .discarded)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .foregroundStyle(.red)
                }

                if idea.status == .attached {
                    if let nid = idea.attachedNodeId, let node = store.node(for: nid) {
                        Text("→ \(node.title)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button("Detach") {
                        store.setIdeaStatus(id: idea.id, status: .inbox, attachedNodeId: nil)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }

                if idea.status == .discarded {
                    Button("Restore") {
                        store.setIdeaStatus(id: idea.id, status: .inbox)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
            }

            // Attach picker
            if showAttachPicker == idea.id {
                attachPicker(idea: idea)
            }
        }
        .padding(.vertical, 4)
    }

    private var statusBadge: some View {
        Text(idea.status.label)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(statusColor.opacity(0.15), in: Capsule())
            .foregroundStyle(statusColor)
    }

    private var statusColor: Color {
        switch idea.status {
        case .inbox: return .blue
        case .attached: return .green
        case .discarded: return .secondary
        }
    }

    private func attachPicker(idea: Idea) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("Search node...", text: $nodeSearchText)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
            let nodes = store.state.nodes.values
                .filter { nodeSearchText.isEmpty || $0.title.localizedCaseInsensitiveContains(nodeSearchText) }
                .sorted { $0.title < $1.title }
            ForEach(nodes.prefix(6)) { node in
                Button {
                    store.setIdeaStatus(id: idea.id, status: .attached, attachedNodeId: node.id)
                    showAttachPicker = nil
                    nodeSearchText = ""
                } label: {
                    HStack {
                        Image(systemName: node.type.icon).font(.caption)
                        Text(node.title).font(.caption)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                .padding(.vertical, 1)
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
    }
}
