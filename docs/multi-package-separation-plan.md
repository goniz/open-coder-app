# Multi-Package Separation Implementation Plan

## Overview

This document provides a detailed implementation plan for separating the OpenCoder iOS app into multiple Swift packages with clear UI/Logic separation, enabling macOS testing for core business logic.

## Target Architecture

```
open-coder-app/
├── Packages/
│   ├── OpenCoderCore/           # Platform-agnostic business logic (iOS + macOS)
│   ├── OpenCoderUI/             # iOS-specific UI and platform integrations
│   └── OpenCoderApp/            # iOS app entry point and configuration
├── Xcode/
│   └── OpenCoder.xcodeproj      # iOS app target
└── Tests/                       # Integration tests
```

## Package 1: OpenCoderCore

### Purpose
Platform-agnostic business logic, data models, and network clients that can run on both iOS and macOS for testing.

### Package.swift Dependencies
```swift
platforms: [.iOS(.v17), .macOS(.v14)]

dependencies: [
  // TCA and Dependencies
  .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.22.2"),
  .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.9.4"),
  .package(url: "https://github.com/pointfreeco/swift-custom-dump", exact: "1.3.3"),
  
  // Networking
  .package(url: "https://github.com/apple/swift-nio-ssh", from: "0.11.0"),
  .package(url: "https://github.com/apple/swift-openapi-generator", from: "1.0.0"),
  .package(url: "https://github.com/apple/swift-openapi-runtime", from: "1.0.0"),
  .package(url: "https://github.com/swift-server/swift-openapi-async-http-client", from: "1.0.0"),
]

products: [
  .library(name: "OpenCoderCore", targets: [
    "Models", 
    "Protocols", 
    "Implementations", 
    "Features", 
    "OpenAPIGenerated"
  ])
]
```

### Modules

#### Models
- **Current State**: Contains iOS dependencies via ActivityKit
- **Target State**: Platform-agnostic data models
- **Files to Move**: All current `Sources/Models/` except iOS-specific parts

**Required Changes**:
- [ ] Extract ActivityKit dependencies from `CodingTaskActivity.swift`
- [ ] Remove SwiftUI import from `Workspace.swift` (likely Color usage)
- [ ] Create platform-agnostic protocols for iOS-specific functionality

#### Protocols  
- **Current State**: Contains UIKit dependency in BackgroundTaskClient
- **Target State**: Pure protocol definitions
- **Files to Move**: All current `Sources/DependencyClients/` except iOS-specific implementations (will be renamed to Protocols)

**Required Changes**:
- [ ] Extract iOS BackgroundTaskClient implementation to UI package
- [ ] Keep only protocol definition for BackgroundTaskClient
- [ ] Create StorageClient protocol to abstract UserDefaults usage

#### Implementations
- **Current State**: Platform-agnostic HTTP/SSH implementations
- **Target State**: No changes needed - already platform-agnostic
- **Files to Move**: All current `Sources/DependencyClientsLive/` (will be renamed to Implementations)

#### Features
- **Current State**: Contains some iOS dependencies (UIKit, ActivityKit)
- **Target State**: Pure TCA business logic
- **Files to Move**: All current `Sources/Features/` with modifications

**Required Changes**:
- [ ] Remove UIKit imports from `ServersFeature.swift`
- [ ] Extract iOS-specific background task logic
- [ ] Abstract UserDefaults usage in `AppFeature.swift`
- [ ] Wrap ActivityKit usage in platform checks in `LiveActivityFeature.swift`
- [ ] Extract iOS-specific Live Activity implementations

#### OpenAPIGenerated
- **Current State**: Platform-agnostic generated code
- **Target State**: No changes needed
- **Files to Move**: All current `Sources/OpenAPIGenerated/`

## Package 2: OpenCoderUI

### Purpose
iOS-specific UI components, platform integrations, and app entry point.

### Package.swift Dependencies
```swift
platforms: [.iOS(.v17)]

dependencies: [
  // Local dependency
  .package(path: "../OpenCoderCore"),
  
  // UI-specific
  .package(url: "https://github.com/exyte/Chat.git", from: "2.6.9"),
  
  // Re-export TCA for UI usage
  .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.22.2"),
]

products: [
  .library(name: "OpenCoderUI", targets: [
    "Views", 
    "IOSProtocols"
  ])
]
```

### Modules

#### Views
- **Current State**: SwiftUI views with iOS dependencies
- **Target State**: No changes needed - already iOS-specific
- **Files to Move**: All current `Sources/Views/`

