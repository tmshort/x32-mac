import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case connection = "Connection"
    case scenes     = "Scenes"
    case liveControl = "Live Control"
    case effects    = "Effects & EQ"
    case routing    = "Channel Routing"
    case terminal   = "OSC Terminal"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .connection:  return "network"
        case .scenes:      return "doc.on.doc"
        case .liveControl: return "slider.horizontal.3"
        case .effects:     return "waveform"
        case .routing:     return "arrow.triangle.branch"
        case .terminal:    return "terminal"
        }
    }
}

struct ContentView: View {
    @Environment(X32Connection.self) private var connection
    @State private var selection: SidebarItem? = .connection

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selection) { item in
                Label(item.rawValue, systemImage: item.icon)
                    .tag(item)
            }
            .navigationTitle("X32 Control")
            Divider()
            connectionStatus
                .padding(.horizontal)
                .padding(.bottom, 8)
        } detail: {
            switch selection {
            case .connection, .none:
                ConnectionView()
            case .scenes:
                ScenesView()
            case .liveControl:
                LiveControlView()
            case .effects:
                EffectsView()
            case .routing:
                RoutingView()
            case .terminal:
                OSCTerminalView()
            }
        }
    }

    @ViewBuilder
    private var connectionStatus: some View {
        switch connection.status {
        case .disconnected:
            Label("Disconnected", systemImage: "circle.fill")
                .foregroundStyle(.secondary)
                .font(.caption)
        case .connecting:
            Label("Connecting…", systemImage: "circle.fill")
                .foregroundStyle(.orange)
                .font(.caption)
        case .connected(_, let name, let model):
            Label("\(model): \(name)", systemImage: "circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
        case .error(let msg):
            Label(msg, systemImage: "circle.fill")
                .foregroundStyle(.red)
                .font(.caption)
                .lineLimit(2)
        }
    }
}

#Preview {
    ContentView()
        .environment(X32Connection())
}
