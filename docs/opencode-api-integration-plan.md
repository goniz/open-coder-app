# OpenCode API Integration Plan

## Overview

This document outlines the plan to integrate the generated OpenCode API client with the SwiftUI + TCA iOS app, replacing manual API client files with automated OpenAPI generation.

## Current State Analysis

### Generated API Client Structure
- **Location**: `.build/plugins/outputs/open-coder-app/OpenAPIGenerated/destination/OpenAPIGenerator/GeneratedSources/`
- **Files**:
  - `Client.swift` - Main client implementation with `APIProtocol` conformance
  - `Types.swift` - Data models and operation definitions
  - `Server.swift` - Server-related types and protocols
- **Key Features**:
  - Async/await support with `async throws` methods
  - Package-level access control
  - OpenAPIRuntime integration
  - HTTP transport abstraction

### App Architecture
- **Pattern**: TCA (The Composable Architecture) with modular design
- **Dependency Flow**: DependencyClients → Features → Views → OpenCoderLib
- **Injection**: `@Dependency` macro with protocol-based clients
- **Testing**: Live/test implementations via `DependencyKey`/`TestDependencyKey`

### Key Integration Points

#### WorkspacesFeature (`Sources/Features/WorkspacesFeature.swift`)
- **Current**: SSH-based workspace management
- **Target**: OpenCode API sessions, projects, commands
- **Operations**: Session creation, workspace opening, background tasks

#### ChatFeature (`Sources/Features/ChatFeature.swift`)
- **Current**: Basic message handling
- **Target**: OpenCode API message interactions
- **Operations**: Send/receive messages, tool interactions

#### LiveActivityFeature (`Sources/Features/LiveActivityFeature.swift`)
- **Current**: Background task monitoring via SSH
- **Target**: API-based task monitoring
- **Operations**: Task lifecycle, progress updates

## Integration Plan

### Phase 1: Foundation Setup

#### 1.1 Package Configuration
**File**: `Package.swift`
```swift
// Add OpenAPI dependencies
.package(url: "https://github.com/apple/swift-openapi-runtime", from: "1.0.0"),
.package(url: "https://github.com/apple/swift-http-types", from: "1.0.0"),

// Update OpenAPIGenerated target
.target(
  name: "OpenAPIGenerated",
  dependencies: [
    .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
    .product(name: "HTTPTypes", package: "swift-http-types"),
  ],
  plugins: [
    .plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator")
  ]
),

// Update DependencyClients dependency
.target(
  name: "DependencyClients",
  dependencies: [
    "Models",
    "OpenAPIGenerated", // Add this
    // ... existing dependencies
  ]
),
```

#### 1.2 OpenCode API Client Wrapper
**File**: `Sources/DependencyClients/OpenCodeAPIClient.swift`

```swift
import Foundation
import OpenAPIGenerated
import OpenAPIRuntime
import HTTPTypes

// MARK: - Protocol Definition

package protocol OpenCodeAPIClientProtocol: Sendable {
  // Session Management
  func listSessions() async throws -> [OpenCodeSession]
  func createSession() async throws -> OpenCodeSession
  func deleteSession(id: String) async throws
  func getSession(id: String) async throws -> OpenCodeSession
  
  // Project Operations
  func listProjects() async throws -> [OpenCodeProject]
  func getCurrentProject() async throws -> OpenCodeProject
  
  // Message Operations
  func sendMessage(sessionID: String, parts: [MessagePart]) async throws -> OpenCodeMessage
  func getMessages(sessionID: String) async throws -> [OpenCodeMessage]
  func getMessage(sessionID: String, messageID: String) async throws -> OpenCodeMessage
  
  // Command Operations
  func sendCommand(sessionID: String, command: String, arguments: [String]) async throws -> OpenCodeMessage
  func runShellCommand(sessionID: String, command: String) async throws -> OpenCodeMessage
  
  // Configuration
  func getConfig() async throws -> OpenCodeConfig
  func listProviders() async throws -> OpenCodeProviders
}

// MARK: - Domain Models

package struct OpenCodeSession: Equatable, Identifiable, Sendable {
  package let id: String
  package let createdAt: Date
  package let updatedAt: Date
  // ... other properties
}

package struct OpenCodeProject: Equatable, Identifiable, Sendable {
  package let id: String
  package let name: String
  package let path: String
  // ... other properties
}

package struct OpenCodeMessage: Equatable, Identifiable, Sendable {
  package let id: String
  package let sessionID: String
  package let parts: [MessagePart]
  package let timestamp: Date
  // ... other properties
}

package enum MessagePart: Equatable, Sendable {
  case text(String)
  case file(path: String, content: String)
  case agent(type: String, result: String)
}

// ... other domain models

// MARK: - Test Implementation

extension OpenCodeAPIClientProtocol: TestDependencyKey {
  package static let testValue = MockOpenCodeAPIClient()
}

extension DependencyValues {
  package var openCodeAPI: OpenCodeAPIClientProtocol {
    get { self[OpenCodeAPIClientKey.self] }
    set { self[OpenCodeAPIClientKey.self] = newValue }
  }
}

private enum OpenCodeAPIClientKey: DependencyKey {
  static let liveValue: OpenCodeAPIClientProtocol = LiveOpenCodeAPIClient()
}
```

