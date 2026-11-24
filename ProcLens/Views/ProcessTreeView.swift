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

        VStack(spacing: 0) {
            HStack {
                Text("\(parent.name) (PID \(parent.pid))")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
            Divider()
            if !parentIsRunning || !hasChildren {
                ContentUnavailableView(
                    parentIsRunning ? "No Subprocesses" : "Process Ended",
                    systemImage: "arrow.triangle.branch"
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
    @State private var isLaunchdExpanded = true
    @State private var sortOrder = KeyPathComparator(\ProcessItem.cpuUsage, order: .reverse)
    @Environment(ProcessManager.self) private var processManager

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                sortButton("PID", by: KeyPathComparator(\ProcessItem.pid))
                    .frame(width: 55, alignment: .leading)
                sortButton("Name", by: KeyPathComparator(\ProcessItem.name, comparator: .localizedStandard))
                Spacer()
                sortButton("CPU %", by: KeyPathComparator(\ProcessItem.cpuUsage, order: .reverse))
                    .frame(width: 55, alignment: .trailing)
                sortButton("Memory", by: KeyPathComparator(\ProcessItem.memoryUsage, order: .reverse))
                    .frame(width: 75, alignment: .trailing)
                sortButton("Received", by: KeyPathComparator(\ProcessItem.networkBytesReceived, order: .reverse))
                    .frame(width: 85, alignment: .trailing)
                sortButton("Sent", by: KeyPathComparator(\ProcessItem.networkBytesSent, order: .reverse))
                    .frame(width: 75, alignment: .trailing)
                sortButton("User", by: KeyPathComparator(\ProcessItem.user, comparator: .localizedStandard))
                    .frame(width: 80, alignment: .trailing)
                sortButton("Threads", by: KeyPathComparator(\ProcessItem.threadCount, order: .reverse))
                    .frame(width: 65, alignment: .trailing)
                sortButton("Status", by: KeyPathComparator(\ProcessItem.status))
                    .frame(width: 65, alignment: .trailing)
            }
            .font(.caption)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            Divider()
            processList
        }
    }

    private var processList: some View {
        let rootNodes = ProcessTreeNode.buildForest(from: processes, under: parentPID, sortedBy: sortOrder)
        return List(selection: $selectedPID) {
            ForEach(rootNodes) { node in
                if node.id == 1, node.process.name == "launchd", let children = node.children {
                    DisclosureGroup(isExpanded: $isLaunchdExpanded) {
                        OutlineGroup(children, children: \.children) { child in
                            processRow(child).tag(child.id)
                        }
                    } label: {
                        processRow(node)
                    }
                    .tag(node.id)
                } else {
                    OutlineGroup(node, children: \.children) { descendant in
                        processRow(descendant).tag(descendant.id)
                    }
                }
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
        .contextMenu(forSelectionType: Int32.self) { pids in
            if let showSubprocesses, let pid = pids.first,
               let process = processManager.processes.first(where: { $0.pid == pid }) {
                Button("Show Subprocesses") { showSubprocesses(process) }
            }
        } primaryAction: { pids in
            if let showSubprocesses, let pid = pids.first,
               let process = processManager.processes.first(where: { $0.pid == pid }) {
                showSubprocesses(process)
            }
        }
    }

    private func sortButton(_ title: String, by comparator: KeyPathComparator<ProcessItem>) -> some View {
        let isActive = sortOrder.keyPath == comparator.keyPath
        return Button {
            if isActive {
                sortOrder.order = sortOrder.order == .forward ? .reverse : .forward
            } else {
                sortOrder = comparator
            }
        } label: {
            HStack(spacing: 4) {
                Text(title)
                if isActive {
                    Image(systemName: sortOrder.order == .forward ? "chevron.up" : "chevron.down")
                }
            }
        }
        .buttonStyle(.plain)
        .help("Sort by \(title)")
        .accessibilityValue(isActive ? (sortOrder.order == .forward ? "Ascending" : "Descending") : "")
    }

    private func processRow(_ node: ProcessTreeNode) -> some View {
        HStack(spacing: 6) {
            Text("\(node.process.pid)")
                .monospacedDigit()
                .foregroundStyle(.tertiary)
                .frame(width: 55, alignment: .leading)

            Image(nsImage: IconProvider.shared.appIcon(for: node.process))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 16, height: 16)

            Text(node.process.name)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            if processManager.historyTracker.hasMeaningfulCPU(for: node.process.pid) {
                SparklineView(
                    values: processManager.historyTracker.cpuHistory(for: node.process.pid),
                    color: cpuColor(node.process.cpuUsage)
                )
                .frame(width: 40, height: 14)
            }

            Text(node.process.formattedCPU)
                .monospacedDigit()
                .foregroundStyle(cpuColor(node.process.cpuUsage))
                .frame(width: 55, alignment: .trailing)

            Text(node.process.formattedMemory)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 75, alignment: .trailing)

            Text(node.process.networkCounters.map { NetworkCounters.formatBytes($0.received) } ?? "—")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 85, alignment: .trailing)

            Text(node.process.networkCounters.map { NetworkCounters.formatBytes($0.sent) } ?? "—")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 75, alignment: .trailing)

            Text(node.process.user)
                .lineLimit(1)
                .help(node.process.user)
                .frame(width: 80, alignment: .trailing)

            Text("\(node.process.threadCount)")
                .monospacedDigit()
                .frame(width: 65, alignment: .trailing)

            Text(node.process.status.displayName)
                .font(.caption)
                .foregroundStyle(node.process.status.color)
                .lineLimit(1)
                .frame(width: 65, alignment: .trailing)
        }
        .font(.callout)
    }

    private func cpuColor(_ usage: Double) -> Color {
        if usage > 80 { return .red }
        if usage > 50 { return .orange }
        if usage > 10 { return .yellow }
        return .primary
    }
}
