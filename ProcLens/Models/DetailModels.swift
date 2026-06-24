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

    static func buildForest(from processes: [ProcessItem]) -> [ProcessTreeNode] {
        var childrenMap: [Int32: [ProcessItem]] = [:]
        var pidSet = Set<Int32>()
        for p in processes {
            pidSet.insert(p.pid)
            childrenMap[p.parentPid, default: []].append(p)
        }
        func makeNode(_ p: ProcessItem) -> ProcessTreeNode {
            let kids = childrenMap[p.pid]?
                .sorted { $0.cpuUsage > $1.cpuUsage }
                .map { makeNode($0) }
            return ProcessTreeNode(process: p, children: kids?.isEmpty == true ? nil : kids)
        }
        return processes
            .filter { $0.parentPid <= 0 || !pidSet.contains($0.parentPid) }
            .sorted { $0.cpuUsage > $1.cpuUsage }
            .map { makeNode($0) }
    }
}
