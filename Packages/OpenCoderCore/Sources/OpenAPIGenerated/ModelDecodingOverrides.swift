import OpenAPIRuntime

extension Components.Schemas.Model {
  // Allow models lacking the optional `options` payload to decode instead of failing.
  package init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)

    let id = try container.decode(Swift.String.self, forKey: .id)
    let name = try container.decode(Swift.String.self, forKey: .name)
    let releaseDate = try container.decode(Swift.String.self, forKey: .release_date)
    let attachment = try container.decode(Swift.Bool.self, forKey: .attachment)
    let reasoning = try container.decode(Swift.Bool.self, forKey: .reasoning)
    let temperature = try container.decode(Swift.Bool.self, forKey: .temperature)
    let toolCall = try container.decode(Swift.Bool.self, forKey: .tool_call)
    let cost = try container.decode(costPayload.self, forKey: .cost)
    let limit = try container.decode(limitPayload.self, forKey: .limit)
    let experimental = try container.decodeIfPresent(Swift.Bool.self, forKey: .experimental)
    let options = try container.decodeIfPresent(optionsPayload.self, forKey: .options) ?? optionsPayload()
    let provider = try container.decodeIfPresent(providerPayload.self, forKey: .provider)

    self.init(
      id: id,
      name: name,
      release_date: releaseDate,
      attachment: attachment,
      reasoning: reasoning,
      temperature: temperature,
      tool_call: toolCall,
      cost: cost,
      limit: limit,
      experimental: experimental,
      options: options,
      provider: provider
    )
  }

  package func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)

    try container.encode(id, forKey: .id)
    try container.encode(name, forKey: .name)
    try container.encode(release_date, forKey: .release_date)
    try container.encode(attachment, forKey: .attachment)
    try container.encode(reasoning, forKey: .reasoning)
    try container.encode(temperature, forKey: .temperature)
    try container.encode(tool_call, forKey: .tool_call)
    try container.encode(cost, forKey: .cost)
    try container.encode(limit, forKey: .limit)
    try container.encodeIfPresent(experimental, forKey: .experimental)
    try container.encode(options, forKey: .options)
    try container.encodeIfPresent(provider, forKey: .provider)
  }
}
