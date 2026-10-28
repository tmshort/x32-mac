import SwiftUI

// Remaps each channel strip's physical input source via /ch/XX/config/source
// Source values: 1–32 = local XLR inputs, 33–40 = aux, 41+ = AES/Dante/etc.
struct RoutingView: View {
    @Environment(X32Connection.self) private var connection
    @State private var sources: [Int] = Array(1...32)   // ch 1–32 → source index
    @State private var isLoading = false
    @State private var status = ""

    var body: some View {
        Form {
            Section {
                Text("Each channel strip's physical input source. Values 1–32 = local XLR, 33–40 = aux, 41+ = AES/Dante.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Channel Input Sources") {
                Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                    GridRow {
                        ForEach(1...8, id: \.self) { col in
                            Text("Ch \(col)")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    Divider().gridCellUnsizedAxes(.horizontal)
                    ForEach(0..<4, id: \.self) { row in
                        GridRow {
                            ForEach(0..<8, id: \.self) { col in
                                let ch = row * 8 + col
                                SourceCell(
                                    channel: ch + 1,
                                    source: $sources[ch],
                                    range: 1...64
                                )
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                HStack(spacing: 10) {
                    Button {
                        loadFromMixer()
                    } label: {
                        Label(isLoading ? "Loading…" : "Load from Mixer", systemImage: "arrow.down.circle")
                    }
                    .disabled(!connection.isConnected || isLoading)

                    Button {
                        pushToMixer()
                    } label: {
                        Label("Push to Mixer", systemImage: "arrow.up.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!connection.isConnected || isLoading)

                    Spacer()

                    Button("Reset 1–32") {
                        sources = Array(1...32)
                    }
                    .foregroundStyle(.secondary)
                }

                if !status.isEmpty {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Input Routing")
        .onAppear { if connection.isConnected { loadFromMixer() } }
    }

    private func loadFromMixer() {
        guard connection.isConnected else { status = "Not connected."; return }
        isLoading = true
        status = "Loading…"
        Task {
            for ch in 0..<32 {
                let addr = String(format: "/ch/%02d/config/source", ch + 1)
                if let reply = try? await connection.request(OSCMessage(addr), timeout: 0.5),
                   case .int(let v) = reply.arguments.first {
                    let i = ch
                    await MainActor.run { sources[i] = Int(v) }
                }
            }
            await MainActor.run { isLoading = false; status = "Loaded." }
        }
    }

    private func pushToMixer() {
        guard connection.isConnected else { status = "Not connected."; return }
        status = "Pushing…"
        Task {
            for ch in 0..<32 {
                let addr = String(format: "/ch/%02d/config/source", ch + 1)
                connection.send(OSCMessage(addr, .int(Int32(sources[ch]))))
                try? await Task.sleep(nanoseconds: 5_000_000)
            }
            await MainActor.run { status = "Pushed 32 channel sources." }
        }
    }
}

// MARK: - Source Cell

struct SourceCell: View {
    let channel: Int
    @Binding var source: Int
    let range: ClosedRange<Int>

    var body: some View {
        VStack(spacing: 3) {
            Text("Ch\(channel)")
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .foregroundStyle(.tertiary)

            HStack(spacing: 0) {
                Button { source = max(range.lowerBound, source - 1) } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 8, weight: .semibold))
                        .frame(width: 14, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Text("\(source)")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .frame(minWidth: 24)
                    .multilineTextAlignment(.center)

                Button { source = min(range.upperBound, source + 1) } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .frame(width: 14, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.primary.opacity(0.06))
            )
        }
        .frame(maxWidth: .infinity)
    }
}
