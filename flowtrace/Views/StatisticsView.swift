import SwiftUI
import Charts

private struct EstimationPoint: Identifiable {
    let id: UUID
    let title: String
    let estimate: Double
    let actual: Double
    let ratio: Double
    let complexity: Int
    let category: String
}

struct StatisticsView: View {
    @Bindable var store: ProjectStore
    @State private var points: [EstimationPoint] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Estimation Statistics")
                    .font(.title2.bold())
                    .padding(.horizontal, 16)
                    .padding(.top, 16)

                if points.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "chart.bar")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("No completed tasks with time data yet")
                            .foregroundStyle(.secondary)
                        Text("Complete tasks that have both estimates and tracked time to see accuracy stats.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                } else {
                    overallCard
                    complexityChart
                    categoryChart
                    scatterChart
                    detailTable
                }
            }
            .padding(.bottom, 32)
        }
        .onAppear { buildPoints() }
        .onChange(of: store.state.updatedAt) { buildPoints() }
    }

    // MARK: - Overall

    private var overallCard: some View {
        let avg = points.isEmpty ? 1.0 : points.map { $0.ratio }.reduce(0, +) / Double(points.count)
        let accurate = points.filter { $0.ratio >= 0.8 && $0.ratio <= 1.2 }.count

        return HStack(spacing: 16) {
            statTile(title: "Avg. Ratio", value: String(format: "%.2fx", avg),
                     subtitle: avg < 1 ? "Under estimates" : "Over estimates",
                     color: avg > 1.3 ? .red : (avg < 0.7 ? .orange : .green))
            statTile(title: "Accuracy Rate", value: "\(accurate)/\(points.count)",
                     subtitle: "within ±20%",
                     color: .blue)
            statTile(title: "Total Tasks", value: "\(points.count)",
                     subtitle: "completed with data",
                     color: .purple)
        }
        .padding(.horizontal, 16)
    }

    private func statTile(title: String, value: String, subtitle: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.bold()).foregroundStyle(color)
            Text(subtitle).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Charts

    private var complexityChart: some View {
        let grouped = Dictionary(grouping: points) { $0.complexity }
        let data = grouped.map { (key, vals) -> (Int, Double) in
            let avg = vals.map { $0.ratio }.reduce(0, +) / Double(vals.count)
            return (key, avg)
        }.sorted { $0.0 < $1.0 }

        return VStack(alignment: .leading, spacing: 8) {
            Text("Accuracy by Complexity")
                .font(.headline)
                .padding(.horizontal, 16)

            Chart {
                ForEach(data, id: \.0) { item in
                    BarMark(
                        x: .value("Complexity", "Level \(item.0)"),
                        y: .value("Avg Ratio", item.1)
                    )
                    .foregroundStyle(item.1 > 1.2 ? Color.red : .blue)
                    .annotation(position: .top) {
                        Text(String(format: "%.2fx", item.1))
                            .font(.caption2)
                    }
                }
                RuleMark(y: .value("Perfect", 1.0))
                    .lineStyle(StrokeStyle(dash: [4, 2]))
                    .foregroundStyle(.green.opacity(0.6))
            }
            .frame(height: 200)
            .padding(.horizontal, 16)
        }
    }

    private var categoryChart: some View {
        let grouped = Dictionary(grouping: points.filter { !$0.category.isEmpty }) { $0.category }
        let data = grouped.map { (key, vals) -> (String, Double) in
            let avg = vals.map { $0.ratio }.reduce(0, +) / Double(vals.count)
            return (key, avg)
        }.sorted { $0.1 > $1.1 }

        return VStack(alignment: .leading, spacing: 8) {
            Text("Accuracy by Category")
                .font(.headline)
                .padding(.horizontal, 16)

            if data.isEmpty {
                Text("No categorized tasks")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
            } else {
                Chart {
                    ForEach(data, id: \.0) { item in
                        BarMark(
                            x: .value("Category", item.0),
                            y: .value("Avg Ratio", item.1)
                        )
                        .foregroundStyle(item.1 > 1.2 ? Color.red : .purple)
                    }
                    RuleMark(y: .value("Perfect", 1.0))
                        .lineStyle(StrokeStyle(dash: [4, 2]))
                        .foregroundStyle(.green.opacity(0.6))
                }
                .frame(height: 200)
                .padding(.horizontal, 16)
            }
        }
    }

    private var scatterChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Estimate vs. Actual")
                .font(.headline)
                .padding(.horizontal, 16)

            Chart {
                ForEach(points) { p in
                    PointMark(
                        x: .value("Estimate", p.estimate),
                        y: .value("Actual", p.actual)
                    )
                    .foregroundStyle(p.ratio > 1.2 ? Color.red : Color.blue)
                    .symbolSize(60)
                }
            }
            .chartXAxisLabel("Estimated (h)")
            .chartYAxisLabel("Actual (h)")
            .frame(height: 240)
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Table

    private var detailTable: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Task Breakdown")
                .font(.headline)
                .padding(.horizontal, 16)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                // Header
                GridRow {
                    Text("Task").font(.caption.bold()).foregroundStyle(.secondary)
                    Text("Est").font(.caption.bold()).foregroundStyle(.secondary)
                    Text("Actual").font(.caption.bold()).foregroundStyle(.secondary)
                    Text("Ratio").font(.caption.bold()).foregroundStyle(.secondary)
                }
                Divider()
                ForEach(points) { p in
                    GridRow {
                        Text(p.title).font(.caption).lineLimit(1)
                        Text(String(format: "%.1fh", p.estimate)).font(.caption.monospaced())
                        Text(String(format: "%.1fh", p.actual)).font(.caption.monospaced())
                        Text(String(format: "%.2fx", p.ratio))
                            .font(.caption.monospaced())
                            .foregroundStyle(p.ratio > 1.3 ? .red : (p.ratio < 0.7 ? .orange : .green))
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Data

    private func buildPoints() {
        points = store.state.nodes.values
            .filter { node in
                node.status == .done &&
                node.timeActual > 0 &&
                (node.timeEstimate ?? 0) > 0
            }
            .map { node in
                let est = node.timeEstimate ?? 1
                let ratio = node.timeActual / est
                return EstimationPoint(
                    id: node.id,
                    title: node.title,
                    estimate: est,
                    actual: node.timeActual,
                    ratio: ratio,
                    complexity: node.complexity ?? 0,
                    category: node.category ?? ""
                )
            }
            .sorted { $0.ratio > $1.ratio }
    }
}
