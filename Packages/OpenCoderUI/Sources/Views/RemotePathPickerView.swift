import ComposableArchitecture
import Dependencies
import OpenCoderCore
import OpenCoderCore
import SwiftUI

struct RemotePathPickerView: View {
  let config: SSHServerConfiguration
  let onPathSelected: (String) -> Void
  let onCancel: () -> Void

  // Display path uses '~' as the root instead of '/'
  @State private var currentPath = "~"
  @State private var files: [RemoteFileInfo] = []
  @State private var isLoading = false
  @State private var errorMessage: String?
  @State private var pathHistory: [String] = ["~"]
  @State private var remoteHomeDirectory: String?
  @State private var showHidden = false

  @Dependency(\.sshClient) private var sshClient

  var body: some View {
    NavigationStack {
      VStack {
        BreadcrumbView(
          components: pathComponents,
          currentPath: currentPath,
          onSelect: { navigateToPath($0) }
        )

        if isLoading {
          ProgressView("Loading directory...")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage = errorMessage {
          ErrorView(message: errorMessage) {
            Task { await loadDirectory(currentPath) }
          }
        } else {
          fileListView
        }
      }
      .navigationTitle("Select Remote Path")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") {
            onCancel()
          }
        }

        ToolbarItem(placement: .confirmationAction) {
          Button("Select") {
            onPathSelected(resolvePath(currentPath))
          }
        }

        ToolbarItemGroup(placement: .navigation) {
          Button(action: goUp) {
            Image(systemName: "arrow.up")
          }
          .disabled(currentPath == "~")

          Button {
            Task {
              await goHome()
            }
          } label: {
            Image(systemName: "house")
          }
          .disabled(isLoading)
        }

        ToolbarItem(placement: .automatic) {
          Button {
            showHidden.toggle()
          } label: {
            Image(systemName: showHidden ? "eye" : "eye.slash")
          }
          .help(showHidden ? "Hide hidden files" : "Show hidden files")
        }
      }
    }
    .task {
      // Try to start at home directory, fall back to root if that fails
      await initializeStartingDirectory()
    }
  }

  private var pathComponents: [(name: String, path: String)] {
    // Build breadcrumb components with '~' as root
    var components: [(name: String, path: String)] = []
    if currentPath == "~" {
      return [(name: "~", path: "~")]
    }

    // Ensure we are working with display path (starts with '~')
    let displayPath = currentPath.hasPrefix("~") ? currentPath : compressToTilde(currentPath)
    let tail = displayPath.dropFirst(2)  // drop '~/'
    let parts = tail.split(separator: "/").map(String.init)

    components.append((name: "~", path: "~"))
    var accumulated = "~"
    for part in parts {
      accumulated += "/\(part)"
      components.append((name: part, path: accumulated))
    }
    return components
  }

  private var fileListView: some View {
    List(displayedFiles) { file in
      FileRowView(file: file) {
        if file.isDirectory {
          navigateToPath(compressToTilde(file.path))
        }
      }
    }
    .listStyle(.inset)
  }

  private var displayedFiles: [RemoteFileInfo] {
    let filtered = showHidden ? files : files.filter { !$0.name.hasPrefix(".") }
    // Sort by recency (lastModified desc), keeping directories first
    return filtered.sorted { lhs, rhs in
      if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory && !rhs.isDirectory }
      if lhs.lastModified != rhs.lastModified { return lhs.lastModified > rhs.lastModified }
      return lhs.name.lowercased() < rhs.name.lowercased()
    }
  }

  private func loadDirectory(_ path: String) async {
    isLoading = true
    errorMessage = nil

    do {
      let directoryFiles = try await sshClient.listDirectory(resolvePath(path), config: config)
      await MainActor.run {
        // Convert absolute paths to display paths using '~' root
        self.files = directoryFiles.map { info in
          RemoteFileInfo(
            name: info.name,
            path: compressToTilde(info.path),
            isDirectory: info.isDirectory,
            size: info.size,
            permissions: info.permissions
          )
        }
        self.isLoading = false
      }
    } catch {
      let errorString = String(describing: error)
      let errorMessage: String

      // Provide more helpful error messages
      if errorString.contains("Permission denied") {
        errorMessage = "Permission denied: Cannot access '\(path)'"
      } else if errorString.contains("does not exist") {
        errorMessage = "Directory does not exist: '\(path)'"
      } else if errorString.contains("channel closed") || errorString.contains("Channel closed") {
        errorMessage = "Connection lost. Please try again."
      } else {
        errorMessage = "Failed to load directory '\(path)': \(error.localizedDescription)"
      }

      await MainActor.run {
        self.errorMessage = errorMessage
        self.isLoading = false
        // Keep existing files if we have them (don't clear on error)
      }
    }
  }
  private func navigateToPath(_ path: String) {
    if path != currentPath {
      pathHistory.append(currentPath)
      currentPath = path
      Task {
        await loadDirectory(path)
      }
    }
  }

  private func goUp() {
    guard currentPath != "~" else { return }

    // Compute parent on display path
    if let range = currentPath.range(of: "/", options: .backwards) {
      let parent = String(currentPath[..<range.lowerBound])
      navigateToPath(parent.isEmpty ? "~" : parent)
    } else {
      navigateToPath("~")
    }
  }

  private func initializeStartingDirectory() async {
    do {
      // Try to get and start at the remote home directory
      let homePath = try await sshClient.getRemoteHomeDirectory(config: config)
      await MainActor.run {
        self.remoteHomeDirectory = homePath
        self.currentPath = "~"
        self.pathHistory = ["~"]
      }
      await loadDirectory("~")
    } catch {
      // Fall back to user's home path guess, represented as '~'
      let fallbackPath = "/home/\(config.username)"

      await MainActor.run {
        self.errorMessage =
          "Failed to determine home directory (\(error.localizedDescription)). "
          + "Using '~' as home..."
        self.remoteHomeDirectory = fallbackPath
        self.currentPath = "~"
        self.pathHistory = ["~"]
      }

      // Try the fallback home path via '~'
      do {
        let files = try await sshClient.listDirectory(fallbackPath, config: config)
        await MainActor.run {
          self.files = files.map { info in
            RemoteFileInfo(
              name: info.name,
              path: compressToTilde(info.path),
              isDirectory: info.isDirectory,
              size: info.size,
              permissions: info.permissions
            )
          }
          self.isLoading = false
          self.errorMessage = nil  // Clear error if successful
        }
      } catch {
        // Last resort: use '/' as actual, but keep '~' as display root
        await MainActor.run {
          self.remoteHomeDirectory = "/"
          self.currentPath = "~"
          self.pathHistory = ["~"]
          self.errorMessage = "Could not access home directory, using '~' mapped to '/'"
        }
        await loadDirectory("~")
      }
    }
  }

  private func goHome() async {
    // Use cached home directory if available
    if remoteHomeDirectory != nil {
      navigateToPath("~")
      return
    }

    // Fetch remote home directory
    do {
      let homePath = try await sshClient.getRemoteHomeDirectory(config: config)
      await MainActor.run {
        self.remoteHomeDirectory = homePath
        navigateToPath("~")
      }
    } catch {
      await MainActor.run {
        // Fallback to '~' mapped to '/' if home directory can't be determined
        self.remoteHomeDirectory = "/"
        navigateToPath("~")
      }
    }
  }

  // MARK: - Path helpers

  private func resolvePath(_ path: String) -> String {
    guard let home = remoteHomeDirectory else { return path }
    if path == "~" { return home }
    if path.hasPrefix("~/") { return home + String(path.dropFirst(1)) }
    return path
  }

  private func compressToTilde(_ absolutePath: String) -> String {
    guard let home = remoteHomeDirectory, !home.isEmpty else { return absolutePath }
    if absolutePath == home { return "~" }
    if absolutePath.hasPrefix(home + "/") {
      return "~" + String(absolutePath.dropFirst(home.count))
    }
    return absolutePath
  }

  private func formatFileSize(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter.string(fromByteCount: bytes)
  }
}

