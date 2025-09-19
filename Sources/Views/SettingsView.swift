import ComposableArchitecture
import Features
import Models
import SwiftUI

#if canImport(UIKit)
  import UIKit
#endif

struct SettingsView: View {
  @Bindable var store: StoreOf<SettingsFeature>
  @StateObject private var logger = AppLogger.shared

  var body: some View {
    Form {
      Section(header: Text("Appearance")) {
        Picker("Theme", selection: $store.theme) {
          ForEach(Theme.allCases, id: \.self) { theme in
            Text(theme.rawValue.capitalized)
          }
        }
      }

      Section(header: Text("Notifications")) {
        Toggle("Enable Notifications", isOn: $store.notificationsEnabled)
      }

      Section(header: Text("General")) {
        Toggle("Auto Save", isOn: $store.autoSaveEnabled)
        Button("Reset to Defaults") {
          store.send(.resetToDefaults)
        }
      }

      Section(header: Text("Live Logs")) {
        Button("View Logs") {
          store.send(.toggleLogs)
        }
      }
    }
    .navigationTitle("Settings")
    .sheet(isPresented: $store.showingLogs) {
      LogsView(store: store)
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

private struct LogEntryView: View {
  let entry: LogEntry

  var body: some View {
    compactLayout
      .contentShape(Rectangle())
      .onTapGesture {
        copyToPasteboard(entry.message)
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
