import SwiftUI

struct NodeDetailView: View {
    let nodeId: UUID
    @Bindable var store: ProjectStore
    @State private var showColorPicker = false
    @State private var selectedColor = Color.blue
    @State private var depSearchText = ""
    @State private var showDepPicker = false
    @State private var estimateHoursInput: Int = 0
    @State private var estimateMinutesInput: Int = 0

    var node: ProjectNode? { store.node(for: nodeId) }

    var body: some View {
        if let node = node {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerSection(node)
                    Divider()
                    descriptionSection(node)
                    Divider()
                    timeSection(node)
                    Divider()
                    complexitySection(node)
                    Divider()
                    checklistSection(node)
                    Divider()
                    dependenciesSection(node)
                    Divider()
                    ideasSection(node)
                    Divider()
                    metaSection(node)
                }
                .padding(16)
            }
            .onAppear { loadEstimate(node) }
            .onChange(of: nodeId) { if let n = store.node(for: nodeId) { loadEstimate(n) } }
        } else {
            VStack {
                Spacer()
                Text("No node selected")
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }

    // MARK: - Header

    private func headerSection(_ node: ProjectNode) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                // Type badge
                Label(node.type.label, systemImage: node.type.icon)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(store.resolvedColor(for: nodeId).opacity(0.15),
                                in: Capsule())
                    .foregroundStyle(store.resolvedColor(for: nodeId))

                Spacer()

                // Color picker
                Button {
                    selectedColor = store.resolvedColor(for: nodeId)
                    showColorPicker.toggle()
                } label: {
                    Circle()
                        .fill(store.resolvedColor(for: nodeId))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showColorPicker) {
                    colorPickerPopover
                }
            }

            // Editable title
            TextField("Title", text: Binding(
                get: { node.title },
                set: { newTitle in store.updateNode(id: nodeId) { $0.title = newTitle } }
            ))
            .font(.title2.bold())
            .textFieldStyle(.plain)

            // Status picker
            Picker("Status", selection: Binding(
                get: { node.status },
                set: { store.setStatus(nodeId: nodeId, status: $0) }
            )) {
                ForEach(NodeStatus.allCases, id: \.self) { s in
                    Label(s.label, systemImage: s.icon).tag(s)
                }
            }
            .pickerStyle(.segmented)

            // Change 4: Output milestone display for group nodes
            if node.type == .group, let milestoneId = node.outputMilestoneId,
               let milestone = store.node(for: milestoneId) {
                HStack(spacing: 6) {
                    Image(systemName: "diamond.fill")
                        .font(.caption)
                        .foregroundStyle(.purple)
                    Text("Output Milestone:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(milestone.title)
                        .font(.caption.bold())
                }
            }
        }
    }

    private var colorPickerPopover: some View {
        VStack(spacing: 12) {
            Text("Choose Color")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Color presets in a scrollable grid
            let presets: [Color] = [
                .red, .orange, .yellow, .green, .mint, .teal,
                .cyan, .blue, .indigo, .purple, .pink, .brown,
                Color(red: 1, green: 0.42, blue: 0.42),   // coral
                Color(red: 0.31, green: 0.78, blue: 0.47), // emerald
                Color(red: 0.27, green: 0.71, blue: 0.82), // sky
                Color(red: 0.59, green: 0.80, blue: 0.71), // sage
                Color(red: 1, green: 0.91, blue: 0.42),    // lemon
                Color(red: 0.87, green: 0.63, blue: 0.87), // lavender
                Color(red: 1, green: 0.6, blue: 0.8),      // rose
                .gray
            ]
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 6), count: 8), spacing: 6) {
                    ForEach(0..<presets.count, id: \.self) { i in
                        Circle()
                            .fill(presets[i])
                            .frame(width: 30, height: 30)
                            .overlay(
                                Circle().stroke(
                                    store.resolvedColor(for: nodeId) == presets[i]
                                        ? Color.primary : Color.primary.opacity(0.15),
                                    lineWidth: 1.5)
                            )
                            .onTapGesture {
                                store.updateNode(id: nodeId) { $0.colorHex = presets[i].hexString }
                                showColorPicker = false
                            }
                    }
                }
                .padding(2)
            }
            .frame(height: 82)

            Divider()
            ColorPicker("Custom", selection: $selectedColor, supportsOpacity: false)
                .labelsHidden()
                .overlay(
                    HStack {
                        Text("Custom Color")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .allowsHitTesting(false)
                    .padding(.leading, 4)
                )
            HStack {
                Button("Reset") {
                    store.updateNode(id: nodeId) { $0.colorHex = nil }
                    showColorPicker = false
                }
                Spacer()
                Button("Apply") {
                    store.updateNode(id: nodeId) { $0.colorHex = selectedColor.hexString }
                    showColorPicker = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(width: 296)
    }

    // MARK: - Description

    private func descriptionSection(_ node: ProjectNode) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Description", systemImage: "doc.text")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            TextEditor(text: Binding(
                get: { node.description },
                set: { newDesc in store.updateNode(id: nodeId) { $0.description = newDesc } }
            ))
            .font(.body)
            .frame(minHeight: 80)
            .scrollContentBackground(.hidden)
            .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
            .padding(2)
        }
    }

    // MARK: - Time

    private func timeSection(_ node: ProjectNode) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Time", systemImage: "clock")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Estimate").font(.caption).foregroundStyle(.secondary)
                    if node.type == .group {
                        if let sum = store.effectiveTimeEstimate(for: nodeId) {
                            HStack(spacing: 4) {
                                Text(String(format: "%.1fh", sum))
                                    .font(.headline)
                                Text("(sum)")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        } else {
                            Text("—")
                                .foregroundStyle(.tertiary)
                        }
                    } else {
                        HStack(spacing: 4) {
                            TextField("0", value: $estimateHoursInput, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 50)
                            Text("h")
                            TextField("0", value: $estimateMinutesInput, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 44)
                            Text("m")
                        }
                        .onChange(of: estimateHoursInput) { updateEstimate() }
                        .onChange(of: estimateMinutesInput) { updateEstimate() }
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("Actual").font(.caption).foregroundStyle(.secondary)
                    Text(String(format: "%.2fh", node.timeActual))
                        .font(.headline)
                    let effectiveEst: Double? = node.type == .group
                        ? store.effectiveTimeEstimate(for: nodeId)
                        : node.timeEstimate
                    if let est = effectiveEst, est > 0 {
                        let ratio = node.timeActual / est
                        Text(String(format: "%.0f%% of est.", ratio * 100))
                            .font(.caption2)
                            .foregroundStyle(ratio > 1.2 ? .red : .secondary)
                    }
                }
            }

            FocusTimerView(nodeId: nodeId, store: store)
                .padding(10)
                .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func loadEstimate(_ node: ProjectNode) {
        let h = node.timeEstimate ?? 0
        estimateHoursInput = Int(h)
        estimateMinutesInput = Int(((h - floor(h)) * 60).rounded())
    }

    private func updateEstimate() {
        let mins = max(0, min(59, estimateMinutesInput))
        let total = Double(estimateHoursInput) + Double(mins) / 60.0
        store.updateNode(id: nodeId) { $0.timeEstimate = total > 0 ? total : nil }
    }

    // MARK: - Complexity

    private func complexitySection(_ node: ProjectNode) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Complexity", systemImage: "bolt.fill")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(1...5, id: \.self) { level in
                    Button {
                        store.updateNode(id: nodeId) {
                            $0.complexity = $0.complexity == level ? nil : level
                        }
                    } label: {
                        Image(systemName: level <= (node.complexity ?? 0) ? "bolt.fill" : "bolt")
                            .foregroundStyle(level <= (node.complexity ?? 0) ? .orange : .secondary)
                            .font(.title2)
                    }
                    .buttonStyle(.plain)
                }
                if let c = node.complexity {
                    Text("Level \(c)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }

    // MARK: - Checklist

    private func checklistSection(_ node: ProjectNode) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Checklist", systemImage: "checklist")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                if !node.checklistItems.isEmpty {
                    let done = node.checklistItems.filter { $0.isCompleted }.count
                    Text("\(done)/\(node.checklistItems.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            ChecklistView(nodeId: nodeId, store: store)
        }
    }

    // MARK: - Dependencies (In / Out)

    private func dependenciesSection(_ node: ProjectNode) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // --- Predecessors (In) ---
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("Predecessors (In)", systemImage: "arrow.triangle.branch")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        showDepPicker.toggle()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                }

                if node.dependencyIds.isEmpty {
                    Text("No prerequisites")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach(node.dependencyIds, id: \.self) { depId in
                        if let depNode = store.node(for: depId) {
                            HStack {
                                Image(systemName: depNode.status.icon)
                                    .foregroundStyle(depNode.status == .done ? .green : .secondary)
                                    .font(.caption)
                                Text(depNode.title)
                                    .font(.body)
                                Spacer()
                                Button {
                                    store.removeDependency(nodeId: nodeId, depId: depId)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.caption)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                if showDepPicker {
                    depPickerView(currentNode: node)
                }
            }

            // --- Dependents (Out) ---
            let outNodes = store.dependents(of: nodeId)
            if !outNodes.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Dependents (Out)", systemImage: "arrow.forward.circle")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    ForEach(Array(outNodes), id: \.self) { depId in
                        if let depNode = store.node(for: depId) {
                            HStack {
                                Image(systemName: depNode.status.icon)
                                    .foregroundStyle(depNode.status == .done ? .green : .secondary)
                                    .font(.caption)
                                Text(depNode.title)
                                    .font(.body)
                                Spacer()
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
        }
    }

    private func depPickerView(currentNode: ProjectNode) -> some View {
        let candidates = store.state.nodes.values
            .filter { $0.id != nodeId && !currentNode.dependencyIds.contains($0.id) }
            .sorted { $0.title < $1.title }

        return VStack(alignment: .leading, spacing: 4) {
            TextField("Search nodes...", text: $depSearchText)
                .textFieldStyle(.roundedBorder)
                .font(.caption)

            let filtered = candidates.filter {
                depSearchText.isEmpty || $0.title.localizedCaseInsensitiveContains(depSearchText)
            }

            ForEach(filtered.prefix(8)) { candidate in
                Button {
                    store.addDependency(nodeId: nodeId, dependsOn: candidate.id)
                    showDepPicker = false
                    depSearchText = ""
                } label: {
                    HStack {
                        Image(systemName: candidate.type.icon).font(.caption)
                        Text(candidate.title).font(.caption)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                .padding(.vertical, 2)
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Ideas

    private func ideasSection(_ node: ProjectNode) -> some View {
        let attachedIdeas = store.state.ideas.values
            .filter { $0.attachedNodeId == nodeId }
            .sorted { $0.createdAt > $1.createdAt }

        return VStack(alignment: .leading, spacing: 6) {
            Label("Attached Ideas", systemImage: "lightbulb")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            if attachedIdeas.isEmpty {
                Text("No ideas attached")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(attachedIdeas) { idea in
                    HStack {
                        Text(idea.text).font(.body)
                        Spacer()
                        Button {
                            store.setIdeaStatus(id: idea.id, status: .inbox, attachedNodeId: nil)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    // MARK: - Meta

    private func metaSection(_ node: ProjectNode) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Category & Notes", systemImage: "tag")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            TextField("Category", text: Binding(
                get: { node.category ?? "" },
                set: { newCat in store.updateNode(id: nodeId) { $0.category = newCat.isEmpty ? nil : newCat } }
            ))
            .textFieldStyle(.roundedBorder)

            TextEditor(text: Binding(
                get: { node.notes },
                set: { newNotes in store.updateNode(id: nodeId) { $0.notes = newNotes } }
            ))
            .font(.body)
            .frame(minHeight: 60)
            .scrollContentBackground(.hidden)
            .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))

            // Dates
            HStack {
                VStack(alignment: .leading) {
                    Text("Created").font(.caption2).foregroundStyle(.secondary)
                    Text(node.createdAt, style: .date).font(.caption)
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text("Updated").font(.caption2).foregroundStyle(.secondary)
                    Text(node.updatedAt, style: .relative).font(.caption)
                }
            }
            .foregroundStyle(.secondary)
        }
    }
}
