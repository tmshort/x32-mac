import Foundation

// OSC message over UDP. All integers/floats are big-endian.
struct OSCMessage {
    let address: String
    let arguments: [OSCArgument]

    enum OSCArgument {
        case int(Int32)
        case float(Float)
        case string(String)
        case blob(Data)
    }

    init(_ address: String, _ arguments: OSCArgument...) {
        self.address = address
        self.arguments = arguments
    }

    init(_ address: String, arguments: [OSCArgument] = []) {
        self.address = address
        self.arguments = arguments
    }

    // MARK: - Encoding

    func encode() -> Data {
        var data = Data()
        data.append(contentsOf: oscString(address))
        var typeTag = ","
        for arg in arguments {
            switch arg {
            case .int:    typeTag += "i"
            case .float:  typeTag += "f"
            case .string: typeTag += "s"
            case .blob:   typeTag += "b"
            }
        }
        data.append(contentsOf: oscString(typeTag))
        for arg in arguments {
            switch arg {
            case .int(let v):
                var be = v.bigEndian
                data.append(contentsOf: withUnsafeBytes(of: &be, Array.init))
            case .float(let v):
                var bits = v.bitPattern.bigEndian
                data.append(contentsOf: withUnsafeBytes(of: &bits, Array.init))
            case .string(let s):
                data.append(contentsOf: oscString(s))
            case .blob(let b):
                var len = Int32(b.count).bigEndian
                data.append(contentsOf: withUnsafeBytes(of: &len, Array.init))
                data.append(b)
                let pad = (4 - (b.count % 4)) % 4
                data.append(contentsOf: [UInt8](repeating: 0, count: pad))
            }
        }
        return data
    }

    private func oscString(_ s: String) -> [UInt8] {
        var bytes = Array(s.utf8) + [0]
        let pad = (4 - (bytes.count % 4)) % 4
        bytes.append(contentsOf: [UInt8](repeating: 0, count: pad))
        return bytes
    }

    // MARK: - Decoding

    static func decode(_ input: Data) -> OSCMessage? {
        // Offsets below are zero-based; rebase slices so startIndex == 0
        let data = input.startIndex == 0 ? input : Data(input)
        var offset = 0
        guard let address = readString(data, offset: &offset) else { return nil }
        guard let typeTag = readString(data, offset: &offset), typeTag.hasPrefix(",") else {
            return OSCMessage(address)
        }
        var args: [OSCArgument] = []
        for ch in typeTag.dropFirst() {
            switch ch {
            case "i":
                guard offset + 4 <= data.count else { return nil }
                args.append(.int(Int32(bitPattern: UInt32(bigEndian: readU32(data, at: offset))))); offset += 4
            case "f":
                guard offset + 4 <= data.count else { return nil }
                args.append(.float(Float(bitPattern: UInt32(bigEndian: readU32(data, at: offset))))); offset += 4
            case "s":
                guard let s = readString(data, offset: &offset) else { return nil }
                args.append(.string(s))
            case "b":
                guard offset + 4 <= data.count else { return nil }
                let len = Int(Int32(bitPattern: UInt32(bigEndian: readU32(data, at: offset))))
                offset += 4
                guard offset + len <= data.count else { return nil }
                // Copy blob into fresh Data so startIndex == 0 for all downstream consumers
                args.append(.blob(Data(data[offset..<offset+len])))
                offset += len + (4 - (len % 4)) % 4
            default: break
            }
        }
        return OSCMessage(address, arguments: args)
    }

    // Safe unaligned 4-byte read — works on any Data slice regardless of startIndex
    private static func readU32(_ data: Data, at offset: Int) -> UInt32 {
        var v: UInt32 = 0
        withUnsafeMutableBytes(of: &v) { dst in
            _ = data.copyBytes(to: dst, from: offset..<(offset + 4))
        }
        return v
    }

    private static func readString(_ data: Data, offset: inout Int) -> String? {
        guard offset < data.count else { return nil }
        var end = offset
        while end < data.count && data[end] != 0 { end += 1 }
        let s = String(bytes: data[offset..<end], encoding: .utf8) ?? ""
        let total = end - offset + 1
        offset += total + (4 - (total % 4)) % 4
        return s
    }

    // MARK: - Convenience accessors

    var intValue: Int32? {
        if case .int(let v) = arguments.first { return v }
        return nil
    }
    var floatValue: Float? {
        if case .float(let v) = arguments.first { return v }
        return nil
    }
    var stringValue: String? {
        if case .string(let v) = arguments.first { return v }
        return nil
    }
}
