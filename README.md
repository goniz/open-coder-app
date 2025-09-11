# OpenCoder

A friendly iOS companion for remote development. Manage SSH servers, run builds/tests/deploys on remote machines, and track progress on your Lock Screen with Live Activities.

## Highlights

- 🔌 SSH server management with persistent, battery‑aware connections
- ⚡ Remote task execution with real‑time progress and logs
- 📱 Live Activities & Dynamic Island updates for active tasks
- 💬 Built‑in chat to coordinate and manage work
- 📁 Simple project organization
- 🧩 Modular architecture powered by The Composable Architecture (TCA)

## Quick start

### Prerequisites
- iOS 17.0+ / macOS 14.0+
- Xcode 16.0+
- Swift 6.0+

### Setup

```bash
git clone <repository-url>
cd open-coder-app
swift package resolve
swift build
# optional helpers if you use just:
# just update
# just build
```

### Run tests

```bash
swift test
# or: just test
```

### Common commands

```bash
# Build
swift build
# Lint
swiftlint Sources
# Beta build (TestFlight)
just beta
```

## Architecture (at a glance)

Modular Swift Package with clear layers:

```
Models → DependencyClients → Features → Views → OpenCoderLib
```

Built with [The Composable Architecture (TCA)](https://github.com/pointfreeco/swift-composable-architecture), [Swift Dependencies](https://github.com/pointfreeco/swift-dependencies), and [SwiftNIO SSH](https://github.com/apple/swift-nio-ssh).

## Contributing

- Follow existing TCA patterns and module boundaries
- Add tests for new behavior
- Run linting before committing

## License

MIT — see [LICENSE](LICENSE).