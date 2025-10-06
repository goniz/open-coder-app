# Event Parsing Plan for OpenCode API Client

## Status: ✅ IMPLEMENTED

## Objective
Implement parsing for `message.updated` and `message.part.updated` events in the OpenCode API client to enable real-time updates in the chat interface without disabling the generated types.

## Current Status
✅ **COMPLETE** - All core event parsing functionality has been implemented:
- ✅ Session events (session.updated, session.deleted) are parsed
- ✅ Message events (message.updated, message.part.updated) are added to OpenCodeEvent enum
- ✅ SSE parsing in OpenCodeAPIClientLive.swift handles all event types using JSONSerialization

## Implementation Phases

### Phase 1: Event Model Updates - ✅ COMPLETE
**Status:** Fully implemented in `OpenCodeAPIClient.swift:40-47`

1. **✅ Update OpenCodeEvent Enum in Models**
   - ✅ Added `messageUpdated(OpenCodeMessage)` case
   - ✅ Added `messagePartUpdated(sessionID: String, messageID: String, partID: String, part: MessagePart)` case
   - ✅ OpenCodeMessage is defined as a struct (lines 94-136)
   - ✅ MessagePart enum is defined (lines 144-151)

### Phase 2: OpenAPI Schema Definition - ✅ COMPLETE
**Status:** Fully implemented in `openapi.yaml:1273-1377`

2. **✅ Update OpenAPI Schema in openapi.yaml**
   - ✅ Event schema defined as oneOf union with discriminator on "type" (lines 1273-1324)
   - ✅ Message schema added with required fields: id, sessionID, role, time (lines 1325-1344)
   - ✅ Part schema added with required fields: type, content (lines 1345-1356)
   - ✅ Session schema already defined (lines 1357-1377)

### Phase 3: Event Parsing Implementation - ✅ COMPLETE
**Status:** Fully implemented in `OpenCodeAPIClientLive.swift:237-346`

3. **✅ Implement Parsing in OpenCodeAPIClientLive.swift**
   - ✅ `parseEvent(from jsonString:)` implemented (lines 237-258)
   - ✅ `parseMessageUpdatedEvent()` decodes message data (lines 289-317)
   - ✅ `parseMessagePartUpdatedEvent()` decodes part updates (lines 319-332)
   - ✅ `parseMessagePartFromJSON()` helper converts JSON to MessagePart (lines 334-345)
   - ✅ Falls back to `.unknown` for unhandled events (line 256)

### Phase 4: SSE Stream Handling - ✅ COMPLETE
**Status:** Fully implemented in `OpenCodeAPIClientLive.swift:175-209`

4. **✅ Update SSE Stream Handling**
   - ✅ `createEventStream(from:)` processes SSE data (lines 175-209)
   - ✅ Parses each "data:" line using parseEvent function (lines 189-194)
   - ✅ Stream yields parsed OpenCodeEvent instances
   - ✅ Proper error handling and stream completion

### Phase 5: Testing & Validation - ⚠️ PARTIAL
**Status:** Mock implementation available, end-to-end testing pending

5. **⚠️ Test with just preview**
   - ✅ Mock implementation in MockOpenCodeAPIClient provides test events (lines 353-379)
   - ⚠️ End-to-end testing with actual OpenCode server pending
   - ⚠️ UI integration testing pending (no ChatFeature found yet)
   - 🔲 Unit tests for event parsing not yet created

## Implementation Details

### Event Structure (As Implemented)
- ✅ `session.updated`: `{ "type": "session.updated", "data": { "id": string, "time": {...}, "title": string } }`
  - Implementation: `OpenCodeAPIClientLive.swift:260-279`
- ✅ `session.deleted`: `{ "type": "session.deleted", "data": string }`
  - Implementation: `OpenCodeAPIClientLive.swift:281-287`
