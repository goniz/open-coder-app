# AGENTS.md - SwiftUI + TCA iOS App

## Commands
- Build: `swift build` or `just build`
- Build iOS app: `just build-ios` (development build without publishing)
- Test all: `swift test` or `just test`
- Test single target: `swift test --filter ModelsTests` or `swift test --filter FeaturesTests.AppFeatureTests`
- Lint: `swiftlint Sources` or `just lint`
- **Fix lint issues: `just fix`** - Auto-fixes SwiftLint violations where possible
- Format: `swift-format --in-place --recursive Sources/` or `just fmt`
- Update packages: `swift package update` or `just update`
- **Validate all: `just validate`** - Runs build, build-ios, lint, and test in sequence
- Beta deployment: `just beta` (runs fastlane from Xcode/)

## Development Workflow
**IMPORTANT**: Always run `just validate` between development cycles to catch all errors before proceeding. This comprehensive command runs:
1. Swift package build with warnings as errors
2. iOS app build for simulator 
3. SwiftLint checks
4. All unit tests

This ensures code quality and prevents issues from propagating through the codebase.

**Code Quality**: When `just validate` shows many lint warnings/errors, run `just fix` first to automatically resolve fixable issues, then re-run validation. This saves time and maintains consistent code style.

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