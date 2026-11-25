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
    @Environment(\.openWindow) private var openWindow
    @State private var searchText = ""
    @State private var sortOrder = [KeyPathComparator(\ProcessItem.cpuUsage, order: .reverse)]
    @State private var showInspector = true
    @State private var showKillAlert = false
    @State private var forceKill = false
    @State private var viewMode: ViewMode = .list
    @State private var columnSettings = ColumnSettings.shared
    @Environment(NetworkActivity.self) private var networkActivity

    init(initialSelectedPID: Int32? = nil, initialViewMode: ViewMode = .list) {
        _selectedPID = State(initialValue: initialSelectedPID)
        _viewMode = State(initialValue: initialViewMode)
    }


    var body: some View {
        VStack(spacing: 0) {
            SystemStatsView()
            Divider()

            HStack(alignment: .top, spacing: 0) {
                mainContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                if showInspector, let process = selectedProcess {
                    Divider()
                    ProcessDetailView(process: process)
                        .frame(width: 380)
                        .frame(maxHeight: .infinity, alignment: .top)
                }
            }

            Divider()
            statusBar
        }
        .searchable(text: $searchText, prompt: "Search processes...")
        .toolbar { toolbarContent }
        .task {
            await networkActivity.monitor(processManager: processManager)
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
        .frame(minWidth: viewMode == .tree && showInspector && selectedProcess != nil ? 1100 : 960, minHeight: 500)
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContent: some View {
        switch viewMode {
        case .list:
            ProcessListView(
                selectedPID: $selectedPID, searchText: $searchText, sortOrder: $sortOrder,
                networkActivity: networkActivity,
                showSubprocesses: { openWindow(value: SubprocessTarget(pid: $0.pid, name: $0.name)) }
            )
        case .tree:
            ProcessTreeView(
                processes: networkActivity.addingCounters(to: filteredProcesses),
                selectedPID: $selectedPID,
                showSubprocesses: { openWindow(value: SubprocessTarget(pid: $0.pid, name: $0.name)) }
            )
        case .network:
            NetworkActivityView(searchText: searchText, selectedPID: $selectedPID, activity: networkActivity)
        }
    }

    private var statusBar: some View {
        HStack(spacing: 12) {
            if viewMode == .network {
                statusItem(icon: "network", text: "Network counters reported by macOS")
                Spacer()
                statusItem(icon: "clock.arrow.circlepath", text: "Samples ~every \(Int(max(5, processManager.refreshInterval)))s")
            } else {
                statusItem(icon: "square.stack.3d.up", text: "\(processManager.processes.count) processes")
                if !searchText.isEmpty {
                    statusItem(icon: "magnifyingglass", text: "\(filteredProcesses.count) shown")
                }
                Spacer()
                if processManager.isRefreshing {
                    ProgressView()
                        .controlSize(.mini)
                }
                statusItem(icon: "clock.arrow.circlepath", text: "Refresh \(Int(processManager.refreshInterval))s")
            }
        }
        .font(.caption)
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .imageScale(.small)
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
        .background(.bar)
    }

    private func statusItem(icon: String, text: String) -> some View {
        Label(text, systemImage: icon)
            .labelStyle(.titleAndIcon)
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

            ControlGroup {
                Button { processManager.refresh(); systemMonitor.refresh() } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r")
                .help("Refresh process list (⌘R)")
            }

            ControlGroup {
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
            }

            ControlGroup {
                Button { exportToCSV() } label: {
                    Label("Export CSV", systemImage: "square.and.arrow.up")
                }
                .keyboardShortcut("e")
                .help("Export process list to CSV (⌘E)")
            }

            Menu {
                Text("Table Columns")
                Divider()
                ForEach(ProcessColumn.allCases) { col in
                    Toggle(col.displayName, isOn: Binding(
                        get: { columnSettings.isVisible(col) },
                        set: { _ in columnSettings.toggle(col) }
                    ))
                }
                Divider()
                Button("Reset to Defaults") {
                    columnSettings.resetDefaults()
                }
            } label: {
                Label("Columns", systemImage: "tablecells.badge.ellipsis")
            }
            .help("Customize visible columns")

            ControlGroup {
                Toggle(isOn: $showInspector) {
                    Label("Inspector", systemImage: "sidebar.trailing")
                }
                .help("Show/hide process inspector panel")
            }
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
        let cleanQuery = query.hasPrefix(":") ? String(query.dropFirst()) : query
        return p.name.localizedCaseInsensitiveContains(query)
            || String(p.pid).contains(query)
            || p.user.localizedCaseInsensitiveContains(query)
            || p.path.localizedCaseInsensitiveContains(query)
            || p.ports.contains { $0.contains(cleanQuery) }
            || p.archShortName.localizedCaseInsensitiveContains(query)
            || p.signatureBadgeText.localizedCaseInsensitiveContains(query)
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
