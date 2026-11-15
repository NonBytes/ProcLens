import Foundation

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
        sortedBy comparator: KeyPathComparator<ProcessItem>
    ) -> [ProcessTreeNode] {
        var childrenMap: [Int32: [ProcessItem]] = [:]
        var pidSet = Set<Int32>()
        for p in processes {
            pidSet.insert(p.pid)
            childrenMap[p.parentPid, default: []].append(p)
        }
        let sortOrder = [comparator, KeyPathComparator(\ProcessItem.pid)]
        var visited: Set<Int32> = parentPID.map { [$0] } ?? []
        func makeNode(_ p: ProcessItem) -> ProcessTreeNode? {
            guard visited.insert(p.pid).inserted else { return nil }
            let kids = childrenMap[p.pid]?
                .sorted(using: sortOrder)
                .compactMap(makeNode)
            return ProcessTreeNode(process: p, children: kids?.isEmpty == true ? nil : kids)
        }
        let roots = if let parentPID {
            childrenMap[parentPID] ?? []
        } else {
            processes.filter { $0.parentPid <= 0 || !pidSet.contains($0.parentPid) }
        }
        var sortedRoots = roots.sorted(using: sortOrder)
        if parentPID == nil,
           let launchdIndex = sortedRoots.firstIndex(where: { $0.pid == 1 && $0.name == "launchd" }),
           launchdIndex > 0 {
            let launchd = sortedRoots.remove(at: launchdIndex)
            sortedRoots.insert(launchd, at: 0)
        }
        return sortedRoots.compactMap(makeNode)
    }
}
