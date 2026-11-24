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
    @State private var columnWidths: [CGFloat] = [55, 200, 110, 85, 90, 80, 85, 75, 75]
    @State private var resizeStart: CGFloat?
    @State private var isLaunchdExpanded = true
    @State private var sortOrder = KeyPathComparator(\ProcessItem.cpuUsage, order: .reverse)
    @Environment(ProcessManager.self) private var processManager

    var body: some View {
        GeometryReader { geometry in
            ScrollView(.horizontal) {
                VStack(spacing: 0) {
                    HStack(spacing: 6) {
                        sortButton("PID", by: KeyPathComparator(\ProcessItem.pid))
                            .frame(minWidth: columnWidths[0], maxWidth: columnWidths[0], alignment: .leading)
                            .overlay(alignment: .trailing) { resizeHandle(0) }
                        sortButton("Name", by: KeyPathComparator(\ProcessItem.name, comparator: .localizedStandard))
                            .frame(minWidth: columnWidths[1], maxWidth: columnWidths[1], alignment: .leading)
                            .overlay(alignment: .trailing) { resizeHandle(1) }
                        sortButton("CPU %", by: KeyPathComparator(\ProcessItem.cpuUsage, order: .reverse))
                            .frame(minWidth: columnWidths[2], maxWidth: columnWidths[2], alignment: .trailing)
                            .overlay(alignment: .trailing) { resizeHandle(2) }
                        sortButton("Memory", by: KeyPathComparator(\ProcessItem.memoryUsage, order: .reverse))
                            .frame(minWidth: columnWidths[3], maxWidth: columnWidths[3], alignment: .trailing)
                            .overlay(alignment: .trailing) { resizeHandle(3) }
                        sortButton("Received", by: KeyPathComparator(\ProcessItem.networkBytesReceived, order: .reverse))
                            .frame(minWidth: columnWidths[4], maxWidth: columnWidths[4], alignment: .trailing)
                            .overlay(alignment: .trailing) { resizeHandle(4) }
                        sortButton("Sent", by: KeyPathComparator(\ProcessItem.networkBytesSent, order: .reverse))
                            .frame(minWidth: columnWidths[5], maxWidth: columnWidths[5], alignment: .trailing)
                            .overlay(alignment: .trailing) { resizeHandle(5) }
                        sortButton("User", by: KeyPathComparator(\ProcessItem.user, comparator: .localizedStandard))
                            .frame(minWidth: columnWidths[6], maxWidth: columnWidths[6], alignment: .trailing)
                            .overlay(alignment: .trailing) { resizeHandle(6) }
                        sortButton("Threads", by: KeyPathComparator(\ProcessItem.threadCount, order: .reverse))
                            .frame(minWidth: columnWidths[7], maxWidth: columnWidths[7], alignment: .trailing)
                            .overlay(alignment: .trailing) { resizeHandle(7) }
                        sortButton("Status", by: KeyPathComparator(\ProcessItem.status))
                            .frame(minWidth: columnWidths[8], maxWidth: columnWidths[8], alignment: .trailing)
                            .overlay(alignment: .trailing) { resizeHandle(8) }
                        Spacer(minLength: 0)
                    }
                    .font(.caption)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    Divider()
                    processList
                }
                .frame(width: max(geometry.size.width, columnWidths.reduce(0, +) + 100), height: geometry.size.height)
            }
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

    private func resizeHandle(_ column: Int) -> some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.35))
            .frame(width: 1, height: 18)
            .frame(width: 10)
            .contentShape(Rectangle())
            .offset(x: 5)
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let initial = resizeStart ?? columnWidths[column]
                        resizeStart = initial
                        columnWidths[column] = max(column == 1 ? 120 : 55, initial + value.translation.width)
                    }
                    .onEnded { _ in resizeStart = nil }
            )
            .help("Drag to resize column")
            .accessibilityLabel("Resize column")
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
                .frame(width: columnWidths[0], alignment: .leading)

            HStack(spacing: 6) {
                Image(nsImage: IconProvider.shared.appIcon(for: node.process))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)
                Text(node.process.name).lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(minWidth: columnWidths[1], maxWidth: columnWidths[1], alignment: .leading)

            HStack(spacing: 4) {
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
            }
            .frame(width: columnWidths[2], alignment: .trailing)

            Text(node.process.formattedMemory)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: columnWidths[3], alignment: .trailing)

            Text(node.process.networkCounters.map { NetworkCounters.formatBytes($0.received) } ?? "—")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: columnWidths[4], alignment: .trailing)

            Text(node.process.networkCounters.map { NetworkCounters.formatBytes($0.sent) } ?? "—")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: columnWidths[5], alignment: .trailing)

            Text(node.process.user)
                .lineLimit(1)
                .help(node.process.user)
                .frame(width: columnWidths[6], alignment: .trailing)

            Text("\(node.process.threadCount)")
                .monospacedDigit()
                .frame(width: columnWidths[7], alignment: .trailing)

            Text(node.process.status.displayName)
                .font(.caption)
                .foregroundStyle(node.process.status.color)
                .lineLimit(1)
                .frame(width: columnWidths[8], alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .font(.callout)
    }

    private func cpuColor(_ usage: Double) -> Color {
        if usage > 80 { return .red }
        if usage > 50 { return .orange }
        if usage > 10 { return .yellow }
        return .primary
    }
}
