import SwiftUI

// X32 has 80 faders total:
// ch 01-32, aux 1-8, fxrtn 1-8, bus 01-16, mtx 1-6, dca 1-8, main LR/M
struct FaderGroup: Identifiable {
    let id: String
    let label: String
    let count: Int
    let oscPrefix: String  // e.g. "/ch/%02d/mix/fader"
}

let allFaderGroups: [FaderGroup] = [
    FaderGroup(id: "ch",    label: "Channels 1–32",  count: 32, oscPrefix: "/ch/%02d/mix/fader"),
    FaderGroup(id: "aux",   label: "Aux 1–8",        count: 8,  oscPrefix: "/auxin/%02d/mix/fader"),
    FaderGroup(id: "fxrtn", label: "FX Returns 1–8", count: 8,  oscPrefix: "/fxrtn/%02d/mix/fader"),
    FaderGroup(id: "bus",   label: "Buses 1–16",     count: 16, oscPrefix: "/bus/%02d/mix/fader"),
    FaderGroup(id: "mtx",   label: "Matrix 1–6",     count: 6,  oscPrefix: "/mtx/%02d/mix/fader"),
    FaderGroup(id: "dca",   label: "DCA 1–8",        count: 8,  oscPrefix: "/dca/%d/fader"),
    FaderGroup(id: "main",  label: "Main L/R",       count: 1,  oscPrefix: "/main/st/mix/fader"),
]

struct LiveControlView: View {
    var body: some View {
        TabView {
            FadeView()
                .tabItem { Label("Fade", systemImage: "slider.vertical.3") }
            AutomixView()
                .tabItem { Label("Automix", systemImage: "waveform.path.ecg") }
            TapTempoView()
                .tabItem { Label("Tap Tempo", systemImage: "hand.tap") }
        }
        .navigationTitle("Live Control")
    }
}

// MARK: - Fade

struct FadeView: View {
    @Environment(X32Connection.self) private var connection
    @State private var selectedGroups: Set<String> = ["ch", "bus", "dca", "main"]
    @State private var fadeDuration: Double = 3.0
    @State private var steps: Int = 30
    @State private var isFading = false
    @State private var fadeTask: Task<Void, Never>?
    @State private var targetLevel: Float = 0.0 // 0.0 = -inf, 0.75 = 0dB, 1.0 = +10dB

    private let levelOptions: [(String, Float)] = [
        ("-∞ (silence)", 0.0), ("-10 dB", 0.5), ("0 dB", 0.75), ("+5 dB", 0.875)
    ]

