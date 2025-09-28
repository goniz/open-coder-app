# OpenCoder Maintenance Report

## 1. Unused Code/Files That Can Be Deleted

Based on a cross-file analysis of imports, usages, and dependencies:

- **Packages/OpenCoderCore/Sources/OpenAPIGenerated/Placeholder.swift**: This file contains only a comment indicating it's a placeholder for OpenAPI-generated code. No references to its contents exist in other files, and the OpenAPI generator plugin is configured but appears unused (no generated code is present). Delete this file to remove boilerplate; regenerate via the plugin if needed.

- **Packages/OpenCoderCore/Tests/ModelsTests/PlaceholderTests.swift**: This test file contains a single trivial assertion (`XCTAssertTrue(true)`). It does not test any functionality and is not referenced by other tests. Delete this file to simplify the test suite.

- **Packages/OpenCoderCore/Sources/Features/WorkspacesFeature+Behavior.swift**: This extension defines `handleWorkspacesLoaded`, `handleAddWorkspace`, etc., but these methods are not called in the main `WorkspacesFeature` reducer or other files. The main reducer uses different handlers (e.g., `handleTask`, `handleOpenWorkspace`). Delete this file as it's redundant or leftover from refactoring.

- **Packages/OpenCoderCore/Sources/Implementations/OpenCodeAPIClientLive+Messages.swift**: This extension defines `sendMessage`, `getMessages`, etc., but the implementations are incomplete or stubbed (e.g., they log but return hardcoded or partial data). No calls to these specific methods are found in other files; the main client uses generated OpenAPI calls. Delete if not intended for use; otherwise, complete the implementations.

- **Unused Variables/Constants**: In `Packages/OpenCoderCore/Sources/Models/AppLogger.swift`, the `LogCategory` enum has cases like `.fileSystem` that are defined but never used in any logging calls across the codebase. Remove unused cases to simplify.

- **Unused Imports**: Several files have unused imports, e.g., `Packages/OpenCoderCore/Sources/Protocols/OpenCodeAPIClient.swift` imports `OpenAPIGenerated` but doesn't use it directly (used in generated code, but if Placeholder.swift is deleted, review). Clean these up globally.

These deletions would reduce codebase size by ~5 files and ~200 lines without impacting functionality.

## 2. Overly Complex Code That Can Be Simplified

The following code sections have high complexity (e.g., cyclomatic complexity >10, long functions >100 lines, or nested conditionals). Each includes a 1-2 sentence simplification suggestion with file:line references.

- **File: Packages/OpenCoderCore/Sources/Implementations/SSHClientLive.swift (lines 37-87, `exec` method)**: This method has nested try-catch blocks, multiple buffer manipulations, and complex error handling for stdout/stderr. Simplify by extracting buffer flushing and error parsing into separate helper methods (e.g., `flushBuffers` and `handleChannelError`), reducing the main method to ~40 lines focused on channel setup and result aggregation.

- **File: Packages/OpenCoderCore/Sources/Features/WorkspacesFeature.swift (lines 76-136, `core` reducer)**: The reducer has high cyclomatic complexity due to a large switch on 20+ actions, with inline state mutations and effect creation. Refactor by breaking into smaller reducer methods (e.g., `reduceTask`, `reduceOpenWorkspace`) called from `core`, each handling 2-3 related actions, to improve readability and testability.

- **File: Packages/OpenCoderCore/Tests/ImplementationsTests/SSHClientIntegrationTests.swift (lines 20-350, multiple test methods)**: The integration tests are overly long and monolithic, with embedded shell scripting and process management. Split into separate test classes (e.g., `SSHDSetupTests`, `SFTPTests`, `NIOSSHClientTests`) and extract helper functions for key generation and process cleanup to reduce each method to <100 lines.

- **File: Packages/OpenCoderCore/Sources/Implementations/SSHClientLive+Extensions.swift (lines 28-63, `spawnWorkspaceSession`)**: This async function has deep nesting for tmux operations, error handling, and retries. Simplify by extracting sub-functions like `createTmuxSession` and `parsePortFromOutput`, and use a state machine (e.g., enum for phases) instead of nested do-try-catch, cutting complexity by 50%.

