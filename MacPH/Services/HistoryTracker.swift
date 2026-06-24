import Foundation

final class HistoryTracker {
    private var histories: [Int32: Samples] = [:]

    struct Samples {
        static let capacity = 30
        var cpu: [Double] = []
        var memoryMB: [Double] = []

        mutating func add(cpu cpuVal: Double, memoryMB memVal: Double) {
            cpu.append(cpuVal)
            memoryMB.append(memVal)
            if cpu.count > Self.capacity { cpu.removeFirst() }
            if memoryMB.count > Self.capacity { memoryMB.removeFirst() }
        }

        var hasMeaningfulCPU: Bool {
            cpu.contains { $0 > 0.1 }
        }
    }

    func recordAll(_ processes: [ProcessItem]) {
        var alive = Set<Int32>()
        for p in processes {
            alive.insert(p.pid)
            var s = histories[p.pid] ?? Samples()
            s.add(cpu: p.cpuUsage, memoryMB: p.memoryMB)
            histories[p.pid] = s
        }
        for pid in histories.keys where !alive.contains(pid) {
            histories.removeValue(forKey: pid)
        }
    }

    func cpuHistory(for pid: Int32) -> [Double] {
        histories[pid]?.cpu ?? []
    }

    func memoryHistory(for pid: Int32) -> [Double] {
        histories[pid]?.memoryMB ?? []
    }

    func hasMeaningfulCPU(for pid: Int32) -> Bool {
        histories[pid]?.hasMeaningfulCPU ?? false
    }
}
