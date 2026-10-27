import SwiftUI
import SwiftData

@main
struct x32_macApp: App {
    @State private var connection = X32Connection()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environment(connection)
                .frame(minWidth: 700, minHeight: 500)
        }
        .modelContainer(for: X32Scene.self)
        .commands {
            CommandGroup(after: .newItem) { }
        }
    }
}
