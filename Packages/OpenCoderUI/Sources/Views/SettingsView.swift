import ComposableArchitecture
import OpenCoderCore
import SwiftUI
import UniformTypeIdentifiers

#if canImport(UIKit)
  import UIKit
#endif

struct SettingsView: View {
  @Bindable var store: StoreOf<SettingsFeature>
  @StateObject private var logger = AppLogger.shared

  var body: some View {
    Form {
      Section(header: Text("General")) {
        Toggle("Show Thinking Blocks", isOn: $store.thinkingBlocksEnabled)
        Button("Reset to Defaults") {
          store.send(.resetToDefaults)
        }
      }

      Section(header: Text("Live Logs")) {
        Button("View Current Logs") {
          store.send(.toggleLogs)
        }

        Button("View Previous Launch Logs") {
          store.send(.togglePreviousLogs)
        }

        Button("Download Logs") {
          store.send(.exportLogs)
        }
      }
    }
    .navigationTitle("Settings")
    .sheet(isPresented: $store.showingLogs) {
      LogsView(store: store)
    }
    .sheet(isPresented: $store.showingPreviousLogs) {
      PreviousLogsView(store: store)
    }
    .fileExporter(
      isPresented: Binding(
        get: { store.logsFileURL != nil },
        set: { if !$0 { store.send(.logsFileGenerated(nil)) } }
      ),
      document: store.logsFileURL.map { LogsDocument(fileURL: $0) },
      contentType: .plainText,
      defaultFilename: store.logsFileURL?.lastPathComponent ?? "opencoder_logs.txt"
    ) { result in
      switch result {
      case .success:
        break
      case .failure(let error):
        AppLogger.shared.log("Failed to export logs: \(error.localizedDescription)", level: .error)
      }
      store.send(.logsFileGenerated(nil))
    }
    .task {
      await store.send(.task).finish()
    }
  }
}

struct LogsView: View {
  @Bindable var store: StoreOf<SettingsFeature>
  @StateObject private var logger = AppLogger.shared
  @State private var isPinnedToBottom = true
  @State private var pendingProgrammaticScroll = false
  @State private var scrollTask: Task<Void, Never>?

  private let bottomSentinelID = UUID()

  var body: some View {
    NavigationView {
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 12) {
            ForEach(logger.logEntries) { entry in
              LogEntryView(entry: entry)
                .id(entry.id)
            }

            Color.clear
              .frame(height: 1)
              .id(bottomSentinelID)
              .onAppear {
                isPinnedToBottom = true
                pendingProgrammaticScroll = false
              }
              .onDisappear {
                if !pendingProgrammaticScroll {
                  isPinnedToBottom = false
                }
              }
          }
          .padding(.horizontal, 16)
          .padding(.vertical, 12)
        }
        .background(.gray.opacity(0.1))
        .onAppear {
          scheduleScrollToBottom(proxy: proxy, force: true)
        }
        .onChange(of: logger.logEntries.count) { _, _ in
          guard logger.latestEntryID != nil else {
            scrollTask?.cancel()
            pendingProgrammaticScroll = false
            isPinnedToBottom = true
            return
          }

          scheduleScrollToBottom(proxy: proxy)
        }
      }
      .navigationTitle("Live Activity Logs")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Done") {
            store.send(.toggleLogs)
          }
        }

        ToolbarItem(placement: .primaryAction) {
          Button("Clear") {
            store.send(.clearLogs)
          }
          .foregroundColor(.red)
        }
      }
    }
    .onDisappear {
      scrollTask?.cancel()
      scrollTask = nil
      pendingProgrammaticScroll = false
    }
  }

  @MainActor
  private func scheduleScrollToBottom(proxy: ScrollViewProxy, force: Bool = false) {
    if !force && !isPinnedToBottom {
      return
    }

    pendingProgrammaticScroll = true
    scrollTask?.cancel()
    scrollTask = Task { @MainActor in
      defer {
        pendingProgrammaticScroll = false
        scrollTask = nil
      }

      await Task.yield()
      guard !Task.isCancelled else { return }

      withAnimation(.easeOut(duration: 0.3)) {
        proxy.scrollTo(bottomSentinelID, anchor: .bottom)
      }
    }
  }
}

struct PreviousLogsView: View {
  @Bindable var store: StoreOf<SettingsFeature>
  @StateObject private var logger = AppLogger.shared
  @State private var isPinnedToBottom = true
  @State private var pendingProgrammaticScroll = false
  @State private var scrollTask: Task<Void, Never>?

  private let bottomSentinelID = UUID()

