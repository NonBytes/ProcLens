import SwiftUI
import AppKit

// MARK: - Network Tab

struct NetworkTabView: View {
    let connections: [NetworkConnection]
    let isLoading: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if isLoading {
                    ProgressView("Loading connections…")
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, minHeight: 100)
                } else if connections.isEmpty {
                    emptyState("No Connections", icon: "network.slash")
                } else {
                    let listeners = connections.filter(\.isListening)
                    let active = connections.filter { !$0.isListening }

                    if !listeners.isEmpty {
                        sectionHeader("Listening Ports", icon: "antenna.radiowaves.left.and.right", color: .orange)
                        ForEach(listeners) { c in connectionRow(c) }
                        if !active.isEmpty { Divider() }
                    }
                    if !active.isEmpty {
                        sectionHeader("Connections", icon: "arrow.left.arrow.right", color: .blue)
                        ForEach(active) { c in connectionRow(c) }
                    }
                }
            }
            .padding()
        }
    }

    private func connectionRow(_ c: NetworkConnection) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                protoBadge(c.proto)
                if !c.state.isEmpty {
                    stateBadge(c.state)
                }
                Spacer()
            }
            Text(c.displayLocal)
                .font(.system(.caption, design: .monospaced))
            if c.displayRemote != "-" {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(c.displayRemote)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        .textSelection(.enabled)
    }

    private func protoBadge(_ proto: String) -> some View {
        let color: Color = proto == "TCP" ? .blue : .green
        return Text(proto)
            .font(.system(.caption2, design: .rounded).weight(.bold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
    }

    private func stateBadge(_ state: String) -> some View {
        Text(state)
            .font(.system(.caption2, design: .rounded).weight(.medium))
            .foregroundStyle(stateColor(state))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(stateColor(state).opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
    }

    private func stateColor(_ s: String) -> Color {
        switch s {
        case "ESTABLISHED": .green
        case "LISTEN": .orange
        case "CLOSE_WAIT", "TIME_WAIT": .yellow
        default: .secondary
        }
    }
}

// MARK: - Files Tab

struct FilesTabView: View {
    let files: [OpenFile]
    let isLoading: Bool
    @State private var search = ""

    private var filtered: [OpenFile] {
        search.isEmpty ? files : files.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isLoading {
                ProgressView("Loading open files…")
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, minHeight: 100)
            } else if files.isEmpty {
                emptyState("No Files", icon: "doc")
            } else {
                TabSearchBar(text: $search, prompt: "Filter files…")

                countLabel("\(filtered.count) of \(files.count) files")

                List(filtered) { f in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(f.fd)
                                .font(.system(.caption2, design: .monospaced).weight(.bold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
                            Text(f.type)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        Text(f.name)
                            .font(.system(.caption2, design: .monospaced))
                            .lineLimit(2)
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 2)
                }
                .listStyle(.plain)
            }
        }
    }
}

// MARK: - Environment Tab

struct EnvironmentTabView: View {
    let vars: [(key: String, value: String)]
    let isLoading: Bool
    @State private var search = ""

    private var filtered: [(key: String, value: String)] {
        search.isEmpty ? vars : vars.filter {
            $0.key.localizedCaseInsensitiveContains(search) || $0.value.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isLoading {
                ProgressView("Loading environment…")
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, minHeight: 100)
            } else if vars.isEmpty {
                emptyState("No Environment", icon: "list.bullet.rectangle")
            } else {
                TabSearchBar(text: $search, prompt: "Filter variables…")

                countLabel("\(filtered.count) of \(vars.count) variables")

                List(filtered.indices, id: \.self) { i in
                    let v = filtered[i]
                    VStack(alignment: .leading, spacing: 3) {
                        Text(v.key)
                            .font(.system(.caption, design: .monospaced).weight(.semibold))
                        Text(v.value)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 2)
                }
                .listStyle(.plain)
            }
        }
    }
}

// MARK: - Modules Tab

struct ModulesTabView: View {
    let modules: [LoadedModule]
    let isLoading: Bool
    let error: String?
    @State private var search = ""
    @State private var selectedModule: LoadedModule?

    private var filtered: [LoadedModule] {
        search.isEmpty ? modules : modules.filter {
            $0.name.localizedCaseInsensitiveContains(search) || $0.path.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isLoading {
                ProgressView("Loading modules…")
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, minHeight: 100)
            } else if let error = error {
                ContentUnavailableView(
                    "Modules Unavailable",
                    systemImage: "lock.shield",
                    description: Text(error)
                )
                .frame(maxWidth: .infinity, minHeight: 100)
            } else if modules.isEmpty {
                emptyState("No Modules Found", icon: "shippingbox")
            } else {
                TabSearchBar(text: $search, prompt: "Filter modules…")

                countLabel("\(filtered.count) of \(modules.count) modules")

                List(filtered) { m in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "shippingbox")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 14)
                            .padding(.top, 1)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(m.name)
                                .font(.system(.caption, design: .monospaced).weight(.semibold))
                            Text(m.path)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                    .onTapGesture { selectedModule = m }
                    .help("Click for full path")
                    .popover(isPresented: Binding(
                        get: { selectedModule?.id == m.id },
                        set: { if !$0 { selectedModule = nil } }
                    )) {
                        ModulePathDetail(module: m)
                    }
                }
                .listStyle(.plain)
            }
        }
    }
}

// MARK: - Module Path Detail

private struct ModulePathDetail: View {
    let module: LoadedModule
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(module.name, systemImage: "shippingbox")
                .font(.headline)

            Divider()

            ScrollView {
                Text(module.path)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 120)

            HStack {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(module.path, forType: .string)
                    copied = true
                } label: {
                    Label(copied ? "Copied" : "Copy Path", systemImage: copied ? "checkmark" : "doc.on.doc")
                }

                Button {
                    NSWorkspace.shared.selectFile(module.path, inFileViewerRootedAtPath: "")
                } label: {
                    Label("Reveal in Finder", systemImage: "folder")
                }

                Spacer()
            }
            .controlSize(.small)
        }
        .padding(16)
        .frame(width: 440)
        .onChange(of: module.id) { copied = false }
    }
}

// MARK: - Shared Helpers

private func sectionHeader(_ title: String, icon: String, color: Color) -> some View {
    Label(title.uppercased(), systemImage: icon)
        .font(.system(size: 9, weight: .semibold))
        .tracking(0.8)
        .foregroundStyle(color)
}

private func countLabel(_ text: String) -> some View {
    Text(text)
        .font(.caption2)
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .padding(.horizontal)
}

private func emptyState(_ title: String, icon: String) -> some View {
    ContentUnavailableView(title, systemImage: icon)
        .frame(maxWidth: .infinity, minHeight: 120)
}

// MARK: - Search Bar

private struct TabSearchBar: View {
    @Binding var text: String
    let prompt: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(.caption)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear filter")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 7))
        .padding(.horizontal)
        .padding(.top, 8)
    }
}
