# OpenCoder

A SwiftUI iOS app for remote development productivity, featuring SSH server management, real-time coding task execution, and Live Activity progress tracking.

## Features

- 🔌 **SSH Server Management**: Connect and manage multiple development servers with persistent connections
- ⚡ **Remote Task Execution**: Run coding tasks (build, test, deploy, install) on remote servers
- 📱 **Live Activities**: Real-time progress tracking with iOS 16+ Live Activities and Dynamic Island
- 💬 **Chat Interface**: Integrated chat for development assistance and task management
- 📁 **Project Management**: Organize and manage multiple development projects
- 🔄 **Background Monitoring**: Intelligent connection pooling with battery-efficient background updates
- 🏗️ **Modular Architecture**: Built with The Composable Architecture (TCA) for scalability

## Key Capabilities

### Remote Development Workflow
- Securely connect to development servers via SSH (password or key-based authentication)
- Execute common development tasks remotely with real-time progress feedback
- Maintain persistent connections for active tasks, with automatic reconnection for idle servers

### Live Activity Integration
- Track build, test, deployment progress directly from your Lock Screen and Dynamic Island
- Background task monitoring ensures progress updates even when app is backgrounded
- Battery-efficient connection management that only maintains connections during active tasks

### Developer Experience
- Modular Swift Package architecture enables fast iteration and testing
- TDD-friendly reducer testing without full app builds
- SwiftUI previews for rapid UI development

## Getting Started

### Prerequisites
- iOS 17.0+ / macOS 14.0+
- Xcode 16.0+
- Swift 6.0+

### Installation

1. Clone the repository:
   ```bash
   git clone <repository-url>
   cd open-coder-app
   ```

2. Install dependencies:
   ```bash
   swift package resolve
   # or
   just update
   ```

3. Build and run:
   ```bash
   swift build
   # or 
   just build
   ```

### Development Commands

```bash
# Build all packages
just build

# Build and test core package on macOS (faster)
just build-core-macos

# Run tests across all packages
just test

# Lint code across all packages
just lint

# Fix lint issues across all packages
just fix

# Development cycle (lint, build, build-ios, test)
just devcycle

# Deploy beta build
just beta
```

## Architecture

OpenCoder uses a multi-package Swift architecture with clear platform separation:

```
Packages/
├── OpenCoderCore/           # Platform-agnostic business logic (iOS + macOS)
│   ├── Models/             # Core data models
│   ├── Protocols/          # Dependency protocols
│   ├── Implementations/    # Network & SSH clients
│   ├── Features/           # TCA reducers and business logic
│   └── OpenAPIGenerated/   # Generated API clients
├── OpenCoderUI/            # iOS-specific UI and platform integrations
│   ├── Views/              # SwiftUI views and UI components
│   └── IOSProtocols/       # iOS-specific dependency implementations
└── OpenCoderApp/           # iOS app entry point and configuration
```

### Package Benefits

- **Faster Testing**: Core business logic tests run on macOS without iOS simulator overhead
- **Platform Flexibility**: Core logic can be reused for potential macOS app
- **Parallel Development**: Teams can work on packages independently
- **Cleaner Architecture**: Clear separation between business logic and UI
- **Better Testability**: Easy mocking of platform-specific dependencies

### Core Package (macOS + iOS)
- **Models**: Platform-agnostic data models with proper platform guards
- **Protocols**: Dependency protocols for external services
- **Implementations**: Network, SSH, and API client implementations
- **Features**: TCA reducers and business logic

### UI Package (iOS Only)
- **Views**: SwiftUI views and iOS-specific UI components
- **IOSProtocols**: iOS platform integrations (UserDefaults, ActivityKit, UIKit)

### Key Features Implementation

- **ServersFeature**: SSH connection management with intelligent connection pooling
- **LiveActivityFeature**: iOS Live Activity integration with background updates
- **ChatFeature**: Development chat interface with task integration
- **ProjectsFeature**: Project organization and management

## Dependencies

- [The Composable Architecture (TCA)](https://github.com/pointfreeco/swift-composable-architecture) - Unidirectional data flow and state management
- [Swift Dependencies](https://github.com/pointfreeco/swift-dependencies) - Dependency injection
- [Swift NIO SSH](https://github.com/apple/swift-nio-ssh) - SSH client implementation
- [CustomDump](https://github.com/pointfreeco/swift-custom-dump) - Enhanced testing utilities

## Contributing

1. Follow the existing code conventions and TCA patterns
2. Write tests for new features in the appropriate test modules
3. Use `package` access modifier for inter-module APIs
4. Leverage SwiftUI previews and TCA's `TestStore` for rapid development
5. Run `just lint` before committing changes

## License

MIT License - see [LICENSE](LICENSE) file for details.