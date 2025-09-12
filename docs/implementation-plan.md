# OpenCoder iOS App - Stage 1 Implementation Plan

## Overview

Build an iPhone UI for opencode with SSH + tmux session management, focusing on local-first architecture with server validation. Scope includes Workspaces management, Add Server flow, Create Workspace modal, Workspace Dashboard, and Sessions list functionality.

## Architecture Goals

- **UI**: SwiftUI with TCA (The Composable Architecture)
- **Runtime**: SSH + tmux session management with on-demand opencode spawn/attach
- **Storage**: Local-first with device storage for Workspaces & Sessions
- **Network**: Server used only for validation and remote session fetching
- **Services**: Separate SSHClient, TmuxService, and WorkspaceService for clean separation of concerns

## Track A: UI Implementation (SwiftUI to Sessions List)

### A1. Project Foundation & Shell
**Goal**: Basic app structure with navigation and design system
- [x] Create app target with NavigationStack
- [x] Implement light design system (spacing, typography, pills)
- [x] Add AppRouter and route models
- [x] Support dark/light themes

**DoD**: App launches to empty Workspaces screen with theme support

### A2. Workspaces Root UI
**Goal**: Main workspace management interface
- [x] WorkspacesView with workspace cards showing:
  - Name, user@host, remote path
  - State pill (Idle/Spawning/Online/Error)
- [x] Swipe actions: Connect/Disconnect, Open
- [x] Pull-to-refresh functionality

**DoD**: List renders from local mock store with state pills reflecting ViewState enum

### A3. Add Server Flow (Stepper)
**Goal**: Multi-step server configuration wizard
- [x] Step 1: Host/IP & Port input
- [x] Step 2: Authentication (username, key import/generate, passphrase)
- [x] Step 3: Fingerprint review (placeholder UI)
- [x] Step 4: Connection test (spinner UI)

**Simplified**: Keep 4-step wizard for comprehensive server setup, but defer key generation to future iteration

**DoD**: Validated forms that persist HostRef locally and return to Workspaces with new server entry

### A4. Create Workspace Modal
**Goal**: Workspace creation interface
- [x] Path picker field (free-text input)
- [x] Idle TTL configuration
- [x] Log retention settings
- [x] Deterministic tmux session name preview

**DoD**: Persists Workspace locally and displays card on Workspaces list

### A5. Workspace Dashboard Shell
**Goal**: Main workspace interface framework
- [x] Header with Context Bar (server · path · branch · tunnel state)
- [x] Segmented control: Sessions · Repo · Terminals · Activity
- [x] Spawning Overlay component with steps: SSH → Launch → Health → Attach
- [x] Enable only Sessions tab initially

**DoD**: Navigation into workspace shows Dashboard with Sessions tab and injectable overlay

### A6. Sessions List UI
**Goal**: Session management interface
- [x] SessionsListView displaying:
  - Session title
  - Last message preview
  - Updated timestamp
- [x] Empty state: "No sessions yet"
- [x] "New Session" button (placeholder/disabled)
- [x] LazyVStack for large data support
- [x] Pull-to-refresh functionality

**DoD**: Renders from local store with smooth scrolling and refresh capability

### A7. Live Output Viewer UI
**Goal**: Real-time log viewing interface
- [x] Full-screen monospaced view
- [x] Controls: Follow/Pause, Copy, Clear buffer
- [x] Accessible via Dashboard header button
- [x] Basic scrolling for moderate log sizes

**Simplified**: Remove search functionality and virtualized scrolling for v1

**DoD**: Accepts async line stream provider with smooth rendering

## Track B: Runtime Implementation (SSH + tmux + opencode)

### B1. Keychain & Known Hosts Foundation
**Goal**: Secure credential and host management
- [x] Import existing Ed25519 keys with secure storage
- [x] Local cache for host fingerprints
- [x] APIs: add, lookup, verify fingerprints

**Simplified**: Defer key generation to future iteration, focus on import

**DoD**: Unit tests for keypair storage round-trip and known_hosts comparison

### B2. SSH Client Implementation
**Goal**: Core SSH functionality
- [x] Minimal wrapper exposing:
  - `exec(_ command: String)` (non-PTY)
  - `openPTY(_ command: String)` (for future terminals)
  - `openDirectTCPIP(host:port:)` → bidirectional stream

**DoD**: Integration test runs echo command with proper error handling for bad auth

### B3. TmuxService
**Goal**: Idempotent tmux session management
- [x] Methods: `hasSession(name)`, `newSession(name, path)`, `newOrReplaceServerWindow(name)`
- [x] Deterministic session naming: `ocw-{user}-{host}-{hash(path)[:8]}`

**DoD**: Create/list/kill windows via SSH with unit tests using command stubs

### B4. Spawn/Attach Orchestrator (WorkspaceService)
**Goal**: Core workspace connection logic
- [x] Attach-or-Spawn algorithm:
  1. Ensure tmux session exists
  2. Check `$CTRL/daemon.json` for existing port → health probe
  3. Spawn `opencode serve --hostname 127.0.0.1 --port <free> --print-logs | tee -a live.log`
  4. Wait for health check (`/config` or `/app`) via temporary direct-tcpip
  5. Establish local port-forward channel
- [x] Implement Spawning Overlay progress callbacks

**DoD**: `attachOrSpawn(workspace)` returns `{port, online: true}` or typed error with visual feedback

### B5. Live Output Stream
**Goal**: Real-time log streaming
- [x] SSH exec to `tail -n 200 -F "$WORKSPACE/.opencode/live.log"`
- [x] Basic text output (defer ANSI parsing)
- [x] Client-side redaction toggle for tokens/URLs

