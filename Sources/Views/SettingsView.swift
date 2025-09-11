import ComposableArchitecture
import Features
import Models
import SwiftUI

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
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationView {
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 8) {
            ForEach(logger.logEntries) { entry in
              LogEntryView(entry: entry)
                .id(entry.id)
                .padding(.horizontal)
            }
          }
          .padding(.vertical)
        }
        .background(Color(Color.RGBColorSpace.sRGB, white: 0.97, opacity: 1))
        .onChange(of: logger.logEntries.count) { _, _ in
          if let lastEntry = logger.logEntries.last {
            withAnimation(.easeOut(duration: 0.3)) {
              proxy.scrollTo(lastEntry.id, anchor: .bottom)
            }
          }
        }
      }
      .navigationTitle("Live Activity Logs")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Done") {
            dismiss()
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
      store.send(.toggleLogs)
    }
  }
}

private struct LogEntryView: View {
  let entry: LogEntry

  var body: some View {
    GeometryReader { geometry in
      if geometry.size.width < 400 {
        compactLayout
      } else {
        standardLayout
      }
    }
    .fixedSize(horizontal: false, vertical: true)
  }

  private var compactLayout: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 8) {
        Text(entry.formattedTimestamp)
          .font(.system(.caption, design: .monospaced))
          .foregroundColor(.secondary)

        Text(entry.level.rawValue)
          .font(.system(.caption, design: .monospaced))
          .foregroundColor(colorForLevel(entry.level))
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(colorForLevel(entry.level).opacity(0.1))
          .cornerRadius(4)

        Text("[\(entry.category.rawValue)]")
          .font(.system(.caption, design: .monospaced))
          .foregroundColor(.secondary)

        Spacer()
      }

      Text(entry.message)
        .font(.system(.callout, design: .monospaced))
        .foregroundColor(.primary)
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(.vertical, 8)
    .padding(.horizontal, 12)
    .background(Color.secondary.opacity(0.1))
    .cornerRadius(8)
  }

  private var standardLayout: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 12) {
        Text(entry.formattedTimestamp)
          .font(.system(.caption, design: .monospaced))
          .foregroundColor(.secondary)
          .frame(width: 80, alignment: .leading)

        Text(entry.level.rawValue)
          .font(.system(.caption, design: .monospaced))
          .foregroundColor(colorForLevel(entry.level))
          .padding(.horizontal, 8)
          .padding(.vertical, 2)
          .background(colorForLevel(entry.level).opacity(0.1))
          .cornerRadius(4)
          .frame(width: 80, alignment: .leading)

        Text("[\(entry.category.rawValue)]")
          .font(.system(.caption, design: .monospaced))
          .foregroundColor(.secondary)
          .frame(width: 100, alignment: .leading)

        Spacer()
      }

      Text(entry.message)
        .font(.system(.callout, design: .monospaced))
        .foregroundColor(.primary)
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(.vertical, 8)
    .padding(.horizontal, 12)
    .background(Color.secondary.opacity(0.1))
    .cornerRadius(8)
  }

  private func colorForLevel(_ level: LogLevel) -> Color {
    switch level {
    case .debug: return .gray
    case .info: return .blue
    case .warning: return .orange
    case .error: return .red
    }
  }
}
