import XCTest
@testable import Implementations
import Models
@testable import OpenAPIGenerated

final class ListProvidersMappingTests: XCTestCase {
  func testExtractDefaultsReturnsAllEntries() {
    let defaultsPayload = OpenAPIGenerated.Operations.config_period_providers.Output.Ok.Body.jsonPayload._defaultPayload(
      additionalProperties: [
        "opencode": "claude-sonnet-4-5",
        "anthropic": "claude-3-7-sonnet"
      ]
    )

    let result = LiveOpenCodeAPIClient.extractDefaults(
      from: defaultsPayload,
      fallback: "opencode"
    )

    XCTAssertEqual(result.primaryProviderID, "opencode")
    XCTAssertEqual(result.primaryModelID, "claude-sonnet-4-5")
    XCTAssertEqual(
      result.modelIDsByProvider["anthropic"],
      "claude-3-7-sonnet"
    )
  }

  func testProvidersWithDefaultsIncludesAllDefaultModels() {
    let providers = [
      "opencode": OpenCodeProviderInfo(name: "OpenCode", models: ["model-a": "Model A"]),
      "anthropic": OpenCodeProviderInfo(name: "Anthropic", models: ["model-b": "Model B"])
    ]
    let openCodeProviders = OpenCodeProviders(
      providers: providers,
      defaultModelsByProvider: ["anthropic": "model-b"],
      primaryDefaultProviderID: "opencode",
      primaryDefaultModelID: "model-a"
    )

    let result = ProvidersWithDefaults.from(openCodeProviders: openCodeProviders)

    XCTAssertEqual(result.defaultProviderID, "opencode")
    XCTAssertEqual(result.defaultModelID, "model-a")
    XCTAssertEqual(result.defaultModelIDsByProvider["anthropic"], "model-b")
  }
}
