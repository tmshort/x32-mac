import Foundation
import SwiftData

@Model
final class X32Scene {
    var name: String
    var notes: String
    var content: String  // raw .scn file text
    var importedAt: Date
    var tags: [String]

    init(name: String, notes: String = "", content: String, tags: [String] = []) {
        self.name = name
        self.notes = notes
        self.content = content
        self.importedAt = Date()
        self.tags = tags
    }

    // Parse OSC commands from scene file content
    func oscCommands() -> [OSCMessage] {
        var messages: [OSCMessage] = []
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("/"), !trimmed.hasPrefix("#") else { continue }
            let parts = trimmed.components(separatedBy: " ")
            guard let address = parts.first else { continue }
            var args: [OSCMessage.OSCArgument] = []
            for token in parts.dropFirst() {
                if let i = Int32(token) {
                    args.append(.int(i))
                } else if let f = Float(token) {
                    args.append(.float(f))
                } else {
                    let s = token.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                    args.append(.string(s))
                }
            }
            messages.append(OSCMessage(address, arguments: args))
        }
        return messages
    }
}
