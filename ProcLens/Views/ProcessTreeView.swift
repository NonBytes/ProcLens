import SwiftUI

struct SubprocessTarget: Hashable, Codable {
    let pid: Int32
    let name: String
}

struct SubprocessWindow: View {
    let parent: SubprocessTarget
    @Environment(NetworkActivity.self) private var networkActivity
    @Environment(ProcessManager.self) private var processManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let processes = processManager.processes
        let parentIsRunning = processes.contains { $0.pid == parent.pid }
        let hasChildren = processes.contains { $0.parentPid == parent.pid }
        let childCount = processes.filter { $0.parentPid == parent.pid }.count

        VStack(spacing: 0) {
            HStack(spacing: 12) {
                if let parentProcess = processes.first(where: { $0.pid == parent.pid }) {
                    Image(nsImage: IconProvider.shared.appIcon(for: parentProcess))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 28, height: 28)
                        .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                } else {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(parent.name)
                        .font(.headline)
                        .lineLimit(1)
                    Text("PID \(parent.pid)" + (childCount > 0 ? "  ·  \(childCount) direct \(childCount == 1 ? "child" : "children")" : ""))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            Divider()
            if !parentIsRunning || !hasChildren {
                ContentUnavailableView(
                    parentIsRunning ? "No Subprocesses" : "Process Ended",
                    systemImage: parentIsRunning ? "arrow.triangle.branch" : "power",
                    description: Text(parentIsRunning
                        ? "\(parent.name) currently has no child processes."
                        : "PID \(parent.pid) is no longer running.")
                )
                .frame(maxHeight: .infinity)
            } else {
                ProcessTreeView(
                    processes: networkActivity.addingCounters(to: processes),
                    parentPID: parent.pid,
                    selectedPID: .constant(nil)
                )
            }
        }
        .frame(minWidth: 720, minHeight: 360)
    }
}

struct ProcessTreeView: View {
    let processes: [ProcessItem]
    var parentPID: Int32? = nil
    @Binding var selectedPID: Int32?
    var showSubprocesses: ((ProcessItem) -> Void)? = nil
    @AppStorage("ProcLens.TreeColumnCustomization") private var columnCustomization = TableColumnCustomization<ProcessTreeNode>()
    @State private var sortOrder = [KeyPathComparator(\ProcessTreeNode.process.cpuUsage, order: .reverse)]
    @Environment(ProcessManager.self) private var processManager

    private var rootNodes: [ProcessTreeNode] {
        ProcessTreeNode.buildForest(from: processes, under: parentPID, sortedBy: sortOrder)
    }

    var body: some View {
        Table(rootNodes, children: \.children, selection: $selectedPID, sortOrder: $sortOrder, columnCustomization: $columnCustomization) {
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
            if let showSubprocesses, let pid = pids.first,
               let process = processManager.processes.first(where: { $0.pid == pid }) {
                showSubprocesses(process)
            }
        }
    }

    @TableColumnBuilder<ProcessTreeNode, KeyPathComparator<ProcessTreeNode>>
    private var primaryColumns: some TableColumnContent<ProcessTreeNode, KeyPathComparator<ProcessTreeNode>> {
        column(for: .pid)
        column(for: .name)
        column(for: .cpu)
        column(for: .memory)
        column(for: .received)
        column(for: .sent)
        column(for: .user)
        column(for: .threads)
    }

    @TableColumnBuilder<ProcessTreeNode, KeyPathComparator<ProcessTreeNode>>
    private var secondaryColumns: some TableColumnContent<ProcessTreeNode, KeyPathComparator<ProcessTreeNode>> {
        column(for: .status)
        column(for: .ports)
        column(for: .arch)
        column(for: .diskRead)
        column(for: .diskWrite)
        column(for: .uptime)
        column(for: .signature)
        column(for: .ppid)
    }

    private func column(for col: ProcessColumn) -> some TableColumnContent<ProcessTreeNode, KeyPathComparator<ProcessTreeNode>> {
        baseColumn(for: col)
            .customizationID(col.rawValue)
            .defaultVisibility(ColumnSettings.defaultColumns.contains(col) ? .visible : .hidden)
    }

