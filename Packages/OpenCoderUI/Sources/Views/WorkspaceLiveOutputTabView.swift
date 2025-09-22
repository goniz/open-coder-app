import OpenCoderCore
import OpenCoderCore
import SwiftUI

struct WorkspaceLiveOutputTabView: View {
  let workspace: Workspace
  @State private var tmuxWindows: [String] = []
  @State private var selectedWindow: String?
  @State private var windowsError: String?
  @State private var isLoadingWindows = false
  @State private var hasLoadedWindows = false
  @State private var outputLines: [String] = []
  @State private var isFollowing = true
  @State private var streamTask: Task<Void, Never>?
  @State private var isWaitingForOutput = true

  var body: some View {
    VStack(spacing: 0) {
      windowSelector

      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 2) {
            ForEach(Array(outputLines.enumerated()), id: \.offset) { index, line in
              Text(line)
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .id(index)
            }
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .foregroundColor(.green)
        .overlay(alignment: .center) {
          if isWaitingForOutput {
            VStack(spacing: 8) {
              ProgressView()
              Text("Waiting for live output…")
                .font(.caption2)
                .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8))
          }
        }
        .onChange(of: outputLines.count) { oldValue, newValue in
          guard isFollowing, newValue > 0, newValue != oldValue else { return }
          withAnimation(.easeOut) {
            proxy.scrollTo(newValue - 1, anchor: .bottom)
          }
        }
      }

      controlsView
    }
    .task { await loadTmuxWindows() }
    .task(id: selectedWindow) { await startLiveOutput() }
    .onDisappear { streamTask?.cancel() }
  }

  private var windowSelector: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(alignment: .center, spacing: 8) {
        VStack(alignment: .leading, spacing: 1) {
          Text("TMUX Tab")
            .font(.caption2)
            .foregroundColor(.secondary)

          if tmuxWindows.isEmpty {
            Text(windowsError ?? "No tmux tabs found yet.")
              .font(.caption)
              .foregroundColor(.secondary)
          } else {
            Picker(
              "TMUX Tab",
              selection: Binding(
                get: { selectedWindow ?? tmuxWindows.first ?? "" },
                set: { newValue in selectedWindow = newValue.isEmpty ? nil : newValue }
              )
            ) {
              ForEach(tmuxWindows, id: \.self) { window in
                Text(window).tag(window)
              }
            }
            .pickerStyle(.menu)
          }
        }

        Spacer()

        if isLoadingWindows {
          ProgressView()
            .controlSize(.small)
        } else {
          Button {
            Task { await loadTmuxWindows(force: true) }
          } label: {
            Image(systemName: "arrow.clockwise")
              .font(.caption)
          }
          .buttonStyle(.borderless)
          .disabled(isLoadingWindows)
        }
      }
      .padding(.horizontal, 12)
      .padding(.top, 8)

      Divider()
        .padding(.horizontal, 12)
    }
  }

  private var controlsView: some View {
    HStack(spacing: 12) {
      Button(
        action: { isFollowing.toggle() },
        label: {
          Image(systemName: isFollowing ? "pause.fill" : "play.fill")
            .font(.body)
        }
      )

      Button(action: copyOutput) {
        Image(systemName: "doc.on.doc")
          .font(.body)
      }

      Button(action: clearOutput) {
        Image(systemName: "trash")
          .font(.body)
      }

      Button {
        Task { await loadTmuxWindows(force: true) }
      } label: {
        Image(systemName: "arrow.triangle.2.circlepath")
          .font(.body)
      }
      .disabled(isLoadingWindows)

      Spacer()

      if let selectedWindow {
        Text("\(selectedWindow) • \(outputLines.count) lines")
          .font(.caption2)
          .foregroundColor(.secondary)
      } else {
        Text("\(outputLines.count) lines")
          .font(.caption2)
          .foregroundColor(.secondary)
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(Color.secondary.opacity(0.1))
  }

  private func loadTmuxWindows(force: Bool = false) async {
    if hasLoadedWindows && !force { return }

    await MainActor.run {
      isLoadingWindows = true
      windowsError = nil
    }

    do {
      let windows = try await WorkspaceLogs.tmuxWindows(for: workspace)
      await MainActor.run {
        tmuxWindows = windows
        hasLoadedWindows = true

        if let current = selectedWindow, windows.contains(current) {
          // keep current selection
        } else {
          selectedWindow = windows.first
        }

        if windows.isEmpty {
          outputLines = [
            "[Live Output] No tmux tabs found for session \(workspace.tmuxSession.value)."
          ]
          isWaitingForOutput = false
        } else {
          outputLines.removeAll()
          isWaitingForOutput = true
        }
      }
    } catch {
      let message: String
      if let localized = error as? LocalizedError, let description = localized.errorDescription {
        message = description
      } else {
        message = error.localizedDescription
      }

      await MainActor.run {
        windowsError = message
        tmuxWindows = []
        selectedWindow = nil
        outputLines = ["[Live Output] \(message)"]
        hasLoadedWindows = true
        isWaitingForOutput = false
      }
    }

    await MainActor.run {
      isLoadingWindows = false
    }
  }

  private func startLiveOutput() async {
    streamTask?.cancel()

    await MainActor.run {
      outputLines.removeAll()
      isWaitingForOutput = true
    }

    guard let window = selectedWindow else {
      await MainActor.run {
        if tmuxWindows.isEmpty {
          outputLines = ["[Live Output] Select a tmux tab to view output."]
        }
        isWaitingForOutput = false
      }
      return
    }

    let stream = WorkspaceLogs.stream(for: workspace, window: window)
    streamTask = Task {
      for await line in stream {
        await MainActor.run {
          outputLines.append(line)
          isWaitingForOutput = false
        }
      }

      await MainActor.run {
        if outputLines.isEmpty {
          outputLines.append("[Live Output] No log entries yet.")
        }
        isWaitingForOutput = false
      }
    }
  }

  private func copyOutput() {
    let text = outputLines.joined(separator: "\n")
    #if os(iOS)
      UIPasteboard.general.string = text
    #elseif os(macOS)
      NSPasteboard.general.setString(text, forType: .string)
    #endif
  }

  private func clearOutput() {
    outputLines.removeAll()
  }
}