// MARK: - Subviews

private struct BreadcrumbView: View {
  let components: [(name: String, path: String)]
  let currentPath: String
  let onSelect: (String) -> Void

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack {
        ForEach(Array(components.enumerated()), id: \.offset) { _, component in
          Button(component.name) { onSelect(component.path) }
            .buttonStyle(.borderless)
            .foregroundColor(.accentColor)

          if component.path != currentPath {
            Image(systemName: "chevron.right")
              .foregroundColor(.secondary)
              .font(.caption)
          }
        }
      }
      .padding(.horizontal)
    }
    .frame(height: 30)
    .background(Color.gray.opacity(0.1))
  }
}

private struct FileRowView: View {
  let file: RemoteFileInfo
  let onTap: () -> Void

  var body: some View {
    HStack {
      Image(systemName: file.isDirectory ? "folder.fill" : "doc.fill")
        .foregroundColor(file.isDirectory ? .blue : .secondary)
        .frame(width: 20)

      VStack(alignment: .leading, spacing: 2) {
        Text(file.name)
          .font(.body)

        HStack {
          Text(file.permissions)
            .font(.caption)
            .foregroundColor(.secondary)

          if !file.isDirectory && file.size > 0 {
            Text(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))
              .font(.caption)
              .foregroundColor(.secondary)
          }
        }
      }

      Spacer()

      if file.isDirectory {
        Image(systemName: "chevron.right")
          .foregroundColor(.secondary)
          .font(.caption)
      }
    }
    .contentShape(Rectangle())
    .onTapGesture { onTap() }
  }
}

private struct ErrorView: View {
  let message: String
  let onRetry: () -> Void

  var body: some View {
    VStack(spacing: 20) {
      Image(systemName: "exclamationmark.triangle")
        .font(.system(size: 48))
        .foregroundColor(.orange)

      Text("Error")
        .font(.title2)
        .fontWeight(.medium)

      Text(message)
        .font(.body)
        .foregroundColor(.secondary)
        .multilineTextAlignment(.center)

      Button("Retry", action: onRetry)
        .buttonStyle(.borderedProminent)
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
