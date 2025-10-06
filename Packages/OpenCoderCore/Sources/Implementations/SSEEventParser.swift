import Foundation

struct SSEEventParser {
  private var lineBuffer = ""
  private var eventBuffer = ""

  mutating func ingest(_ chunk: String, onEvent: (String) -> Void) {
    lineBuffer.append(chunk)
    processBuffer(onEvent: onEvent)
  }

  mutating func finish(onEvent: (String) -> Void) {
    if !lineBuffer.isEmpty && !lineBuffer.hasSuffix("\n") {
      lineBuffer.append("\n")
    }

    processBuffer(onEvent: onEvent)
    lineBuffer.removeAll(keepingCapacity: true)

    guard !eventBuffer.isEmpty else { return }
    onEvent(eventBuffer)
    eventBuffer.removeAll(keepingCapacity: true)
  }

  private mutating func processBuffer(onEvent: (String) -> Void) {
    while let newlineRange = lineBuffer.range(of: "\n") {
      let line = String(lineBuffer[..<newlineRange.lowerBound])
      lineBuffer.removeSubrange(..<newlineRange.upperBound)
      if let event = handleLine(line) {
        onEvent(event)
      }
    }
  }

  private mutating func handleLine(_ line: String) -> String? {
    let sanitizedLine = line.replacingOccurrences(of: "\r", with: "")

    if sanitizedLine.hasPrefix("data:") {
      appendDataLine(sanitizedLine)
      return nil
    }

    if sanitizedLine.trimmingCharacters(in: .whitespaces).isEmpty {
      return extractBufferedEvent()
    }

    return nil
  }

  private mutating func appendDataLine(_ line: String) {
    let dataStartIndex = line.index(line.startIndex, offsetBy: 5)
    var payload = String(line[dataStartIndex...])
    if payload.hasPrefix(" ") {
      payload.removeFirst()
    }

    if !eventBuffer.isEmpty {
      eventBuffer.append("\n")
    }
    eventBuffer.append(payload)
  }

  private mutating func extractBufferedEvent() -> String? {
    guard !eventBuffer.isEmpty else { return nil }
    let bufferedEvent = eventBuffer
    eventBuffer.removeAll(keepingCapacity: true)
    return bufferedEvent
  }
}
