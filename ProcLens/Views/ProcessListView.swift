import SwiftUI

struct ProcessListView: View {
    @Environment(ProcessManager.self) private var processManager
    @Binding var selectedPID: Int32?
    @Binding var searchText: String
    @Binding var sortOrder: [KeyPathComparator<ProcessItem>]

    private var displayProcesses: [ProcessItem] {
        let base = searchText.isEmpty
            ? processManager.processes
            : processManager.processes.filter { p in
                p.name.localizedCaseInsensitiveContains(searchText)
                    || String(p.pid).contains(searchText)
                    || p.user.localizedCaseInsensitiveContains(searchText)
                    || p.path.localizedCaseInsensitiveContains(searchText)
            }
        return base.sorted(using: sortOrder)
    }

    var body: some View {
        Table(displayProcesses, selection: $selectedPID, sortOrder: $sortOrder) {
            TableColumn("PID", value: \.pid) { p in
                Text("\(p.pid)").monospacedDigit()
            }
            .width(min: 50, ideal: 65, max: 80)

            TableColumn("Name", value: \.name) { p in
                HStack(spacing: 4) {
                    Image(nsImage: IconProvider.shared.appIcon(for: p))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 16, height: 16)
                        .help(iconTooltip(for: p))
                    Text(p.name).lineLimit(1)
                }
            }
            .width(min: 120, ideal: 200)

            TableColumn("CPU %", value: \.cpuUsage) { p in
                HStack(spacing: 4) {
                    Text(p.formattedCPU)
                        .monospacedDigit()
                        .foregroundStyle(cpuColor(p.cpuUsage))
                    if processManager.historyTracker.hasMeaningfulCPU(for: p.pid) {
                        SparklineView(
                            values: processManager.historyTracker.cpuHistory(for: p.pid),
                            color: cpuColor(p.cpuUsage)
                        )
                        .frame(width: 40, height: 14)
                    }
                }
            }
            .width(min: 100, ideal: 130, max: 160)

            TableColumn("Memory", value: \.memoryUsage) { p in
                Text(p.formattedMemory).monospacedDigit()
            }
            .width(min: 70, ideal: 90, max: 110)

            TableColumn("User", value: \.user)
                .width(min: 60, ideal: 80, max: 120)

            TableColumn("Threads", value: \.threadCount) { p in
                Text("\(p.threadCount)").monospacedDigit()
            }
            .width(min: 55, ideal: 65, max: 80)

            TableColumn("Status", value: \.status) { p in
                Text(p.status.displayName)
                    .foregroundStyle(p.status.color)
                    .font(.caption)
            }
            .width(min: 60, ideal: 75, max: 90)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .contextMenu(forSelectionType: Int32.self) { pids in
            if let pid = pids.first,
               let process = processManager.processes.first(where: { $0.pid == pid }) {
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
                    Button("Resume (SIGCONT)") { _ = processManager.resumeProcess(pid) }
                } else {
                    Button("Suspend (SIGSTOP)") { _ = processManager.suspendProcess(pid) }
                }
                Button("Terminate (SIGTERM)") { _ = processManager.killProcess(pid) }
                Button("Force Kill (SIGKILL)") { _ = processManager.killProcess(pid, force: true) }
            }
        }
    }

    private func copyText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
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
