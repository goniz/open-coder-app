import Foundation
import OpenAPIGenerated
import OpenAPIRuntime
import Protocols
import Models

extension LiveOpenCodeAPIClient {
  public func log(_ message: String, level: LogLevel = .info) {
    Task { @MainActor in
      AppLogger.shared.log(message, level: level, category: .api)
    }
  }

  private func handleAPIError<T>(_ operation: String, error: Error) throws -> T {
    log("OpenCode API: \(operation) failed: \(error.localizedDescription)", level: .error)
    throw error
  }

  private func handleUndocumentedResponse<T>(_ operation: String, statusCode: Int) throws -> T {
    log("OpenCode API: \(operation) failed with status code: \(statusCode)", level: .error)
    throw OpenCodeAPIError.serverError("Failed to \(operation.lowercased()): \(statusCode)")
  }

  private func performAPICall<Input, Output, Result>(
    _ operation: String,
    input: Input,
    apiCall: (Input) async throws -> Output,
    responseHandler: (Output) throws -> Result
  ) async throws -> Result {
    log("OpenCode API: \(operation)")

    do {
      let response = try await apiCall(input)
      let result = try responseHandler(response)
      log("OpenCode API: Successfully completed \(operation.lowercased())")
      return result
    } catch {
      return try handleAPIError(operation, error: error)
    }
  }
}

// MARK: - Command Operations Extension

extension LiveOpenCodeAPIClient {
  public func sendCommand(sessionID: String, command: String, arguments: [String]) async throws -> OpenCodeMessage {
      let requestBody = Operations.session_period_command.Input.Body.json(
        .init(arguments: arguments.joined(separator: " "), command: command)
      )

      let input = Operations.session_period_command.Input(
        path: .init(id: sessionID),
        body: requestBody
      )

      return try await performAPICall(
        "Sending command '\(command)' to session: \(sessionID)",
        input: input,
        apiCall: client.session_period_command
      ) { response in
        switch response {
        case let .ok(okResponse):
          switch okResponse.body {
          case let .json(messageData):
            // Parse the actual server response instead of creating a fake message
            guard let message = parseMessageData(from: .commandResponse(messageData), sessionID: sessionID) else {
              throw OpenCodeAPIError.decodingError("Failed to parse command response")
            }
            return message
          }
        case let .undocumented(statusCode, _):
          return try handleUndocumentedResponse("send command", statusCode: statusCode)
        }
      }
    }

  public func runShellCommand(sessionID: String, command: String) async throws -> OpenCodeMessage {
      let requestBody = Operations.session_period_shell.Input.Body.json(
        .init(agent: "shell", command: command)
      )

      let input = Operations.session_period_shell.Input(
        path: .init(id: sessionID),
        body: requestBody
      )

      return try await performAPICall(
        "Running shell command '\(command)' in session: \(sessionID)",
        input: input,
        apiCall: client.session_period_shell
      ) { response in
        switch response {
        case let .ok(okResponse):
          switch okResponse.body {
          case let .json(assistantMessage):
            // Parse the actual server response instead of creating a fake message
            guard let message = parseMessageData(from: .shellResponse(assistantMessage), sessionID: sessionID) else {
              throw OpenCodeAPIError.decodingError("Failed to parse shell command response")
            }
            return message
          }
        case let .undocumented(statusCode, _):
          return try handleUndocumentedResponse("run shell command", statusCode: statusCode)
        }
      }
    }
}

// MARK: - Configuration Operations Extension

extension LiveOpenCodeAPIClient {
  public func getConfig() async throws -> OpenCodeConfig {
     let input = Operations.config_period_get.Input()

     return try await performAPICall(
       "Getting configuration",
       input: input,
       apiCall: client.config_period_get
     ) { response in
       switch response {
       case let .ok(okResponse):
         switch okResponse.body {
         case let .json(configData):
           let version = extractVersionFromSchema(configData._dollar_schema)
           let environment = determineEnvironment(from: configData)
           let features = extractFeatures(from: configData)

           return OpenCodeConfig(
             version: version,
             environment: environment,
             features: features
           )
         }
       case let .undocumented(statusCode, _):
         return try handleUndocumentedResponse("get config", statusCode: statusCode)
       }
     }
   }

  private func extractVersionFromSchema(_ schema: String?) -> String {
     guard let schema = schema else { return "unknown" }

     return schema
       .split(separator: "/").last?
       .split(separator: "#").first
       .map(String.init) ?? "unknown"
   }

  private func determineEnvironment(from configData: Components.Schemas.Config) -> String {
     if configData.theme?.contains("debug") == true {
       return "debug"
     } else if configData.theme?.contains("dev") == true {
       return "development"
     } else {
       return "production"
     }
   }

  private func extractFeatures(from configData: Components.Schemas.Config) -> [String] {
     var features: [String] = []

     if configData.keybinds?.session_new != nil {
       features.append("sessions")
     }

     if configData.command?.additionalProperties.isEmpty == false {
       features.append("commands")
     }

     if configData.theme != nil {
       features.append("theming")
     }

     if configData.tui != nil {
       features.append("tui")
     }

     if features.isEmpty {
       features = ["basic"]
     }

     return features
   }

  public func listProviders() async throws -> OpenCodeProviders {
     let input = Operations.config_period_providers.Input()

     return try await performAPICall(
       "Listing providers",
       input: input,
       apiCall: client.config_period_providers
      ) { response in
        switch response {
        case let .ok(okResponse):
          switch okResponse.body {
          case let .json(providersData):
            let providerDict = buildProviderDictionary(from: providersData.providers)
            let (defaultProvider, defaultModel) = extractDefaults(
              from: providersData._default,
              fallback: providersData.providers.first?.id
            )

            return OpenCodeProviders(
              providers: providerDict,
              defaultProvider: defaultProvider,
              defaultModel: defaultModel
            )
          }
        case let .undocumented(statusCode, _):
          return try handleUndocumentedResponse("list providers", statusCode: statusCode)
        }
      }
   }

  private func buildProviderDictionary(
    from providers: [Components.Schemas.Provider]
  ) -> [String: OpenCodeProviderInfo] {
     var providerDict: [String: OpenCodeProviderInfo] = [:]

      for provider in providers {
        var models: [String: String] = [:]

        for (modelId, model) in provider.models.additionalProperties {
          models[modelId] = model.name
        }

        if models.isEmpty {
          models[provider.id] = provider.name
        }

        providerDict[provider.id] = OpenCodeProviderInfo(
          name: provider.name,
          models: models
        )
      }

     return providerDict
   }

   private func extractDefaults(
    from defaultData: Operations.config_period_providers.Output.Ok.Body.jsonPayload._defaultPayload,
    fallback: String?
  ) -> (provider: String, model: String?) {
     if let providerID = defaultData.additionalProperties.keys.first {
       let modelID = defaultData.additionalProperties[providerID]
       return (providerID, modelID)
     }
     return (fallback ?? "openai", nil)
   }
}
