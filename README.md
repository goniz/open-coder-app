# OpenCoder 🚀

> Your friendly iOS companion for remote development - code, build, and deploy from anywhere!

OpenCoder is a SwiftUI app that brings the power of remote development to your iPhone. With SSH server management, real-time task execution, and Live Activity progress tracking, you'll never miss a build status again.

## ✨ What Makes OpenCoder Special

- **🔌 Connect Anywhere**: Manage multiple dev servers with secure SSH (password or key-based auth)
- **⚡ Run Tasks Remotely**: Build, test, deploy, and install - all from your phone
- **📱 Live Activities**: Track progress right from your Lock Screen and Dynamic Island
- **💬 Chat Assistant**: Get help and manage tasks through an integrated chat interface
- **🔋 Battery Friendly**: Smart connection pooling that only stays active when you need it

## 🎯 Quick Start

### Requirements
- iOS 17.0+ / macOS 14.0+
- Xcode 16.0+
- Swift 6.0+

### Get Up and Running

```bash
# Clone and setup
git clone <repository-url>
cd open-coder-app

# Install dependencies
swift package resolve  # or: just update

# Build and run
swift build           # or: just build
```

### Handy Commands

```bash
just test              # Run all tests
just lint              # Check code style
just beta              # Deploy beta build
swift test --filter ModelsTests  # Run specific tests
```

## 🏗️ Architecture

Built with [The Composable Architecture (TCA)](https://github.com/pointfreeco/swift-composable-architecture) for rock-solid state management and testability.

**Module Structure:**
- `Models` - Core data types
- `DependencyClients` - Protocol definitions
- `Features` - Business logic with TCA reducers
- `Views` - Beautiful SwiftUI interfaces
- `OpenCoderLib` - App composition

Each module comes with comprehensive tests, making development fast and reliable!

## 🤝 Contributing

We'd love your help! Here's how to contribute:

1. Follow TCA patterns and existing conventions
2. Write tests for new features
3. Use SwiftUI previews for rapid UI development
4. Run `just lint` before committing

## 📦 Key Dependencies

- [TCA](https://github.com/pointfreeco/swift-composable-architecture) - State management
- [Swift NIO SSH](https://github.com/apple/swift-nio-ssh) - SSH connections
- [Swift Dependencies](https://github.com/pointfreeco/swift-dependencies) - Dependency injection

## 📄 License

MIT License - see [LICENSE](LICENSE) for details.

---

Made with ❤️ for developers who code on the go!