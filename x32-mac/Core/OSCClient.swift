import Foundation
import Network
import os

private nonisolated let log = Logger(subsystem: "com.walters-short.x32-mac", category: "OSCClient")

@MainActor
@Observable
final class OSCClient {
    static let x32Port: UInt16 = 10023
    static let xremoteInterval: TimeInterval = 9.0

    private(set) var isConnected = false
    private var connection: NWConnection?
    private var xremoteTimer: Timer?
    var messageHandler: ((OSCMessage) -> Void)?

    func connect(to host: String) async throws {
        disconnect()
        log.info("connecting to \(host, privacy: .public):\(OSCClient.x32Port)")
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: OSCClient.x32Port)!
        )
        let conn = NWConnection(to: endpoint, using: .udp)
        self.connection = conn
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    c.resume()
                case .failed(let err):
                    log.error("connection failed: \(err.localizedDescription, privacy: .public)")
                    c.resume(throwing: err)
                case .cancelled:
                    c.resume(throwing: CancellationError())
                default:
                    break
                }
            }
            conn.start(queue: .main)
        }
        conn.stateUpdateHandler = nil
        log.info("connection ready")
        startReceiving(on: conn)
        isConnected = true
        startXRemote()
    }

    func disconnect() {
        if connection != nil { log.info("disconnecting") }
        xremoteTimer?.invalidate()
        xremoteTimer = nil
        connection?.cancel()
        connection = nil
        isConnected = false
    }

    func send(_ message: OSCMessage) {
        guard let conn = connection else { return }
        log.debug("send \(message.address, privacy: .public)")
        conn.send(content: message.encode(), completion: .idempotent)
    }

    // Send and wait for the next reply (any address) within timeout
    func request(_ message: OSCMessage, timeout: TimeInterval = 2.0) async throws -> OSCMessage {
        try await withTimeout(seconds: timeout) {
            try await withCheckedThrowingContinuation { @MainActor continuation in
                // Install handler BEFORE sending so a fast localhost reply isn't missed
                let existing = self.messageHandler
                self.messageHandler = { msg in
                    self.messageHandler = existing
                    continuation.resume(returning: msg)
                }
                self.send(message)
            }
        }
    }

    // MARK: - Private

    private func startReceiving(on conn: NWConnection) {
        conn.receiveMessage { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data {
                if let msg = OSCMessage.decode(data) {
                    log.debug("recv \(msg.address, privacy: .public)")
                    self.messageHandler?(msg)
                } else {
                    log.error("failed to decode \(data.count) byte packet")
                }
            }
            if let error {
                log.error("receive error: \(error.localizedDescription, privacy: .public)")
            } else {
                self.startReceiving(on: conn)
            }
        }
    }

    private func startXRemote() {
        send(OSCMessage("/xremote"))
        xremoteTimer = Timer.scheduledTimer(withTimeInterval: OSCClient.xremoteInterval, repeats: true) { [weak self] _ in
            self?.send(OSCMessage("/xremote"))
        }
    }
}

// MARK: - Timeout helper

private func withTimeout<T: Sendable>(seconds: TimeInterval, operation: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw URLError(.timedOut)
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
