import SwiftUI

// MARK: - Network Tab

struct NetworkTabView: View {
    let connections: [NetworkConnection]
    let isLoading: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if isLoading {
                    ProgressView("Loading...")
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
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(c.proto).font(.caption2).fontWeight(.bold)
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(c.proto == "TCP" ? Color.blue.opacity(0.2) : Color.green.opacity(0.2))
                    .cornerRadius(3)
                if !c.state.isEmpty {
                    Text(c.state).font(.caption2)
                        .foregroundStyle(stateColor(c.state))
                }
                Spacer()
            }
            Text(c.displayLocal).font(.system(.caption, design: .monospaced))
            if c.displayRemote != "-" {
                HStack(spacing: 2) {
                    Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.secondary)
                    Text(c.displayRemote).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
        .textSelection(.enabled)
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
        VStack(alignment: .leading, spacing: 6) {
            if isLoading {
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, minHeight: 100)
            } else if files.isEmpty {
                emptyState("No Files", icon: "doc.slash")
            } else {
                TextField("Filter files...", text: $search)
                    .textFieldStyle(.roundedBorder).font(.caption)
                    .padding(.horizontal)
                    .padding(.top, 8)

                Text("\(filtered.count) of \(files.count) files")
                    .font(.caption2).foregroundStyle(.secondary)
                    .padding(.horizontal)

                List(filtered) { f in
                    VStack(alignment: .leading, spacing: 1) {
                        HStack {
                            Text(f.fd).font(.caption2).fontWeight(.bold).frame(width: 35, alignment: .leading)
                            Text(f.type).font(.caption2).foregroundStyle(.secondary)
                            Spacer()
                        }
                        Text(f.name).font(.system(.caption2, design: .monospaced)).lineLimit(2).textSelection(.enabled)
                    }
                    .padding(.vertical, 1)
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
        VStack(alignment: .leading, spacing: 6) {
            if isLoading {
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, minHeight: 100)
            } else if vars.isEmpty {
                emptyState("No Environment", icon: "list.bullet.rectangle")
            } else {
                TextField("Filter...", text: $search)
                    .textFieldStyle(.roundedBorder).font(.caption)
                    .padding(.horizontal)
                    .padding(.top, 8)

                Text("\(filtered.count) variables")
                    .font(.caption2).foregroundStyle(.secondary)
                    .padding(.horizontal)

                List(filtered.indices, id: \.self) { i in
                    let v = filtered[i]
                    VStack(alignment: .leading, spacing: 1) {
                        Text(v.key).font(.system(.caption, design: .monospaced)).fontWeight(.semibold)
                        Text(v.value).font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary).lineLimit(3).textSelection(.enabled)
                    }
                    .padding(.vertical, 1)
                }
                .listStyle(.plain)
            }
        }
    }
}

// MARK: - Shared Helpers

private func sectionHeader(_ title: String, icon: String, color: Color) -> some View {
    Label(title, systemImage: icon)
        .font(.caption).fontWeight(.semibold).foregroundStyle(color)
}

private func emptyState(_ title: String, icon: String) -> some View {
    VStack(spacing: 8) {
        Image(systemName: icon).font(.largeTitle).foregroundStyle(.secondary)
        Text(title).font(.caption).foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, minHeight: 100)
}
