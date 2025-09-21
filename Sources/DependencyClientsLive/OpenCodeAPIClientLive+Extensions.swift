import Foundation
import OpenAPIGenerated
import OpenAPIRuntime
import DependencyClients
import Models

extension LiveOpenCodeAPIClient {
  package func log(_ message: String, level: LogLevel = .info) {
    Task { @MainActor in
      AppLogger.shared.log(message, level: level, category: .api)
    }
  }
}

// MARK: - Command Operations Extension

extension LiveOpenCodeAPIClient {
  package func sendCommand(sessionID: String, command: String, arguments: [String]) async throws -> OpenCodeMessage {
    log("🔗 OpenCode API: Sending command '\(command)' to session: \(sessionID)")

    let requestBody = Operations.session_period_command.Input.Body.json(
      .init(arguments: arguments.joined(separator: " "), command: command)
    )

    let input = Operations.session_period_command.Input(
      path: .init(id: sessionID),
      body: requestBody
    )

    do {
      let response = try await client.session_period_command(input)

      switch response {
      case let .ok(okResponse):
        switch okResponse.body {
        case .json:
          let message = OpenCodeMessage(
            id: UUID().uuidString,
            sessionID: sessionID,
            parts: [.text("Command executed: \(command)")],
            timestamp: Date(),
            role: .assistant
          )
          log("✅ OpenCode API: Successfully executed command '\(command)' in session: \(sessionID)")
          return message
        }
      case let .undocumented(statusCode, _):
        log("❌ OpenCode API: Send command failed with status code: \(statusCode)", level: .error)
        throw OpenCodeAPIError.serverError("Failed to send command: \(statusCode)")
      }
    } catch {
      log("❌ OpenCode API: Send command failed: \(error.localizedDescription)", level: .error)
      throw error
    }
  }

  package func runShellCommand(sessionID: String, command: String) async throws -> OpenCodeMessage {
    log("🔗 OpenCode API: Running shell command '\(command)' in session: \(sessionID)")

    let requestBody = Operations.session_period_shell.Input.Body.json(
      .init(agent: "shell", command: command)
    )

    let input = Operations.session_period_shell.Input(
      path: .init(id: sessionID),
      body: requestBody
    )

    do {
      let response = try await client.session_period_shell(input)

      switch response {
      case let .ok(okResponse):
        switch okResponse.body {
        case .json:
          let message = OpenCodeMessage(
            id: UUID().uuidString,
            sessionID: sessionID,
            parts: [.text("Shell command executed: \(command)")],
            timestamp: Date(),
            role: .assistant
          )
          log("✅ OpenCode API: Successfully executed shell command '\(command)' in session: \(sessionID)")
          return message
        }
      case let .undocumented(statusCode, _):
        log("❌ OpenCode API: Run shell command failed with status code: \(statusCode)", level: .error)
        throw OpenCodeAPIError.serverError("Failed to run shell command: \(statusCode)")
      }
    } catch {
      log("❌ OpenCode API: Run shell command failed: \(error.localizedDescription)", level: .error)
      throw error
    }
  }
}

// MARK: - Configuration Operations Extension

extension LiveOpenCodeAPIClient {
   package func getConfig() async throws -> OpenCodeConfig {
     log("🔗 OpenCode API: Getting configuration")

     let input = Operations.config_period_get.Input()

     do {
       let response = try await client.config_period_get(input)

       switch response {
       case let .ok(okResponse):
         switch okResponse.body {
         case let .json(configData):
           // Parse the actual JSON response
           let version = configData._dollar_schema?
             .split(separator: "/").last?
             .split(separator: "#").first
             .map(String.init) ?? "0.10.1"
           let environment = "development" // Default environment
           let features = ["sessions", "projects", "chat"] // Default features

           let config = OpenCodeConfig(
             version: version,
             environment: environment,
             features: features
           )
           log("✅ OpenCode API: Successfully retrieved configuration (version: \(version))")
           return config
         }
       case let .undocumented(statusCode, _):
         log("❌ OpenCode API: Get config failed with status code: \(statusCode)", level: .error)
         throw OpenCodeAPIError.serverError("Failed to get config: \(statusCode)")
       }
     } catch {
       log("❌ OpenCode API: Get config failed: \(error.localizedDescription)", level: .error)
       throw error
     }
   }

  package func listProviders() async throws -> OpenCodeProviders {
    log("🔗 OpenCode API: Listing providers")

    let input = Operations.config_period_providers.Input()

    do {
      let response = try await client.config_period_providers(input)

      switch response {
      case let .ok(okResponse):
        switch okResponse.body {
        case let .json(providersData):
          // Convert providers array to dictionary format expected by domain model
          var providerDict: [String: [String: String]] = [:]
          for provider in providersData.providers {
            // For now, create a simple mapping
            providerDict[provider.id] = [provider.id: provider.id]
          }

          let providers = OpenCodeProviders(
            providers: providerDict,
            defaultProvider: providersData.providers.first?.id ?? "openai"
          )
          log("✅ OpenCode API: Successfully retrieved \(providersData.providers.count) providers")
          return providers
        }
      case let .undocumented(statusCode, _):
        log("❌ OpenCode API: List providers failed with status code: \(statusCode)", level: .error)
        throw OpenCodeAPIError.serverError("Failed to list providers: \(statusCode)")
      }
    } catch {
      log("❌ OpenCode API: List providers failed: \(error.localizedDescription)", level: .error)
      throw error
    }
  }
}
