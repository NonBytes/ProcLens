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
                ProgressView("Sampling network activity…").frame(maxHeight: .infinity)
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
            TableColumn("Name", value: \.name).width(min: 115, ideal: 190)
            TableColumn("PID", value: \.id) { row in
                Text(String(row.id)).monospacedDigit()
            }
            .width(min: 48, ideal: 55)
            TableColumn("Received", value: \.received) { row in
                Text(NetworkCounters.formatBytes(row.received)).monospacedDigit()
            }
            TableColumn("Sent", value: \.sent) { row in
                Text(NetworkCounters.formatBytes(row.sent)).monospacedDigit()
            }
            TableColumn("Received/s", value: \.receiveRate) { row in
                Text(formatRate(row.rate?.received)).monospacedDigit()
            }
            TableColumn("Sent/s", value: \.sendRate) { row in
                Text(formatRate(row.rate?.sent)).monospacedDigit()
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

    private var throughput: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Tracked Process Traffic").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 16) {
                Text("Received \(formatRate(activity.history.last?.received))")
                SparklineView(values: activity.history.map { Double($0.received) }, color: .blue)
                    .frame(maxWidth: 100).frame(height: 16)
                    .accessibilityHidden(true)
                Text("Sent \(formatRate(activity.history.last?.sent))")
                SparklineView(values: activity.history.map { Double($0.sent) }, color: .green)
                    .frame(maxWidth: 100).frame(height: 16)
                    .accessibilityHidden(true)
                Spacer(minLength: 0)
            }
            .font(.callout.monospacedDigit())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func formatRate(_ bytes: UInt64?) -> String {
        bytes.map { "\(NetworkCounters.formatBytes($0))/s" } ?? "—"
    }

}
