import Foundation
import Darwin
import Observation
import Security

@Observable
final class ProcessDetails {
    var identity: ProcessIdentity?
    var isIdentityLoading = false
    var modules: [LoadedModule] = []
    var modulesError: String?
    var isModulesLoading = false
    var networkConnections: [NetworkConnection] = []
    var openFiles: [OpenFile] = []
    var environmentVars: [(key: String, value: String)] = []
    var isLoading = false
    @ObservationIgnored private var loadID: UUID?

    func loadAll(for pid: Int32, parentPid: Int32 = 0, executablePath: String = "") {
        let requestID = UUID()
        loadID = requestID
        identity = nil
        isIdentityLoading = true
        modules = []
        modulesError = nil
        isModulesLoading = false
        networkConnections = []
        openFiles = []
        environmentVars = []
        isLoading = true

        // 1. Fast path: Process identity, deep metadata & environment (Darwin APIs / sysctl / Security)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let argsAndEnv = ProcessDetails.fetchArgsAndEnvironment(pid: pid)
            let startTime = ProcessDetails.fetchStartTime(pid: pid)
            let arch = ProcessDetails.fetchArchitecture(pid: pid)
            let bundle = ProcessDetails.resolveBundle(path: executablePath, pid: pid)
            let codeSign = ProcessDetails.fetchCodeSigningInfo(pid: pid, executablePath: executablePath)
            let origin = ProcessDetails.sanitizePrivacy(ProcessDetails.fetchLaunchOrigin(pid: pid, parentPid: parentPid, executablePath: executablePath))

            let cleanArgs = argsAndEnv?.arguments.map { ProcessDetails.sanitizePrivacy($0) }
            let ident = ProcessIdentity(
                pid: pid,
                startTime: startTime,
                architecture: arch,
                bundleIdentifier: bundle?.bundleID,
                bundleVersion: bundle?.shortVersion,
                bundleBuild: bundle?.buildVersion,
                arguments: cleanArgs,
                launchOrigin: origin,
                signatureStatus: codeSign.status,
                signingAuthority: codeSign.authority,
                teamIdentifier: codeSign.teamIdentifier,
                entitlements: codeSign.entitlements,
                infoPlist: bundle?.infoPlist
            )
            let env = (argsAndEnv?.environment ?? []).map { (key: ProcessDetails.sanitizePrivacy($0.key), value: ProcessDetails.sanitizePrivacy($0.value)) }

            DispatchQueue.main.async {
                guard let self, self.loadID == requestID else { return }
                self.identity = ident
                self.environmentVars = env
                self.isIdentityLoading = false
            }
        }

