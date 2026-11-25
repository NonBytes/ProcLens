import SwiftUI

enum ProcessColumn: String, CaseIterable, Identifiable, Codable, Hashable {
    case pid = "PID"
    case name = "Name"
    case cpu = "CPU %"
    case memory = "Memory"
    case received = "Received"
    case sent = "Sent"
    case user = "User"
    case threads = "Threads"
    case status = "Status"
    case ports = "Ports"
    case arch = "Arch"
    case diskRead = "Disk Read"
    case diskWrite = "Disk Write"
    case uptime = "Uptime"
    case signature = "Signature"
    case ppid = "PPID"

    var id: String { rawValue }

    var displayName: String { rawValue }

    var systemImage: String {
        switch self {
        case .pid: "number"
        case .name: "app.dashed"
        case .cpu: "cpu"
        case .memory: "memorychip"
        case .received: "arrow.down.circle"
        case .sent: "arrow.up.circle"
        case .user: "person"
        case .threads: "point.3.filled.connected.trianglepath.dotted"
        case .status: "circle.badge.checkmark"
        case .ports: "network"
        case .arch: "apple.terminal"
        case .diskRead: "opticaldiscdrive"
        case .diskWrite: "internaldrive"
        case .uptime: "clock"
        case .signature: "checkmark.seal"
        case .ppid: "arrow.triangle.branch"
        }
    }

    var defaultWidth: CGFloat {
        switch self {
        case .pid: 65
        case .name: 200
        case .cpu: 130
        case .memory: 90
        case .received: 90
        case .sent: 80
        case .user: 80
        case .threads: 65
        case .status: 84
        case .ports: 95
        case .arch: 75
        case .diskRead: 85
        case .diskWrite: 85
        case .uptime: 80
        case .signature: 100
        case .ppid: 60
        }
    }

    var minWidth: CGFloat {
        switch self {
        case .pid: 50
        case .name: 120
        case .cpu: 100
        case .memory: 70
        case .received: 75
        case .sent: 65
        case .user: 60
        case .threads: 55
        case .status: 70
        case .ports: 70
        case .arch: 65
        case .diskRead: 75
        case .diskWrite: 75
        case .uptime: 65
        case .signature: 80
        case .ppid: 50
        }
    }

    var isAlignmentTrailing: Bool {
        switch self {
        case .cpu, .memory, .received, .sent, .threads, .diskRead, .diskWrite, .uptime, .ppid:
            return true
        default:
            return false
        }
    }
}

enum ColumnSettings {
    /// Columns visible by default; the rest start hidden until shown via the
    /// table header's native right-click customization menu.
    static let defaultColumns: [ProcessColumn] = [
        .pid, .name, .cpu, .memory, .received, .sent, .user, .threads, .status, .ports, .arch
    ]
}
