# AGENTS.md - SwiftUI + TCA iOS App

## Commands
- **Build all packages: `just build`** - Builds OpenCoderCore (macOS+iOS), OpenCoderUI (iOS), and OpenCoderApp (iOS)
- **Build core package on macOS: `just build-core-macos`** - Faster testing of business logic without iOS simulator
- Build iOS app: `just build-ios` (development build without publishing)
- Test core package: `just test` - Runs tests for OpenCoderCore package only
- Test single core package: `cd Packages/OpenCoderCore && swift test`
- **Lint all packages: `just lint`** - Lints all packages with strict mode (warnings as errors)
- **Fix lint issues: `just fix`** - Auto-fixes SwiftLint violations across all packages
- Format all packages: `just fmt` - Formats code across all packages
- Update packages: `just update` - Updates dependencies for root workspace
- **Development cycle: `just devcycle`** - Runs lint, build, build-ios, and test in sequence with early exit on failure
- Beta deployment: `just beta` (runs fastlane from Xcode/)

## Development Workflow
**IMPORTANT**: Always run `just devcycle` between development cycles to catch all errors before proceeding. This comprehensive command runs:
1. SwiftLint checks with strict mode (warnings as errors)
2. Swift package build with warnings as errors
3. iOS app build for simulator 
4. Core package unit tests

This ensures code quality and prevents issues from propagating through the codebase. The command uses `&&` chaining to exit immediately on any failure.

**Code Quality**: When `just devcycle` shows lint warnings/errors, run `just fix` first to automatically resolve fixable issues, then re-run the development cycle. Always fix all issues raised by `just devcycle` before proceeding with development.

**Feature Completion**: When finishing up with a feature request or major bug fix, run `just beta` after a successful `just devcycle` to deploy to TestFlight for testing.

**Git Usage**: NEVER use `git add .` - always add specific paths to avoid committing unwanted files like node_modules. Use `git add <specific-file>` or `git add <directory>` for targeted changes.

## Architecture
- **Multi-package Swift architecture** with platform separation and TCA (The Composable Architecture)
- **OpenCoderCore** (iOS + macOS): Models, Protocols, Implementations, Features, OpenAPIGenerated
- **OpenCoderUI** (iOS only): Views, IOSProtocols (platform-specific implementations)
- **OpenCoderApp** (iOS only): App entry point with dependency configuration
- **Platform separation**: Core business logic testable on macOS, UI layer iOS-specific
- Test targets for each package and module

## Generated API Files
- Auto-generated API files are created during the build process from OpenAPI specifications in `Packages/OpenCoderCore/Sources/OpenAPIGenerated/`.
- Key files include `Types.swift` which contains type definitions for API models.
- After running `swift build`, generated files can be found in the `.build/` directory under the OpenAPIGenerated target.
- Use `just generate-opencode-api` to regenerate API specifications from the latest OpenCode CLI.

## Code Style
- Swift 6.0 with strict concurrency
- Package access level for public APIs within modules
- TCA patterns: `@Reducer`, `@ObservableState`, scoped actions
- Dependency injection via `@Dependency` and protocol-based clients
- File organization: group by feature, separate protocols from implementations
- Use `package` access modifier for inter-module APIs, `private`/`fileprivate` for internal
- No force unwrapping; prefer guard statements and optional binding
- Follow existing naming: UpperCamelCase for types, lowerCamelCase for properties/functions