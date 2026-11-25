import Foundation
import Observation

struct NetworkCounters: Hashable {
    static func formatBytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .decimal)
    }

    var received: UInt64 = 0
    var sent: UInt64 = 0

    func rate(since earlier: Self, seconds: Double) -> Self {
        Self(
            received: Self.rate(received, since: earlier.received, seconds: seconds),
            sent: Self.rate(sent, since: earlier.sent, seconds: seconds)
        )
    }

    private static func rate(_ current: UInt64, since earlier: UInt64, seconds: Double) -> UInt64 {
        guard current >= earlier, seconds > 0 else { return 0 }
        return UInt64(exactly: (Double(current - earlier) / seconds).rounded(.down)) ?? 0
    }
}

struct NetworkSample {
    let uptime: TimeInterval
    let processes: [Int32: Entry]

    struct Entry {
        let name: String
        let counters: NetworkCounters
    }
}

enum NetworkSampler {
    private static let queue = DispatchQueue(label: "com.nonbytes.ProcLens.network", qos: .utility)

    static func sample() async -> NetworkSample? {
        guard !Task.isCancelled else { return nil }
        return await withCheckedContinuation { continuation in
            queue.async {
                let uptime = ProcessInfo.processInfo.systemUptime
                let output = ProcessDetails.run(
                    "/usr/bin/nettop", ["-P", "-L", "1", "-x", "-J", "bytes_in,bytes_out"],
                    requireSuccess: true
                )
                let entries = output.flatMap(parse)
                continuation.resume(returning: entries.map { NetworkSample(uptime: uptime, processes: $0) })
            }
        }
    }

    static func parse(_ output: String) -> [Int32: NetworkSample.Entry]? {
        let lines = output.split(whereSeparator: \.isNewline)
        guard let header = lines.first else { return nil }
        let columns = header.split(separator: ",", omittingEmptySubsequences: false)
            .dropFirst().filter { !$0.isEmpty }
        guard let receivedColumn = columns.firstIndex(of: "bytes_in"),
              let sentColumn = columns.firstIndex(of: "bytes_out") else { return nil }

        var processes: [Int32: NetworkSample.Entry] = [:]
        for line in lines.dropFirst() {
            var fields = line.split(separator: ",", omittingEmptySubsequences: false)
            if fields.last == "" { fields.removeLast() }
            let labelCount = fields.count - columns.count
            guard labelCount > 0 else { continue }

            let label = fields.prefix(labelCount).joined(separator: ",")
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            guard let separator = label.lastIndex(of: "."),
                  let pid = Int32(label[label.index(after: separator)...]), pid > 0,
                  let received = UInt64(fields[labelCount + receivedColumn]),
                  let sent = UInt64(fields[labelCount + sentColumn]) else { continue }

            processes[pid] = NetworkSample.Entry(
                name: String(label[..<separator]),
                counters: NetworkCounters(received: received, sent: sent)
            )
        }
        return processes
    }
}

@Observable
final class NetworkActivity {
    private(set) var rows: [Int32: Row] = [:] {
        didSet { revision &+= 1 }
    }
    private(set) var revision: UInt64 = 0
    @ObservationIgnored private var monitoringTask: Task<Void, Never>?
    @ObservationIgnored private var monitoringClients = 0
    private(set) var history: [NetworkCounters] = []
    private(set) var isLoading = true
    private(set) var hasError = false

    func addingCounters(to processes: [ProcessItem]) -> [ProcessItem] {
        let sampledRows = rows
        guard !sampledRows.isEmpty else { return processes }
        return processes.map { process in
            var process = process
            process.networkCounters = sampledRows[process.pid]?.totals
            return process
        }
    }

    struct Row: Identifiable {
        let id: Int32
        let name: String
        let totals: NetworkCounters
        let rate: NetworkCounters?
        var received: UInt64 { totals.received }
        var sent: UInt64 { totals.sent }
        var receiveRate: UInt64 { rate?.received ?? 0 }
        var sendRate: UInt64 { rate?.sent ?? 0 }
    }

    @MainActor
    func startMonitoring(processManager: ProcessManager) {
        monitoringClients += 1
        guard monitoringClients == 1 else { return }
        monitoringTask = Task { [weak self] in
            await self?.monitor(processManager: processManager)
        }
    }

    @MainActor
    func stopMonitoring() {
        guard monitoringClients > 0 else { return }
        monitoringClients -= 1
        guard monitoringClients == 0 else { return }
        monitoringTask?.cancel()
        monitoringTask = nil
    }

    @MainActor
    private func monitor(processManager: ProcessManager) async {
        let clock = ContinuousClock()
        var previous: NetworkSample?
        while !Task.isCancelled {
            let nextRefresh = clock.now.advanced(by: .seconds(max(5, processManager.refreshInterval)))
            let sample = await NetworkSampler.sample()
            guard !Task.isCancelled else { return }
            isLoading = false
            hasError = sample == nil

            if let sample {
                update(sample, since: previous, processManager: processManager)
            } else {
                rows.removeAll()
                history.removeAll()
            }
            previous = sample
            do {
                try await clock.sleep(until: nextRefresh)
            } catch {
                return
            }
        }
    }

    private func update(_ sample: NetworkSample, since previous: NetworkSample?, processManager: ProcessManager) {
        let names = Dictionary(processManager.processes.map { ($0.pid, $0.name) }, uniquingKeysWith: { first, _ in first })
        var rates = NetworkCounters()
        rows = Dictionary(uniqueKeysWithValues: sample.processes.map { pid, entry in
            let rate: NetworkCounters?
            if let previous, let earlier = previous.processes[pid], entry.name == earlier.name {
                rate = entry.counters.rate(since: earlier.counters, seconds: sample.uptime - previous.uptime)
                rates.received += rate?.received ?? 0
                rates.sent += rate?.sent ?? 0
            } else {
                rate = nil
            }
            return (pid, Row(id: pid, name: names[pid] ?? entry.name, totals: entry.counters, rate: rate))
        })
        if previous != nil {
            history.append(rates)
            if history.count > 30 { history.removeFirst() }
        }
    }
}
