import XCTest
import OpenAPIGenerated
import OpenAPIRuntime
@testable import Implementations
@testable import Models
@testable import Protocols

final class OpenCodeAPIClientLiveTests: XCTestCase {
  
  // MARK: - Configuration Parsing Tests
  
  func testExtractVersionFromSchema() {
    let client = createTestClient()
    
    // Test valid schema with version
    let schema1 = "https://example.com/schema/v1.2.3#/definitions/config"
    let version1 = client.extractVersionFromSchema(schema1)
    XCTAssertEqual(version1, "v1.2.3")
    
    // Test schema without version
    let schema2 = "https://example.com/schema/#/definitions/config"
    let version2 = client.extractVersionFromSchema(schema2)
    XCTAssertEqual(version2, "")
    
    // Test nil schema
    let version3 = client.extractVersionFromSchema(nil)
    XCTAssertEqual(version3, "unknown")
  }
  
  func testDetermineEnvironment() {
    let client = createTestClient()
    
    // Test debug theme
    var config = Components.Schemas.Config(theme: "debug-theme")
    var environment = client.determineEnvironment(from: config)
    XCTAssertEqual(environment, "debug")
    
    // Test development theme
    config = Components.Schemas.Config(theme: "dev-theme")
    environment = client.determineEnvironment(from: config)
    XCTAssertEqual(environment, "development")
    
    // Test production (default)
    config = Components.Schemas.Config(theme: "production-theme")
    environment = client.determineEnvironment(from: config)
    XCTAssertEqual(environment, "production")
    
    // Test nil theme (defaults to production)
    config = Components.Schemas.Config(theme: nil)
    environment = client.determineEnvironment(from: config)
    XCTAssertEqual(environment, "production")
  }
  
  func testExtractFeatures() {
    let client = createTestClient()
    
    // Test config with various features
    let keybinds = Components.Schemas.KeybindsConfig(session_new: "ctrl+n")
    let command = Components.Schemas.Config.commandPayload(
      additionalProperties: ["test": Components.Schemas.Config.commandPayload.additionalPropertiesPayload(template: "test")]
    )
    let tui = Components.Schemas.Config.tuiPayload(scroll_speed: 1.0)
    
    let config = Components.Schemas.Config(
      _dollar_schema: nil,
      theme: "dark",
      keybinds: keybinds,
      tui: tui,
      command: command
    )
    
    let features = client.extractFeatures(from: config)
    
    XCTAssertTrue(features.contains("sessions"))
    XCTAssertTrue(features.contains("commands"))
    XCTAssertTrue(features.contains("theming"))
    XCTAssertTrue(features.contains("tui"))
  }
  
  func testExtractFeaturesEmpty() {
    let client = createTestClient()
    
    // Test empty config
    let config = Components.Schemas.Config()
    let features = client.extractFeatures(from: config)
    
    XCTAssertEqual(features, ["basic"])
  }
  
  // MARK: - Provider Mapping Tests
  
  func testBuildProviderDictionary() {
    let client = createTestClient()
    
    let model1 = Components.Schemas.Model(name: "GPT-4")
    let model2 = Components.Schemas.Model(name: "Claude-3")
    
    let provider1Models = Components.Schemas.Provider.modelsPayload(
      additionalProperties: ["gpt-4": model1]
    )
    let provider2Models = Components.Schemas.Provider.modelsPayload(
      additionalProperties: ["claude-3": model2]
    )
    
    let provider1 = Components.Schemas.Provider(
      api: nil,
      name: "OpenAI",
      env: [],
      id: "openai",
      npm: nil,
      models: provider1Models
    )
    
    let provider2 = Components.Schemas.Provider(
      api: nil,
      name: "Anthropic", 
      env: [],
      id: "anthropic",
      npm: nil,
      models: provider2Models
    )
    
    let providers = [provider1, provider2]
    let result = client.buildProviderDictionary(from: providers)
    
    XCTAssertEqual(result["openai"]?["gpt-4"], "GPT-4")
    XCTAssertEqual(result["anthropic"]?["claude-3"], "Claude-3")
  }
  
  func testBuildProviderDictionaryNoModels() {
    let client = createTestClient()
    
    let provider = Components.Schemas.Provider(
      api: nil,
      name: "TestProvider",
      env: [],
      id: "test",
      npm: nil,
      models: nil
    )
    
    let providers = [provider]
    let result = client.buildProviderDictionary(from: providers)
    
    XCTAssertEqual(result["test"]?["test"], "TestProvider")
  }
  
  // MARK: - Error Handling Tests
  
  func testHandleAPIError() {
    let client = createTestClient()
    
    let testError = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Test error"])
    
    XCTAssertThrowsError(try client.handleAPIError("test operation", error: testError) as Void) { error in
      XCTAssertEqual((error as NSError).localizedDescription, "Test error")
    }
  }
  
  func testHandleUndocumentedResponse() {
    let client = createTestClient()
    
    XCTAssertThrowsError(try client.handleUndocumentedResponse("test operation", statusCode: 500) as Void) { error in
      XCTAssertTrue(error is OpenCodeAPIError)
      if case .serverError(let message) = error as? OpenCodeAPIError {
        XCTAssertEqual(message, "Failed to test operation: 500")
      } else {
        XCTFail("Expected serverError")
      }
    }
  }
  
  // MARK: - Helper Methods
  
  private func createTestClient() -> TestableOpenCodeAPIClient {
    let config = OpenCodeConfiguration.development
    return TestableOpenCodeAPIClient(configuration: config)
  }
}

// MARK: - Testable Client

private class TestableOpenCodeAPIClient: LiveOpenCodeAPIClient {
  
  // Expose private methods for testing
  func extractVersionFromSchema(_ schema: String?) -> String {
    super.extractVersionFromSchema(schema)
  }
  
  func determineEnvironment(from configData: Components.Schemas.Config) -> String {
    super.determineEnvironment(from: configData)
  }
  
  func extractFeatures(from configData: Components.Schemas.Config) -> [String] {
    super.extractFeatures(from: configData)
  }
  
  func buildProviderDictionary(from providers: [Components.Schemas.Provider]) -> [String: [String: String]] {
    super.buildProviderDictionary(from: providers)
  }
  
  func handleAPIError<T>(_ operation: String, error: Error) throws -> T {
    return try super.handleAPIError(operation, error: error)
  }
  
  func handleUndocumentedResponse<T>(_ operation: String, statusCode: Int) throws -> T {
    return try super.handleUndocumentedResponse(operation, statusCode: statusCode)
  }
}