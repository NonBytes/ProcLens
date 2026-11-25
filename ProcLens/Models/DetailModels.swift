import Foundation

enum ProcessArchitecture: String, Equatable, Sendable, Codable, Hashable {
    case native = "Apple Silicon (arm64)"
    case rosetta = "Intel (Rosetta 2)"
    case unavailable = "Unavailable"
}

enum SignatureStatus: String, Equatable, Sendable, Codable, Hashable {
    case valid = "Valid"
    case adHoc = "Ad-hoc signed"
    case unsigned = "Unsigned"
    case invalid = "Invalid"
    case unavailable = "Unavailable"
}

struct LoadedModule: Identifiable, Sendable {
    var id: String { path }
    let name: String
    let path: String
}

struct ProcessIdentity: Sendable {
    let pid: Int32
    let startTime: Date?
    let architecture: ProcessArchitecture
    let bundleIdentifier: String?
    let bundleVersion: String?
    let bundleBuild: String?
    let arguments: [String]?
    let launchOrigin: String?
    let signatureStatus: SignatureStatus
    let signingAuthority: String?
    let teamIdentifier: String?
    let entitlements: [(key: String, value: String)]?
    let infoPlist: [(key: String, value: String)]?

    var formattedStartTime: String {
        guard let startTime else { return "Unavailable" }
        return ProcessIdentity.dateFormatter.string(from: startTime)
    }

    var formattedVersion: String? {
        guard bundleVersion != nil || bundleBuild != nil else { return nil }
        if let v = bundleVersion, let b = bundleBuild, !b.isEmpty, b != v {
            return "\(v) (\(b))"
        }
        return bundleVersion ?? bundleBuild
    }

    var commandLine: String? {
        guard let arguments else { return nil }
        return arguments.map { ProcessIdentity.formatArgument($0) }.joined(separator: " ")
    }

    static func formatArgument(_ arg: String) -> String {
        if arg.isEmpty {
            return "\"\""
        }
        if arg.contains(where: { $0.isWhitespace || $0 == "\"" || $0 == "\\" }) {
            let escaped = arg
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(escaped)\""
        }
        return arg
    }

    static func formatPlistDict(_ dict: [String: Any]) -> [(key: String, value: String)] {
        dict.map { k, v in
            let valStr: String
            if let b = v as? Bool {
                valStr = b ? "true" : "false"
            } else if let arr = v as? [Any] {
                valStr = arr.map { "\($0)" }.joined(separator: ", ")
            } else if let d = v as? [String: Any] {
                valStr = "{\(d.keys.joined(separator: ", "))}"
            } else {
                valStr = "\(v)"
            }
            return (key: k, value: valStr)
        }.sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .medium
        return f
    }()
}

struct NetworkConnection: Identifiable {
    let id = UUID()
    let fd: String
    let family: String
    let proto: String
    let localAddress: String
    let localPort: String
    let remoteAddress: String
    let remotePort: String
    let state: String

    var isListening: Bool { state == "LISTEN" }
    var displayLocal: String {
        localPort.isEmpty ? localAddress : "\(localAddress):\(localPort)"
    }
    var displayRemote: String {
        guard !remoteAddress.isEmpty else { return "-" }
        return remotePort.isEmpty ? remoteAddress : "\(remoteAddress):\(remotePort)"
    }
}

struct OpenFile: Identifiable {
    let id = UUID()
    let fd: String
    let type: String
    let name: String
}

struct ProcessTreeNode: Identifiable {
    var id: Int32 { process.pid }
    let process: ProcessItem
    var children: [ProcessTreeNode]?

    static func buildForest(
        from processes: [ProcessItem], under parentPID: Int32?,
        sortedBy comparators: [KeyPathComparator<ProcessTreeNode>]
    ) -> [ProcessTreeNode] {
        var childrenMap: [Int32: [ProcessItem]] = [:]
        var pidSet = Set<Int32>()
        for p in processes {
            pidSet.insert(p.pid)
            childrenMap[p.parentPid, default: []].append(p)
        }
        let sortOrder = comparators + [KeyPathComparator(\ProcessTreeNode.process.pid)]
        var visited: Set<Int32> = parentPID.map { [$0] } ?? []
        func makeNode(_ p: ProcessItem) -> ProcessTreeNode? {
            guard visited.insert(p.pid).inserted else { return nil }
            let kids = childrenMap[p.pid]?
                .compactMap(makeNode)
                .sorted(using: sortOrder)
            return ProcessTreeNode(process: p, children: kids?.isEmpty == true ? nil : kids)
        }
        let roots = if let parentPID {
            childrenMap[parentPID] ?? []
        } else {
            processes.filter { $0.parentPid <= 0 || !pidSet.contains($0.parentPid) }
        }
        var sortedRoots = roots.compactMap(makeNode).sorted(using: sortOrder)
        if parentPID == nil,
           let launchdIndex = sortedRoots.firstIndex(where: { $0.process.pid == 1 && $0.process.name == "launchd" }),
           launchdIndex > 0 {
            let launchd = sortedRoots.remove(at: launchdIndex)
            sortedRoots.insert(launchd, at: 0)
        }
        return sortedRoots
    }
}
