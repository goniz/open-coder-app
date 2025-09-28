import Foundation
import XCTest
@testable import Models

final class TmuxSessionNameTests: XCTestCase {
  private let hexCharacters = CharacterSet(charactersIn: "0123456789abcdef")

  private func sanitize(_ raw: String) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    let candidate = trimmed.isEmpty ? "workspace" : trimmed
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))

    var sanitized = String()
    sanitized.reserveCapacity(candidate.count)

    var previousSeparator = false
    for scalar in candidate.unicodeScalars {
      if allowed.contains(scalar) {
        sanitized.append(Character(scalar))
        previousSeparator = false
      } else {
        if !previousSeparator {
          sanitized.append("_")
        }
        previousSeparator = true
      }
    }

    let trimmedSeparators = sanitized.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    let base = trimmedSeparators.isEmpty ? "workspace" : trimmedSeparators
    return String(base.prefix(48))
  }

  private func assertHexEight(_ value: String, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(value.count, 8, file: file, line: line)
    XCTAssertTrue(value.unicodeScalars.allSatisfy { hexCharacters.contains($0) }, file: file, line: line)
  }

  func testSanitizesWorkspaceName() {
    let sessionName = TmuxSessionName(
      workspaceName: "My Workspace!",
      path: "/Users/gzahavy/PersonalProjects/open-coder-app"
    )

    XCTAssertEqual(sessionName.workspaceComponent, sanitize("My Workspace!"))
    XCTAssertEqual(sessionName.value, "ocw-\(sessionName.workspaceComponent)-\(sessionName.hashComponent)")
    XCTAssertFalse(sessionName.value.contains(" "))
    XCTAssertFalse(sessionName.value.contains("!"))
    assertHexEight(sessionName.hashComponent)
  }

  func testDeterministicForSameInputs() {
    let first = TmuxSessionName(workspaceName: "Dev", path: "/srv/workspaces/foo")
    let second = TmuxSessionName(workspaceName: "Dev", path: "/srv/workspaces/foo")

    XCTAssertEqual(first, second)
    XCTAssertEqual(first.value, second.value)
  }

  func testShortensLongWorkspaceNames() {
    let sessionName = TmuxSessionName(
      workspaceName: String(repeating: "a", count: 64),
      path: "/very/long/path/component/with/characters"
    )

    XCTAssertLessThanOrEqual(sessionName.workspaceComponent.count, 48)
    XCTAssertEqual(sessionName.value, "ocw-\(sessionName.workspaceComponent)-\(sessionName.hashComponent)")
    assertHexEight(sessionName.hashComponent)
  }

  func testFallbackWhenWorkspaceNameEmpty() {
    let sessionName = TmuxSessionName(workspaceName: "   ", path: "/tmp/workspace")
    XCTAssertEqual(sessionName.workspaceComponent, "workspace")
    XCTAssertEqual(sessionName.value, "ocw-\(sessionName.workspaceComponent)-\(sessionName.hashComponent)")
    assertHexEight(sessionName.hashComponent)
  }

  func testCanonicalizesLegacyNamesWithoutPrefix() {
    let legacy = TmuxSessionName(rawValue: "custom-session")
    XCTAssertEqual(legacy.workspaceComponent, sanitize("custom-session"))
    XCTAssertEqual(legacy.value, "ocw-\(legacy.workspaceComponent)-\(legacy.hashComponent)")
    assertHexEight(legacy.hashComponent)
  }

  func testCanonicalizesLegacyNamesWithDots() {
    let legacy = TmuxSessionName(rawValue: "ocw-gzahavy-192.168.1.252--3138353")
    XCTAssertEqual(legacy.workspaceComponent, sanitize("gzahavy-192.168.1.252--3138353"))
    XCTAssertEqual(legacy.value, "ocw-\(legacy.workspaceComponent)-\(legacy.hashComponent)")
    XCTAssertFalse(legacy.value.contains("."))
    assertHexEight(legacy.hashComponent)
  }

  func testCodableRoundTripUsesRawValue() throws {
    let original = TmuxSessionName(workspaceName: "Docs", path: "/srv/docs")
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(TmuxSessionName.self, from: data)

    XCTAssertEqual(decoded.value, original.value)
    XCTAssertEqual(decoded.workspaceComponent, original.workspaceComponent)
    XCTAssertEqual(decoded.hashComponent, original.hashComponent)
  }
}

final class WorkspaceTests: XCTestCase {
  func testInitializerGeneratesSessionWhenMissing() {
    let workspace = Workspace(
      name: "Project Alpha",
      host: "example.com",
      user: "user",
      remotePath: "/srv/workspaces/alpha"
    )

    XCTAssertEqual(workspace.tmuxSession.workspaceComponent, "Project_Alpha")
    XCTAssertEqual(workspace.tmuxSession.value, "ocw-\(workspace.tmuxSession.workspaceComponent)-\(workspace.tmuxSession.hashComponent)")
  }

  func testInitializerRespectsProvidedSession() {
    let provided = TmuxSessionName(rawValue: "custom")
    let workspace = Workspace(
      name: "Project Beta",
      host: "example.com",
      user: "user",
      remotePath: "/srv/workspaces/beta",
      tmuxSession: provided
    )

    XCTAssertEqual(workspace.tmuxSession, provided)
  }

  func testGenerateTmuxSessionNameDelegatesToType() {
    let generated = Workspace.generateTmuxSessionName(name: "Team Workspace", path: "/srv/path")
    let expected = TmuxSessionName.generate(workspaceName: "Team Workspace", path: "/srv/path")
    XCTAssertEqual(generated, expected)
  }
}
