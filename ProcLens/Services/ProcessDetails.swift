import Foundation
import Darwin
import Observation

@Observable
final class ProcessDetails {
    var networkConnections: [NetworkConnection] = []
    var openFiles: [OpenFile] = []
    var environmentVars: [(key: String, value: String)] = []
    var isLoading = false
    private var loadedPID: Int32 = -1

    func loadAll(for pid: Int32) {
        guard pid != loadedPID else { return }
        loadedPID = pid
        isLoading = true
        networkConnections = []
        openFiles = []
        environmentVars = []

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let net = ProcessDetails.fetchNetwork(pid: pid)
            let files = ProcessDetails.fetchFiles(pid: pid)
            let env = ProcessDetails.fetchEnvironment(pid: pid)
            DispatchQueue.main.async {
                self?.networkConnections = net
                self?.openFiles = files
                self?.environmentVars = env
                self?.isLoading = false
            }
        }
    }

    func reset() {
        loadedPID = -1
        networkConnections = []
        openFiles = []
        environmentVars = []
    }

    // MARK: - Network

    private static func fetchNetwork(pid: Int32) -> [NetworkConnection] {
        guard let output = run("/usr/sbin/lsof", ["-i", "-n", "-P", "-a", "-p", "\(pid)"]) else { return [] }
        var result: [NetworkConnection] = []
        for line in output.components(separatedBy: "\n").dropFirst() {
            let cols = line.split(separator: " ", maxSplits: 9, omittingEmptySubsequences: true)
            guard cols.count >= 9 else { continue }
            let fd = String(cols[3])
            let family = String(cols[4])
            let proto = cols.count > 7 ? String(cols[7]) : ""
            let name = cols.count > 8 ? String(cols[8]) : ""
            let state: String
            if cols.count > 9 {
                state = String(cols[9]).trimmingCharacters(in: CharacterSet(charactersIn: "()"))
            } else { state = "" }

            var la = "", lp = "", ra = "", rp = ""
            if name.contains("->") {
                let parts = name.components(separatedBy: "->")
                if parts.count == 2 {
                    (la, lp) = splitAddr(parts[0])
                    (ra, rp) = splitAddr(parts[1])
                }
            } else {
                (la, lp) = splitAddr(name)
            }
            result.append(NetworkConnection(fd: fd, family: family, proto: proto,
                localAddress: la, localPort: lp, remoteAddress: ra, remotePort: rp, state: state))
        }
        return result
    }

    // MARK: - Files

    private static func fetchFiles(pid: Int32) -> [OpenFile] {
        guard let output = run("/usr/sbin/lsof", ["-p", "\(pid)"]) else { return [] }
        var result: [OpenFile] = []
        for line in output.components(separatedBy: "\n").dropFirst() {
            let cols = line.split(separator: " ", maxSplits: 8, omittingEmptySubsequences: true)
            guard cols.count >= 9 else { continue }
            result.append(OpenFile(fd: String(cols[3]), type: String(cols[4]), name: String(cols[8])))
        }
        return result
    }

    // MARK: - Environment

    static func fetchEnvironment(pid: Int32) -> [(key: String, value: String)] {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size: size_t = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return [] }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return [] }

        let argc = buffer.withUnsafeBytes { $0.load(as: Int32.self) }
        var offset = MemoryLayout<Int32>.size

        while offset < size && buffer[offset] != 0 { offset += 1 }
        while offset < size && buffer[offset] == 0 { offset += 1 }

        var skipped: Int32 = 0
        while offset < size && skipped < argc {
            while offset < size && buffer[offset] != 0 { offset += 1 }
            offset += 1; skipped += 1
        }

        var result: [(key: String, value: String)] = []
        while offset < size {
            var end = offset
            while end < size && buffer[end] != 0 { end += 1 }
            guard end > offset else { break }
            if let str = String(bytes: buffer[offset..<end], encoding: .utf8),
               let eq = str.firstIndex(of: "=") {
                result.append((key: String(str[..<eq]), value: String(str[str.index(after: eq)...])))
            }
            offset = end + 1
        }
        return result.sorted { $0.key < $1.key }
    }

    // MARK: - Helpers

    private static func splitAddr(_ s: String) -> (String, String) {
        guard let i = s.lastIndex(of: ":") else { return (s, "") }
        return (String(s[..<i]), String(s[s.index(after: i)...]))
    }

    private static func run(_ path: String, _ args: [String]) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = args
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do { try task.run(); task.waitUntilExit() } catch { return nil }
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
    }
}
