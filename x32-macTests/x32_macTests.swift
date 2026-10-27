//
//  x32_macTests.swift
//  x32-macTests
//
//  Created by Todd Short on 10/27/26.
//

import Foundation
import Testing
@testable import x32_mac

struct OSCMessageTests {

    @Test func encodesAddressOnlyMessageWithPadding() {
        let data = OSCMessage("/info").encode()
        // "/info\0" padded to 8 bytes, then ",\0\0\0"
        #expect(Array(data) == Array("/info".utf8) + [0, 0, 0] + [0x2C, 0, 0, 0])
    }

    @Test func encodesIntBigEndian() {
        let data = OSCMessage("/a", .int(1)).encode()
        #expect(Array(data.suffix(4)) == [0, 0, 0, 1])
    }

    @Test func roundTripsAllArgumentTypes() throws {
        let blob = Data([1, 2, 3, 4, 5])  // length not a multiple of 4 exercises padding
        let original = OSCMessage("/test/path", .int(-7), .float(0.75), .string("hello"), .blob(blob))
        let decoded = try #require(OSCMessage.decode(original.encode()))

        #expect(decoded.address == "/test/path")
        #expect(decoded.arguments.count == 4)
        guard decoded.arguments.count == 4 else { return }
        #expect(decoded.arguments[0].asInt == -7)
        #expect(decoded.arguments[1].asFloat == 0.75)
        #expect(decoded.arguments[2].asString == "hello")
        #expect(decoded.arguments[3].asBlob == blob)
    }

    @Test func decodesAddressWithoutTypeTag() throws {
        var data = Data("/xremote".utf8)
        data.append(contentsOf: [0, 0, 0, 0])
        let decoded = try #require(OSCMessage.decode(data))
        #expect(decoded.address == "/xremote")
        #expect(decoded.arguments.isEmpty)
    }

    @Test func decodesFromDataSliceWithNonZeroStartIndex() throws {
        let encoded = OSCMessage("/ch/01/mix/fader", .float(0.5)).encode()
        let padded = Data([0xFF, 0xFF, 0xFF]) + encoded
        let slice = padded.dropFirst(3)
        let decoded = try #require(OSCMessage.decode(slice))
        #expect(decoded.address == "/ch/01/mix/fader")
        #expect(decoded.floatValue == 0.5)
    }

    @Test func rejectsTruncatedArguments() {
        let encoded = OSCMessage("/a", .int(42)).encode()
        #expect(OSCMessage.decode(encoded.dropLast(2)) == nil)
    }

    @Test func rejectsEmptyData() {
        #expect(OSCMessage.decode(Data()) == nil)
    }
}

struct X32SceneTests {

    @Test func parsesCommandsAndSkipsCommentsAndBlanks() {
        let scene = X32Scene(name: "test", content: """
        #4.0# "Scene"
        # a comment

        /ch/01/config "Kick" 1 YE 1
        /ch/01/mix/fader 0.75
        """)
        let commands = scene.oscCommands()

        #expect(commands.count == 2)
        guard commands.count == 2 else { return }
        #expect(commands[0].address == "/ch/01/config")
        #expect(commands[0].arguments.count == 4)
        #expect(commands[0].arguments[0].asString == "Kick")
        #expect(commands[0].arguments[1].asInt == 1)
        #expect(commands[0].arguments[2].asString == "YE")
        #expect(commands[1].address == "/ch/01/mix/fader")
        #expect(commands[1].arguments[0].asFloat == 0.75)
    }
}

private extension OSCMessage.OSCArgument {
    var asInt: Int32? { if case .int(let v) = self { v } else { nil } }
    var asFloat: Float? { if case .float(let v) = self { v } else { nil } }
    var asString: String? { if case .string(let v) = self { v } else { nil } }
    var asBlob: Data? { if case .blob(let v) = self { v } else { nil } }
}
