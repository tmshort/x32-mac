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

    /// Directed broadcast addresses for each up, non-loopback IPv4 interface, derived from its
    /// address and netmask, plus the limited broadcast address as a fallback.
    nonisolated static func localBroadcastAddresses() -> [String] {
        var addresses = ["255.255.255.255"]
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let first = ifaddrPtr else { return addresses }
        defer { freeifaddrs(first) }

        for ifa in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ifa.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_BROADCAST != 0, flags & IFF_LOOPBACK == 0,
                let addrPtr = ifa.pointee.ifa_addr, let maskPtr = ifa.pointee.ifa_netmask,
                addrPtr.pointee.sa_family == sa_family_t(AF_INET)
            else { continue }

            let ip = addrPtr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
            let mask = maskPtr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }

            let broadcast = ip | ~mask
            let text = "\(broadcast >> 24).\((broadcast >> 16) & 0xFF).\((broadcast >> 8) & 0xFF).\(broadcast & 0xFF)"
            if !addresses.contains(text) { addresses.append(text) }
        }
        return addresses
    }

    private func performScan() async {
        // Broadcast /info and /xinfo to the broadcast address of every local IPv4 interface
        let broadcastAddresses = Self.localBroadcastAddresses()
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