- **File: Packages/OpenCoderCore/Sources/Protocols/SSHClient.swift (lines 486-588, `exec` method)**: Deep nesting in connection setup, auth delegation, and error recovery. Refactor the NIO bootstrap and channel creation into a dedicated `SSHConnectionBuilder` struct, separating concerns and reducing the method to high-level orchestration (~30 lines).

## 3. Unnecessary Abstractions

The following abstractions add indirection without clear benefits (e.g., protocols with single implementations or over-generalization). Explanations include why they're unnecessary and file references.

- **Protocol: OpenCodeAPIClientFactoryProtocol in Packages/OpenCoderCore/Sources/Protocols/OpenCodeAPIClientFactoryDependency.swift**: This protocol defines a single `make` closure with no additional methods, and its only implementation is `OpenCodeAPIClientFactory` (which wraps another closure). It's unnecessary boilerplate; directly use the concrete `OpenCodeAPIClientFactory` type or inline the closure in dependency injection. This simplifies DI without losing testability (remove lines 4-6, use concrete types in live/test values).

- **Protocol: PortForwardingClient in Packages/OpenCoderCore/Sources/Protocols/PortForwardingClient.swift**: Single implementation (`LivePortForwardingClient`) with no variations or mocking needs beyond the basic interface. The abstraction adds no value since there's no polymorphism; replace with direct use of `LivePortForwardingClient` in `WorkspacesFeature.swift` (lines 62-64) and remove the protocol (saves ~20 lines, reduces indirection).

- **Enum: SSHError in Packages/OpenCoderCore/Sources/Protocols/SSHClient.swift (lines 408-435)**: Overly broad with cases like `.connectionFailed(String)` that duplicate underlying errors (e.g., NIO's ChannelError). Unnecessary as it wraps errors without adding value; remove and propagate underlying errors directly in callers like `exec` (line 486+), using `detailedErrorDescription` helper for logging. This avoids error proliferation (remove lines 408-435, update usages).

- **Struct: WorkspaceDTO and SessionMetaDTO in Packages/OpenCoderCore/Sources/Models/Workspace.swift (lines 104-125)**: These are simple 1:1 mappings from domain models to Codable types, but no serialization/deserialization is used in the codebase (e.g., no JSON encoding/decoding calls). Unnecessary if not used for API; inline conversions in any future API layers or delete if unused (remove lines 104-125, simplify Workspace init).

- **Actor: SSHConnectionPool in Packages/OpenCoderCore/Sources/Protocols/SSHConnectionPool.swift (lines 6-38)**: Actor isolation adds overhead for a simple dictionary of managers, with no concurrent access patterns beyond basic get/set. Unnecessary actor; make it a plain class with a mutex for thread-safety if needed, or use a simple dictionary in a non-actor class (remove actor keyword line 6, simplify accessors).

## 4. Unused Mock Implementations

- **MockOpenCodeAPIClient in Packages/OpenCoderCore/Sources/Protocols/OpenCodeAPIClient.swift (lines 175-302)**: This mock provides test data for sessions/projects but is only used in the testValue of `OpenCodeAPIClientKey` (line 307). No non-test code calls it; it's unused in production. Delete if tests can use live client with mocked responses, or keep only if expanding test coverage.

- **UnimplementedPortForwardingClient in Packages/OpenCoderCore/Sources/Protocols/PortForwardingClient.swift (lines 39-49)**: This stub throws an error and is only assigned to testValue of `PortForwardingClientKey` (line 28). Unused in non-test code; delete and use a failing implementation directly in tests.

- **MockFactory in Packages/OpenCoderCore/Sources/Protocols/OpenCodeAPIClientFactoryDependency.swift (lines 29-33)**: Returns `MockOpenCodeAPIClient` but is only used in testValue (line 10). Unused elsewhere; delete if mocks are not needed in integration tests.

## 5. Mock Implementations Used in Non-Test Code

No mock implementations are used in non-test code. All production paths use live implementations (e.g., `LiveOpenCodeAPIClient` in `OpenCodeAPIClientFactory.live`, `LivePortForwardingClient` in dependency values). Mocks are strictly confined to testValues in dependency keys, ensuring production code uses real services. If mocks leak into non-test paths (e.g., via unconfigured DI), add assertions in init methods to fatalError.