#### IOSProtocols (New Module)
- **Purpose**: iOS-specific dependency implementations
- **Files to Create**:
  - `BackgroundTaskClientLive.swift` (extracted from current Protocols module)
  - `StorageClientLive.swift` (UserDefaults implementation)
  - `LiveActivityClientLive.swift` (ActivityKit implementation)



## Package 3: OpenCoderApp

### Purpose
iOS application entry point, configuration, and dependency setup that integrates UI and Core packages.

### Package.swift Dependencies
```swift
platforms: [.iOS(.v17)]

dependencies: [
  // Local dependencies
  .package(path: "../OpenCoderCore"),
  .package(path: "../OpenCoderUI"),
  
  // TCA for app configuration
  .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.22.2"),
]

products: [
  .library(name: "OpenCoderApp", targets: ["OpenCoderApp"])
]
```

### Modules

#### OpenCoderApp
- **Current State**: App entry point in OpenCoderLib
- **Target State**: iOS app configuration and startup with dependency integration
- **Files to Move**: Current `Sources/OpenCoderLib/OpenCoderApp.swift`

**Required Changes**:
- [ ] Import both OpenCoderCore and OpenCoderUI
- [ ] Configure dependency injection for both Core and UI packages
- [ ] Set up proper module imports

## Package 4: OpenCoderApp (Xcode Project)

### Purpose
iOS application target that depends on OpenCoderApp package.

### Dependencies
- Local package: `../Packages/OpenCoderApp`

## Implementation Tasks

### Phase 1: Create Package Structure

#### Task 1.1: Create OpenCoderCore Package
- [ ] Create `Packages/OpenCoderCore/` directory
- [ ] Create `Packages/OpenCoderCore/Package.swift` with specified dependencies
- [ ] Create module directories:
  - [ ] `Sources/Models/`
  - [ ] `Sources/Protocols/`
  - [ ] `Sources/Implementations/`
  - [ ] `Sources/Features/`
  - [ ] `Sources/OpenAPIGenerated/`
- [ ] Create test directories:
  - [ ] `Tests/ModelsTests/`
  - [ ] `Tests/ProtocolsTests/`
  - [ ] `Tests/FeaturesTests/`

#### Task 1.2: Create OpenCoderUI Package
- [ ] Create `Packages/OpenCoderUI/` directory
- [ ] Create `Packages/OpenCoderUI/Package.swift` with specified dependencies
- [ ] Create module directories:
  - [ ] `Sources/Views/`
  - [ ] `Sources/IOSProtocols/`
- [ ] Create test directories:
  - [ ] `Tests/ViewsTests/`

#### Task 1.3: Create OpenCoderApp Package
- [ ] Create `Packages/OpenCoderApp/` directory
- [ ] Create `Packages/OpenCoderApp/Package.swift` with specified dependencies
- [ ] Create module directories:
  - [ ] `Sources/OpenCoderApp/`
- [ ] Create test directories:
  - [ ] `Tests/OpenCoderAppTests/`

### Phase 2: Extract and Clean iOS Dependencies

#### Task 2.1: Clean Models Module
- [ ] **File**: `Sources/Models/CodingTaskActivity.swift`
  - [ ] Extract ActivityKit-specific implementation to UI package
  - [ ] Create protocol-based abstraction in core package
  - [ ] Add `#if canImport(ActivityKit)` guards for platform-specific code

- [ ] **File**: `Sources/Models/Workspace.swift`
  - [ ] Remove SwiftUI import
  - [ ] Replace SwiftUI.Color with platform-agnostic color representation
  - [ ] Create color protocol/extension in UI package

#### Task 2.2: Clean Protocols Module
- [ ] **File**: `Sources/Protocols/BackgroundTaskClient.swift` (renamed from DependencyClients)
  - [ ] Extract iOS implementation to `OpenCoderUI/Sources/IOSProtocols/BackgroundTaskClientLive.swift`
  - [ ] Keep only protocol definition in core package
  - [ ] Add mock implementation for macOS testing

- [ ] **Create**: `Sources/Protocols/StorageClient.swift`
  - [ ] Define protocol for persistent storage operations
  - [ ] Abstract UserDefaults usage from Features

#### Task 2.3: Clean Features Module
- [ ] **File**: `Sources/Features/ServersFeature.swift`
  - [ ] Remove UIKit imports
  - [ ] Extract iOS-specific pasteboard/clipboard functionality to UI package
  - [ ] Use dependency injection for platform-specific services

