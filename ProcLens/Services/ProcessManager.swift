import Foundation
import Darwin
import Observation

@Observable
final class ProcessManager {
    var processes: [ProcessItem] = [] {
        didSet { revision &+= 1 }
    }
    private(set) var revision: UInt64 = 0
    var isRefreshing = false
    var refreshInterval: TimeInterval = 2.0 {
        didSet { restartTimer() }
    }
    @ObservationIgnored let historyTracker = HistoryTracker()

    @ObservationIgnored private var previousCPUTimes: [Int32: (user: UInt64, system: UInt64, time: UInt64)] = [:]
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var monitoringClients = 0
    @ObservationIgnored private var nameCache: [Int32: String] = [:]
    @ObservationIgnored private var pathCache: [Int32: String] = [:]
    @ObservationIgnored private var userCache: [uid_t: String] = [:]
    @ObservationIgnored private var archCache: [Int32: ProcessArchitecture] = [:]
    @ObservationIgnored private var signatureCache: [String: (status: SignatureStatus, authority: String?)] = [:]
    @ObservationIgnored private var portMap: [Int32: [String]] = [:]
    @ObservationIgnored private var isSamplingPorts = false
    @ObservationIgnored private var lastPortSampleTime: CFAbsoluteTime = 0

    func startMonitoring() {
        monitoringClients += 1
        guard monitoringClients == 1 else { return }
        refresh()
        startTimer()
    }

    func stopMonitoring() {
        guard monitoringClients > 0 else { return }
        monitoringClients -= 1
        guard monitoringClients == 0 else { return }
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        samplePortsIfNeeded()
        // Snapshot main-thread state before port sampling publishes another map.
        let ports = portMap
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let newProcesses = autoreleasepool { self.fetchProcesses(ports: ports) }
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
        timer?.tolerance = min(0.2, refreshInterval * 0.1)
    }

    private func restartTimer() {
        guard monitoringClients > 0 else { return }
        timer?.invalidate()
        startTimer()
    }

    private func fetchProcesses(ports: [Int32: [String]]) -> [ProcessItem] {
        var numPids = proc_listallpids(nil, 0)
        guard numPids > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(numPids))
        numPids = proc_listallpids(&pids, Int32(MemoryLayout<pid_t>.size * Int(numPids)))
        guard numPids > 0 else { return [] }

        let now = mach_absolute_time()
        var result: [ProcessItem] = []
        var newCPUTimes: [Int32: (user: UInt64, system: UInt64, time: UInt64)] = [:]

