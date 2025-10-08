import Foundation
import XCTest
@testable import OpenAPIGenerated

final class OpenCodeProvidersDecodingTests: XCTestCase {
  func testGeneratedProviderDecodingHandlesMissingOptions() throws {
    let data = try loadFixture(named: "config_providers_response", withExtension: "json")

    let payload: Operations.config_period_providers.Output.Ok.Body.jsonPayload
    do {
      payload = try JSONDecoder().decode(
        Operations.config_period_providers.Output.Ok.Body.jsonPayload.self,
        from: data
      )
    } catch {
      XCTFail("Decoding failed: \(error)")
      throw error
    }

    let opencode = try XCTUnwrap(payload.providers.first(where: { $0.id == "opencode" }))
    let grokCode = try XCTUnwrap(opencode.models.additionalProperties["grok-code"])
    let codeSupernova = try XCTUnwrap(opencode.models.additionalProperties["code-supernova"])

    XCTAssertEqual(grokCode.name, "Grok Code Fast 1")
    XCTAssertTrue(grokCode.options.additionalProperties.isEmpty)

    XCTAssertEqual(codeSupernova.name, "Code Supernova 1M")
    XCTAssertTrue(codeSupernova.options.additionalProperties.isEmpty)
  }

  func testGeneratedProviderDecodingIncludesDefaultMappings() throws {
    let data = try loadFixture(named: "config_providers_response", withExtension: "json")

    let payload: Operations.config_period_providers.Output.Ok.Body.jsonPayload
    do {
      payload = try JSONDecoder().decode(
        Operations.config_period_providers.Output.Ok.Body.jsonPayload.self,
        from: data
      )
    } catch {
      XCTFail("Decoding failed: \(error)")
      throw error
    }

    XCTAssertEqual(payload._default.additionalProperties["opencode"], "claude-sonnet-4-5")
    XCTAssertEqual(payload._default.additionalProperties["anthropic"], "claude-sonnet-4-5-20250929")
  }
}

private func loadFixture(named name: String, withExtension ext: String) throws -> Data {
  let filename = "\(name).\(ext)"
  let directURL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("Fixtures")
    .appendingPathComponent(filename)

  var candidateURLs = [directURL]

  if let testSrcDir = ProcessInfo.processInfo.environment["TEST_SRCDIR"] {
    let base = URL(fileURLWithPath: testSrcDir)
    candidateURLs.append(
      base
        .appendingPathComponent("Packages/OpenCoderCore/Tests/ImplementationsTests/Fixtures", isDirectory: true)
        .appendingPathComponent(filename)
    )

    if let workspace = ProcessInfo.processInfo.environment["TEST_WORKSPACE"] {
      candidateURLs.append(
        base
          .appendingPathComponent(workspace, isDirectory: true)
          .appendingPathComponent("Packages/OpenCoderCore/Tests/ImplementationsTests/Fixtures", isDirectory: true)
          .appendingPathComponent(filename)
      )
    }

    candidateURLs.append(
      base
        .appendingPathComponent("_main", isDirectory: true)
        .appendingPathComponent("Packages/OpenCoderCore/Tests/ImplementationsTests/Fixtures", isDirectory: true)
        .appendingPathComponent(filename)
    )
  }

  if let runfilesDir = ProcessInfo.processInfo.environment["RUNFILES_DIR"] {
    let runfilesBase = URL(fileURLWithPath: runfilesDir)
    candidateURLs.append(
      runfilesBase
        .appendingPathComponent("Packages/OpenCoderCore/Tests/ImplementationsTests/Fixtures", isDirectory: true)
        .appendingPathComponent(filename)
    )

    candidateURLs.append(
      runfilesBase
        .appendingPathComponent("_main", isDirectory: true)
        .appendingPathComponent("Packages/OpenCoderCore/Tests/ImplementationsTests/Fixtures", isDirectory: true)
        .appendingPathComponent(filename)
    )

    if let workspace = ProcessInfo.processInfo.environment["TEST_WORKSPACE"] {
      candidateURLs.append(
        runfilesBase
          .appendingPathComponent(workspace, isDirectory: true)
          .appendingPathComponent("Packages/OpenCoderCore/Tests/ImplementationsTests/Fixtures", isDirectory: true)
          .appendingPathComponent(filename)
      )
    }
  }

  for url in candidateURLs {
    if let data = FileManager.default.contents(atPath: url.path), !data.isEmpty {
      return data
    }
  }

  struct FixtureError: LocalizedError {
    let name: String
    let searched: [String]
    var errorDescription: String? {
      let locations = searched.joined(separator: ", ")
      return "Missing fixture \(name). Searched: \(locations)"
    }
  }

  throw FixtureError(name: filename, searched: candidateURLs.map(\.path))
}
