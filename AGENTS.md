# AGENTS.md - SwiftUI + TCA iOS App

## Commands
- Build: `swift build` or `just build`
- Build iOS app: `just build-ios` (development build without publishing)
- Test all: `swift test` or `just test`
- Test single target: `swift test --filter ModelsTests` or `swift test --filter FeaturesTests.AppFeatureTests`
- Lint: `swiftlint Sources` or `just lint`
- Format: `swift-format --in-place --recursive Sources/` or `just fmt`
- Update packages: `swift package update` or `just update`
- Beta deployment: `just beta` (runs fastlane from Xcode/)

## Architecture
- Modular Swift Package with TCA (The Composable Architecture)
- Dependency hierarchy: Models → DependencyClients → Features → Views → OpenCoderLib
- Test targets for Features, Models, and Views modules

## Code Style
- Swift 6.0 with strict concurrency
- Package access level for public APIs within modules
- TCA patterns: `@Reducer`, `@ObservableState`, scoped actions
- Dependency injection via `@Dependency` and protocol-based clients
- File organization: group by feature, separate protocols from implementations
- Use `package` access modifier for inter-module APIs, `private`/`fileprivate` for internal
- No force unwrapping; prefer guard statements and optional binding
- Follow existing naming: UpperCamelCase for types, lowerCamelCase for properties/functions