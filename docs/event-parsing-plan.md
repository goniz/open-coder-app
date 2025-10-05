# Event Parsing Plan for OpenCode API Client

## Objective
Implement parsing for `message.updated` and `message.part.updated` events in the OpenCode API client to enable real-time updates in the chat interface without disabling the generated types.

## Current Status
- Basic session events (session.updated, session.deleted) are already parsed using generated types.
- Message events need to be added to the OpenCodeEvent enum.
- The SSE parsing in OpenCodeAPIClientLive.swift needs to be updated to handle the new events using JSONSerialization for flexibility.

## Steps

1. **Update OpenCodeEvent Enum in Models**
   - Add cases for `messageUpdated(OpenCodeMessage)` and `messagePartUpdated(sessionID: String, messageID: String, partID: String, part: MessagePart)`.
   - Ensure OpenCodeMessage conforms to Codable for direct decoding.

2. **Update OpenAPI Schema in openapi.yaml**
   - Define the Event schema as a oneOf union with discriminator on "type".
   - Add Message and Part schemas with required fields: id, sessionID, role, time, modelID, providerID for Message; type, content, id for Part.
   - Regenerate the types with the OpenAPI generator.

3. **Implement Parsing in OpenCodeAPIClientLive.swift**
   - In `parseEvent(from jsonString:)`, use JSONDecoder to decode the Event union.
   - For message.updated, decode to OpenCodeMessage directly.
   - For message.part.updated, decode the part and return the specific case.
   - Fall back to .unknown for unhandled events.

4. **Update SSE Stream Handling**
   - In `createEventStream(from:)`, parse each line's "data:" field using the new parseEvent function.
   - Ensure the stream yields the parsed OpenCodeEvent.

5. **Test with just preview**
   - Run `just preview` to verify compilation and basic functionality.
   - Test with mock SSE data to ensure events are parsed correctly.
   - Verify UI updates in the chat view respond to the new events.

## Implementation Details
- **Event Structure**:
  - `session.updated`: { "type": "session.updated", "data": { "info": Session } }
  - `session.deleted`: { "type": "session.deleted", "data": { "info": { "id": string } } }
  - `message.updated`: { "type": "message.updated", "data": { "info": Message } }
  - `message.part.updated`: { "type": "message.part.updated", "data": { "sessionID": string, "messageID": string, "part": Part } }

- **Message Model**:
  - id: String
  - sessionID: String
  - parts: [MessagePart]
  - timestamp: Date
  - role: String (maps to MessageRole)
  - modelID: String?
  - providerID: String?

- **MessagePart Model**:
  - type: String ("text", "reasoning", etc.)
  - content: String
  - id: String?

- **Parsing Logic**:
  - Use try? decoder.decode(Event.self, from: jsonData) where Event is the union.
  - Map the decoded value to the appropriate OpenCodeEvent case.
  - Handle decoding errors gracefully with .unknown.

## Potential Issues
- **Schema Compatibility**: Ensure the generated types match the API response exactly.
- **Performance**: JSONSerialization for complex unions might be slow; monitor for large streams.
- **Error Handling**: Log parsing errors but don't crash the stream.
- **Backward Compatibility**: Keep existing session event parsing intact.

## Next Steps After Implementation
- Integrate with ChatFeature to update messages in real-time.
- Add unit tests for event parsing.
- Test end-to-end with the actual OpenCode server.

This plan ensures robust event handling for real-time chat updates.