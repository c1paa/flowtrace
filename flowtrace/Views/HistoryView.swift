import SwiftUI

struct HistoryView: View {
    @Bindable var store: ProjectStore
    @State private var showSnapshotPrompt = false
    @State private var snapshotDescription = ""
    @State private var restoreTarget: URL? = nil
    @State private var showRestoreConfirm = false
    @State private var selectedTab = 0
    @State private var snapshots: [(name: String, url: URL)] = []

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("History")
                    .font(.headline)
                Spacer()
                Button {
                    showSnapshotPrompt.toggle()
                } label: {
                    Label("Snapshot", systemImage: "camera")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            // Snapshot prompt
            if showSnapshotPrompt {
                HStack {
                    TextField("Snapshot description...", text: $snapshotDescription)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { createSnapshot() }
                    Button("Save", action: createSnapshot)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    Button("Cancel") {
                        showSnapshotPrompt = false
                        snapshotDescription = ""
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                Divider()
            }

            // Tabs
            Picker("", selection: $selectedTab) {
                Text("Snapshots").tag(0)
                Text("Event Log").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            if selectedTab == 0 {
                snapshotsList
            } else {
                eventLogList
            }
        }
        .onAppear { loadSnapshots() }
        .alert("Restore Snapshot?", isPresented: $showRestoreConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Restore", role: .destructive) {
                if let url = restoreTarget {
                    store.restoreSnapshot(from: url)
                    loadSnapshots()
                }
            }
        } message: {
            Text("This will replace the current project state with the snapshot. This action cannot be undone.")
        }
    }

    // MARK: - Snapshots

    private var snapshotsList: some View {
        Group {
            if snapshots.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "camera")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("No snapshots yet")
                        .foregroundStyle(.secondary)
                    Text("Create a snapshot to save the current project state")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
            } else {
                List {
                    ForEach(snapshots, id: \.url) { snapshot in
                        HStack {
                            Image(systemName: "camera.fill")
                                .foregroundStyle(.blue)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(snapshot.name)
                                    .font(.body)
                                    .lineLimit(1)
                                Text(formattedSnapshotDate(snapshot.name))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Restore") {
                                restoreTarget = snapshot.url
                                showRestoreConfirm = true
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        .padding(.vertical, 2)
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    // MARK: - Event Log

    private var eventLogList: some View {
        Group {
            if store.events.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("No events yet")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                List {
                    ForEach(store.events.reversed(), id: \.id) { event in
                        EventRowView(event: event, store: store)
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    // MARK: - Actions

    private func createSnapshot() {
        let desc = snapshotDescription.trimmingCharacters(in: .whitespaces)
        store.createSnapshot(description: desc.isEmpty ? "manual" : desc)
        showSnapshotPrompt = false
        snapshotDescription = ""
        loadSnapshots()
    }

    private func loadSnapshots() {
        snapshots = PersistenceManager.listSnapshots(dir: store.snapshotsURL)
    }

    private func formattedSnapshotDate(_ name: String) -> String {
        // Name format: 2026-02-23T12-30-00Z_description
        let parts = name.components(separatedBy: "_")
        return parts.first ?? name
    }
}

struct EventRowView: View {
    let event: Event
    @Bindable var store: ProjectStore

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: event.type.icon)
                .font(.system(size: 14))
                .foregroundStyle(eventColor)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.summary)
                    .font(.body)
                    .lineLimit(2)
                HStack {
                    Text(event.timestamp, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let nodeId = event.nodeId, let uuid = UUID(uuidString: nodeId),
                       let node = store.node(for: uuid) {
                        Text("•").foregroundStyle(.secondary).font(.caption)
                        Text(node.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var eventColor: Color {
        switch event.type {
        case .nodeCreated: return .green
        case .nodeDeleted: return .red
        case .statusChanged: return .blue
        case .timerStarted, .timerStopped: return .orange
        case .snapshotCreated: return .purple
        case .ideaAdded, .ideaAttached: return .yellow
        default: return .secondary
        }
    }
}
