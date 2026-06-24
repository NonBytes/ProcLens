import Foundation
import Darwin
import Observation

struct SystemStats {
    var cpuUsage: Double = 0
    var userCPU: Double = 0
    var systemCPU: Double = 0
    var idleCPU: Double = 0

    var totalMemory: UInt64 = 0
    var usedMemory: UInt64 = 0
    var freeMemory: UInt64 = 0
    var activeMemory: UInt64 = 0
    var inactiveMemory: UInt64 = 0
    var wiredMemory: UInt64 = 0
    var compressedMemory: UInt64 = 0

    var memoryUsagePercent: Double {
        guard totalMemory > 0 else { return 0 }
        return Double(usedMemory) / Double(totalMemory) * 100
    }

    var totalMemoryGB: Double { Double(totalMemory) / 1_073_741_824 }
    var usedMemoryGB: Double { Double(usedMemory) / 1_073_741_824 }
    var freeMemoryGB: Double { Double(freeMemory) / 1_073_741_824 }
    var wiredMemoryGB: Double { Double(wiredMemory) / 1_073_741_824 }
    var compressedMemoryGB: Double { Double(compressedMemory) / 1_073_741_824 }
}

@Observable
final class SystemMonitor {
    var stats = SystemStats()

    private var previousTicks: (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)?
    private var timer: Timer?

    func startMonitoring() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        updateCPU()
        updateMemory()
    }

    // MARK: - CPU

    private func updateCPU() {
        var cpuInfo: processor_info_array_t?
        var numCPUInfo: mach_msg_type_number_t = 0
        var numCPUs: natural_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &numCPUs,
            &cpuInfo,
            &numCPUInfo
        )
        guard result == KERN_SUCCESS, let info = cpuInfo else { return }

        var totalUser: UInt64 = 0
        var totalSystem: UInt64 = 0
        var totalIdle: UInt64 = 0
        var totalNice: UInt64 = 0

        for i in 0..<Int(numCPUs) {
            let offset = Int(CPU_STATE_MAX) * i
            totalUser   += UInt64(info[offset + Int(CPU_STATE_USER)])
            totalSystem += UInt64(info[offset + Int(CPU_STATE_SYSTEM)])
            totalIdle   += UInt64(info[offset + Int(CPU_STATE_IDLE)])
            totalNice   += UInt64(info[offset + Int(CPU_STATE_NICE)])
        }

        if let prev = previousTicks {
            let uDelta = totalUser - prev.user
            let sDelta = totalSystem - prev.system
            let iDelta = totalIdle - prev.idle
            let nDelta = totalNice - prev.nice
            let total  = uDelta + sDelta + iDelta + nDelta
            if total > 0 {
                stats.userCPU   = Double(uDelta + nDelta) / Double(total) * 100
                stats.systemCPU = Double(sDelta) / Double(total) * 100
                stats.idleCPU   = Double(iDelta) / Double(total) * 100
                stats.cpuUsage  = 100.0 - stats.idleCPU
            }
        }

        previousTicks = (totalUser, totalSystem, totalIdle, totalNice)

        let size = vm_size_t(numCPUInfo) * vm_size_t(MemoryLayout<integer_t>.size)
        vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), size)
    }

    // MARK: - Memory

    private func updateMemory() {
        stats.totalMemory = ProcessInfo.processInfo.physicalMemory

        var vmStats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )

        let result = withUnsafeMutablePointer(to: &vmStats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, intPtr, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }

        let pageSize = UInt64(vm_kernel_page_size)
        stats.activeMemory     = UInt64(vmStats.active_count) * pageSize
        stats.inactiveMemory   = UInt64(vmStats.inactive_count) * pageSize
        stats.wiredMemory      = UInt64(vmStats.wire_count) * pageSize
        stats.compressedMemory = UInt64(vmStats.compressor_page_count) * pageSize
        stats.freeMemory       = UInt64(vmStats.free_count) * pageSize
        stats.usedMemory       = stats.activeMemory + stats.wiredMemory + stats.compressedMemory
    }
}
