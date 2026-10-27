import Foundation
import SwiftUI
import os

private nonisolated let log = Logger(subsystem: "com.walters-short.x32-mac", category: "X32Connection")

// Shared connection state injected via SwiftUI environment
@MainActor
@Observable
final class X32Connection {
    enum Status: Equatable {
        case disconnected
        case connecting
        case connected(host: String, name: String, model: String)
        case error(String)
    }

    private(set) var status: Status = .disconnected
    let client = OSCClient()

    var isConnected: Bool {
        if case .connected = status { return true }
        return false
    }

    var connectedHost: String? {
        if case .connected(let h, _, _) = status { return h }
        return nil
    }

    func connect(host: String) async {
        status = .connecting
        do {
            try await client.connect(to: host)
            // Query device info
            // /info reply: ,ssss  version  name  model  firmware
            let reply = try await client.request(OSCMessage("/info"))
            let name: String
            let model: String
            if reply.arguments.count > 1, case .string(let n) = reply.arguments[1] { name = n } else { name = "X32 Emulator" }
            if reply.arguments.count > 2, case .string(let m) = reply.arguments[2] { model = m } else { model = "X32" }
            status = .connected(host: host, name: name, model: model)
            log.info("connected to \(model, privacy: .public) \"\(name, privacy: .public)\" at \(host, privacy: .public)")
        } catch {
            log.error("connect to \(host, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            status = .error(error.localizedDescription)
        }
    }

    func disconnect() {
        client.disconnect()
        status = .disconnected
    }

    // Convenience: send without awaiting reply
    func send(_ msg: OSCMessage) {
        guard isConnected else { return }
        client.send(msg)
    }

    // Convenience: send and await reply
    func request(_ msg: OSCMessage, timeout: TimeInterval = 2.0) async throws -> OSCMessage {
        try await client.request(msg, timeout: timeout)
    }

    // Subscribe to all parameter changes via XRemote
    var onMessage: ((OSCMessage) -> Void)? {
        get { client.messageHandler }
        set { client.messageHandler = newValue }
    }
}