#### 1.3 Live Implementation
**File**: `Sources/DependencyClientsLive/OpenCodeAPIClientLive.swift`

```swift
import Foundation
import OpenAPIGenerated
import OpenAPIRuntime
import HTTPTypes
import DependencyClients

package struct LiveOpenCodeAPIClient: OpenCodeAPIClientProtocol {
  private let client: Client
  
  package init(
    serverURL: URL = URL(string: "http://localhost:8080")!,
    transport: any ClientTransport = URLSessionTransport()
  ) {
    self.client = Client(
      serverURL: serverURL,
      transport: transport
    )
  }
  
  package func listSessions() async throws -> [OpenCodeSession] {
    let response = try await client.session_period_list(.init())
    
    switch response {
    case let .ok(okResponse):
      switch okResponse.body {
      case let .json(sessions):
        return sessions.map { session in
          OpenCodeSession(
            id: session.id,
            createdAt: session.createdAt,
            updatedAt: session.updatedAt
          )
        }
      }
    case .badRequest:
      throw OpenCodeAPIError.badRequest
    }
  }
  
  // ... implement other protocol methods
}

// MARK: - Error Handling

package enum OpenCodeAPIError: Error, Equatable {
  case badRequest
  case unauthorized
  case notFound
  case serverError
  case networkError(String)
  case decodingError(String)
}
```

### Phase 2: Feature Integration

#### 2.1 WorkspacesFeature Integration
**File**: `Sources/Features/WorkspacesFeature.swift`

Key changes:
- Add `@Dependency(\.openCodeAPI) var openCodeAPI`
- Replace SSH session management with API calls
- Update `WorkspaceState` to include `OpenCodeSession`
- Modify handlers to use API operations

```swift
// Example integration in WorkspacesFeature
case .openWorkspace(let workspaceID):
  guard let workspace = state.workspaces.first(where: { $0.id == workspaceID }) else {
    return .none
  }
  
  state.workspaces[id: workspaceID]?.onlineState = .connecting
  
  return .run { send in
    do {
      // Create OpenCode session for workspace
      let session = try await openCodeAPI.createSession()
      
      // Initialize session for the workspace
      try await openCodeAPI.sendCommand(
        sessionID: session.id,
        command: "init",
        arguments: [workspace.workspace.remotePath]
      )
      
      let spawnResult = WorkspaceService.SpawnResult(
        port: 8080, // API port
        online: true,
        error: nil
      )
      
      await send(.workspaceOpened(workspaceID, .success(spawnResult)))
    } catch {
      let sshError = SSHError.connectionFailed("API connection failed: \(error)")
      await send(.workspaceOpened(workspaceID, .failure(sshError)))
    }
  }
```

#### 2.2 ChatFeature Enhancement
**File**: `Sources/Features/ChatFeature.swift`

```swift
@Reducer
package struct ChatFeature {
  @ObservableState
  package struct State: Equatable {
    package var messages: [OpenCodeMessage] = []
    package var currentMessage = ""
    package var isLoading = false
    package var sessionID: String? // Add session context
    
    package init(sessionID: String? = nil) {
      self.sessionID = sessionID
    }
  }
  
  package enum Action: Equatable, BindableAction {
    case binding(BindingAction<State>)
    case task
    case sendMessage
    case messagesLoaded([OpenCodeMessage])
    case messageReceived(OpenCodeMessage)
  }
  
  @Dependency(\.openCodeAPI) var openCodeAPI
  
  package var body: some ReducerOf<Self> {
    BindingReducer()
    Reduce(core)
  }
  
  package func core(state: inout State, action: Action) -> Effect<Action> {
    switch action {
    case .task:
      guard let sessionID = state.sessionID else { return .none }
      
      return .run { send in
        do {
          let messages = try await openCodeAPI.getMessages(sessionID: sessionID)
          await send(.messagesLoaded(messages))
        } catch {
          // Handle error
        }
      }
      
    case .sendMessage:
      guard !state.currentMessage.isEmpty,
            let sessionID = state.sessionID else { return .none }
      
      let messageContent = state.currentMessage
      state.currentMessage = ""
      state.isLoading = true
      
      return .run { send in
        do {
          let message = try await openCodeAPI.sendMessage(
            sessionID: sessionID,
            parts: [.text(messageContent)]
          )
          await send(.messageReceived(message))
        } catch {
          // Handle error
        }
      }
      
    // ... other cases
    }
  }
}
```

