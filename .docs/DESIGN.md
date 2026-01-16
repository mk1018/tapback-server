# Tapback macOS App - Design Document

## Overview

Native macOS app to sync terminal with mobile devices. Monitor multiple Claude Code/Codex instances from your phone.

## Goals

1. **Multiple session monitoring** - Select and monitor multiple Claude Code/Codex instances
2. **Port selection** - Choose which ports to monitor
3. **Tab-based mobile UI** - Single port for mobile, tabs to switch between sessions
4. **Built-in web server** - Embedded HTTP/WebSocket server

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    macOS App (SwiftUI)                       │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐ │
│  │ SessionMgr  │  │ ServerMgr   │  │  TmuxHelper         │ │
│  │             │  │             │  │                     │ │
│  │ - sessions  │  │ - Vapor     │  │ - capture()         │ │
│  │ - polling   │  │ - WebSocket │  │ - sendKeys()        │ │
│  │ - output    │  │ - PIN auth  │  │ - listSessions()    │ │
│  └─────────────┘  └─────────────┘  └─────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
                            │
                            │ HTTP/WebSocket
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                    Mobile Browser                            │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Tab Bar: [Session1] [Session2] [Session3]          │   │
│  ├─────────────────────────────────────────────────────┤   │
│  │                                                     │   │
│  │  Terminal Output (real-time sync via WebSocket)     │   │
│  │                                                     │   │
│  ├─────────────────────────────────────────────────────┤   │
│  │  [0] [1] [2] [3] [4]  Quick buttons                 │   │
│  │  [_______________] [Send]  Input field              │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## Components

### 1. SessionManager
- Manages multiple tmux sessions
- Polls output every 1 second
- Caches output per session
- Handles input forwarding

### 2. ServerManager
- Embedded Vapor web server
- WebSocket for real-time sync
- PIN authentication
- Serves mobile HTML UI

### 3. TmuxHelper
- `capture(session:)` - Get terminal output
- `sendKeys(session:text:)` - Send input + Enter
- `listSessions()` - Discover running sessions

### 4. Mobile UI (HTML)
- Tab-based session switching
- Real-time terminal output
- Quick number buttons (0-4)
- Text input field

## Data Flow

1. **Startup**
   - User adds tmux session(s)
   - SessionManager starts polling
   - User clicks "Start" to launch server

2. **Mobile Connection**
   - Mobile opens URL, enters PIN
   - WebSocket connection established
   - Server sends all session outputs

3. **Real-time Sync**
   - SessionManager polls tmux every 1s
   - Output changes sent via WebSocket
   - Mobile UI updates terminal display

4. **Input**
   - User taps button or enters text
   - WebSocket sends `{t:"i", id:"...", c:"..."}`
   - Server forwards to TmuxHelper
   - tmux receives keys + Enter

## Tech Stack

- **SwiftUI** - macOS UI framework
- **Vapor** - Embedded web server
- **WebSocket** - Real-time communication
- **Process** - tmux interaction

## File Structure

```
Sources/TapbackApp/
├── TapbackApp.swift          # App entry point
├── Models/
│   ├── Session.swift         # Session data model
│   ├── SessionManager.swift  # Session management
│   └── TmuxHelper.swift      # tmux commands
├── Views/
│   └── ContentView.swift     # Main UI
└── Server/
    ├── ServerManager.swift   # Vapor server
    └── HTMLTemplates.swift   # Mobile HTML
```

## Known Issues

- [ ] Freeze when clicking Sessions (async issue)
- [ ] Need to handle tmux not installed
- [ ] Need error handling for server start failure

## Future Enhancements

- Menu bar quick access
- Auto-discovery of Claude Code instances
- Multiple port support
- Dark/light mode sync with system