- ✅ `message.updated`: `{ "type": "message.updated", "data": { "id": string, "sessionID": string, "parts": [...], ... } }`
  - Implementation: `OpenCodeAPIClientLive.swift:289-317`
- ✅ `message.part.updated`: `{ "type": "message.part.updated", "data": { "sessionID": string, "messageID": string, "part": {...} } }`
  - Implementation: `OpenCodeAPIClientLive.swift:319-332`

### Message Model (OpenCodeMessage)
Location: `OpenCodeAPIClient.swift:94-136`
- ✅ id: String
- ✅ sessionID: String
- ✅ parts: [MessagePart]
- ✅ timestamp: Date
- ✅ role: MessageRole (enum: user, assistant, system)
- ✅ modelID: String?
- ✅ providerID: String?
- ✅ displayModelName: String (computed property)

### MessagePart Model (Enum)
Location: `OpenCodeAPIClient.swift:144-151`
- ✅ `.text(String, id: String?)`
- ✅ `.reasoning(String, id: String?)`
- ✅ `.file(path: String, content: String, id: String?)`
- ✅ `.agent(type: String, result: String, id: String?)`
- ✅ `.tool(name: String, input: String, output: String, error: String?, id: String?)`
- ✅ `.patch(hash: String, files: [String], id: String?)`

### Parsing Logic (As Implemented)
Location: `OpenCodeAPIClientLive.swift:237-346`
- ✅ Uses JSONSerialization to parse raw JSON string
- ✅ Extracts "type" field to determine event type
- ✅ Delegates to type-specific parsing functions
- ✅ Manual JSON parsing for flexibility (not using Codable for events)
- ✅ Handles decoding errors gracefully with `.unknown(jsonString)`

## Resolved Issues & Implementation Notes

### Schema Compatibility - ✅ RESOLVED
- ✅ OpenAPI schema defined in `openapi.yaml:1273-1377`
- ✅ Event types match between schema and implementation
- ⚠️ Note: Implementation uses manual JSON parsing instead of generated types for flexibility

### Performance - ✅ ACCEPTABLE
- ✅ JSONSerialization used for event parsing (simple dictionary access)
- ✅ Minimal overhead for SSE stream processing
- ✅ Type-specific parsing functions keep logic organized
- ℹ️ Performance monitoring recommended for high-volume streams

### Error Handling - ✅ IMPLEMENTED
- ✅ Parsing errors log warnings and return `.unknown` event (line 242)
- ✅ Stream errors are caught and logged (lines 200-206)
- ✅ Stream properly completes on success or failure
- ✅ No crashes on malformed events

### Backward Compatibility - ✅ MAINTAINED
- ✅ Session event parsing intact (lines 260-287)
- ✅ New message events added without breaking existing code
- ✅ `.unknown` case handles future event types gracefully

## Next Steps & Recommendations

### High Priority
1. **🔲 Add Unit Tests** - Create test file for event parsing
   - Test all event types (session.updated, session.deleted, message.updated, message.part.updated)
   - Test malformed JSON handling
   - Test unknown event types
   - Suggested location: `Packages/OpenCoderCore/Tests/ImplementationsTests/EventParsingTests.swift`

2. **🔲 End-to-End Testing** - Validate with actual OpenCode server
   - Test SSE stream with real server responses
   - Verify event data matches expected structure
   - Confirm UI updates work correctly

3. **🔲 Chat Feature Integration** - Build or integrate ChatFeature
   - Use subscribeToEvents() to receive real-time updates
   - Update message list when receiving messageUpdated events
   - Handle partial updates with messagePartUpdated events

### Medium Priority
4. **⚠️ Documentation** - Document event usage patterns
   - Add code examples for consuming events
   - Document event flow from SSE → parsing → UI updates

5. **🔲 Performance Monitoring** - Add metrics for production
   - Track event parsing latency
   - Monitor stream health and reconnection logic

This plan has been **successfully implemented** with core functionality complete. Testing and integration work remains.