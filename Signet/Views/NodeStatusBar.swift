import SwiftUI

/// Thin strip at the bottom of the window: a coloured light and a line about the node.
struct NodeStatusBar: View {
    let monitor: NodeMonitor

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 9, height: 9)
                .overlay(Circle().strokeBorder(.black.opacity(0.15)))
                .accessibilityHidden(true)
            Text("Node:")
                .foregroundStyle(.secondary)
            Text(monitor.network.rpcURL.host() ?? monitor.network.rpcURL.absoluteString)
                .fontWeight(.medium)
            if let level = monitor.status.level {
                Text("level \(level.formatted())")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer()
            Text(monitor.status.summary)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
        .contentShape(Rectangle())
        .onTapGesture { Task { await monitor.checkNow() } }
        .help(helpText)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Node \(monitor.network.rpcURL.host() ?? ""): \(monitor.status.summary)")
    }

    private var color: Color {
        switch monitor.status.light {
        case .grey: .gray
        case .green: .green
        case .yellow: .yellow
        case .red: .red
        }
    }

    private var helpText: String {
        var lines = [monitor.network.rpcURL.absoluteString, monitor.status.detail]
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
    NodeStatusBar(monitor: NodeMonitor(network: .mainnet))
}