### Phase 3: Configuration & Dependencies

#### 3.1 Configuration Management
**File**: `Sources/Models/OpenCodeConfiguration.swift`

```swift
import Foundation

package struct OpenCodeConfiguration: Equatable, Sendable {
  package let serverURL: URL
  package let timeout: TimeInterval
  package let retryCount: Int
  
  package init(
    serverURL: URL = URL(string: "http://localhost:8080")!,
    timeout: TimeInterval = 30,
    retryCount: Int = 3
  ) {
    self.serverURL = serverURL
    self.timeout = timeout
    self.retryCount = retryCount
  }
  
  package static let development = OpenCodeConfiguration(
    serverURL: URL(string: "http://localhost:8080")!
  )
  
  package static let production = OpenCodeConfiguration(
    serverURL: URL(string: "https://api.opencode.app")!
  )
}
```

#### 3.2 Environment-based Configuration
Update `AppFeature.swift` to configure the API client based on environment:

```swift
// In AppFeature initialization
case .task:
  return .run { send in
    // Configure OpenCode API based on environment
    let config = Bundle.main.object(forInfoDictionaryKey: "OPENCODE_ENV") as? String == "production" 
      ? OpenCodeConfiguration.production 
      : OpenCodeConfiguration.development
    
    // Initialize API client with config
    // This would require updating the dependency injection to accept configuration
  }
```

### Phase 4: Testing & Validation

#### 4.1 Mock Implementation
**File**: `Sources/DependencyClients/OpenCodeAPIClient+Mock.swift`

```swift
package struct MockOpenCodeAPIClient: OpenCodeAPIClientProtocol {
  package var sessions: [OpenCodeSession] = []
  package var projects: [OpenCodeProject] = []
  package var messages: [String: [OpenCodeMessage]] = [:]
  
  package func listSessions() async throws -> [OpenCodeSession] {
    return sessions
  }
  
  package func createSession() async throws -> OpenCodeSession {
    let session = OpenCodeSession(
      id: UUID().uuidString,
      createdAt: Date(),
      updatedAt: Date()
    )
    sessions.append(session)
    return session
  }
  
  // ... implement other mock methods
}
```

#### 4.2 Integration Tests
**File**: `Tests/FeaturesTests/WorkspacesFeatureAPITests.swift`

```swift
import XCTest
import ComposableArchitecture
@testable import Features
@testable import DependencyClients

final class WorkspacesFeatureAPITests: XCTestCase {
  func testWorkspaceOpeningWithAPI() async {
    let mockAPI = MockOpenCodeAPIClient()
    
    let store = TestStore(
      initialState: WorkspacesFeature.State(),
      reducer: { WorkspacesFeature() }
    ) {
      $0.openCodeAPI = mockAPI
    }
    
    // Test workspace opening with API integration
    await store.send(.openWorkspace(UUID())) {
      // Verify state changes
    }
    
    await store.receive(.workspaceOpened(UUID(), .success(SpawnResult(port: 8080, online: true, error: nil))))
  }
}
```

## Implementation Timeline

### Week 1: Foundation
- [ ] Update Package.swift with OpenAPI dependencies
- [ ] Create OpenCodeAPIClient protocol and domain models
- [ ] Implement LiveOpenCodeAPIClient wrapper
- [ ] Set up dependency injection

### Week 2: Core Integration
- [ ] Integrate with WorkspacesFeature
- [ ] Enhance ChatFeature with API support
- [ ] Update LiveActivityFeature for API-based monitoring
- [ ] Add configuration management

### Week 3: Testing & Polish
- [ ] Create comprehensive mock implementation
- [ ] Add integration tests
- [ ] Performance optimization
- [ ] Error handling improvements

### Week 4: Migration & Validation
- [ ] Gradual migration from SSH-based operations
- [ ] End-to-end testing
- [ ] Documentation updates
- [ ] Production readiness validation

## Success Criteria

1. **Functional**: All existing app functionality works with API integration
2. **Performance**: API operations complete within acceptable timeframes
3. **Reliability**: Robust error handling and recovery
4. **Testability**: Comprehensive test coverage for API integration
5. **Maintainability**: Clean separation of concerns and dependency injection

## Risk Mitigation

1. **API Availability**: Implement fallback mechanisms for API unavailability
2. **Breaking Changes**: Version API contract and handle changes gracefully  
3. **Performance**: Implement caching and connection pooling
4. **Security**: Secure API communication and credential management
5. **Migration**: Gradual rollout with ability to rollback to SSH-based operations

## Future Enhancements

1. **Real-time Updates**: WebSocket integration for live message streaming
2. **Offline Support**: Local caching and sync capabilities
3. **Multi-server Support**: Connect to multiple OpenCode instances
4. **Advanced Features**: Tool integration, custom commands, workspace templates