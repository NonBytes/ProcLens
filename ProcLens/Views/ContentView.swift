import SwiftUI
import AppKit

enum ViewMode: String, CaseIterable {
    case list = "List"
    case tree = "Tree"
    case network = "Network"
}

struct ContentView: View {
    @Environment(ProcessManager.self) private var processManager
    @Environment(SystemMonitor.self) private var systemMonitor
    @State private var selectedPID: Int32?
    @State private var subprocessParent: ProcessItem?
    @State private var searchText = ""
    @State private var sortOrder = [KeyPathComparator(\ProcessItem.cpuUsage, order: .reverse)]
    @State private var showInspector = true
    @State private var showKillAlert = false
    @State private var forceKill = false
    @State private var viewMode: ViewMode = .list
    @State private var networkActivity = NetworkActivity()

    private var needsNetworkCounters: Bool { viewMode != .tree }

    var body: some View {
        VStack(spacing: 0) {
            SystemStatsView()
            Divider()

            HStack(spacing: 0) {
                mainContent
                    .frame(maxWidth: .infinity)

                if showInspector, let process = selectedProcess {
                    Divider()
                    ProcessDetailView(process: process)
                        .frame(width: 320)
                }
            }

            Divider()
            statusBar
        }
        .searchable(text: $searchText, prompt: "Search processes...")
        .toolbar { toolbarContent }
        .task(id: needsNetworkCounters) {
            if needsNetworkCounters {
                await networkActivity.monitor(processManager: processManager)
            }
        }
        .sheet(item: $subprocessParent) { parent in
            SubprocessSheet(parent: parent)
        }
        .onAppear {
            processManager.startMonitoring()
            systemMonitor.startMonitoring()
        }
        .onDisappear {
            processManager.stopMonitoring()
            systemMonitor.stopMonitoring()
        }
        .alert("Kill Process?", isPresented: $showKillAlert) {
            Button("Cancel", role: .cancel) {}
            Button(forceKill ? "Force Kill (SIGKILL)" : "Kill (SIGTERM)", role: .destructive) {
                if let pid = selectedPID { _ = processManager.killProcess(pid, force: forceKill) }
            }
        } message: {
            if let p = selectedProcess {
                Text("Are you sure you want to \(forceKill ? "force kill" : "terminate") \"\(p.name)\" (PID \(p.pid))?")
            }
        }
        .frame(minWidth: 900, minHeight: 500)
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContent: some View {
        switch viewMode {
        case .list:
            ProcessListView(
                selectedPID: $selectedPID, searchText: $searchText, sortOrder: $sortOrder,
                networkActivity: networkActivity,
                showSubprocesses: { subprocessParent = $0 }
            )
        case .tree:
            ProcessTreeView(
                processes: filteredProcesses,
                selectedPID: $selectedPID,
                showSubprocesses: { subprocessParent = $0 }
            )
        case .network:
            NetworkActivityView(searchText: searchText, selectedPID: $selectedPID, activity: networkActivity)
        }
    }

    private var statusBar: some View {
        HStack {
            if viewMode == .network {
                Text("Network counters reported by macOS")
                Spacer()
                Text("Samples: ~\(Int(max(5, processManager.refreshInterval)))s")
            } else {
                Text("\(processManager.processes.count) processes")
                if !searchText.isEmpty { Text("(\(filteredProcesses.count) shown)") }
                Spacer()
                if processManager.isRefreshing { ProgressView().controlSize(.mini) }
                Text("Refresh: \(Int(processManager.refreshInterval))s")
            }
        }
        .font(.caption).foregroundStyle(.secondary)
        .padding(.horizontal, 16).padding(.vertical, 4)
        .background(.bar)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .automatic) {
            Picker("Process View", selection: $viewMode) {
                Label("List", systemImage: "list.bullet")
                    .accessibilityLabel("Process List")
                    .tag(ViewMode.list)
                Label("Tree", systemImage: "arrow.triangle.branch")
                    .accessibilityLabel("Process Tree")
                    .tag(ViewMode.tree)
                Label("Network", systemImage: "network")
                    .accessibilityLabel("Network Activity")
                    .tag(ViewMode.network)
            }
            .pickerStyle(.segmented)
            .help("Switch between List, Tree, and Network views")

            Divider()

            Button { processManager.refresh(); systemMonitor.refresh() } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .keyboardShortcut("r")
            .help("Refresh process list (⌘R)")

            Divider()

            Button {
                if let pid = selectedPID {
                    if selectedProcess?.status == .stopped {
                        _ = processManager.resumeProcess(pid)
                    } else {
                        _ = processManager.suspendProcess(pid)
                    }
                }
            } label: {
                Label(
                    selectedProcess?.status == .stopped ? "Resume" : "Suspend",
                    systemImage: selectedProcess?.status == .stopped ? "play.circle" : "pause.circle"
                )
            }
            .disabled(selectedPID == nil)
            .help(selectedProcess?.status == .stopped ? "Resume process (SIGCONT)" : "Suspend process (SIGSTOP)")

            Button { forceKill = false; showKillAlert = true } label: {
                Label("Terminate", systemImage: "xmark.circle")
            }
            .disabled(selectedPID == nil)
            .help("Terminate process (SIGTERM)")

            Button { forceKill = true; showKillAlert = true } label: {
                Label("Force Kill", systemImage: "bolt.circle.fill")
            }
            .disabled(selectedPID == nil)
            .help("Force kill process (SIGKILL)")

            Divider()

            Button { exportToCSV() } label: {
                Label("Export CSV", systemImage: "square.and.arrow.up")
            }
            .keyboardShortcut("e")
            .help("Export process list to CSV (⌘E)")

            Divider()

            Toggle(isOn: $showInspector) {
                Label("Inspector", systemImage: "sidebar.trailing")
            }
            .help("Show/hide process inspector panel")
        }
    }

    // MARK: - Helpers

    private var selectedProcess: ProcessItem? {
        guard let pid = selectedPID else { return nil }
        return processManager.processes.first { $0.pid == pid }
    }

    private var filteredProcesses: [ProcessItem] {
        guard !searchText.isEmpty else { return processManager.processes }
        return processManager.processes.filter { matches($0, searchText) }
    }

    private func matches(_ p: ProcessItem, _ query: String) -> Bool {
        p.name.localizedCaseInsensitiveContains(query)
            || String(p.pid).contains(query)
            || p.user.localizedCaseInsensitiveContains(query)
            || p.path.localizedCaseInsensitiveContains(query)
    }

    private func exportToCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "processes.csv"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? processManager.exportCSV().write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
