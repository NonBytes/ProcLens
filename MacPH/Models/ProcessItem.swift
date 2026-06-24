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
