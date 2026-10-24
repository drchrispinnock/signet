import SwiftUI

/// Thin strip at the bottom of the window: a coloured light and a line about the layer 1 node
/// and, while the network has Layer 2 on, a second line beneath it for the Layer 2 Michelson
/// node. The lines are a grid so hosts, levels and summaries line up in columns.
struct NodeStatusBar: View {
    let monitor: NodeMonitor
    var layer2: NodeMonitor? = nil

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 4) {
            GridRow { cells(monitor, label: "Layer 1:") }
            if let layer2, layer2.endpoint != nil {
                GridRow { cells(layer2, label: "Layer 2:") }
            }
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    /// One node's cells: light, label, host, head level and the summary, which takes the rest
    /// of the width. Clicking the host or summary checks that node again.
    @ViewBuilder
    private func cells(_ monitor: NodeMonitor, label: String) -> some View {
        NodeLight(monitor: monitor)
        Text(label).foregroundStyle(.secondary)
        NodeHostText(monitor: monitor, label: label)
        Text(monitor.status.level.map { "level \($0.formatted())" } ?? "")
            .foregroundStyle(.secondary)
            .monospacedDigit()
        Text(monitor.status.summary)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .contentShape(Rectangle())
            .onTapGesture { Task { await monitor.checkNow() } }
            .help(NodeHostText.helpText(for: monitor))
    }
}

private struct NodeLight: View {
    let monitor: NodeMonitor

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 9, height: 9)
            .overlay(Circle().strokeBorder(.black.opacity(0.15)))
            .accessibilityHidden(true)
    }

    private var color: Color {
        switch monitor.status.light {
        case .grey: .gray
        case .green: .green
        case .yellow: .yellow
        case .red: .red
        }
    }
}

private struct NodeHostText: View {
    let monitor: NodeMonitor
    let label: String

    private var host: String {
        guard let endpoint = monitor.endpoint else { return "—" }
        return endpoint.host() ?? endpoint.absoluteString
    }

    var body: some View {
        Text(host)
            .fontWeight(.medium)
            .contentShape(Rectangle())
            .onTapGesture { Task { await monitor.checkNow() } }
            .help(Self.helpText(for: monitor))
            .accessibilityLabel("\(label) \(host): \(monitor.status.summary)")
    }

    static func helpText(for monitor: NodeMonitor) -> String {
        var lines = [monitor.endpoint?.absoluteString ?? "No node", monitor.status.detail]
        if case .healthy(_, _, let latency) = monitor.status {
            lines.append("Reply in \(String(format: "%.2f", latency)) s")
        }
        if let checked = monitor.lastChecked {
            lines.append("Checked \(checked.formatted(date: .omitted, time: .standard))")
        }
        lines.append("Click to check again.")
        return lines.joined(separator: "\n")
    }
}

#Preview {
    NodeStatusBar(monitor: NodeMonitor(network: .mainnet), layer2: NodeMonitor(network: .mainnet, layer: .two))
}