  var body: some View {
    NavigationView {
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 12) {
            if logger.previousLaunchLogs.isEmpty {
              VStack(spacing: 16) {
                Image(systemName: "doc.text")
                  .font(.system(size: 48))
                  .foregroundColor(.secondary)

                Text("No Previous Launch Logs")
                  .font(.title2)
                  .fontWeight(.medium)
                  .foregroundColor(.secondary)

                Text("Logs from previous app launches will appear here to help debug crashes and issues.")
                  .font(.body)
                  .foregroundColor(.secondary)
                  .multilineTextAlignment(.center)
                  .padding(.horizontal, 32)
              }
              .frame(maxWidth: .infinity)
              .padding(.top, 100)
            } else {
              ForEach(logger.previousLaunchLogs) { entry in
                LogEntryView(entry: entry)
                  .id(entry.id)
              }
            }

            Color.clear
              .frame(height: 1)
              .id(bottomSentinelID)
              .onAppear {
                isPinnedToBottom = true
                pendingProgrammaticScroll = false
              }
              .onDisappear {
                if !pendingProgrammaticScroll {
                  isPinnedToBottom = false
                }
              }
          }
          .padding(.horizontal, 16)
          .padding(.vertical, 12)
        }
        .background(.gray.opacity(0.1))
        .onAppear {
          scheduleScrollToBottom(proxy: proxy, force: true)
        }
        .onChange(of: logger.previousLaunchLogs.count) { _, _ in
          scheduleScrollToBottom(proxy: proxy)
        }
      }
      .navigationTitle("Previous Launch Logs")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Done") {
            store.send(.togglePreviousLogs)
          }
        }

        ToolbarItem(placement: .primaryAction) {
          Button("Clear") {
            store.send(.clearPreviousLogs)
          }
          .foregroundColor(.red)
          .disabled(logger.previousLaunchLogs.isEmpty)
        }
      }
    }
    .onDisappear {
      scrollTask?.cancel()
      scrollTask = nil
      pendingProgrammaticScroll = false
    }
  }

  @MainActor
  private func scheduleScrollToBottom(proxy: ScrollViewProxy, force: Bool = false) {
    if !force && !isPinnedToBottom {
      return
    }

    pendingProgrammaticScroll = true
    scrollTask?.cancel()
    scrollTask = Task { @MainActor in
      defer {
        pendingProgrammaticScroll = false
        scrollTask = nil
      }

      await Task.yield()
      guard !Task.isCancelled else { return }

      withAnimation(.easeOut(duration: 0.3)) {
        proxy.scrollTo(bottomSentinelID, anchor: .bottom)
      }
    }
  }
}

struct LogsDocument: FileDocument {
  static var readableContentTypes: [UTType] { [.plainText] }

  let fileURL: URL

  init(fileURL: URL) {
    self.fileURL = fileURL
  }

  init(configuration: ReadConfiguration) throws {
    throw CocoaError(.fileReadUnknown)
  }

  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
    guard let data = try? Data(contentsOf: fileURL) else {
      throw CocoaError(.fileReadUnknown)
    }
    return FileWrapper(regularFileWithContents: data)
  }
}

private struct LogEntryView: View {
  let entry: LogEntry

  var body: some View {
    compactLayout
      .contentShape(Rectangle())
      .onTapGesture {
        copyToPasteboard(entry.clipboardText)
      }
  }

  private var compactLayout: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 8) {
        Text(entry.formattedTimestamp)
          .font(.system(.caption2, design: .monospaced))
          .foregroundColor(.secondary)
          .lineLimit(1)

        Text(entry.level.rawValue)
          .font(.system(.caption2, design: .monospaced, weight: .medium))
          .foregroundColor(colorForLevel(entry.level))
          .padding(.horizontal, 8)
          .padding(.vertical, 3)
          .background(colorForLevel(entry.level).opacity(0.15))
          .clipShape(RoundedRectangle(cornerRadius: 6))

        Text("[\(entry.category.rawValue)]")
          .font(.system(.caption2, design: .monospaced))
          .foregroundColor(.secondary)
          .lineLimit(1)

        Spacer()
      }

      Text(entry.message)
        .font(.system(.footnote, design: .monospaced))
        .foregroundColor(.primary)
        .multilineTextAlignment(.leading)
        .lineLimit(nil)
    }
    .padding(.vertical, 12)
    .padding(.horizontal, 16)
    .background(.gray.opacity(0.15))
    .clipShape(RoundedRectangle(cornerRadius: 10))
  }

  private func colorForLevel(_ level: LogLevel) -> Color {
    switch level {
    case .trace: return .secondary
    case .debug: return .gray
    case .info: return .blue
    case .warning: return .orange
    case .error: return .red
    }
  }

  private func copyToPasteboard(_ text: String) {
    #if canImport(UIKit)
      UIPasteboard.general.string = text
      let generator = UINotificationFeedbackGenerator()
      generator.notificationOccurred(.success)
    #endif
  }
}
