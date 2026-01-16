# Tapback macOS App

Native macOS app to sync terminal with mobile devices. Monitor multiple Claude Code/Codex instances from your phone.

## Features

- **Multiple session monitoring** - Add and monitor multiple tmux sessions
- **Tab-based mobile UI** - Switch between sessions on mobile
- **Built-in web server** - Embedded HTTP/WebSocket server
- **PIN authentication** - Secure access

## Requirements

- macOS 13+
- tmux

## Build

```bash
swift build
```

## Run

```bash
swift run TapbackApp
```

Or open in Xcode:
```bash
open Package.swift
```

## Usage

1. Launch the app
2. Click "+" to add a tmux session
3. Click "Start" to start the server
4. Open the displayed URL on your phone
5. Enter the PIN

## License

MIT
