import SwiftUI

// MARK: - Scroll offset tracking

private struct ScrollOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

// MARK: - Data model

@MainActor
@Observable
final class SpectrographData {
    var history: [[Float]] = []
    var isRunning = false
    var historyDepth: Int = 3600 {
        didSet { if oldValue != historyDepth { history.removeAll() } }
    }
    var channelCount: Int = 32 {
        didSet { if oldValue != channelCount { history.removeAll() } }
    }

    private weak var connection: X32Connection?
    private var renewalTimer: Timer?

    func start(on conn: X32Connection) {
        guard !isRunning else { return }
        connection = conn
        isRunning = true
        sendSub(conn)
        conn.onMessage = { [weak self] msg in
            guard let self else { return }
            self.handle(msg)
        }
        renewalTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak self] _ in
            guard let self, let c = self.connection else { return }
            self.sendSub(c)
        }
    }

    func stop(from conn: X32Connection) {
        renewalTimer?.invalidate()
        renewalTimer = nil
        conn.onMessage = nil
        connection = nil
        isRunning = false
    }

    func fillWithTestData() {
        let cols = channelCount
        let depth = historyDepth
        let baseLevels: [Float] = (0..<cols).map { ch in
            switch ch % 8 {
            case 0: return 0.65
            case 1: return 0.55
            case 2, 3: return 0.40
            case 4, 5: return 0.30
            case 6: return 0.20
            default: return 0.05
            }
        }
        history = (0..<depth).map { row in
            let t = Float(row) / Float(depth)
            return (0..<cols).map { ch in
                let base  = baseLevels[ch]
                let swell = 0.15 * sin(Float.pi * 2 * t * 3 + Float(ch) * 0.4)
                let noise = Float.random(in: -0.06...0.06)
                let spike: Float = (row % (12 + ch % 7) == 0) ? Float.random(in: 0.15...0.35) : 0
                return max(0, min(1, base + swell + noise + spike))
            }
        }
    }

    private func sendSub(_ conn: X32Connection) {
        conn.send(OSCMessage("/meters", .string("/meters/1")))
    }

    private func handle(_ msg: OSCMessage) {
        guard msg.address.hasPrefix("/meters"),
              case .blob(let data) = msg.arguments.first,
              data.count > 4 else { return }
        history.append(parseFrame(data))
        if history.count > historyDepth {
            history.removeFirst()
        }
    }

    private func parseFrame(_ data: Data) -> [Float] {
        let cap = min(channelCount, (data.count - 4) / 4)
        var result = [Float](repeating: 0, count: channelCount)
        for i in 0..<cap {
            let offset = 4 + i * 4
            guard offset + 4 <= data.count else { break }
            var rawBits: UInt32 = 0
            _ = withUnsafeMutableBytes(of: &rawBits) { data.copyBytes(to: $0, from: offset..<(offset + 4)) }
            result[i] = Float(bitPattern: UInt32(bigEndian: rawBits))
        }
        return result
    }
}

// MARK: - View

struct SpectrographView: View {
    @Environment(X32Connection.self) private var connection
    @State private var data = SpectrographData()
    @State private var rowHeight: CGFloat = 4
    @State private var scrollOffset: CGFloat = 0

    private let labelH: CGFloat = 18

    // Duration presets: label → frame count (at 50 ms/frame)
    private let durations: [(String, Int)] = [
        ("30 s",  600),
        ("1 min", 1200),
        ("2 min", 2400),
        ("3 min", 3600),
    ]

