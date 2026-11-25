import SwiftUI

struct ProcessListView: View {
    @Environment(ProcessManager.self) private var processManager
    @Binding var selectedPID: Int32?
    @Binding var searchText: String
    @Binding var sortOrder: [KeyPathComparator<ProcessItem>]
    let networkActivity: NetworkActivity
    let showSubprocesses: (ProcessItem) -> Void

    @AppStorage("ProcLens.ListColumnCustomization") private var columnCustomization = TableColumnCustomization<ProcessItem>()

    @State private var projection = ProcessListProjection()

    private var displayProcesses: [ProcessItem] {
        projection.rows(
            processRevision: processManager.revision,
            networkRevision: networkActivity.revision,
            searchText: searchText, sortOrder: sortOrder
        ) {
            makeDisplayProcesses()
        }
    }

    private func makeDisplayProcesses() -> [ProcessItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let base: [ProcessItem]
        if query.isEmpty {
            base = processManager.processes
        } else {
            let cleanQuery = query.hasPrefix(":") ? String(query.dropFirst()) : query
            base = processManager.processes.filter { p in
                p.name.localizedCaseInsensitiveContains(query)
                    || String(p.pid).contains(query)
                    || p.user.localizedCaseInsensitiveContains(query)
                    || p.path.localizedCaseInsensitiveContains(query)
                    || p.ports.contains { $0.contains(cleanQuery) }
                    || p.archShortName.localizedCaseInsensitiveContains(query)
                    || p.signatureBadgeText.localizedCaseInsensitiveContains(query)
            }
        }
        return networkActivity.addingCounters(to: base).sorted(using: sortOrder)
    }

    @TableColumnBuilder<ProcessItem, KeyPathComparator<ProcessItem>>
    private var primaryColumns: some TableColumnContent<ProcessItem, KeyPathComparator<ProcessItem>> {
        column(for: .pid)
        column(for: .name)
        column(for: .cpu)
        column(for: .memory)
        column(for: .received)
        column(for: .sent)
        column(for: .user)
        column(for: .threads)
    }

    @TableColumnBuilder<ProcessItem, KeyPathComparator<ProcessItem>>
    private var secondaryColumns: some TableColumnContent<ProcessItem, KeyPathComparator<ProcessItem>> {
        column(for: .status)
        column(for: .ports)
        column(for: .arch)
        column(for: .diskRead)
        column(for: .diskWrite)
        column(for: .uptime)
        column(for: .signature)
        column(for: .ppid)
    }

    private func column(for col: ProcessColumn) -> some TableColumnContent<ProcessItem, KeyPathComparator<ProcessItem>> {
        baseColumn(for: col)
            .customizationID(col.rawValue)
            .defaultVisibility(ColumnSettings.defaultColumns.contains(col) ? .visible : .hidden)
    }