    var body: some View {
        Form {
            Section("Target Level") {
                Picker("Fade to", selection: $targetLevel) {
                    ForEach(levelOptions, id: \.1) { label, val in
                        Text(label).tag(val)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Fader Groups") {
                ForEach(allFaderGroups) { group in
                    Toggle(group.label, isOn: Binding(
                        get: { selectedGroups.contains(group.id) },
                        set: { on in
                            if on { selectedGroups.insert(group.id) }
                            else  { selectedGroups.remove(group.id) }
                        }
                    ))
                }
            }

            Section("Timing") {
                HStack {
                    Text("Duration")
                    Slider(value: $fadeDuration, in: 0.5...30, step: 0.5)
                    Text("\(fadeDuration, specifier: "%.1f") s").frame(width: 50)
                }
                Stepper("Steps: \(steps)", value: $steps, in: 5...100, step: 5)
            }

            Section {
                HStack {
                    Button(isFading ? "Stop" : "Fade In") {
                        if isFading { stopFade() } else { startFade(to: targetLevel) }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(isFading ? .red : .blue)

                    Button("Fade Out") {
                        if isFading { stopFade() } else { startFade(to: 0.0) }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isFading)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func startFade(to level: Float) {
        isFading = true
        let groups = allFaderGroups.filter { selectedGroups.contains($0.id) }
        let n = steps
        let interval = fadeDuration / Double(n)

        fadeTask = Task {
            for step in 1...n {
                guard !Task.isCancelled else { break }
                let frac = Float(step) / Float(n)
                let current = level * frac
                for group in groups {
                    for i in 1...group.count {
                        let addr = String(format: group.oscPrefix, i)
                        connection.send(OSCMessage(addr, .float(current)))
                    }
                }
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
            await MainActor.run { isFading = false }
        }
    }

    private func stopFade() {
        fadeTask?.cancel()
        isFading = false
    }
}

// MARK: - Meter state (class so closures capture a reference, not a frozen struct copy)

@MainActor
@Observable
final class MeterMonitor {
    var levels: [Float] = Array(repeating: 0, count: 32)

    func subscribe(to connection: X32Connection) {
        connection.send(OSCMessage("/meters", .string("/meters/1")))
        connection.onMessage = { [weak self] msg in
            guard let self else { return }
            self.handle(msg)
        }
    }

    func unsubscribe(from connection: X32Connection) {
        connection.onMessage = nil
    }

    private func handle(_ msg: OSCMessage) {
        guard msg.address.hasPrefix("/meters"),
              case .blob(let data) = msg.arguments.first,
              data.count >= 4 else { return }
        levels = Self.parse(data)
    }

    // copyBytes avoids unaligned-load crashes on ARM
    private static func parse(_ data: Data) -> [Float] {
        var rawCount: Int32 = 0
        _ = withUnsafeMutableBytes(of: &rawCount) { data.copyBytes(to: $0, from: 0..<4) }
        let count = Int(Int32(bigEndian: rawCount))

        var result = [Float]()
        result.reserveCapacity(min(count, 32))
        for i in 0..<min(count, 32) {
            let offset = 4 + i * 4
            guard offset + 4 <= data.count else { break }
            var rawBits: UInt32 = 0
            _ = withUnsafeMutableBytes(of: &rawBits) { data.copyBytes(to: $0, from: offset..<(offset + 4)) }
            result.append(Float(bitPattern: UInt32(bigEndian: rawBits)))
        }
        return result
    }
}

// MARK: - Automix

struct MeterBarView: View {
    let level: Float
    let channel: Int

    var body: some View {
        VStack(spacing: 2) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 16, height: 60)
                RoundedRectangle(cornerRadius: 2)
                    .fill(level > 0.8 ? Color.red : level > 0.5 ? Color.orange : Color.green)
                    .frame(width: 16, height: CGFloat(level) * 60)
            }
            Text("\(channel)").font(.caption2)
        }
    }
}

struct AutomixView: View {
    @Environment(X32Connection.self) private var connection
    @State private var threshold: Float = -40.0
    @State private var releaseDelay: Double = 2.0
    @State private var channelStart = 1
    @State private var channelEnd = 8
    @State private var isRunning = false
    @State private var automixTask: Task<Void, Never>?
    @State private var monitor = MeterMonitor()

    var body: some View {
        Form {
            Section("Channel Range") {
                HStack {
                    Stepper("From: \(channelStart)", value: $channelStart, in: 1...32)
                    Spacer()
                    Stepper("To: \(channelEnd)", value: $channelEnd, in: 1...32)
                }
            }
            Section("Sensitivity") {
                HStack {
                    Text("Gate threshold")
                    Slider(value: $threshold, in: -80...0, step: 1)
                    Text("\(Int(threshold)) dB").frame(width: 60)
                }
                HStack {
                    Text("Release delay")
                    Slider(value: $releaseDelay, in: 0.1...10, step: 0.1)
                    Text(String(format: "%.1f s", releaseDelay)).frame(width: 50)
                }
            }
            Section("Level Meters") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8)) {
                    ForEach(channelStart...max(channelStart, channelEnd), id: \.self) { ch in
                        MeterBarView(
                            level: ch - 1 < monitor.levels.count ? monitor.levels[ch - 1] : 0,
                            channel: ch
                        )
                    }
                }
            }
            Section {
                Button(isRunning ? "Stop Automix" : "Start Automix") {
                    isRunning ? stopAutomix() : startAutomix()
                }
                .buttonStyle(.borderedProminent)
                .tint(isRunning ? .red : .green)
            }
        }
        .formStyle(.grouped)
        .onAppear { monitor.subscribe(to: connection) }
        .onDisappear { stopAutomix(); monitor.unsubscribe(from: connection) }
    }

    private func startAutomix() {
        isRunning = true
        let range = channelStart...max(channelStart, channelEnd)
        let thresh = threshold
        let delay = releaseDelay

        automixTask = Task {
            var lastActiveTime: [Int: Date] = [:]
            while !Task.isCancelled {
                for ch in range {
                    let level = ch - 1 < monitor.levels.count ? monitor.levels[ch - 1] : 0
                    let dbLevel = level > 0 ? 20 * log10(level) : -90.0
                    let addr = String(format: "/ch/%02d/mix/fader", ch)
                    if Float(dbLevel) > thresh {
                        lastActiveTime[ch] = Date()
                        connection.send(OSCMessage(addr, .float(0.75)))
                    } else if let t = lastActiveTime[ch], Date().timeIntervalSince(t) > delay {
                        connection.send(OSCMessage(addr, .float(0.0)))
                    }
                }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
    }

    private func stopAutomix() {
        automixTask?.cancel()
        isRunning = false
    }
}

// MARK: - Tap Tempo

struct TapTempoView: View {
    @Environment(X32Connection.self) private var connection
    @State private var fxSlot = 1
    @State private var tapTimes: [Date] = []
    @State private var bpm: Double? = nil
    @State private var lastDetectedEffect = ""
    @State private var isStereoDelay = false

    var body: some View {
        Form {
            Section("FX Slot") {
                Picker("Slot", selection: $fxSlot) {
                    ForEach(1...4, id: \.self) { Text("FX \($0)").tag($0) }
                }
                .pickerStyle(.segmented)
                if !lastDetectedEffect.isEmpty {
                    Text("Detected: \(lastDetectedEffect)").font(.caption).foregroundStyle(.secondary)
                }
            }
            Section {
                Button(action: tap) {
                    Text("TAP")
                        .font(.system(size: 48, weight: .bold))
                        .frame(maxWidth: .infinity, minHeight: 120)
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.space, modifiers: [])
            }
            if let bpm {
                Section("Tempo") {
                    HStack {
                        Text(String(format: "%.1f BPM", bpm)).font(.largeTitle.monospacedDigit())
                        Spacer()
                        Text(String(format: "%.0f ms", 60000 / bpm)).foregroundStyle(.secondary)
                    }
                    Button("Send to FX \(fxSlot)") { sendTempo() }
                        .buttonStyle(.borderedProminent)
                }
            }
            Section {
                Button("Reset") { tapTimes.removeAll(); bpm = nil }
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { detectEffect() }
        .onChange(of: fxSlot) { detectEffect() }
    }

    private func tap() {
        let now = Date()
        tapTimes.append(now)
        if tapTimes.count > 8 { tapTimes.removeFirst() }
        if tapTimes.count >= 2 {
            let intervals = zip(tapTimes, tapTimes.dropFirst()).map { $1.timeIntervalSince($0) }
            let avg = intervals.reduce(0, +) / Double(intervals.count)
            bpm = 60.0 / avg
        }
    }

    private func sendTempo() {
        guard let bpm, connection.isConnected else { return }
        let ms = 60000.0 / bpm
        // X32 delay time is a float 0.0-1.0 where 1.0 = 3000 ms (per X32TapW.c)
        let normalized = Float(min(max(ms / 3000.0, 0.0), 1.0))
        // Stereo Delay (type 10) uses par/02; all other delay types use par/01
        let par = isStereoDelay ? "02" : "01"
        connection.send(OSCMessage("/fx/\(fxSlot)/par/\(par)", .float(normalized)))
    }

    private func detectEffect() {
        guard connection.isConnected else { return }
        Task {
            if let reply = try? await connection.request(OSCMessage("/fx/\(fxSlot)/type")) {
                // X32 returns effect type as an integer enum
                let (name, stereo): (String, Bool)
                switch reply.intValue {
                case 10: (name, stereo) = ("Stereo Delay", true)
                case 11: (name, stereo) = ("3-Tap Delay", false)
                case 12: (name, stereo) = ("4-Tap Delay", false)
                case 21: (name, stereo) = ("Delay+Reverb", false)
                case 24: (name, stereo) = ("Delay+Chorus", false)
                case 25: (name, stereo) = ("Delay+Flanger", false)
                case 26: (name, stereo) = ("Mod Delay", false)
                default:
                    let label = reply.stringValue ?? reply.intValue.map { "type \($0)" } ?? "unknown"
                    (name, stereo) = (label, false)
                }
                await MainActor.run {
                    lastDetectedEffect = name
                    isStereoDelay = stereo
                }
            }
        }
    }
}
