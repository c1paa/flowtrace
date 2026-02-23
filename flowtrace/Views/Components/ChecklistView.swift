import SwiftUI

struct ChecklistView: View {
    let nodeId: UUID
    @Bindable var store: ProjectStore
    @State private var newItemText = ""
    @FocusState private var isFieldFocused: Bool

    var node: ProjectNode? { store.node(for: nodeId) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let node = node {
                ForEach(node.checklistItems) { item in
                    HStack(spacing: 8) {
                        Button {
                            store.toggleChecklistItem(nodeId: nodeId, itemId: item.id)
                        } label: {
                            Image(systemName: item.isCompleted ? "checkmark.square.fill" : "square")
                                .foregroundStyle(item.isCompleted ? .green : .secondary)
                        }
                        .buttonStyle(.plain)

                        Text(item.text)
                            .strikethrough(item.isCompleted)
                            .foregroundStyle(item.isCompleted ? .secondary : .primary)
                            .font(.body)

                        Spacer()

                        Button {
                            store.deleteChecklistItem(nodeId: nodeId, itemId: item.id)
                        } label: {
                            Image(systemName: "trash")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .opacity(0.6)
                    }
                    .padding(.vertical, 4)
                    Divider()
                }
            }

            // Add new item
            HStack(spacing: 8) {
                Image(systemName: "plus.circle")
                    .foregroundStyle(.secondary)
                TextField("Add item...", text: $newItemText)
                    .textFieldStyle(.plain)
                    .focused($isFieldFocused)
                    .onSubmit { addItem() }
                if !newItemText.isEmpty {
                    Button("Add", action: addItem)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.mini)
                }
            }
            .padding(.vertical, 6)
        }
    }

    private func addItem() {
        let text = newItemText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        store.addChecklistItem(nodeId: nodeId, text: text)
        newItemText = ""
        isFieldFocused = true
    }
}
