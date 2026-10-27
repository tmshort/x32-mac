import SwiftUI

// X32 Custom Layer: maps each of 32 fader positions to a channel source
// OSC path: /-stat/userctrl/a/ch/XX -> channel number
struct RoutingView: View {
    @Environment(X32Connection.self) private var connection
    @State private var layer: LayerBank = .a
    @State private var assignments: [Int] = Array(1...32)  // fader position -> channel number
    @State private var isLoading = false
    @State private var status = ""

    enum LayerBank: String, CaseIterable {
        case a = "A", b = "B", c = "C"
    }

    var body: some View {
        Form {
            Section("User Layer") {
                Picker("Bank", selection: $layer) {
                    ForEach(LayerBank.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: layer) { loadFromMixer() }
            }

            Section("Fader Assignments") {
                Text("Each position maps to a channel input source (1–80).")
                    .font(.caption).foregroundStyle(.secondary)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 80)), count: 8)) {
                    ForEach(0..<32, id: \.self) { pos in
                        VStack(spacing: 2) {
                            Text("Pos \(pos + 1)").font(.caption2).foregroundStyle(.secondary)
                            TextField("", value: $assignments[pos], formatter: channelFormatter)
                                .textFieldStyle(.roundedBorder)
                                .multilineTextAlignment(.center)
                                .frame(width: 48)
                        }
                    }
                }
            }

            Section {
                HStack {
                    Button("Load from Mixer") { loadFromMixer() }
                        .disabled(!connection.isConnected || isLoading)
                    Button("Push to Mixer") { pushToMixer() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!connection.isConnected || isLoading)
                    Button("Reset (1–32)") {
                        assignments = Array(1...32)
                    }
                }
                if !status.isEmpty {
                    Text(status).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Channel Routing")
        .onAppear { if connection.isConnected { loadFromMixer() } }
    }

    private var channelFormatter: NumberFormatter {
        let f = NumberFormatter()
        f.minimum = 1; f.maximum = 80; f.allowsFloats = false
        return f
    }

    private func loadFromMixer() {
        guard connection.isConnected else { return }
        isLoading = true
        status = "Loading…"
        Task {
            let bankLower = layer.rawValue.lowercased()
            for pos in 0..<32 {
                let addr = String(format: "/-stat/userctrl/%@/ch/%02d", bankLower, pos + 1)
                if let reply = try? await connection.request(OSCMessage(addr), timeout: 0.5),
                   case .int(let v) = reply.arguments.first {
                    let idx = pos
                    await MainActor.run { assignments[idx] = Int(v) }
                }
            }
            await MainActor.run { isLoading = false; status = "Loaded layer \(layer.rawValue)." }
        }
    }

    private func pushToMixer() {
        guard connection.isConnected else { return }
        status = "Pushing…"
        Task {
            let bankLower = layer.rawValue.lowercased()
            for pos in 0..<32 {
                let addr = String(format: "/-stat/userctrl/%@/ch/%02d", bankLower, pos + 1)
                connection.send(OSCMessage(addr, .int(Int32(assignments[pos]))))
                try? await Task.sleep(nanoseconds: 5_000_000)
            }
            await MainActor.run { status = "Layer \(layer.rawValue) pushed to mixer." }
        }
    }
}