- [ ] **File**: `Sources/Features/AppFeature.swift`
  - [ ] Replace UserDefaults usage with StorageClient dependency
  - [ ] Make storage operations injectable for testing

- [ ] **File**: `Sources/Features/LiveActivityFeature.swift`
  - [ ] Add stronger platform guards around ActivityKit usage
  - [ ] Extract iOS-specific Live Activity logic to UI package
  - [ ] Create protocol-based abstraction for activity management

### Phase 3: Move Files to New Packages

#### Task 3.1: Move Core Package Files
- [ ] Copy `Sources/Models/` → `Packages/OpenCoderCore/Sources/Models/`
- [ ] Copy `Sources/DependencyClients/` → `Packages/OpenCoderCore/Sources/Protocols/`
- [ ] Copy `Sources/DependencyClientsLive/` → `Packages/OpenCoderCore/Sources/Implementations/`
- [ ] Copy `Sources/Features/` → `Packages/OpenCoderCore/Sources/Features/`
- [ ] Copy `Sources/OpenAPIGenerated/` → `Packages/OpenCoderCore/Sources/OpenAPIGenerated/`
- [ ] Copy relevant test files to `Packages/OpenCoderCore/Tests/`

#### Task 3.2: Move UI Package Files
- [ ] Copy `Sources/Views/` → `Packages/OpenCoderUI/Sources/Views/`
- [ ] Create iOS-specific dependency implementations in `Packages/OpenCoderUI/Sources/IOSProtocols/`
- [ ] Copy relevant test files to `Packages/OpenCoderUI/Tests/`

#### Task 3.3: Move App Package Files
- [ ] Copy `Sources/OpenCoderLib/` → `Packages/OpenCoderApp/Sources/OpenCoderApp/`
- [ ] Update imports to use OpenCoderCore and OpenCoderUI packages
- [ ] Update dependency injection to register implementations from both packages

#### Task 3.4: Create iOS-Specific Implementations
- [ ] **Create**: `Packages/OpenCoderUI/Sources/IOSProtocols/BackgroundTaskClientLive.swift`
  - [ ] Move UIKit-based background task implementation
  - [ ] Register as live dependency

- [ ] **Create**: `Packages/OpenCoderUI/Sources/IOSProtocols/StorageClientLive.swift`
  - [ ] Implement UserDefaults-based storage
  - [ ] Register as live dependency

- [ ] **Create**: `Packages/OpenCoderUI/Sources/IOSProtocols/LiveActivityClientLive.swift`
  - [ ] Move ActivityKit implementation from Features
  - [ ] Register as live dependency

### Phase 4: Update Xcode Project

#### Task 4.1: Modify Xcode Project Dependencies
- [ ] Remove Swift Package Manager dependency on root `Package.swift`
- [ ] Add local package dependency: `../Packages/OpenCoderApp`
- [ ] Update app target to import `OpenCoderApp` instead of `OpenCoderLib`
- [ ] Update build settings if necessary

#### Task 4.2: Update Import Statements
- [ ] Update iOS app target files to import from `OpenCoderApp`
- [ ] Ensure proper module imports across all packages
- [ ] Update test targets to use new package structure

### Phase 5: Testing and Validation

#### Task 5.1: Core Package Testing
- [ ] Create macOS test scheme for OpenCoderCore package
- [ ] Verify all core tests run on macOS
- [ ] Add mock implementations for iOS-specific dependencies
- [ ] Ensure business logic tests pass without iOS simulator

#### Task 5.2: UI Package Testing
- [ ] Verify iOS-specific tests still work
- [ ] Test integration between packages
- [ ] Validate app builds and runs correctly

#### Task 5.3: CI/CD Updates
- [ ] Update GitHub Actions workflow to test core package on macOS
- [ ] Add separate test jobs for each package
- [ ] Ensure proper dependency resolution in CI

### Phase 6: Documentation and Cleanup

#### Task 6.1: Update Build Scripts
- [ ] Update `Justfile` commands to work with new package structure
- [ ] Add package-specific build/test commands
- [ ] Update development cycle commands

#### Task 6.2: Update Documentation
- [ ] Update `README.md` with new architecture
- [ ] Update `AGENTS.md` with new build commands
- [ ] Document package separation rationale and benefits

#### Task 6.3: Cleanup
- [ ] Remove old source files from root package
- [ ] Clean up unused dependencies in root `Package.swift`
- [ ] Archive or remove root package file if not needed

## Testing Strategy

### Core Package (macOS + iOS)
- **Models**: Pure Swift model testing
- **Protocols**: Protocol conformance testing
- **Features**: Business logic testing with mocked dependencies
- **Implementations**: Network/SSH integration testing