**Simplified**: Defer ANSI parsing to future iteration

**DoD**: Live Output viewer displays stream with <200ms latency, survives log rotation

### B6. Health & Error Handling
**Goal**: Robust error management and recovery
- [x] Typed errors: fingerprint mismatch, auth failed, port collision, spawn timeout, stale lock
- [x] Recovery actions:
  - "Clean & Retry" → removes stale daemon.json/lock, restarts window
  - "Choose new port" on port collision
- [x] Basic error logging for spawn times and failures

**Simplified**: Defer telemetry hooks to future iteration

**DoD**: Simulated errors surface correct banners and recovery CTAs with basic logging

## Track C: Sessions List Data (Local-first + Server)

### C1. Local Store
**Goal**: Persistent local data management
- [x] Choose storage: Core Data (simpler than SQLite/GRDB)
- [x] Entities: `Workspace`, `SessionMeta {id, title, lastMessagePreview, updatedAt, workspaceId}`
- [x] DAO methods: upsert/list per workspace

**Simplified**: Use Core Data for simpler implementation

**DoD**: Persistence tested with cold app start showing saved sessions

### C2. OpenAPI Client
**Goal**: Minimal server communication
- [x] Implement endpoints:
  - `GET /session` → `[SessionMetaDTO]`
  - [x] Transport via direct-tcpip tunnel

**DoD**: `fetchSessions()` returns decoded DTOs given port from B4

### C3. Sessions List Sync
**Goal**: Local-first data synchronization
- [x] On workspace entry (after successful attach):
  - Fetch remote sessions
  - Merge with local (upsert by id, update timestamps/previews)
  - Show optimistic local list immediately
  - Update cells on data arrival

**DoD**: Sessions list updates within one refresh cycle after spawn; offline shows last local copy

## Cross-Cutting: Integration & Testing

### X1. View Models & State Management
**Goal**: Clean architecture with TCA
- [x] `WorkspaceVM`: state management for Idle/Spawning/Online/Error, overlay control
- [x] `SessionsVM`: sessions list, refresh state, load() calling attach→fetch

**DoD**: No business logic in Views; proper cancellation on disappear

### X2. Integration Tests (Happy Paths)
**Goal**: End-to-end functionality validation
- [x] Add Server → Create Workspace → Open Workspace flow
- [x] Spawning overlay progression and completion
- [x] Sessions list populated from mocked opencode instance

### X3. Error/Recovery Tests
**Goal**: Robust error handling validation
- [x] Bad fingerprint → blocking error sheet
- [x] Port collision → auto retry with new port
- [x] Stale daemon.json → successful "Clean & Retry"

### X4. Performance Requirements
**Goal**: Smooth user experience
- [x] Spawn p95 ≤ 12s on LTE (simulated)
- [x] Sessions list scrolls smoothly with 100 items
- [x] Live Output handles 1k lines with stable memory

**Simplified**: Relaxed performance targets for v1

## Implementation Iterations

### Iteration 1: Foundations
**Components**: A1, B1, B2, C1
**Outcome**: App shell, local store, SSH basics proven

### Iteration 2: Workspaces UI + tmux
**Components**: A2, A3, A4, B3
**Outcome**: Create servers/workspaces, deterministic tmux sessions

### Iteration 3: Spawn/Attach + Overlay
**Components**: A5, B4, B6
**Outcome**: Real spawn/attach from UI with progress & error handling

### Iteration 4: Sessions List + Live Output
**Components**: A6, C2, C3, B5, A7
**Outcome**: Sessions list synced post-spawn, Live Output viewer streaming

### Iteration 5: Hardening (Optional)
**Components**: X2–X4
**Outcome**: Polish, basic logging, edge-case fixes

**Simplified**: Defer telemetry to future iteration

## Core Data Models

```swift
struct Workspace: Identifiable, Codable {
    let id: UUID
    var name: String
    var host: String
    var user: String
    var remotePath: String
    var tmuxSession: String
    var idleTTLMinutes: Int
}

enum WorkspaceOnlineState { 
    case idle
    case spawning(phase: SpawnPhase)
    case online(port: Int)
    case error(String) 
}

enum SpawnPhase: String { 
    case ssh, launch, health, attach 
}

struct SessionMeta: Identifiable, Codable {
    let id: String
    var title: String
    var lastMessagePreview: String
    var updatedAt: Date
    var workspaceId: UUID
}
```

## Acceptance Criteria

From cold start, user can:
1. Add server and create workspace (no systemd required)
2. Open workspace → app spawns opencode via tmux and attaches
3. View Sessions list populated from server (or last local snapshot offline)
4. Open Live Output and watch real-time stdout streaming

Robust error handling for:
- Fingerprint mismatches
- Authentication failures  
- Stale locks
- Spawn timeouts

## Risk Mitigation

- **Background suspension during spawn**: Keep overlay resumable, re-run attach-or-spawn on foreground
- **CLI/API drift**: Encapsulate commands/paths, add capability probe before endpoint reliance
- **Large logs**: Basic scrolling view with "Clear" action

**Simplified**: Remove ring buffer and virtualization for v1

## Current Status

- [x] Project structure established with TCA architecture
- [x] Basic models and features scaffolded
- [x] Core functionality implementation completed

This plan provides a focused path to ship Workspaces → Spawn/Attach → Sessions list with real opencode processes under tmux and a clean, resilient UI foundation. Key simplifications include Core Data for storage, deferred ANSI parsing, and relaxed performance targets for v1.