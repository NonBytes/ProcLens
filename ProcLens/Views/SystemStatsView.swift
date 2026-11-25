import SwiftUI

struct SystemStatsView: View {
    @Environment(SystemMonitor.self) private var systemMonitor
    @Environment(ProcessManager.self) private var processManager

    var body: some View {
        HStack(spacing: 24) {
            StatGauge(
                title: "CPU",
                value: systemMonitor.stats.cpuUsage,
                detail: String(format: "User %.0f%%  ·  Sys %.0f%%",
                               systemMonitor.stats.userCPU,
                               systemMonitor.stats.systemCPU),
                color: gaugeColor(systemMonitor.stats.cpuUsage)
            )

            Divider()
                .frame(height: 38)

            StatGauge(
                title: "Memory",
                value: systemMonitor.stats.memoryUsagePercent,
                detail: String(format: "%.1f / %.1f GB",
                               systemMonitor.stats.usedMemoryGB,
                               systemMonitor.stats.totalMemoryGB),
                color: gaugeColor(systemMonitor.stats.memoryUsagePercent)
            )

            Divider()
                .frame(height: 38)

            memoryBreakdown

            Spacer()

            VStack(alignment: .trailing, spacing: 1) {
                Text("\(processManager.processes.count)")
                    .font(.system(.title3, design: .rounded))
                    .fontWeight(.bold)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("PROCESSES")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var memoryBreakdown: some View {
        HStack(spacing: 8) {
            MemoryChip(label: "Active", gb: systemMonitor.stats.usedMemoryGB, color: .blue)
            MemoryChip(label: "Wired", gb: systemMonitor.stats.wiredMemoryGB, color: .orange)
            MemoryChip(label: "Compressed", gb: systemMonitor.stats.compressedMemoryGB, color: .purple)
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
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.08), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: min(max(value, 0), 100) / 100)
                    .stroke(
                        AngularGradient(
                            colors: [color.opacity(0.55), color],
                            center: .center,
                            startAngle: .degrees(0),
                            endAngle: .degrees(360 * min(max(value, 0), 100) / 100)
                        ),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.smooth(duration: 0.6), value: value)
                Text(String(format: "%.0f", value))
                    .font(.system(.caption, design: .rounded))
                    .fontWeight(.bold)
                    .monospacedDigit()
                    .foregroundStyle(color)
                    .contentTransition(.numericText())
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(.caption, design: .rounded))
                    .fontWeight(.semibold)
                Text(detail)
                    .font(.caption2)
                    .monospacedDigit()
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
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .foregroundStyle(.secondary)
            Text(String(format: "%.1fG", gb))
                .fontWeight(.medium)
                .foregroundStyle(.primary)
        }
        .font(.caption2)
        .monospacedDigit()
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.primary.opacity(0.05), in: Capsule())
    }
}