### UI Package (iOS Only)
- **Views**: SwiftUI view testing
- **IOSProtocols**: iOS platform integration testing

### App Package (iOS Only)
- **OpenCoderApp**: App entry point and dependency configuration testing
- **Integration**: Full app flow testing

## Benefits

1. **Faster Testing**: Core business logic tests run on macOS without iOS simulator overhead
2. **Parallel Development**: Teams can work on packages independently
3. **Platform Flexibility**: Core logic can be reused for potential macOS app
4. **Cleaner Architecture**: Clear separation between business logic and UI
5. **Faster Builds**: Parallel package compilation
6. **Better Testability**: Easy mocking of platform-specific dependencies

## Risks and Mitigation

### Risk: Dependency Circular References
**Mitigation**: Strict dependency hierarchy - Core → UI → App (where App depends on both Core and UI)

### Risk: Integration Issues
**Mitigation**: Comprehensive integration testing in final phase

### Risk: Build Complexity
**Mitigation**: Update build scripts and documentation early

### Risk: Development Workflow Changes
**Mitigation**: Update development commands and team documentation

## Success Criteria

- [ ] Core package tests run successfully on macOS
- [ ] iOS app builds and functions identically to current version
- [ ] All existing tests pass in new package structure
- [ ] CI/CD pipeline supports new architecture
- [ ] Development workflow commands work with new structure
- [ ] Documentation reflects new architecture

## Dependencies by Usage Analysis

### OpenCoderCore Package Dependencies

#### Swift Foundation & Language
- `Foundation` - Used in 36 files for basic Swift functionality
- `Swift` runtime - Platform-agnostic

#### TCA Ecosystem
- `ComposableArchitecture` - Used in 28 files for state management
- `Dependencies` - Used in 13 files for dependency injection
- `DependenciesMacros` - Used for dependency registration

#### Networking & SSH
- `NIOSSH` - Used in 3 files for SSH client functionality
- `NIOCore` - Used in 3 files for networking primitives
- `NIOPosix` - Used in 2 files for POSIX networking
- `HTTPTypes` - Used in 3 files for HTTP type definitions

#### OpenAPI Client
- `OpenAPIRuntime` - Used in 4 files for API client runtime
- `OpenAPIAsyncHTTPClient` - Used in 2 files for HTTP transport
- `OpenAPIGenerator` - Build-time code generation

#### Security & Crypto
- `Security` - Used in 1 file for keychain operations
- `Crypto` - Used in 1 file for cryptographic operations

#### Testing
- `CustomDump` - Testing utilities for better test output

### OpenCoderUI Package Dependencies

#### UI Frameworks
- `SwiftUI` - Used in 20 files for iOS UI
- `UIKit` - Used in 2 files for iOS platform integration

#### iOS Platform Features
- `ActivityKit` - Used in 2 files for Live Activities
- `BackgroundTasks` - Used in 1 file for background processing

#### UI Libraries
- `ExyteChat` - Used in 4 files for chat interface

#### Re-exported Core Dependencies
- `ComposableArchitecture` - For UI state management
- `OpenCoderCore` - Local package dependency

### Dependency Movement Plan

#### Moving to Core Package
```swift
// Third-party dependencies that are platform-agnostic
.package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.22.2")
.package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.9.4")
.package(url: "https://github.com/pointfreeco/swift-custom-dump", exact: "1.3.3")
.package(url: "https://github.com/apple/swift-nio-ssh", from: "0.11.0")
.package(url: "https://github.com/apple/swift-openapi-generator", from: "1.0.0")
.package(url: "https://github.com/apple/swift-openapi-runtime", from: "1.0.0")
.package(url: "https://github.com/swift-server/swift-openapi-async-http-client", from: "1.0.0")
```

#### Moving to UI Package
```swift
// iOS-specific dependencies
.package(url: "https://github.com/exyte/Chat.git", from: "2.6.9")
.package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.22.2") // Re-export for UI
.package(path: "../OpenCoderCore") // Local dependency
```

#### Moving to App Package
```swift
// App entry point dependencies
.package(path: "../OpenCoderCore") // Local dependency
.package(path: "../OpenCoderUI") // Local dependency
.package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.22.2") // For app configuration
```

#### Staying in Root (if needed)
```swift
// Integration testing or app-specific dependencies
// None currently identified - root Package.swift can be removed
```

This dependency analysis ensures that each package only includes the dependencies it actually uses, reducing build times and maintaining clean separation of concerns.