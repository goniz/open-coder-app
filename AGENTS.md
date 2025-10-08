# AGENTS.md - SwiftUI + TCA iOS App

## Commands
- **Preview app in Xcode: `just preview`** - Opens the app in Xcode Previews for interactive UI development and validation

- **Build core package on macOS: `just build-core-macos`** - Faster testing of business logic without iOS simulator
- Build iOS app: `just build-ios` (development build without publishing)
- Test core package: `just test` - Runs tests for OpenCoderCore package only
- Test single core package: `cd Packages/OpenCoderCore && swift test`
- **Lint all packages: `just lint`** - Lints all packages with strict mode (warnings as errors)
- **Fix lint issues: `just fix`** - Auto-fixes SwiftLint violations across all packages
- Format all packages: `just fmt` - Formats code across all packages
- Update packages: `just update` - Updates dependencies for root workspace
- **Development cycle: `just devcycle`** - Runs fix, lint, and preview in sequence with early exit on failure
- Beta deployment: `just beta` (runs fastlane from Xcode/)

## Development Workflow

**Testing Changes**: After making code changes, use `just preview` to validate UI changes interactively in Xcode Previews, or run `just devcycle` for comprehensive validation. Choose based on the nature of your changes:
- For UI-only changes: `just preview` provides immediate visual feedback
- For any code changes: `just devcycle` runs fix → lint → preview with early exit on failure

**IMPORTANT**: Always run `just devcycle` after completing work to ensure code quality. This command automatically:
1. Auto-fixes SwiftLint violations with `just fix`
2. Validates with strict SwiftLint checks (warnings as errors)
3. Opens Xcode Previews for interactive validation

The command uses `&&` chaining to exit immediately on any failure, ensuring issues are caught early.

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
- **IMPORTANT: Files in `Packages/OpenCoderCore/Sources/OpenAPIGenerated/` are AUTO-GENERATED and MUST NOT be edited manually**
- These files include:
  - `Client.swift` - Generated API client implementation
  - `Types.swift` - Generated type definitions for API models
  - `openapi.yaml` - OpenAPI specification (generated from OpenCode CLI)
  - `openapi-generator-config.yaml` - Configuration for code generation (do not edit)
- **To update these files, ALWAYS use: `just generate-opencode-api`**
- This command fetches the latest OpenAPI spec from OpenCode CLI and regenerates all client code
- Never commit manual edits to generated files - they will be overwritten on next generation

## Code Style
- Swift 6.0 with strict concurrency
- Package access level for public APIs within modules
- TCA patterns: `@Reducer`, `@ObservableState`, scoped actions
- Dependency injection via `@Dependency` and protocol-based clients
- File organization: group by feature, separate protocols from implementations
- Use `package` access modifier for inter-module APIs, `private`/`fileprivate` for internal
- No force unwrapping; prefer guard statements and optional binding
- Follow existing naming: UpperCamelCase for types, lowerCamelCase for properties/functions