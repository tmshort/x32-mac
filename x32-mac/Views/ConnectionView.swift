import SwiftUI

struct ConnectionView: View {
    @Environment(X32Connection.self) private var connection
    @State private var discovery = X32Discovery()
    @State private var manualIP = ""
    @AppStorage("lastConnectedIP") private var lastIP = ""

    var body: some View {
        Form {
            Section("Auto-Discovery") {
                if discovery.isScanning {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Scanning network…").foregroundStyle(.secondary)
                    }
                } else if discovery.devices.isEmpty {
                    Text("No devices found yet.").foregroundStyle(.secondary)
                } else {
                    ForEach(discovery.devices) { device in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(device.name).fontWeight(.medium)
                                Text("\(device.model) — \(device.ip)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Connect") {
                                connectTo(device.ip)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(connection.isConnected && connection.connectedHost == device.ip)
                        }
                    }
                }
                Button(discovery.isScanning ? "Scanning…" : "Scan Network") {
                    discovery.scan()
                }
                .disabled(discovery.isScanning)
            }

            Section("Manual Connection") {
                HStack {
                    TextField("IP Address", text: $manualIP)
                        .textFieldStyle(.roundedBorder)
                        .onAppear { manualIP = lastIP }
                    Button("Connect") {
                        connectTo(manualIP)
                    }
                    .disabled(manualIP.isEmpty || connection.status == .connecting)
                }
            }

            if connection.isConnected {
                Section {
                    Button("Disconnect", role: .destructive) {
                        connection.disconnect()
                    }
                }
            }

            if case .error(let msg) = connection.status {
                Section {
                    Label(msg, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Connection")
        .onAppear {
            if !lastIP.isEmpty { manualIP = lastIP }
        }
    }

    private func connectTo(_ ip: String) {
        lastIP = ip
        Task { await connection.connect(host: ip) }
    }
}
