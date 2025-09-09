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
# Build the project
swift build
just build

# Run tests
swift test
just test

# Run specific test target
swift test --filter ModelsTests
swift test --filter FeaturesTests.AppFeatureTests

# Lint code
swiftlint Sources
just lint

# Deploy beta build
just beta
```

## Architecture

OpenCoder uses a modular Swift Package structure with clear separation of concerns:

```
Models → DependencyClients → Features → Views → OpenCoderLib
   ↓           ↓                ↓        ↓
Tests      Tests            Tests    Tests
```

### Modules

- **Models**: Core data models (CodingTask, SSHServerConfiguration, etc.)
- **DependencyClients**: Protocol definitions for external dependencies (SSH, API, Background tasks)
- **DependencyClientsLive**: Live implementations of dependency clients
- **Features**: TCA reducers and business logic
- **Views**: SwiftUI views and UI components
- **OpenCoderLib**: Main app composition and dependency injection

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