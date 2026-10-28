# x32-mac

A macOS SwiftUI app for remote control of a Behringer X32 / X Air mixer over OSC/UDP.

## Features

- **Connection**: discover mixers on the local network (UDP broadcast) or connect by IP address
- **Scenes**: store `.scn` scene files and push them to the mixer
- **Live Control**: faders for channels, buses, aux inputs, and DCAs
- **Effects & EQ**
- **Channel Routing**
- **Spectrograph**
- **OSC Terminal**: send raw OSC messages and see replies

## Requirements

- macOS 26.5 or later
- Xcode 26.6 to build
- An X32 or X Air mixer on the same network

The app sandbox is disabled so the app can send UDP broadcasts and reach devices on the local network.

## Building

```sh
xcodebuild -project x32-mac.xcodeproj -scheme x32-mac -destination 'platform=macOS' build
```

Or open `x32-mac.xcodeproj` in Xcode and run the `x32-mac` scheme. There are no external dependencies.

## Testing

```sh
xcodebuild -project x32-mac.xcodeproj -scheme x32-mac -destination 'platform=macOS' \
  -only-testing:x32-macTests test
```

## Architecture

`OSCMessage` (wire format) → `OSCClient` (UDP transport to port 10023) → `X32Connection` (app state) → SwiftUI views. See `CLAUDE.md` for more detail.

Discovery enumerates the machine's network interfaces and broadcasts to every up IPv4 interface, using its address and netmask (plus `255.255.255.255`); mixers on other subnets must be connected to directly.

## License

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE).
