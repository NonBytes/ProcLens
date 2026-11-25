import SwiftUI

struct NetworkActivityView: View {
    @Environment(ProcessManager.self) private var processManager
    let searchText: String
    @Binding var selectedPID: Int32?
    let activity: NetworkActivity
    @State private var sortOrder = [KeyPathComparator(\NetworkActivity.Row.received, order: .reverse)]

    private var rows: [NetworkActivity.Row] {
        activity.rows.values.filter { row in
            searchText.isEmpty || row.name.localizedCaseInsensitiveContains(searchText)
                || String(row.id).contains(searchText)
        }
        .sorted(using: sortOrder + [KeyPathComparator(\NetworkActivity.Row.id)])
    }

    var body: some View {
        VStack(spacing: 0) {
            if activity.isLoading {
                ProgressView("Sampling network activity…")
                    .controlSize(.small)
                    .frame(maxHeight: .infinity)
            } else if activity.hasError {
                ContentUnavailableView(
                    "Network Data Unavailable", systemImage: "network.slash",
                    description: Text("Waiting for the next macOS network sample.")
                )
            } else {
                table
                Divider()
                throughput
            }
        }
    }

    private var table: some View {
        Table(rows, selection: $selectedPID, sortOrder: $sortOrder) {
            TableColumn("Name", value: \.name) { row in
                Text(row.name).fontWeight(.medium).lineLimit(1)
            }
            .width(min: 115, ideal: 190)

            TableColumn("PID", value: \.id) { row in
                Text(String(row.id))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .width(min: 48, ideal: 55)

            TableColumn("Received", value: \.received) { row in
                Text(NetworkCounters.formatBytes(row.received))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            TableColumn("Sent", value: \.sent) { row in
                Text(NetworkCounters.formatBytes(row.sent))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            TableColumn("Received/s", value: \.receiveRate) { row in
                rateBadge(row.rate?.received, color: .blue, icon: "arrow.down")
            }

            TableColumn("Sent/s", value: \.sendRate) { row in
                rateBadge(row.rate?.sent, color: .green, icon: "arrow.up")
            }
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .contextMenu(forSelectionType: Int32.self) { pids in
            if let pid = pids.first,
               let process = processManager.processes.first(where: { $0.pid == pid }) {
                ProcessContextMenu(process: process)
            }
        }
        .overlay {
            if rows.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "No Network Activity" : "No Matching Processes",
                    systemImage: "network"
                )
            }
        }
    }

    @ViewBuilder
    private func rateBadge(_ bytes: UInt64?, color: Color, icon: String) -> some View {
        if let bytes {
            Label(formatRate(bytes), systemImage: icon)
                .font(.caption.monospacedDigit())
                .imageScale(.small)
                .foregroundStyle(color)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(color.opacity(0.12), in: Capsule())
        } else {
            Text("—")
                .monospacedDigit()
                .foregroundStyle(.tertiary)
        }
    }

    private var throughput: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TRACKED PROCESS TRAFFIC")
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                throughputCard(
                    title: "Received",
                    value: formatRate(activity.history.last?.received),
                    values: activity.history.map { Double($0.received) },
                    color: .blue,
                    icon: "arrow.down.circle.fill"
                )
                throughputCard(
                    title: "Sent",
                    value: formatRate(activity.history.last?.sent),
                    values: activity.history.map { Double($0.sent) },
                    color: .green,
                    icon: "arrow.up.circle.fill"
                )
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
    }

    private func throughputCard(title: String, value: String, values: [Double], color: Color, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
            }
            .frame(minWidth: 84, alignment: .leading)
            SparklineView(values: values, color: color)
                .frame(width: 90, height: 22)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(color.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(color.opacity(0.15), lineWidth: 1)
        )
    }

    private func formatRate(_ bytes: UInt64?) -> String {
        bytes.map { "\(NetworkCounters.formatBytes($0))/s" } ?? "—"
    }

}
