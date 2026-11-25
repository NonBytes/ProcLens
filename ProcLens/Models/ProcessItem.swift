import SwiftUI

enum ProcessStatus: Int8, CaseIterable, Comparable {
    case unknown = 0
    case idle = 1
    case running = 2
    case sleeping = 3
    case stopped = 4
    case zombie = 5

    static func < (lhs: ProcessStatus, rhs: ProcessStatus) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var displayName: String {
        switch self {
        case .idle: "Idle"
        case .running: "Running"
        case .sleeping: "Sleeping"
        case .stopped: "Stopped"
        case .zombie: "Zombie"
        case .unknown: "Unknown"
        }
    }

    var color: Color {
        switch self {
        case .running: .green
        case .sleeping: .secondary
        case .stopped: .orange
        case .zombie: .red
        case .idle: .blue
        case .unknown: .gray
        }
    }
}

struct ProcessItem: Identifiable, Hashable {
    var id: Int32 { pid }
    let pid: Int32
    let name: String
    let user: String
    var cpuUsage: Double
    var memoryUsage: UInt64
    var virtualMemory: UInt64
    var threadCount: Int32
    let status: ProcessStatus
    let path: String
    let parentPid: Int32
    var niceValue: Int32
    var diskReadBytes: UInt64
    var diskWriteBytes: UInt64
    var networkCounters: NetworkCounters? = nil
    var networkBytesReceived: UInt64 { networkCounters?.received ?? 0 }
    var networkBytesSent: UInt64 { networkCounters?.sent ?? 0 }
    var architecture: ProcessArchitecture = .unavailable
    var startTime: Date? = nil
    var ports: [String] = []
    var signatureStatus: SignatureStatus = .unavailable
    var signatureAuthority: String? = nil

    var memoryMB: Double {
        Double(memoryUsage) / 1_048_576.0
    }

    var formattedMemory: String {
        if memoryMB >= 1024 {
            return String(format: "%.1f GB", memoryMB / 1024)
        }
        return String(format: "%.1f MB", memoryMB)
    }

    var formattedCPU: String {
        String(format: "%.1f%%", cpuUsage)
    }

    var formattedDiskRead: String { Self.formatBytes(diskReadBytes) }
    var formattedDiskWrite: String { Self.formatBytes(diskWriteBytes) }

    var formattedPorts: String {
        ports.isEmpty ? "—" : ports.joined(separator: ", ")
    }

    var portsSortKey: Int {
        Int(ports.first ?? "0") ?? 0
    }

    var uptimeSeconds: TimeInterval {
        guard let startTime else { return 0 }
        return max(0, Date().timeIntervalSince(startTime))
    }

    var formattedUptime: String {
        guard startTime != nil else { return "—" }
        let sec = Int(uptimeSeconds)
        if sec < 60 {
            return "\(sec)s"
        } else if sec < 3600 {
            return "\(sec / 60)m \(sec % 60)s"
        } else if sec < 86400 {
            return "\(sec / 3600)h \((sec % 3600) / 60)m"
        } else {
            return "\(sec / 86400)d \((sec % 86400) / 3600)h"
        }
    }

    var archShortName: String {
        switch architecture {
        case .native: "arm64"
        case .rosetta: "x86_64"
        case .unavailable: "—"
        }
    }

    var archBadgeColor: Color {
        switch architecture {
        case .native: .purple
        case .rosetta: .orange
        case .unavailable: .secondary
        }
    }

    var signatureBadgeText: String {
        if let auth = signatureAuthority {
            if auth.contains("Apple") { return "Apple" }
            if auth.contains("Developer ID") { return "Developer" }
        }
        switch signatureStatus {
        case .valid: return "Valid"
        case .adHoc: return "Ad-hoc"
        case .unsigned: return "Unsigned"
        case .invalid: return "Invalid"
        case .unavailable: return "—"
        }
    }

    var signatureBadgeColor: Color {
        switch signatureStatus {
        case .valid: return .blue
        case .adHoc: return .teal
        case .unsigned: return .red
        case .invalid: return .red
        case .unavailable: return .secondary
        }
    }

    var formattedNice: String {
        niceValue == 0 ? "Normal (0)" : "\(niceValue)"
    }

    static func formatBytes(_ bytes: UInt64) -> String {
        let mb = Double(bytes) / 1_048_576
        if mb >= 1024 {
            return String(format: "%.1f GB", mb / 1024)
        }
        return String(format: "%.1f MB", mb)
    }
}
