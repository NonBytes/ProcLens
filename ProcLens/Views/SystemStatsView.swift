import SwiftUI

struct SystemStatsView: View {
    @Environment(SystemMonitor.self) private var systemMonitor
    @Environment(ProcessManager.self) private var processManager

    var body: some View {
        HStack(spacing: 24) {
            StatGauge(
                title: "CPU",
                value: systemMonitor.stats.cpuUsage,
                detail: String(format: "User %.0f%%  Sys %.0f%%",
                               systemMonitor.stats.userCPU,
                               systemMonitor.stats.systemCPU),
                color: gaugeColor(systemMonitor.stats.cpuUsage)
            )

            Divider()
                .frame(height: 36)

            StatGauge(
                title: "Memory",
                value: systemMonitor.stats.memoryUsagePercent,
                detail: String(format: "%.1f / %.1f GB",
                               systemMonitor.stats.usedMemoryGB,
                               systemMonitor.stats.totalMemoryGB),
                color: gaugeColor(systemMonitor.stats.memoryUsagePercent)
            )

            Divider()
                .frame(height: 36)

            memoryBreakdown

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(processManager.processes.count)")
                    .font(.title2)
                    .fontWeight(.bold)
                    .monospacedDigit()
                Text("Processes")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var memoryBreakdown: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                MemoryChip(label: "Active", gb: systemMonitor.stats.usedMemoryGB, color: .blue)
                MemoryChip(label: "Wired", gb: systemMonitor.stats.wiredMemoryGB, color: .orange)
                MemoryChip(label: "Compressed", gb: systemMonitor.stats.compressedMemoryGB, color: .purple)
            }
        }
    }

    private func gaugeColor(_ value: Double) -> Color {
        if value > 80 { return .red }
        if value > 60 { return .orange }
        return .green
    }
}

// MARK: - Stat Gauge

struct StatGauge: View {
    let title: String
    let value: Double
    let detail: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.2), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: min(max(value, 0), 100) / 100)
                    .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(String(format: "%.0f%%", value))
                    .font(.system(.caption2, design: .monospaced))
                    .fontWeight(.bold)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Memory Chip

struct MemoryChip: View {
    let label: String
    let gb: Double
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text("\(label): \(String(format: "%.1f", gb))G")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
