# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

macOS-only SwiftUI app (deployment target macOS 26.5, Xcode 26.6) for remote control of a Behringer X32 / X Air mixer over OSC/UDP. Single scheme `x32-mac`, bundle id `com.walters-short.x32-mac`. The project is `x32-mac.xcodeproj` (no workspace, no SPM/CocoaPods dependencies, no `.xcconfig` files). App sandbox is disabled (`ENABLE_APP_SANDBOX = NO`), which is what allows UDP broadcast and local network access.

## Commands

Run from the repo root (`~/git/x32-mac/x32-mac`):

- Build: `xcodebuild -project x32-mac.xcodeproj -scheme x32-mac -destination 'platform=macOS' build 2>&1 | xcbeautify`
- All tests: `xcodebuild -project x32-mac.xcodeproj -scheme x32-mac -destination 'platform=macOS' test 2>&1 | xcbeautify`
- Single test: add `-only-testing:x32-macTests/x32_macTests/example` (format `Target/Suite/function`). Unit tests use Swift Testing (`@Test`, `#expect`), not XCTest. `x32-macUITests` uses XCTest UI tests and launches the app, so avoid running it unless needed.
- Build settings: `xcodebuild -project x32-mac.xcodeproj -scheme x32-mac -showBuildSettings`
- Lint/format: `xcrun swift-format lint -r x32-mac x32-macTests` (config in `.swift-format`; swift-format ships with Xcode). The existing code predates it and has ~150 findings (semicolons, spacing, blank lines), so don't reformat files you aren't otherwise changing. Format files you edit with `xcrun swift-format format -i <file>`.
- `/test [Suite/function]` runs the unit tests via `.claude/commands/test.md`.
- Xcode's MCP server is registered in `.mcp.json` (`xcrun mcpbridge`). It connects to a running Xcode (and may require enabling external agent/MCP access in Xcode's settings; unverified), and Claude Code asks you to approve project-scoped MCP servers the first time.

Run only the unit tests (skips the slow UI tests) with `-only-testing:x32-macTests`. Current coverage is `OSCMessage` encode/decode and `X32Scene.oscCommands()` parsing; there are no tests for `OSCClient`, `X32Connection`, or `X32Discovery` (they need a live socket or mixer). `x32-macUITests` is still the Xcode template stub.

A `Stop` hook (`.claude/hooks/build-check.sh`) builds at the end of a turn if any `.swift` file has uncommitted changes, and feeds build errors back. Do not hand-edit `project.pbxproj`; new Swift files in the existing synchronized folders should be picked up by Xcode, and structural project changes are best made in Xcode itself.

## Logs

The networking layer (`OSCClient`, `X32Connection`, `X32Discovery`) logs with `Logger`, subsystem `com.walters-short.x32-mac` and category equal to the class name. Sends and receives are logged at `debug` level (use `--level debug`). Use the same subsystem for new logging:

- Live: `log stream --predicate 'subsystem == "com.walters-short.x32-mac"' --level debug` (run in background or with a timeout; it never terminates)
- Past: `log show --last 5m --predicate 'subsystem == "com.walters-short.x32-mac"'`
- Crash logs: `~/Library/Logs/DiagnosticReports/`

## Architecture

Layering is `OSCMessage` (wire format) -> `OSCClient` (UDP transport) -> `X32Connection` (app-level state) -> SwiftUI views.

- **`Core/OSCMessage.swift`**: OSC encoder/decoder (big-endian ints/floats, 4-byte padded strings, blobs). Arguments are `.int(Int32)`, `.float`, `.string`, `.blob`.
- **`Core/OSCClient.swift`**: wraps one `NWConnection` (UDP) to port 10023. Two behaviors span the file and are easy to break:
  - It sends `/xremote` on connect and every 9 s. The X32 only pushes parameter changes to a client for about 10 s after each `/xremote`, so removing or slowing the timer silently stops incoming updates.
  - There is a single `messageHandler` for all incoming messages. `request(_:timeout:)` temporarily replaces it to capture the **next message of any address** (replies are not matched to the request address), then restores the previous handler. Concurrent requests, or unsolicited `/xremote` updates arriving mid-request, can be mistaken for the reply.
- **`Core/X32Connection.swift`**: `@MainActor @Observable` object created once in `x32_macApp` and injected with `.environment(connection)`. Views read it via `@Environment(X32Connection.self)`. It owns the `OSCClient`, publishes `status` (`disconnected / connecting / connected(host,name,model) / error`), and exposes `send` (fire-and-forget, ignored when not connected) and `request` (await reply). It populates device name/model from the `/info` reply.
- **`Core/X32Discovery.swift`**: finds mixers by broadcasting `/info` and `/xinfo` to a hardcoded list of broadcast addresses (255.255.255.255, 192.168.0.255, 192.168.1.255, 10.0.0.255) and listening for 3 s. Other subnets will not be found.
- **`Models/Scene.swift`**: `X32Scene` is the only SwiftData `@Model` (container configured in `x32_macApp`). It stores raw `.scn` file text and `oscCommands()` parses each `/path args` line into `OSCMessage`s, so "pushing" a scene means replaying those commands to the mixer.
- **`ContentView.swift`**: `NavigationSplitView` driven by the `SidebarItem` enum. Adding a feature screen means adding a case there plus its icon and detail view.
- **`Views/`**: one view per sidebar item (Connection, Scenes, Live Control, Effects & EQ, Channel Routing, OSC Terminal). Most views talk to the mixer via `connection.send/request` with literal OSC addresses.

### X32 domain notes

- Fader values are normalized floats in 0.0...1.0, not dB. In `LiveControlView`, 0.0 = -inf, 0.75 = 0 dB, 1.0 = +10 dB.
- OSC address patterns use zero-padded indices for most sections (`/ch/%02d/mix/fader`, `/bus/%02d/...`, `/auxin/%02d/...`) but not DCAs (`/dca/%d/fader`). `allFaderGroups` in `LiveControlView.swift` is the canonical list of fader paths.
- `/info` replies carry `(version, name, model, firmware)`; code that indexes arguments should bounds-check as `X32Connection.connect` does.

### Concurrency

Core types are `@MainActor` and `@Observable`, and `NWConnection` callbacks run on `.main`, so mutable state is accessed on the main thread. Keep new networking code on the main actor unless there is a reason not to.
