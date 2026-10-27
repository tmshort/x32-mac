import SwiftUI

struct OSCEntry: Identifiable {
    let id = UUID()
    let direction: Direction
    let address: String
    let args: String
    let timestamp: Date

    enum Direction { case sent, received }
}

struct OSCTerminalView: View {
    @Environment(X32Connection.self) private var connection
    @State private var commandText = ""
    @State private var log: [OSCEntry] = []
    @State private var isMonitoring = false
    @State private var filterText = ""
    @State private var autoscroll = true

    private var filteredLog: [OSCEntry] {
        guard !filterText.isEmpty else { return log }
        return log.filter { $0.address.localizedCaseInsensitiveContains(filterText) ||
                             $0.args.localizedCaseInsensitiveContains(filterText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Log display
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(filteredLog) { entry in
                            HStack(spacing: 6) {
                                Image(systemName: entry.direction == .sent ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                                    .foregroundStyle(entry.direction == .sent ? .blue : .green)
                                    .font(.caption)
                                Text(entry.timestamp, format: .dateTime.hour().minute().second())
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                Text(entry.address)
                                    .font(.system(.caption, design: .monospaced))
                                    .fontWeight(.medium)
                                Text(entry.args)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 1)
                            .id(entry.id)
                        }
                    }
                }
                .background(Color(nsColor: .textBackgroundColor))
                .onChange(of: log.count) {
                    if autoscroll, let last = filteredLog.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }

            Divider()

            // Controls bar
            HStack {
                TextField("Filter", text: $filterText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 140)

                Toggle("Monitor", isOn: $isMonitoring)
                    .onChange(of: isMonitoring) { startOrStopMonitor() }

                Toggle("Autoscroll", isOn: $autoscroll)

                Spacer()

                Button("Clear") { log.removeAll() }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            Divider()

            // Input bar
            HStack {
                TextField("OSC address and args, e.g.  /ch/01/mix/fader 0.75", text: $commandText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit { sendCommand() }
                Button("Send") { sendCommand() }
                    .buttonStyle(.borderedProminent)
                    .disabled(commandText.isEmpty || !connection.isConnected)
            }
            .padding(8)
        }
        .navigationTitle("OSC Terminal")
    }

    private func sendCommand() {
        guard !commandText.isEmpty, connection.isConnected else { return }
        let parts = commandText.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard let address = parts.first else { return }
        var args: [OSCMessage.OSCArgument] = []
        for token in parts.dropFirst() {
            if let i = Int32(token)        { args.append(.int(i)) }
            else if let f = Float(token)   { args.append(.float(f)) }
            else                            { args.append(.string(token.trimmingCharacters(in: CharacterSet(charactersIn: "\"")))) }
        }
        let msg = OSCMessage(address, arguments: args)
        connection.send(msg)
        appendLog(OSCEntry(direction: .sent, address: address, args: parts.dropFirst().joined(separator: " "), timestamp: Date()))
        commandText = ""
    }

    private func startOrStopMonitor() {
        if isMonitoring {
            connection.client.messageHandler = { msg in
                let args = msg.arguments.map { arg -> String in
                    switch arg {
                    case .int(let v):    return "\(v)"
                    case .float(let v):  return String(format: "%.4f", v)
                    case .string(let s): return "\"\(s)\""
                    case .blob(let d):   return "<blob:\(d.count)>"
                    }
                }.joined(separator: " ")
                Task { @MainActor in
                    self.appendLog(OSCEntry(direction: .received, address: msg.address, args: args, timestamp: Date()))
                }
            }
        } else {
            connection.client.messageHandler = nil
        }
    }

    private func appendLog(_ entry: OSCEntry) {
        log.append(entry)
        if log.count > 1000 { log.removeFirst(log.count - 1000) }
    }
}
