import Foundation

final class HistoryTracker {
    private var histories: [Int32: Samples] = [:]

    // A reference keeps dictionary lookups from copying the backing array on every
    // update. One interleaved ring stores both metrics without shifting samples.
    final class Samples {
        static let capacity = 30
        private struct Sample {
            let cpu: Double
            let memoryMB: Double
        }
        private var storage: [Sample] = []
        private var nextIndex = 0

        init() {
            storage.reserveCapacity(Self.capacity)
        }

        func add(cpu: Double, memoryMB: Double) {
            let sample = Sample(cpu: cpu, memoryMB: memoryMB)
            if storage.count < Self.capacity {
                storage.append(sample)
            } else {
                storage[nextIndex] = sample
            }
            nextIndex = (nextIndex + 1) % Self.capacity
        }

        private func values(_ keyPath: KeyPath<Sample, Double>) -> [Double] {
            let start = storage.count == Self.capacity ? nextIndex : 0
            return (0..<storage.count).map {
                storage[(start + $0) % storage.count][keyPath: keyPath]
            }
        }

        var cpu: [Double] { values(\.cpu) }
        var memoryMB: [Double] { values(\.memoryMB) }
        var hasMeaningfulCPU: Bool { storage.contains { $0.cpu > 0.1 } }
    }

    func recordAll(_ processes: [ProcessItem]) {
        var alive = Set<Int32>()
        alive.reserveCapacity(processes.count)
        for p in processes {
            alive.insert(p.pid)
            if histories[p.pid] == nil { histories[p.pid] = Samples() }
            histories[p.pid]?.add(cpu: p.cpuUsage, memoryMB: p.memoryMB)
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