        result.reserveCapacity(Int(numPids))
        newCPUTimes.reserveCapacity(Int(numPids))
        for i in 0..<Int(numPids) {
            let pid = pids[i]
            if pid <= 0 { continue }
            guard let item = autoreleasepool(invoking: {
                buildProcessItem(pid: pid, now: now, ports: ports[pid] ?? [], cpuTimesOut: &newCPUTimes)
            }) else { continue }
            result.append(item)
        }
        previousCPUTimes = newCPUTimes
        let alivePids = Set(result.map(\.pid))
        for pid in nameCache.keys where !alivePids.contains(pid) {
            nameCache.removeValue(forKey: pid)
            pathCache.removeValue(forKey: pid)
            archCache.removeValue(forKey: pid)
        }
        let activePaths = Set(result.lazy.map(\.path))
        signatureCache = signatureCache.filter { activePaths.contains($0.key) }
        return result
    }

    private func samplePortsIfNeeded() {
        let now = CFAbsoluteTimeGetCurrent()
        guard !isSamplingPorts, now - lastPortSampleTime >= 2.0 else { return }
        lastPortSampleTime = now
        isSamplingPorts = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let map = autoreleasepool { Self.fetchListeningPorts() }
            DispatchQueue.main.async {
                self?.portMap = map
                self?.isSamplingPorts = false
            }
        }
    }

    private static func fetchListeningPorts() -> [Int32: [String]] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        task.arguments = ["-nP", "-iTCP", "-sTCP:LISTEN", "-iUDP"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do { try task.run() } catch { return [:] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard let output = String(data: data, encoding: .utf8) else { return [:] }
        var map: [Int32: Set<String>] = [:]
        for line in output.components(separatedBy: "\n").dropFirst() {
            let cols = line.split(separator: " ", maxSplits: 9, omittingEmptySubsequences: true)
            guard cols.count >= 9 else { continue }
            guard let pid = Int32(cols[1]) else { continue }
            let name = String(cols[8])
            let addrPart = name.components(separatedBy: "->").first ?? name
            if let colonIdx = addrPart.lastIndex(of: ":") {
                let portStr = String(addrPart[addrPart.index(after: colonIdx)...])
                if !portStr.isEmpty && portStr != "*" {
                    map[pid, default: []].insert(portStr)
                }
            }
        }
        return map.mapValues { ports in
            ports.sorted { (Int($0) ?? 0) < (Int($1) ?? 0) }
        }
    }

    private func buildProcessItem(
        pid: Int32, now: UInt64, ports: [String],
        cpuTimesOut: inout [Int32: (user: UInt64, system: UInt64, time: UInt64)]
    ) -> ProcessItem? {
        var kinfo = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &kinfo, &size, nil, 0) == 0, size > 0 else { return nil }

        let name: String
        if let cached = nameCache[pid] { name = cached }
        else { name = fetchProcessName(pid: pid, kinfo: kinfo); nameCache[pid] = name }

        let path: String
        if let cached = pathCache[pid] { path = cached }
        else { path = fetchProcessPath(pid: pid); pathCache[pid] = path }

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
        var userName: String
        if let cached = userCache[uid] { userName = cached }
        else if let pw = getpwuid(uid) { userName = String(cString: pw.pointee.pw_name); userCache[uid] = userName }
        else { userName = "\(uid)"; userCache[uid] = userName }

        if getenv("PROCLENS_MASK_USERNAME") != nil {
            userName = userName.replacingOccurrences(of: "nonbytes", with: "developer", options: .caseInsensitive)
        }

        let status = ProcessStatus(rawValue: kinfo.kp_proc.p_stat) ?? .unknown
        let diskIO = fetchDiskIO(pid: pid)

        let arch: ProcessArchitecture
        if let cached = archCache[pid] { arch = cached }
        else { arch = ProcessDetails.fetchArchitecture(pid: pid); archCache[pid] = arch }

        let startSec = kinfo.kp_proc.p_starttime.tv_sec
        let startTime = startSec > 0 ? Date(timeIntervalSince1970: TimeInterval(startSec)) : nil

        var sigStatus = SignatureStatus.unavailable
        var sigAuth: String? = nil
        if !path.isEmpty {
            if let cached = signatureCache[path] {
                sigStatus = cached.status
                sigAuth = cached.authority
            } else {
                let cs = ProcessDetails.fetchCodeSigningInfo(pid: pid, executablePath: path)
                sigStatus = cs.status
                sigAuth = cs.authority
                signatureCache[path] = (cs.status, cs.authority)
            }
        }

        return ProcessItem(
            pid: pid, name: name, user: userName, cpuUsage: cpuUsage,
            memoryUsage: hasTaskInfo ? taskInfo.pti_resident_size : 0,
            virtualMemory: hasTaskInfo ? taskInfo.pti_virtual_size : 0,
            threadCount: hasTaskInfo ? taskInfo.pti_threadnum : 0,
            status: status, path: path, parentPid: kinfo.kp_eproc.e_ppid,
            niceValue: Int32(kinfo.kp_proc.p_nice),
            diskReadBytes: diskIO.read, diskWriteBytes: diskIO.write,
            architecture: arch, startTime: startTime, ports: ports,
            signatureStatus: sigStatus, signatureAuthority: sigAuth
        )
    }

    private func fetchDiskIO(pid: Int32) -> (read: UInt64, write: UInt64) {
        let r = fetch_disk_io(pid)
        return (r.read_bytes, r.write_bytes)
    }

    private func fetchProcessName(pid: Int32, kinfo: kinfo_proc) -> String {
        var nameBuffer = [CChar](repeating: 0, count: 1024)
        let nameLen = proc_name(pid, &nameBuffer, UInt32(nameBuffer.count))
        var name: String
        if nameLen > 0 {
            name = String(cString: nameBuffer)
        } else {
            var comm = kinfo.kp_proc.p_comm
            name = withUnsafeBytes(of: &comm) { buf in
                guard let base = buf.baseAddress else { return "?" }
                return String(cString: base.assumingMemoryBound(to: CChar.self))
            }
        }
        if getenv("PROCLENS_MASK_USERNAME") != nil {
            name = name.replacingOccurrences(of: "nonbytes", with: "developer", options: .caseInsensitive)
        }
        return name
    }

    private func fetchProcessPath(pid: Int32) -> String {
        let maxSize = 4 * Int(MAXPATHLEN)
        var pathBuffer = [CChar](repeating: 0, count: maxSize)
        let pathLen = proc_pidpath(pid, &pathBuffer, UInt32(maxSize))
        guard pathLen > 0 else { return "" }
        var path = String(cString: pathBuffer)
        if getenv("PROCLENS_MASK_USERNAME") != nil {
            path = path.replacingOccurrences(of: "nonbytes", with: "developer", options: .caseInsensitive)
        }
        return path
    }
}