    private func baseColumn(for col: ProcessColumn) -> TableColumn<ProcessItem, KeyPathComparator<ProcessItem>, AnyView, Text> {
        switch col {
        case .pid:
            TableColumn("PID", value: \.pid) { p in
                AnyView(
                    Text("\(p.pid)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                )
            }
            .width(min: 50, ideal: 65, max: 80)
        case .name:
            TableColumn("Name", value: \.name) { p in
                AnyView(
                    HStack(spacing: 6) {
                        Image(nsImage: IconProvider.shared.appIcon(for: p))
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 16, height: 16)
                            .help(iconTooltip(for: p))
                        Text(p.name).fontWeight(.medium).lineLimit(1)
                    }
                )
            }
            .width(min: 120, ideal: 200)
        case .cpu:
            TableColumn("CPU %", value: \.cpuUsage) { p in
                AnyView(
                    HStack(spacing: 6) {
                        if processManager.historyTracker.hasMeaningfulCPU(for: p.pid) {
                            SparklineView(
                                values: processManager.historyTracker.cpuHistory(for: p.pid),
                                color: cpuColor(p.cpuUsage)
                            )
                            .frame(width: 40, height: 14)
                        }
                        Text(p.formattedCPU)
                            .monospacedDigit()
                            .fontWeight(.medium)
                            .foregroundStyle(cpuColor(p.cpuUsage))
                    }
                )
            }
            .width(min: 100, ideal: 130, max: 160)
        case .memory:
            TableColumn("Memory", value: \.memoryUsage) { p in
                AnyView(
                    Text(p.formattedMemory)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                )
            }
            .width(min: 70, ideal: 90, max: 110)
        case .ports:
            TableColumn("Ports", value: \.portsSortKey) { p in
                AnyView(
                    Group {
                        if p.ports.isEmpty {
                            Text("—")
                                .foregroundStyle(.tertiary)
                        } else {
                            Text(p.formattedPorts)
                                .font(.system(.caption, design: .monospaced))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                                .foregroundStyle(.blue)
                                .help("Listening ports: \(p.formattedPorts)")
                        }
                    }
                )
            }
            .width(min: 70, ideal: 95)
        case .arch:
            TableColumn("Arch", value: \.archShortName) { p in
                AnyView(
                    Group {
                        if p.architecture == .unavailable {
                            Text("—").foregroundStyle(.tertiary)
                        } else {
                            Text(p.archShortName)
                                .font(.system(.caption2, design: .monospaced).weight(.semibold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(p.archBadgeColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                                .foregroundStyle(p.archBadgeColor)
                        }
                    }
                )
            }
            .width(min: 65, ideal: 75)
        case .diskRead:
            TableColumn("Disk Read", value: \.diskReadBytes) { p in
                AnyView(
                    Text(p.formattedDiskRead)
                        .monospacedDigit()
                        .foregroundStyle(p.diskReadBytes == 0 ? .tertiary : .secondary)
                )
            }
            .width(min: 75, ideal: 85)
        case .diskWrite:
            TableColumn("Disk Write", value: \.diskWriteBytes) { p in
                AnyView(
                    Text(p.formattedDiskWrite)
                        .monospacedDigit()
                        .foregroundStyle(p.diskWriteBytes == 0 ? .tertiary : .secondary)
                )
            }
            .width(min: 75, ideal: 85)
        case .uptime:
            TableColumn("Uptime", value: \.uptimeSeconds) { p in
                AnyView(
                    Text(p.formattedUptime)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                )
            }
            .width(min: 65, ideal: 80)
        case .received:
            TableColumn("Received", value: \.networkBytesReceived) { process in
                AnyView(
                    Text(process.networkCounters.map { NetworkCounters.formatBytes($0.received) } ?? "—")
                        .monospacedDigit()
                        .foregroundStyle(process.networkCounters == nil ? .tertiary : .secondary)
                )
            }
            .width(min: 75, ideal: 90)
        case .sent:
            TableColumn("Sent", value: \.networkBytesSent) { process in
                AnyView(
                    Text(process.networkCounters.map { NetworkCounters.formatBytes($0.sent) } ?? "—")
                        .monospacedDigit()
                        .foregroundStyle(process.networkCounters == nil ? .tertiary : .secondary)
                )
            }
            .width(min: 65, ideal: 80)
        case .user:
            TableColumn("User", value: \.user) { p in
                AnyView(
                    Text(p.user)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                )
            }
            .width(min: 60, ideal: 80, max: 120)
        case .threads:
            TableColumn("Threads", value: \.threadCount) { p in
                AnyView(
                    Text("\(p.threadCount)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                )
            }
            .width(min: 55, ideal: 65, max: 80)
        case .status:
            TableColumn("Status", value: \.status) { p in
                AnyView(StatusBadge(status: p.status))
            }
            .width(min: 70, ideal: 84, max: 100)
        case .signature:
            TableColumn("Signature", value: \.signatureBadgeText) { p in
                AnyView(
                    Text(p.signatureBadgeText)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(p.signatureBadgeColor)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(p.signatureBadgeColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                )
            }
            .width(min: 80, ideal: 100)
        case .ppid:
            TableColumn("PPID", value: \.parentPid) { p in
                AnyView(
                    Text("\(p.parentPid)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                )
            }
            .width(min: 50, ideal: 60)
        }
    }

    var body: some View {
        Table(displayProcesses, selection: $selectedPID, sortOrder: $sortOrder, columnCustomization: $columnCustomization) {
            primaryColumns
            secondaryColumns
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .contextMenu(forSelectionType: Int32.self) { pids in
            if let pid = pids.first,
               let process = processManager.processes.first(where: { $0.pid == pid }) {
                ProcessContextMenu(process: process)
            }
        } primaryAction: { pids in
            if let pid = pids.first,
               let process = processManager.processes.first(where: { $0.pid == pid }) {
                showSubprocesses(process)
            }
        }
    }

    private func iconTooltip(for p: ProcessItem) -> String {
        if p.user == "root" { return "System process (root)" }
        if p.user == "_windowserver" { return "Window Server (system)" }
        if p.user.hasPrefix("_") { return "System service (\(p.user))" }
        if p.name.hasSuffix("daemon") { return "Daemon — \(p.user)" }
        if p.name.hasSuffix("d") && !p.name.contains(" ") { return "Background service — \(p.user)" }
        if p.status == .zombie { return "Zombie process" }
        return "User process — \(p.user)"
    }

    private func cpuColor(_ usage: Double) -> Color {
        if usage > 80 { return .red }
        if usage > 50 { return .orange }
        if usage > 10 { return .yellow }
        return .primary
    }
}

struct MiniBar: View {
    let value: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2).fill(color.opacity(0.2))
                RoundedRectangle(cornerRadius: 2).fill(color)
                    .frame(width: max(0, geo.size.width * value))
            }
        }
    }
}

// MARK: - Status Badge

struct StatusBadge: View {
    let status: ProcessStatus

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(status.color)
                .frame(width: 5, height: 5)
            Text(status.displayName)
                .lineLimit(1)
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(status.color)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(status.color.opacity(0.12), in: Capsule())
    }
}


struct ProcessContextMenu: View {
    let process: ProcessItem
    @Environment(ProcessManager.self) private var processManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Show Subprocesses") { openWindow(value: SubprocessTarget(pid: process.pid, name: process.name)) }
        Divider()
        Button("Copy PID") { copyText("\(process.pid)") }
        Button("Copy Name") { copyText(process.name) }
        if !process.path.isEmpty {
            Button("Copy Path") { copyText(process.path) }
            Button("Reveal in Finder") {
                NSWorkspace.shared.selectFile(process.path, inFileViewerRootedAtPath: "")
            }
        }
        Divider()
        if process.status == .stopped {
            Button("Resume (SIGCONT)") { _ = processManager.resumeProcess(process.pid) }
        } else {
            Button("Suspend (SIGSTOP)") { _ = processManager.suspendProcess(process.pid) }
        }
        Button("Terminate (SIGTERM)") { _ = processManager.killProcess(process.pid) }
        Button("Force Kill (SIGKILL)") { _ = processManager.killProcess(process.pid, force: true) }
    }

    private func copyText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

// The key deliberately excludes selection and column layout: neither changes rows.
// Store only the latest projection so repeated UI updates do not sort the full list.
final class ProcessListProjection {
    private struct Key: Equatable {
        let processRevision: UInt64
        let networkRevision: UInt64
        let searchText: String
        let sortOrder: [KeyPathComparator<ProcessItem>]
    }
    private var key: Key?
    private var cachedRows: [ProcessItem] = []

    func rows(
        processRevision: UInt64, networkRevision: UInt64,
        searchText: String, sortOrder: [KeyPathComparator<ProcessItem>],
        build: () -> [ProcessItem]
    ) -> [ProcessItem] {
        let nextKey = Key(processRevision: processRevision, networkRevision: networkRevision,
                          searchText: searchText, sortOrder: sortOrder)
        if key != nextKey {
            cachedRows = build()
            key = nextKey
        }
        return cachedRows
    }
}