    private func baseColumn(for col: ProcessColumn) -> TableColumn<ProcessTreeNode, KeyPathComparator<ProcessTreeNode>, AnyView, Text> {
        switch col {
        case .pid:
            TableColumn("PID", value: \.process.pid) { node in
                AnyView(
                    Text("\(node.process.pid)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                )
            }
            .width(min: ProcessColumn.pid.minWidth, ideal: ProcessColumn.pid.defaultWidth, max: 80)
        case .name:
            TableColumn("Name", value: \.process.name) { node in
                AnyView(
                    HStack(spacing: 6) {
                        Image(nsImage: IconProvider.shared.appIcon(for: node.process))
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 16, height: 16)
                        Text(node.process.name)
                            .fontWeight(.medium)
                            .lineLimit(1)
                    }
                )
            }
            .width(min: ProcessColumn.name.minWidth, ideal: ProcessColumn.name.defaultWidth)
        case .cpu:
            TableColumn("CPU %", value: \.process.cpuUsage) { node in
                AnyView(
                    HStack(spacing: 6) {
                        if processManager.historyTracker.hasMeaningfulCPU(for: node.process.pid) {
                            SparklineView(
                                values: processManager.historyTracker.cpuHistory(for: node.process.pid),
                                color: cpuColor(node.process.cpuUsage)
                            )
                            .frame(width: 40, height: 14)
                        }
                        Text(node.process.formattedCPU)
                            .monospacedDigit()
                            .fontWeight(.medium)
                            .foregroundStyle(cpuColor(node.process.cpuUsage))
                    }
                )
            }
            .width(min: ProcessColumn.cpu.minWidth, ideal: ProcessColumn.cpu.defaultWidth, max: 160)
        case .memory:
            TableColumn("Memory", value: \.process.memoryUsage) { node in
                AnyView(
                    Text(node.process.formattedMemory)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                )
            }
            .width(min: ProcessColumn.memory.minWidth, ideal: ProcessColumn.memory.defaultWidth, max: 110)
        case .ports:
            TableColumn("Ports", value: \.process.portsSortKey) { node in
                AnyView(
                    Group {
                        if node.process.ports.isEmpty {
                            Text("—").foregroundStyle(.tertiary)
                        } else {
                            Text(node.process.formattedPorts)
                                .font(.system(.caption, design: .monospaced))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                                .foregroundStyle(.blue)
                        }
                    }
                )
            }
            .width(min: ProcessColumn.ports.minWidth, ideal: ProcessColumn.ports.defaultWidth)
        case .arch:
            TableColumn("Arch", value: \.process.archShortName) { node in
                AnyView(
                    Group {
                        if node.process.architecture == .unavailable {
                            Text("—").foregroundStyle(.tertiary)
                        } else {
                            Text(node.process.archShortName)
                                .font(.system(.caption2, design: .monospaced).weight(.semibold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(node.process.archBadgeColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                                .foregroundStyle(node.process.archBadgeColor)
                        }
                    }
                )
            }
            .width(min: ProcessColumn.arch.minWidth, ideal: ProcessColumn.arch.defaultWidth)
        case .diskRead:
            TableColumn("Disk Read", value: \.process.diskReadBytes) { node in
                AnyView(
                    Text(node.process.formattedDiskRead)
                        .monospacedDigit()
                        .foregroundStyle(node.process.diskReadBytes == 0 ? .tertiary : .secondary)
                )
            }
            .width(min: ProcessColumn.diskRead.minWidth, ideal: ProcessColumn.diskRead.defaultWidth)
        case .diskWrite:
            TableColumn("Disk Write", value: \.process.diskWriteBytes) { node in
                AnyView(
                    Text(node.process.formattedDiskWrite)
                        .monospacedDigit()
                        .foregroundStyle(node.process.diskWriteBytes == 0 ? .tertiary : .secondary)
                )
            }
            .width(min: ProcessColumn.diskWrite.minWidth, ideal: ProcessColumn.diskWrite.defaultWidth)
        case .uptime:
            TableColumn("Uptime", value: \.process.uptimeSeconds) { node in
                AnyView(
                    Text(node.process.formattedUptime)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                )
            }
            .width(min: ProcessColumn.uptime.minWidth, ideal: ProcessColumn.uptime.defaultWidth)
        case .received:
            TableColumn("Received", value: \.process.networkBytesReceived) { node in
                AnyView(
                    Text(node.process.networkCounters.map { NetworkCounters.formatBytes($0.received) } ?? "—")
                        .monospacedDigit()
                        .foregroundStyle(node.process.networkCounters == nil ? .tertiary : .secondary)
                )
            }
            .width(min: ProcessColumn.received.minWidth, ideal: ProcessColumn.received.defaultWidth)
        case .sent:
            TableColumn("Sent", value: \.process.networkBytesSent) { node in
                AnyView(
                    Text(node.process.networkCounters.map { NetworkCounters.formatBytes($0.sent) } ?? "—")
                        .monospacedDigit()
                        .foregroundStyle(node.process.networkCounters == nil ? .tertiary : .secondary)
                )
            }
            .width(min: ProcessColumn.sent.minWidth, ideal: ProcessColumn.sent.defaultWidth)
        case .user:
            TableColumn("User", value: \.process.user) { node in
                AnyView(
                    Text(node.process.user)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .help(node.process.user)
                )
            }
            .width(min: ProcessColumn.user.minWidth, ideal: ProcessColumn.user.defaultWidth, max: 120)
        case .threads:
            TableColumn("Threads", value: \.process.threadCount) { node in
                AnyView(
                    Text("\(node.process.threadCount)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                )
            }
            .width(min: ProcessColumn.threads.minWidth, ideal: ProcessColumn.threads.defaultWidth, max: 80)
        case .status:
            TableColumn("Status", value: \.process.status) { node in
                AnyView(StatusBadge(status: node.process.status))
            }
            .width(min: ProcessColumn.status.minWidth, ideal: ProcessColumn.status.defaultWidth, max: 100)
        case .signature:
            TableColumn("Signature", value: \.process.signatureBadgeText) { node in
                AnyView(
                    Text(node.process.signatureBadgeText)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(node.process.signatureBadgeColor)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(node.process.signatureBadgeColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                )
            }
            .width(min: ProcessColumn.signature.minWidth, ideal: ProcessColumn.signature.defaultWidth)
        case .ppid:
            TableColumn("PPID", value: \.process.parentPid) { node in
                AnyView(
                    Text("\(node.process.parentPid)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                )
            }
            .width(min: ProcessColumn.ppid.minWidth, ideal: ProcessColumn.ppid.defaultWidth)
        }
    }

    private func cpuColor(_ usage: Double) -> Color {
        if usage > 80 { return .red }
        if usage > 50 { return .orange }
        if usage > 10 { return .yellow }
        return .primary
    }
}