    var body: some View {
        // Capture @Observable state in @MainActor body so Canvas closure
        // reads plain captured locals (not MainActor-isolated properties)
        let snapshot    = data.history
        let cols        = data.channelCount
        let rH          = rowHeight
        let lH          = labelH
        let canvasH     = lH + CGFloat(data.historyDepth) * rH
        let offset      = scrollOffset

        VStack(spacing: 0) {
            controlBar
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            Divider()

            // GeometryReader gives us the viewport height for culling
            GeometryReader { geo in
                let viewportH = geo.size.height

                ScrollView(.vertical, showsIndicators: true) {
                    Canvas { ctx, size in
                        let cW = size.width / CGFloat(cols)

                        // Only draw what falls within [offset, offset+viewportH]
                        // Labels occupy y ∈ [0, lH)
                        if offset < lH {
                            for ch in 0..<cols {
                                ctx.draw(
                                    Text("\(ch + 1)")
                                        .font(.system(size: min(9, cW * 0.55),
                                                      weight: .medium, design: .monospaced))
                                        .foregroundColor(.secondary),
                                    at: CGPoint(x: (CGFloat(ch) + 0.5) * cW, y: lH / 2)
                                )
                            }
                        }

                        // Row i (newest=0) sits at y ∈ [lH + i*rH, lH + (i+1)*rH)
                        let firstRow = max(0, Int((offset - lH) / rH))
                        let lastRow  = min(snapshot.count - 1,
                                          Int((offset + viewportH - lH) / rH) + 1)
                        guard firstRow <= lastRow else { return }

                        let reversedSnapshot = snapshot.reversed() as ReversedCollection
                        for i in firstRow...lastRow {
                            guard i < reversedSnapshot.count else { break }
                            let frame = reversedSnapshot[reversedSnapshot.index(reversedSnapshot.startIndex, offsetBy: i)]
                            let y = lH + CGFloat(i) * rH
                            for ch in 0..<min(cols, frame.count) {
                                ctx.fill(
                                    Path(CGRect(x: CGFloat(ch) * cW, y: y,
                                                width: cW + 0.5, height: rH + 0.5)),
                                    with: .color(heatColor(frame[ch]))
                                )
                            }
                        }
                    }
                    .background(Color.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: canvasH)
                    // Report canvas position within the scroll coordinate space
                    .background(
                        GeometryReader { inner in
                            Color.clear.preference(
                                key: ScrollOffsetKey.self,
                                value: -inner.frame(in: .named("scroll")).minY
                            )
                        }
                    )
                }
                .coordinateSpace(name: "scroll")
                .onPreferenceChange(ScrollOffsetKey.self) { scrollOffset = max(0, $0) }
            }
        }
        .navigationTitle("Spectrograph")
        .onAppear  { data.start(on: connection) }
        .onDisappear { data.stop(from: connection) }
    }

    @ViewBuilder
    private var controlBar: some View {
        HStack(spacing: 12) {
            Stepper(
                "Channels: \(data.channelCount)",
                value: Binding(get: { data.channelCount }, set: { data.channelCount = $0 }),
                in: 1...96
            )
            .frame(width: 175)

            Stepper(
                "Row: \(Int(rowHeight))px",
                value: $rowHeight,
                in: 2...12,
                step: 1
            )
            .frame(width: 150)

            Text("History:")
                .foregroundStyle(.secondary)
            Picker("", selection: Binding(
                get: { data.historyDepth },
                set: { data.historyDepth = $0 }
            )) {
                ForEach(durations, id: \.1) { label, frames in
                    Text(label).tag(frames)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 90)
            .labelsHidden()

            Spacer()

            Button("Test Data") { data.fillWithTestData() }
                .buttonStyle(.bordered)

            Button {
                if data.isRunning { data.stop(from: connection) }
                else              { data.start(on: connection) }
            } label: {
                Label(data.isRunning ? "Stop" : "Start",
                      systemImage: data.isRunning ? "stop.fill" : "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(data.isRunning ? .red : .green)

            Button("Clear") { data.history.removeAll() }
                .buttonStyle(.bordered)
        }
    }

    private func heatColor(_ level: Float) -> Color {
        let l = Double(max(0, min(1, level)))
        guard l > 0.005 else { return Color(white: 0.06) }
        let hue = 0.333 * (1.0 - l)
        let brightness = 0.25 + 0.75 * l
        return Color(hue: hue, saturation: 1.0, brightness: brightness)
    }
}
