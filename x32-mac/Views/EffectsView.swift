import SwiftUI

struct EffectsView: View {
    var body: some View {
        TabView {
            CopyFXView()
                .tabItem { Label("Copy FX", systemImage: "doc.on.doc") }
            GEQView()
                .tabItem { Label("GEQ Copy/Reset", systemImage: "waveform") }
        }
        .navigationTitle("Effects & EQ")
    }
}

// MARK: - Copy FX

struct CopyFXView: View {
    @Environment(X32Connection.self) private var connection
    @State private var sourceSlot = 1
    @State private var destSlot = 2
    @State private var copyMode: CopyMode = .full
    @State private var status = ""

    enum CopyMode: String, CaseIterable {
        case full = "Full Effect"
        case sideA = "Side A Only"
        case sideB = "Side B Only"
        case reset = "Reset to Default"
    }

    var body: some View {
        Form {
            Section("Source / Destination") {
                HStack {
                    Picker("From", selection: $sourceSlot) {
                        ForEach(1...8, id: \.self) { Text("FX \($0)").tag($0) }
                    }
                    Image(systemName: "arrow.right")
                    Picker("To", selection: $destSlot) {
                        ForEach(1...8, id: \.self) { Text("FX \($0)").tag($0) }
                    }
                }
            }
            Section("Operation") {
                Picker("Mode", selection: $copyMode) {
                    ForEach(CopyMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.radioGroup)
            }
            Section {
                Button("Apply") { apply() }
                    .buttonStyle(.borderedProminent)
                    .disabled(copyMode != .reset && sourceSlot == destSlot)
                if !status.isEmpty {
                    Text(status).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func apply() {
        guard connection.isConnected else { status = "Not connected."; return }
        Task {
            switch copyMode {
            case .reset:
                // Set all parameters to 0 for the destination slot
                for par in 0..<64 {
                    let addr = String(format: "/fx/%d/par/%02d", destSlot, par)
                    connection.send(OSCMessage(addr, .float(0.0)))
                    try? await Task.sleep(nanoseconds: 5_000_000)
                }
                status = "Reset FX \(destSlot) to defaults."
            case .full, .sideA, .sideB:
                // Read all parameters from source, write to dest
                // X32 FX has up to 64 parameters per slot
                let parCount = 64
                let srcBase = "/fx/\(sourceSlot)/par"
                let dstBase = "/fx/\(destSlot)/par"
                var copied = 0
                for par in 0..<parCount {
                    let addr = String(format: "%@/%02d", srcBase, par)
                    if let reply = try? await connection.request(OSCMessage(addr)) {
                        let dst = String(format: "%@/%02d", dstBase, par)
                        switch reply.arguments.first {
                        case .float(let f): connection.send(OSCMessage(dst, .float(f)))
                        case .int(let i):   connection.send(OSCMessage(dst, .int(i)))
                        default: break
                        }
                        copied += 1
                        try? await Task.sleep(nanoseconds: 5_000_000)
                    }
                }
                status = "Copied \(copied) parameters from FX \(sourceSlot) → FX \(destSlot)."
            }
        }
    }
}

// MARK: - GEQ

struct GEQView: View {
    @Environment(X32Connection.self) private var connection
    @State private var sourceSlot = 1
    @State private var destSlot = 2
    @State private var operation: GEQOp = .copy
    @State private var includeMaster = false
    @State private var status = ""

    enum GEQOp: String, CaseIterable {
        case copy      = "Copy A → B"
        case copyB2A   = "Copy B → A"
        case reset     = "Reset to 0 dB"
    }

    // GEQ/TEQ band parameters for X32
    // GEQ: 31 bands, par 00-30 are gains
    // For dual (2-sided) GEQ, side A is par 00-30, side B is par 32-62
    private let bandCount = 31
    private let sideAOffset = 0
    private let sideBOffset = 32

    var body: some View {
        Form {
            Section("FX Slot") {
                HStack {
                    Picker("Slot", selection: $sourceSlot) {
                        ForEach(1...8, id: \.self) { Text("FX \($0)").tag($0) }
                    }
                    if operation == .copy || operation == .copyB2A {
                        Image(systemName: "arrow.right")
                        Picker("Dest", selection: $destSlot) {
                            ForEach(1...8, id: \.self) { Text("FX \($0)").tag($0) }
                        }
                    }
                }
            }
            Section("Operation") {
                Picker("", selection: $operation) {
                    ForEach(GEQOp.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.radioGroup)
                Toggle("Include master level", isOn: $includeMaster)
            }
            Section {
                Button("Apply") { applyGEQ() }
                    .buttonStyle(.borderedProminent)
                if !status.isEmpty {
                    Text(status).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func applyGEQ() {
        guard connection.isConnected else { status = "Not connected."; return }
        Task {
            let base = "/fx/\(sourceSlot)/par"
            let dbase = "/fx/\(destSlot)/par"

            switch operation {
            case .copy:
                for b in 0..<bandCount {
                    let src = String(format: "%@/%02d", base, sideAOffset + b)
                    if let r = try? await connection.request(OSCMessage(src)),
                       case .float(let v) = r.arguments.first {
                        let dst = String(format: "%@/%02d", dbase, sideBOffset + b)
                        connection.send(OSCMessage(dst, .float(v)))
                        try? await Task.sleep(nanoseconds: 5_000_000)
                    }
                }
                status = "Copied GEQ A → B in FX \(sourceSlot)."
            case .copyB2A:
                for b in 0..<bandCount {
                    let src = String(format: "%@/%02d", base, sideBOffset + b)
                    if let r = try? await connection.request(OSCMessage(src)),
                       case .float(let v) = r.arguments.first {
                        let dst = String(format: "%@/%02d", dbase, sideAOffset + b)
                        connection.send(OSCMessage(dst, .float(v)))
                        try? await Task.sleep(nanoseconds: 5_000_000)
                    }
                }
                status = "Copied GEQ B → A in FX \(sourceSlot)."
            case .reset:
                for b in 0..<bandCount {
                    for offset in [sideAOffset, sideBOffset] {
                        let addr = String(format: "%@/%02d", base, offset + b)
                        connection.send(OSCMessage(addr, .float(0.5))) // 0.5 = 0 dB for GEQ
                        try? await Task.sleep(nanoseconds: 5_000_000)
                    }
                }
                status = "Reset GEQ bands in FX \(sourceSlot)."
            }
        }
    }
}
