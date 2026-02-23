import SwiftUI

struct NodeCardView: View {
    let node: ProjectNode
    let color: Color
    let isSelected: Bool
    let isHighlighted: Bool
    let isDimmed: Bool
    let isTimerActive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Top row: color dot + title + type icon
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 10, height: 10)
                Text(node.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: node.type.icon)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                if isTimerActive {
                    Image(systemName: "timer")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                }
            }

            // Meta row
            HStack(spacing: 10) {
                if let est = node.timeEstimate {
                    Label(String(format: "%.1fh", est), systemImage: "clock")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                if let comp = node.complexity {
                    HStack(spacing: 2) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 9))
                        Text("\(comp)")
                            .font(.system(size: 10))
                    }
                    .foregroundStyle(.secondary)
                }
                Spacer()
                // Status icon
                Image(systemName: node.status.icon)
                    .font(.system(size: 11))
                    .foregroundStyle(statusColor)
            }

            // Checklist progress
            if !node.checklistItems.isEmpty {
                let completed = node.checklistItems.filter { $0.isCompleted }.count
                let total = node.checklistItems.count
                HStack(spacing: 6) {
                    ProgressView(value: Double(completed), total: Double(total))
                        .progressViewStyle(.linear)
                        .frame(height: 4)
                    Text("\(completed)/\(total)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .frame(width: 200)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: isSelected ? color.opacity(0.4) : .black.opacity(0.12),
                        radius: isSelected ? 6 : 3,
                        x: 0, y: isSelected ? 3 : 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? color : (isHighlighted ? color.opacity(0.5) : Color.clear),
                        lineWidth: isSelected ? 2 : 1)
        )
        .opacity(isDimmed ? 0.3 : (node.status == .done ? 0.6 : 1.0))
    }

    private var statusColor: Color {
        switch node.status {
        case .todo: return .secondary
        case .doing: return .orange
        case .done: return .green
        }
    }
}
