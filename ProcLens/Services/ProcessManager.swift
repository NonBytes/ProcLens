import Foundation
import Darwin
import Observation

@Observable
final class ProcessManager {
    var processes: [ProcessItem] = []
    var isRefreshing = false
    var refreshInterval: TimeInterval = 2.0 {
        didSet { restartTimer() }
    }
    let historyTracker = HistoryTracker()

    private var previousCPUTimes: [Int32: (user: UInt64, system: UInt64, time: UInt64)] = [:]
    private var timer: Timer?

    func startMonitoring() {
        refresh()
        startTimer()
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let newProcesses = self.fetchProcesses()
            DispatchQueue.main.async {
                self.historyTracker.recordAll(newProcesses)
                self.processes = newProcesses
                self.isRefreshing = false
            }
        }
    }

    // MARK: - Process Actions

    func killProcess(_ pid: Int32, force: Bool = false) -> Bool {
        kill(pid, force ? SIGKILL : SIGTERM) == 0
    }

    func suspendProcess(_ pid: Int32) -> Bool {
        kill(pid, SIGSTOP) == 0
    }

    func resumeProcess(_ pid: Int32) -> Bool {
        kill(pid, SIGCONT) == 0
    }

    func setProcessPriority(_ pid: Int32, nice: Int32) -> Bool {
        setpriority(PRIO_PROCESS, id_t(pid), nice) == 0
    }

    // MARK: - Export

    func exportCSV() -> String {
        var csv = "PID,Name,User,CPU%,Memory (bytes),Virtual (bytes),Threads,Status,Nice,Disk Read,Disk Write,Path\n"
        for p in processes {
            let n = p.name.replacingOccurrences(of: ",", with: ";")
            let pt = p.path.replacingOccurrences(of: ",", with: ";")
            csv += "\(p.pid),\(n),\(p.user),\(String(format:"%.2f",p.cpuUsage)),\(p.memoryUsage),\(p.virtualMemory),\(p.threadCount),\(p.status.displayName),\(p.niceValue),\(p.diskReadBytes),\(p.diskWriteBytes),\(pt)\n"
        }
        return csv
    }

    // MARK: - Private

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    private func restartTimer() {
        stopMonitoring()
        startTimer()
    }

    private func fetchProcesses() -> [ProcessItem] {
        var numPids = proc_listallpids(nil, 0)
        guard numPids > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(numPids))
        numPids = proc_listallpids(&pids, Int32(MemoryLayout<pid_t>.size * Int(numPids)))
        guard numPids > 0 else { return [] }

        let now = mach_absolute_time()
        var result: [ProcessItem] = []
        var newCPUTimes: [Int32: (user: UInt64, system: UInt64, time: UInt64)] = [:]

        for i in 0..<Int(numPids) {
            let pid = pids[i]
            if pid <= 0 { continue }
            guard let item = buildProcessItem(pid: pid, now: now, cpuTimesOut: &newCPUTimes) else { continue }
            result.append(item)
        }
        previousCPUTimes = newCPUTimes
        return result
    }

    private func buildProcessItem(
        pid: Int32, now: UInt64,
        cpuTimesOut: inout [Int32: (user: UInt64, system: UInt64, time: UInt64)]
    ) -> ProcessItem? {
        var kinfo = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &kinfo, &size, nil, 0) == 0, size > 0 else { return nil }

        let name = fetchProcessName(pid: pid, kinfo: kinfo)
        let path = fetchProcessPath(pid: pid)

        var taskInfo = proc_taskinfo()
        let taskInfoSize = proc_pidinfo(
            pid, Int32(PROC_PIDTASKINFO), 0,
            &taskInfo, Int32(MemoryLayout<proc_taskinfo>.size)
        )
        let hasTaskInfo = taskInfoSize == Int32(MemoryLayout<proc_taskinfo>.size)

        var cpuUsage: Double = 0
        if hasTaskInfo {
            let totalUser = taskInfo.pti_total_user
            let totalSystem = taskInfo.pti_total_system
            if let prev = previousCPUTimes[pid] {
                let userDelta = totalUser >= prev.user ? totalUser - prev.user : 0
                let systemDelta = totalSystem >= prev.system ? totalSystem - prev.system : 0
                let timeDelta = now - prev.time
                if timeDelta > 0 {
                    cpuUsage = (Double(userDelta + systemDelta) / Double(timeDelta)) * 100.0
                    cpuUsage = min(cpuUsage, 100.0 * Double(ProcessInfo.processInfo.activeProcessorCount))
                }
            }
            cpuTimesOut[pid] = (totalUser, totalSystem, now)
        }

        let uid = kinfo.kp_eproc.e_ucred.cr_uid
        let userName: String
        if let pw = getpwuid(uid) { userName = String(cString: pw.pointee.pw_name) }
        else { userName = "\(uid)" }

        let status = ProcessStatus(rawValue: kinfo.kp_proc.p_stat) ?? .unknown
        let diskIO = fetchDiskIO(pid: pid)

        return ProcessItem(
            pid: pid, name: name, user: userName, cpuUsage: cpuUsage,
            memoryUsage: hasTaskInfo ? taskInfo.pti_resident_size : 0,
            virtualMemory: hasTaskInfo ? taskInfo.pti_virtual_size : 0,
            threadCount: hasTaskInfo ? taskInfo.pti_threadnum : 0,
            status: status, path: path, parentPid: kinfo.kp_eproc.e_ppid,
            niceValue: Int32(kinfo.kp_proc.p_nice),
            diskReadBytes: diskIO.read, diskWriteBytes: diskIO.write
        )
    }

    private func fetchDiskIO(pid: Int32) -> (read: UInt64, write: UInt64) {
        let r = fetch_disk_io(pid)
        return (r.read_bytes, r.write_bytes)
    }

    private func fetchProcessName(pid: Int32, kinfo: kinfo_proc) -> String {
        var nameBuffer = [CChar](repeating: 0, count: 1024)
        let nameLen = proc_name(pid, &nameBuffer, UInt32(nameBuffer.count))
        if nameLen > 0 {
            return String(cString: nameBuffer)
        }
        var comm = kinfo.kp_proc.p_comm
        return withUnsafeBytes(of: &comm) { buf in
            guard let base = buf.baseAddress else { return "?" }
            return String(cString: base.assumingMemoryBound(to: CChar.self))
        }
    }

    private func fetchProcessPath(pid: Int32) -> String {
        let maxSize = 4 * Int(MAXPATHLEN)
        var pathBuffer = [CChar](repeating: 0, count: maxSize)
        let pathLen = proc_pidpath(pid, &pathBuffer, UInt32(maxSize))
        guard pathLen > 0 else { return "" }
        return String(cString: pathBuffer)
    }
}
