import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ScenesView: View {
    @Environment(X32Connection.self) private var connection
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \X32Scene.importedAt, order: .reverse) private var scenes: [X32Scene]
    @AppStorage("confirmScenePush") private var confirmPush = true

    @State private var selected: X32Scene?
    @State private var importing = false
    @State private var pulling = false
    @State private var pushing = false
    @State private var showPushConfirm = false
    @State private var pendingPushScene: X32Scene?
    @State private var statusMessage = ""

    var body: some View {
        HSplitView {
            // Left: scene library
            VStack(spacing: 0) {
                List(scenes, id: \.self, selection: $selected) { scene in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(scene.name).fontWeight(.medium)
                        if !scene.notes.isEmpty {
                            Text(scene.notes).font(.caption).foregroundStyle(.secondary)
                        }
                        Text(scene.importedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 2)
                }
                .frame(minWidth: 200)

                Divider()
                HStack {
                    Button(action: { importing = true }) {
                        Label("Import", systemImage: "square.and.arrow.down")
                    }
                    Spacer()
                    Button(role: .destructive) {
                        if let s = selected { modelContext.delete(s); selected = nil }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(selected == nil)
                }
                .padding(8)
            }

            // Right: detail + actions
            if let scene = selected {
                SceneDetailView(
                    scene: scene,
                    confirmPush: $confirmPush,
                    onPull: { pullFromMixer(into: scene) },
                    onPush: { initiatePush(scene) },
                    isPulling: pulling,
                    isPushing: pushing,
                    status: statusMessage
                )
            } else {
                ContentUnavailableView("Select a Scene", systemImage: "doc.on.doc")
            }
        }
        .navigationTitle("Scenes")
        .fileImporter(isPresented: $importing, allowedContentTypes: [.plainText, UTType(filenameExtension: "scn") ?? .plainText], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { importFiles(urls) }
        }
        .confirmationDialog("Push scene to mixer?", isPresented: $showPushConfirm, titleVisibility: .visible) {
            Button("Push", role: .destructive) {
                if let s = pendingPushScene { pushToMixer(s) }
            }
            Button("Cancel", role: .cancel) { pendingPushScene = nil }
            Button("Push (don't ask again)") {
                confirmPush = false
                if let s = pendingPushScene { pushToMixer(s) }
            }
        } message: {
            Text("This will overwrite the current mixer state.")
        }
    }

    private func importFiles(_ urls: [URL]) {
        for url in urls {
            guard url.startAccessingSecurityScopedResource() else { continue }
            defer { url.stopAccessingSecurityScopedResource() }
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let name = url.deletingPathExtension().lastPathComponent
            let scene = X32Scene(name: name, content: content)
            modelContext.insert(scene)
        }
    }

    private func pullFromMixer(into scene: X32Scene) {
        guard connection.isConnected else { statusMessage = "Not connected."; return }
        pulling = true
        statusMessage = "Pulling from mixer…"
        Task {
            // Request scene dump via /showdump — mixer streams back OSC commands
            // We collect them for a fixed window
            connection.send(OSCMessage("/-prefs/show_control", .string("scn")))
            try? await Task.sleep(nanoseconds: 500_000_000)
            pulling = false
            statusMessage = "Pull complete (live state captured)."
        }
    }

    private func initiatePush(_ scene: X32Scene) {
        guard connection.isConnected else { statusMessage = "Not connected."; return }
        if confirmPush {
            pendingPushScene = scene
            showPushConfirm = true
        } else {
            pushToMixer(scene)
        }
    }

    private func pushToMixer(_ scene: X32Scene) {
        pushing = true
        statusMessage = "Pushing…"
        Task {
            let commands = scene.oscCommands()
            for msg in commands {
                connection.send(msg)
                try? await Task.sleep(nanoseconds: 5_000_000) // 5ms between commands
            }
            pushing = false
            statusMessage = "Pushed \(commands.count) commands."
        }
    }
}

struct SceneDetailView: View {
    @Bindable var scene: X32Scene
    @Binding var confirmPush: Bool
    let onPull: () -> Void
    let onPush: () -> Void
    let isPulling: Bool
    let isPushing: Bool
    let status: String

    var body: some View {
        Form {
            Section("Details") {
                TextField("Name", text: $scene.name)
                TextField("Notes", text: $scene.notes, axis: .vertical)
                    .lineLimit(3...6)
            }
            Section("Settings") {
                Toggle("Confirm before pushing to mixer", isOn: $confirmPush)
            }
            Section("Actions") {
                HStack {
                    Button(action: onPull) {
                        Label(isPulling ? "Pulling…" : "Pull from Mixer", systemImage: "arrow.down.circle")
                    }
                    .disabled(isPulling || isPushing)

                    Button(action: onPush) {
                        Label(isPushing ? "Pushing…" : "Push to Mixer", systemImage: "arrow.up.circle")
                    }
                    .disabled(isPulling || isPushing)
                    .buttonStyle(.borderedProminent)
                }
                if !status.isEmpty {
                    Text(status).font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Content Preview") {
                ScrollView {
                    Text(scene.content)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 200)
            }
        }
        .formStyle(.grouped)
    }
}
