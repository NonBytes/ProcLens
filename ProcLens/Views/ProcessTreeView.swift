import SwiftUI

struct ProcessTreeView: View {
    let rootNodes: [ProcessTreeNode]
    @Binding var selectedPID: Int32?
    @Environment(ProcessManager.self) private var processManager

    var body: some View {
        List(rootNodes, id: \.id, children: \.children, selection: $selectedPID) { node in
            HStack(spacing: 6) {
                Image(nsImage: IconProvider.shared.appIcon(for: node.process))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)

                Text(node.process.name)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if processManager.historyTracker.hasMeaningfulCPU(for: node.process.pid) {
                    SparklineView(
                        values: processManager.historyTracker.cpuHistory(for: node.process.pid),
                        color: cpuColor(node.process.cpuUsage)
                    )
                    .frame(width: 40, height: 14)
                }

                Text(node.process.formattedCPU)
                    .monospacedDigit()
                    .foregroundStyle(cpuColor(node.process.cpuUsage))
                    .frame(width: 55, alignment: .trailing)

                Text(node.process.formattedMemory)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 75, alignment: .trailing)

                Text("\(node.process.pid)")
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                    .frame(width: 55, alignment: .trailing)
            }
            .font(.callout)
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }

    private func cpuColor(_ usage: Double) -> Color {
        if usage > 80 { return .red }
        if usage > 50 { return .orange }
        if usage > 10 { return .yellow }
        return .primary
    }
}