        // 2. Slow path: Network & Open Files (lsof)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let net = ProcessDetails.fetchNetwork(pid: pid)
            let rawFiles = ProcessDetails.fetchFiles(pid: pid)
            let files = rawFiles.map { OpenFile(fd: $0.fd, type: $0.type, name: ProcessDetails.sanitizePrivacy($0.name)) }
            DispatchQueue.main.async {
                guard let self, self.loadID == requestID else { return }
                self.networkConnections = net
                self.openFiles = files
                self.isLoading = false
            }
        }
    }

    private static func sanitizePrivacy(_ str: String) -> String {
        guard getenv("PROCLENS_MASK_USERNAME") != nil else { return str }
        return str
            .replacingOccurrences(of: "NonceBytes", with: "Developer")
            .replacingOccurrences(of: "nonbytes", with: "developer")
    }

    func loadModules(for pid: Int32) {
        guard !isModulesLoading else { return }
        let requestID = loadID
        isModulesLoading = true
        modules = []
        modulesError = nil

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let (mods, err) = ProcessDetails.fetchLoadedModules(pid: pid)
            DispatchQueue.main.async {
                guard let self, self.loadID == requestID else { return }
                self.modules = mods
                self.modulesError = err
                self.isModulesLoading = false
            }
        }
    }

    // MARK: - Identity & Environment

    static func fetchArgsAndEnvironment(pid: Int32) -> (arguments: [String], environment: [(key: String, value: String)])? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size: size_t = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else {
            return nil
        }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0, size >= MemoryLayout<Int32>.size else {
            return nil
        }

        let argc = buffer.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
        guard argc >= 0 else { return nil }

        var offset = MemoryLayout<Int32>.size

        // Skip executable path (NUL-terminated)
        while offset < size && buffer[offset] != 0 {
            offset += 1
        }
        guard offset < size else {
            return (arguments: [], environment: [])
        }

        // Skip NUL padding after executable path
        while offset < size && buffer[offset] == 0 {
            offset += 1
        }

        // Parse exactly argc arguments
        var args: [String] = []
        for _ in 0..<argc {
            guard offset < size else { break }
            var argBytes: [UInt8] = []
            while offset < size && buffer[offset] != 0 {
                argBytes.append(buffer[offset])
                offset += 1
            }
            if let str = String(bytes: argBytes, encoding: .utf8) {
                args.append(str)
            } else {
                args.append(String(decoding: argBytes, as: UTF8.self))
            }
            if offset < size && buffer[offset] == 0 {
                offset += 1
            }
        }

        // Parse environment strings
        var env: [(key: String, value: String)] = []
        while offset < size {
            while offset < size && buffer[offset] == 0 {
                offset += 1
            }
            guard offset < size else { break }
            var envBytes: [UInt8] = []
            while offset < size && buffer[offset] != 0 {
                envBytes.append(buffer[offset])
                offset += 1
            }
            if offset < size && buffer[offset] == 0 {
                offset += 1
            }
            guard !envBytes.isEmpty else { continue }
            if let str = String(bytes: envBytes, encoding: .utf8) ?? String(bytes: envBytes, encoding: .isoLatin1),
               let eq = str.firstIndex(of: "=") {
                let key = String(str[..<eq])
                let val = String(str[str.index(after: eq)...])
                env.append((key: key, value: val))
            }
        }

        return (arguments: args, environment: env.sorted { $0.key < $1.key })
    }

    static func fetchStartTime(pid: Int32) -> Date? {
        var bsdInfo = proc_bsdinfo()
        let size = proc_pidinfo(
            pid,
            PROC_PIDTBSDINFO,
            0,
            &bsdInfo,
            Int32(MemoryLayout<proc_bsdinfo>.size)
        )
        if size == Int32(MemoryLayout<proc_bsdinfo>.size), bsdInfo.pbi_start_tvsec > 0 {
            return Date(timeIntervalSince1970: TimeInterval(bsdInfo.pbi_start_tvsec) + TimeInterval(bsdInfo.pbi_start_tvusec) / 1_000_000.0)
        }

        // Fallback for system root processes (e.g. PID 1) via sysctl KERN_PROC_PID
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var kinfo = kinfo_proc()
        var ksize = MemoryLayout<kinfo_proc>.size
        if sysctl(&mib, 4, &kinfo, &ksize, nil, 0) == 0, kinfo.kp_proc.p_starttime.tv_sec > 0 {
            return Date(timeIntervalSince1970: TimeInterval(kinfo.kp_proc.p_starttime.tv_sec) + TimeInterval(kinfo.kp_proc.p_starttime.tv_usec) / 1_000_000.0)
        }

        return nil
    }

    static func fetchArchitecture(pid: Int32) -> ProcessArchitecture {
        var archInfo = proc_archinfo()
        let size = proc_pidinfo(
            pid,
            PROC_PIDARCHINFO,
            0,
            &archInfo,
            Int32(MemoryLayout<proc_archinfo>.size)
        )
        guard size == Int32(MemoryLayout<proc_archinfo>.size) else {
            return .unavailable
        }
        let CPU_TYPE_ARM64: cpu_type_t = 0x01000000 | 12
        let CPU_TYPE_X86_64: cpu_type_t = 0x01000000 | 7
        if archInfo.p_cputype == CPU_TYPE_ARM64 {
            return .native
        } else if archInfo.p_cputype == CPU_TYPE_X86_64 {
            return .rosetta
        } else {
            return .unavailable
        }
    }

    static func resolveBundle(path: String, pid: Int32) -> (bundleID: String?, shortVersion: String?, buildVersion: String?, infoPlist: [(key: String, value: String)]?)? {
        var resolvedPath = path
        if resolvedPath.isEmpty {
            let maxSize = 4 * Int(MAXPATHLEN)
            var pathBuffer = [CChar](repeating: 0, count: maxSize)
            let pathLen = proc_pidpath(pid, &pathBuffer, UInt32(maxSize))
            if pathLen > 0 {
                resolvedPath = String(cString: pathBuffer)
            }
        }
        guard !resolvedPath.isEmpty else { return nil }

        let url = URL(fileURLWithPath: resolvedPath).standardized
        var current = url
        var bundleURL: URL? = nil
        while current.path != "/" && current.pathComponents.count > 1 {
            let ext = current.pathExtension.lowercased()
            if ext == "app" || ext == "xpc" || ext == "appex" || ext == "framework" || ext == "bundle" {
                bundleURL = current
                break
            }
            current = current.deletingLastPathComponent()
        }

        guard let bURL = bundleURL, let b = Bundle(url: bURL) else {
            return nil
        }

        let bid = b.bundleIdentifier
        let shortVer = b.infoDictionary?["CFBundleShortVersionString"] as? String
        let buildVer = b.infoDictionary?["CFBundleVersion"] as? String
        var formattedPlist: [(key: String, value: String)]? = nil
        if let dict = b.infoDictionary {
            formattedPlist = ProcessIdentity.formatPlistDict(dict)
        }
        if bid == nil && shortVer == nil && buildVer == nil && formattedPlist == nil {
            return nil
        }
        return (bundleID: bid, shortVersion: shortVer, buildVersion: buildVer, infoPlist: formattedPlist)
    }

    // MARK: - Deep Metadata (Code Signing, Launch Origin, Modules)

    struct CodeSigningResult {
        let status: SignatureStatus
        let authority: String?
        let teamIdentifier: String?
        let identifier: String?
        let entitlements: [(key: String, value: String)]?
    }

    static func fetchCodeSigningInfo(pid: Int32, executablePath: String) -> CodeSigningResult {
        var code: SecCode?
        let attrs = [kSecGuestAttributePid: pid] as CFDictionary
        let guestStatus = SecCodeCopyGuestWithAttributes(nil, attrs, [], &code)

        var staticCode: SecStaticCode?
        if guestStatus == errSecSuccess, let c = code {
            _ = SecCodeCopyStaticCode(c, [], &staticCode)
        }

        if staticCode == nil && !executablePath.isEmpty {
            let url = URL(fileURLWithPath: executablePath) as CFURL
            _ = SecStaticCodeCreateWithPath(url, [], &staticCode)
        }

        guard let sc = staticCode else {
            return CodeSigningResult(status: .unavailable, authority: nil, teamIdentifier: nil, identifier: nil, entitlements: nil)
        }

        var info: CFDictionary?
        let flags: SecCSFlags = [SecCSFlags(rawValue: kSecCSSigningInformation), SecCSFlags(rawValue: kSecCSRequirementInformation)]
        let infoStatus = SecCodeCopySigningInformation(sc, flags, &info)

        if infoStatus != errSecSuccess {
            if infoStatus == errSecCSUnsigned {
                return CodeSigningResult(status: .unsigned, authority: nil, teamIdentifier: nil, identifier: nil, entitlements: nil)
            }
            return CodeSigningResult(status: .unavailable, authority: nil, teamIdentifier: nil, identifier: nil, entitlements: nil)
        }

        guard let dict = info as? [String: Any] else {
            return CodeSigningResult(status: .unavailable, authority: nil, teamIdentifier: nil, identifier: nil, entitlements: nil)
        }

        let validStatus = SecStaticCodeCheckValidity(sc, [], nil)
        let certs = dict[kSecCodeInfoCertificates as String] as? [SecCertificate]
        let status: SignatureStatus
        if validStatus == errSecSuccess {
            if let certs = certs, !certs.isEmpty {
                status = .valid
            } else {
                status = .adHoc
            }
        } else if validStatus == errSecCSUnsigned {
            status = .unsigned
        } else {
            status = .invalid
        }

        var authorityName: String? = nil
        if let certs = certs, let first = certs.first {
            var commonName: CFString?
            SecCertificateCopyCommonName(first, &commonName)
            if let cn = commonName as String? {
                authorityName = cn
            }
        }

        let teamID = dict[kSecCodeInfoTeamIdentifier as String] as? String
        let identifier = dict[kSecCodeInfoIdentifier as String] as? String
        var entitlementsList: [(key: String, value: String)]? = nil
        if let entDict = dict[kSecCodeInfoEntitlementsDict as String] as? [String: Any] {
            entitlementsList = ProcessIdentity.formatPlistDict(entDict)
        }

        return CodeSigningResult(
            status: status,
            authority: authorityName,
            teamIdentifier: teamID,
            identifier: identifier,
            entitlements: entitlementsList
        )
    }

    private static var cachedJobs: (timestamp: Date, map: [Int32: String])?
    private static let cacheLock = NSLock()

    static func fetchLaunchctlJobs() -> [Int32: String] {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let cached = cachedJobs, Date().timeIntervalSince(cached.timestamp) < 3.0 {
            return cached.map
        }
        guard let output = run("/bin/launchctl", ["list"]) else {
            return cachedJobs?.map ?? [:]
        }
        var jobs: [Int32: String] = [:]
        for line in output.components(separatedBy: "\n").dropFirst() {
            let parts = line.split(separator: "\t")
            if parts.count >= 3, let pid = Int32(parts[0]) {
                jobs[pid] = String(parts[2])
            }
        }
        cachedJobs = (timestamp: Date(), map: jobs)
        return jobs
    }

    static func fetchLaunchOrigin(pid: Int32, parentPid: Int32, executablePath: String) -> String {
        let jobs = fetchLaunchctlJobs()
        if let label = jobs[pid] {
            let daemonPaths = [
                "/Library/LaunchDaemons/\(label).plist",
                "/System/Library/LaunchDaemons/\(label).plist"
            ]
            if daemonPaths.contains(where: { FileManager.default.fileExists(atPath: $0) }) {
                return "LaunchDaemon (\(label))"
            }

            let home = NSHomeDirectory()
            let agentPaths = [
                "/Library/LaunchAgents/\(label).plist",
                "\(home)/Library/LaunchAgents/\(label).plist",
                "/System/Library/LaunchAgents/\(label).plist"
            ]
            if agentPaths.contains(where: { FileManager.default.fileExists(atPath: $0) }) {
                return "LaunchAgent (\(label))"
            }

            if label.hasPrefix("application.") {
                let appName = label.components(separatedBy: ".").dropFirst().first ?? label
                return "Application (\(appName))"
            }

            return "launchd Job (\(label))"
        }

        if executablePath.contains("/Contents/Library/LoginItems/") {
            let name = (executablePath as NSString).lastPathComponent
            return "Login Item (\(name))"
        }

        if executablePath.contains("/LaunchDaemons/") {
            return "LaunchDaemon"
        }
        if executablePath.contains("/LaunchAgents/") {
            return "LaunchAgent"
        }

        if parentPid == 1 {
            if executablePath.hasPrefix("/System/") || executablePath.hasPrefix("/usr/libexec/") {
                return "System Service (PID 1)"
            }
            return "launchd (PID 1)"
        }

        if parentPid > 1 {
            return "Interactive (PID \(parentPid))"
        }

        return "Unavailable"
    }

    static func fetchLoadedModules(pid: Int32) -> (modules: [LoadedModule], error: String?) {
        guard let output = runWithStderr("/usr/bin/vmmap", ["-submap", "\(pid)"]) else {
            return ([], "Inspection restricted or process ended")
        }
        if output.status != 0 {
            if output.stderr.contains("privileges") || output.stderr.contains("mach port") {
                return ([], "Unavailable (requires privileges or target is restricted)")
            }
            return ([], "Unavailable (error code \(output.status))")
        }
        var modules: [LoadedModule] = []
        var seenPaths = Set<String>()
        for line in output.stdout.components(separatedBy: "\n") {
            guard line.contains(".dylib") || line.contains(".framework") else { continue }
            let path: String
            if let smRange = line.range(of: "SM=") {
                let afterSM = line[smRange.upperBound...]
                if let slash = afterSM.firstIndex(of: "/") {
                    path = String(afterSM[slash...]).trimmingCharacters(in: .whitespaces)
                } else { continue }
            } else if let spaceSlash = line.range(of: " /", options: .backwards) {
                path = String(line[line.index(after: spaceSlash.lowerBound)...]).trimmingCharacters(in: .whitespaces)
            } else {
                continue
            }
            guard !path.isEmpty, !seenPaths.contains(path) else { continue }
            seenPaths.insert(path)
            let name = (path as NSString).lastPathComponent
            modules.append(LoadedModule(name: name, path: path))
        }
        return (modules.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }, nil)
    }

    static func runWithStderr(_ path: String, _ args: [String]) -> (stdout: String, stderr: String, status: Int32)? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = args
        let outPipe = Pipe()
        let errPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = errPipe
        do {
            try task.run()
        } catch {
            return nil
        }
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        let outStr = String(data: outData, encoding: .utf8) ?? ""
        let errStr = String(data: errData, encoding: .utf8) ?? ""
        return (stdout: outStr, stderr: errStr, status: task.terminationStatus)
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
        return fetchArgsAndEnvironment(pid: pid)?.environment ?? []
    }

    // MARK: - Helpers

    private static func splitAddr(_ s: String) -> (String, String) {
        guard let i = s.lastIndex(of: ":") else { return (s, "") }
        return (String(s[..<i]), String(s[s.index(after: i)...]))
    }

    static func run(_ path: String, _ args: [String], requireSuccess: Bool = false) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = args
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
        } catch {
            return nil
        }
        // Drain stdout before waiting so large file lists cannot fill the pipe.
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        if requireSuccess && task.terminationStatus != 0 { return nil }
        return String(data: output, encoding: .utf8)
    }
}
