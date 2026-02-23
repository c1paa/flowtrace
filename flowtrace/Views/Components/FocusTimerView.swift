import SwiftUI
import Combine

struct FocusTimerView: View {
    let nodeId: UUID
    @Bindable var store: ProjectStore
    @State private var showManualEntry = false
    @State private var manualHours = ""
    @State private var tick = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var isActive: Bool { store.activeTimerNodeId == nodeId }
    var node: ProjectNode? { store.node(for: nodeId) }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Focus Timer")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(formattedElapsed)
                        .font(.system(size: 28, weight: .medium, design: .monospaced))
                        .foregroundStyle(isActive ? .orange : .primary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("Total logged")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.2fh", node?.timeActual ?? 0))
                        .font(.headline)
                }
            }

            HStack(spacing: 8) {
                Button {
                    if isActive {
                        store.stopTimer()
                    } else {
                        store.startTimer(nodeId: nodeId)
                    }
                } label: {
                    Label(isActive ? "Stop" : "Start",
                          systemImage: isActive ? "stop.circle.fill" : "play.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(isActive ? .red : .green)

                Button {
                    showManualEntry.toggle()
                } label: {
                    Image(systemName: "clock.badge.plus")
                }
                .buttonStyle(.bordered)
                .help("Set time manually")
            }

            if showManualEntry {
                HStack {
                    TextField("Hours (e.g. 1.5)", text: $manualHours)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { applyManual() }
                    Button("Set", action: applyManual)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    Button("Cancel") { showManualEntry = false }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
        }
        .onReceive(timer) { date in
            if isActive { tick = date }
        }
    }

    private var formattedElapsed: String {
        _ = tick // trigger update
        let totalSeconds: Int
        if isActive, let start = store.timerStartTime {
            totalSeconds = Int(Date().timeIntervalSince(start))
        } else {
            totalSeconds = 0
        }
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }

    private func applyManual() {
        guard let hours = Double(manualHours) else { return }
        store.setTimeManual(nodeId: nodeId, hours: hours)
        manualHours = ""
        showManualEntry = false
    }
}
