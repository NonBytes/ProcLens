import SwiftUI

enum DetailTab: String, CaseIterable {
    case info = "Info"
    case network = "Network"
    case files = "Files"
    case env = "Env"
}

struct ProcessDetailView: View {
    let process: ProcessItem
    let details: ProcessDetails
    @Environment(ProcessManager.self) private var processManager
    private var historyTracker: HistoryTracker { processManager.historyTracker }
    @State private var selectedTab: DetailTab = .info
    @State private var newNice: Double = 0

    var body: some View {
        VStack(spacing: 0) {
            header.padding()
            Divider()

            Picker("", selection: $selectedTab) {
                ForEach(DetailTab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal).padding(.vertical, 6)

            Divider()

            switch selectedTab {
            case .info: infoTab
            case .network: NetworkTabView(connections: details.networkConnections, isLoading: details.isLoading)
            case .files: FilesTabView(files: details.openFiles, isLoading: details.isLoading)
            case .env: EnvironmentTabView(vars: details.environmentVars, isLoading: details.isLoading)
            }
        }
        .background(.background)
        .onAppear { newNice = Double(process.niceValue) }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: {
                let img = IconProvider.shared.appIcon(for: process)
                img.size = NSSize(width: 36, height: 36)
                return img
            }())
            .shadow(radius: 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(process.name).font(.title3).fontWeight(.bold).lineLimit(1)
                Text("PID \(process.pid)").font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer()
        }
    }

    // MARK: - Info Tab

    private var infoTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("CPU History").font(.caption).foregroundStyle(.secondary)
                    SparklineView(
                        values: historyTracker.cpuHistory(for: process.pid),
                        color: cpuColor
                    )
                    .frame(height: 40)
                    .background(Color.primary.opacity(0.03))
                    .cornerRadius(4)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Memory History").font(.caption).foregroundStyle(.secondary)
                    SparklineView(
                        values: historyTracker.memoryHistory(for: process.pid),
                        color: .blue
                    )
                    .frame(height: 40)
                    .background(Color.primary.opacity(0.03))
                    .cornerRadius(4)
                }

                Divider()

                Group {
                    InfoRow(label: "Status", value: process.status.displayName, valueColor: process.status.color)
                    InfoRow(label: "User", value: process.user)
                    InfoRow(label: "Parent PID", value: "\(process.parentPid)")
                    InfoRow(label: "CPU", value: process.formattedCPU, valueColor: cpuColor)
                    InfoRow(label: "Memory", value: process.formattedMemory)
                    InfoRow(label: "Virtual", value: ProcessItem.formatBytes(process.virtualMemory))
                    InfoRow(label: "Threads", value: "\(process.threadCount)")
                }

                Divider()

                Group {
                    Text("Disk I/O").font(.caption).foregroundStyle(.secondary)
                    InfoRow(label: "Read", value: ProcessItem.formatBytes(process.diskReadBytes))
                    InfoRow(label: "Written", value: ProcessItem.formatBytes(process.diskWriteBytes))
                }

                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    Text("Priority").font(.caption).foregroundStyle(.secondary)
                    InfoRow(label: "Nice", value: process.formattedNice)
                    HStack {
                        Text("Set:").font(.caption).foregroundStyle(.secondary)
                        Slider(value: $newNice, in: -20...20, step: 1)
                        Text("\(Int(newNice))").font(.caption).monospacedDigit().frame(width: 30)
                        Button("Apply") {
                            _ = processManager.setProcessPriority(process.pid, nice: Int32(newNice))
                        }
                        .controlSize(.small)
                    }
                }

                if !process.path.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Executable Path").font(.caption).foregroundStyle(.secondary)
                        Text(process.path)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled).lineLimit(5)
                    }
                }

                Spacer()
            }
            .padding()
        }
    }

    private var cpuColor: Color {
        if process.cpuUsage > 80 { return .red }
        if process.cpuUsage > 50 { return .orange }
        return .green
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    var valueColor: Color = .primary

    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary).frame(width: 80, alignment: .leading)
            Text(value).foregroundStyle(valueColor).fontWeight(.medium).textSelection(.enabled)
            Spacer()
        }
        .font(.callout)
    }
}
