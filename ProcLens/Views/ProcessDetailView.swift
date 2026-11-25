import SwiftUI

enum DetailTab: String, CaseIterable {
    case info = "Info"
    case modules = "Modules"
    case network = "Network"
    case files = "Files"
    case env = "Env"
}

struct ProcessDetailView: View {
    let process: ProcessItem
    @State private var details = ProcessDetails()
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
            .labelsHidden()
            .controlSize(.small)
            .padding(.horizontal).padding(.vertical, 6)

            Divider()

            switch selectedTab {
            case .info: infoTab
            case .modules: ModulesTabView(modules: details.modules, isLoading: details.isModulesLoading, error: details.modulesError)
            case .network: NetworkTabView(connections: details.networkConnections, isLoading: details.isLoading)
            case .files: FilesTabView(files: details.openFiles, isLoading: details.isLoading)
            case .env: EnvironmentTabView(vars: details.environmentVars, isLoading: details.isLoading)
            }
        }
        .background(.background)
        .onChange(of: process.pid, initial: true) {
            newNice = Double(process.niceValue)
            details.loadAll(for: process.pid, parentPid: process.parentPid, executablePath: process.path)
            if selectedTab == .modules {
                details.loadModules(for: process.pid)
            }
        }
        .onChange(of: selectedTab) {
            if selectedTab == .modules && details.modules.isEmpty && !details.isModulesLoading {
                details.loadModules(for: process.pid)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: IconProvider.shared.appIcon(for: process))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 40, height: 40)
                .shadow(color: .black.opacity(0.25), radius: 3, y: 1.5)

            VStack(alignment: .leading, spacing: 4) {
                Text(process.name)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text("PID \(process.pid)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                    StatusBadge(status: process.status)
                }
            }
            Spacer()
        }
    }

    // MARK: - Section Label

    private func sectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 9, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(.secondary)
    }

    private func chartCard<Content: View>(title: String, value: String, valueColor: Color,
                                          @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                sectionLabel(title)
                Spacer()
                Text(value)
                    .font(.caption.monospacedDigit())
                    .fontWeight(.medium)
                    .foregroundStyle(valueColor)
            }
            content()
                .frame(height: 44)
                .padding(6)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Info Tab

    private var infoTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                chartCard(title: "CPU History", value: process.formattedCPU, valueColor: cpuColor) {
                    SparklineView(
                        values: historyTracker.cpuHistory(for: process.pid),
                        color: cpuColor
                    )
                }

                chartCard(title: "Memory History", value: process.formattedMemory, valueColor: .blue) {
                    SparklineView(
                        values: historyTracker.memoryHistory(for: process.pid),
                        color: .blue
                    )
                }

                Divider()

                Group {
                    InfoRow(label: "Status", value: process.status.displayName, valueColor: process.status.color)
                    InfoRow(label: "Architecture", value: details.isIdentityLoading ? "Loading..." : (details.identity?.architecture.rawValue ?? "Unavailable"))
                    InfoRow(label: "Started", value: details.isIdentityLoading ? "Loading..." : (details.identity?.formattedStartTime ?? "Unavailable"))

                    if let origin = details.identity?.launchOrigin {
                        InfoRow(label: "Origin", value: origin)
                    }

                    if let sig = details.identity?.signatureStatus {
                        InfoRow(label: "Signature", value: sig.rawValue, valueColor: signatureColor(sig))
                    }
                    if let auth = details.identity?.signingAuthority {
                        InfoRow(label: "Signed By", value: auth)
                    }
                    if let team = details.identity?.teamIdentifier {
                        InfoRow(label: "Team ID", value: team)
                    }

                    InfoRow(label: "User", value: process.user)
                    InfoRow(label: "Parent PID", value: "\(process.parentPid)")

                    if let bundleID = details.identity?.bundleIdentifier {
                        InfoRow(label: "Bundle ID", value: bundleID)
                    }
                    if let version = details.identity?.formattedVersion {
                        InfoRow(label: "Version", value: version)
                    }

                    InfoRow(label: "CPU", value: process.formattedCPU, valueColor: cpuColor)
                    InfoRow(label: "Memory", value: process.formattedMemory)
                    InfoRow(label: "Virtual", value: ProcessItem.formatBytes(process.virtualMemory))
                    InfoRow(label: "Threads", value: "\(process.threadCount)")
                }

                Divider()

                Group {
                    sectionLabel("Disk I/O")
                    InfoRow(label: "Read", value: ProcessItem.formatBytes(process.diskReadBytes))
                    InfoRow(label: "Written", value: ProcessItem.formatBytes(process.diskWriteBytes))
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    sectionLabel("Priority")
                    InfoRow(label: "Nice", value: process.formattedNice)
                    HStack(spacing: 8) {
                        Text("-20").font(.caption2).foregroundStyle(.tertiary).monospacedDigit()
                        Slider(value: $newNice, in: -20...20, step: 1)
                        Text("+20").font(.caption2).foregroundStyle(.tertiary).monospacedDigit()
                        Text("\(Int(newNice))")
                            .font(.caption.monospacedDigit())
                            .fontWeight(.medium)
                            .frame(width: 28, alignment: .trailing)
                        Button("Apply") {
                            _ = processManager.setProcessPriority(process.pid, nice: Int32(newNice))
                        }
                        .controlSize(.small)
                    }
                }

                if !process.path.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        sectionLabel("Executable Path")
                        Text(process.path)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .lineLimit(5)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        sectionLabel("Command Line")
                        Spacer()
                        if let args = details.identity?.arguments {
                            Text("\(args.count) \(args.count == 1 ? "arg" : "args")")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.primary.opacity(0.05), in: Capsule())
                        }
                    }

                    if details.isIdentityLoading {
                        Text("Loading...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let identity = details.identity {
                        if let cmd = identity.commandLine, !cmd.isEmpty {
                            Text(cmd)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .lineLimit(nil)
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))

                            if let args = identity.arguments, args.count > 1 {
                                DisclosureGroup("Arguments (\(args.count))") {
                                    VStack(alignment: .leading, spacing: 3) {
                                        ForEach(Array(args.enumerated()), id: \.offset) { index, arg in
                                            HStack(alignment: .top, spacing: 6) {
                                                Text("[\(index)]")
                                                    .font(.system(.caption2, design: .monospaced))
                                                    .foregroundStyle(.secondary)
                                                    .frame(width: 24, alignment: .trailing)
                                                Text(ProcessIdentity.formatArgument(arg))
                                                    .font(.system(.caption, design: .monospaced))
                                                    .textSelection(.enabled)
                                            }
                                        }
                                    }
                                    .padding(.top, 4)
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        } else if let args = identity.arguments, args.isEmpty {
                            Text("(None)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Unavailable")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Unavailable")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let ents = details.identity?.entitlements, !ents.isEmpty {
                    Divider()
                    DisclosureGroup("Entitlements (\(ents.count))") {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(ents.indices, id: \.self) { i in
                                let item = ents[i]
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.key)
                                        .font(.system(.caption2, design: .monospaced))
                                        .fontWeight(.semibold)
                                    Text(item.value)
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                                .padding(.vertical, 1)
                            }
                        }
                        .padding(.top, 4)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if let plist = details.identity?.infoPlist, !plist.isEmpty {
                    Divider()
                    DisclosureGroup("Info.plist (\(plist.count))") {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(plist.indices, id: \.self) { i in
                                let item = plist[i]
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.key)
                                        .font(.system(.caption2, design: .monospaced))
                                        .fontWeight(.semibold)
                                    Text(item.value)
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                                .padding(.vertical, 1)
                            }
                        }
                        .padding(.top, 4)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding()
        }
    }

    private func signatureColor(_ status: SignatureStatus) -> Color {
        switch status {
        case .valid: return .green
        case .adHoc: return .secondary
        case .unsigned: return .orange
        case .invalid: return .red
        case .unavailable: return .secondary
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
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 88, alignment: .leading)
            Text(value)
                .foregroundStyle(valueColor)
                .fontWeight(.medium)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .font(.callout)
    }
}
