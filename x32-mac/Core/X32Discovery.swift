import Foundation
import Network
import os

private nonisolated let log = Logger(subsystem: "com.walters-short.x32-mac", category: "X32Discovery")

struct DiscoveredDevice: Identifiable, Equatable {
    let id = UUID()
    let ip: String
    let name: String
    let model: String // "X32" or "XAir"
}

@MainActor
@Observable
final class X32Discovery {
    private(set) var devices: [DiscoveredDevice] = []
    private(set) var isScanning = false
    private var scanTask: Task<Void, Never>?

    func scan() {
        guard !isScanning else { return }
        devices.removeAll()
        isScanning = true
        scanTask = Task {
            await performScan()
            isScanning = false
        }
    }

    func cancel() {
        scanTask?.cancel()
        isScanning = false
    }

    // MARK: - Private

    private func performScan() async {
        // Broadcast /info and /xinfo to the subnet broadcast addresses
        let broadcastAddresses = ["255.255.255.255", "192.168.0.255", "192.168.1.255", "10.0.0.255"]
        let infoData = OSCMessage("/info").encode()
        let xinfoData = OSCMessage("/xinfo").encode()

        // Set up a listener on an ephemeral port to catch replies
        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true
        guard let listener = try? NWListener(using: params) else {
            log.error("could not create discovery listener")
            return
        }
        log.info("scanning \(broadcastAddresses.count) broadcast addresses")

        var found: [DiscoveredDevice] = []

        listener.newConnectionHandler = { conn in
            conn.start(queue: .main)
            conn.receiveMessage { data, context, _, _ in
                guard let data, let msg = OSCMessage.decode(data) else { return }
                // X32 /info reply: address, X32Name, Model, FirmwareVersion
                // XAir /xinfo reply: address, XAirName, Model, FirmwareVersion
                if msg.address == "/info" || msg.address == "/xinfo" {
                    let args = msg.arguments
                    let ip: String
                    if case .string(let s) = args.first { ip = s } else { return }
                    let name: String
                    if args.count > 1, case .string(let s) = args[1] { name = s } else { return }
                    let modelStr: String
                    if args.count > 2, case .string(let s) = args[2] { modelStr = s } else { return }
                    let kind = modelStr.lowercased().contains("xair") ? "XAir" : "X32"
                    let device = DiscoveredDevice(ip: ip, name: name, model: kind)
                    Task { @MainActor in
                        if !found.contains(device) {
                            found.append(device)
                        }
                    }
                }
            }
        }
        listener.start(queue: .main)

        // Send broadcasts
        for addr in broadcastAddresses {
            let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(addr), port: NWEndpoint.Port(rawValue: OSCClient.x32Port)!)
            for data in [infoData, xinfoData] {
                let conn = NWConnection(to: endpoint, using: .udp)
                conn.start(queue: .main)
                conn.send(content: data, completion: .contentProcessed { _ in conn.cancel() })
            }
        }

        // Wait up to 3 seconds for replies
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        listener.cancel()
        log.info("scan finished, found \(found.count) device(s)")
        self.devices = found
    }
}
