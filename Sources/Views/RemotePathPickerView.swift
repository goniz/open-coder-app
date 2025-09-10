import ComposableArchitecture
import DependencyClients
import Models
import SwiftUI

struct RemotePathPickerView: View {
  let config: SSHServerConfiguration
  let onPathSelected: (String) -> Void
  let onCancel: () -> Void

  @State private var currentPath = "/"
  @State private var files: [RemoteFileInfo] = []
  @State private var isLoading = false
  @State private var errorMessage: String?
  @State private var pathHistory: [String] = ["/"]

  private let sshClient = SSHClient()

  var body: some View {
    NavigationStack {
      VStack {
        pathBreadcrumbView

        if isLoading {
          ProgressView("Loading directory...")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage = errorMessage {
          errorView(errorMessage)
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
            onPathSelected(currentPath)
          }
        }

        ToolbarItemGroup(placement: .navigation) {
          Button(action: goUp) {
            Image(systemName: "arrow.up")
          }
          .disabled(currentPath == "/")

          Button(action: goHome) {
            Image(systemName: "house")
          }
        }
      }
    }
    .task {
      await loadDirectory(currentPath)
    }
  }

  private var pathBreadcrumbView: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack {
        ForEach(Array(pathComponents.enumerated()), id: \.offset) { _, component in
          Button(component.name) {
            navigateToPath(component.path)
          }
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

  private var pathComponents: [(name: String, path: String)] {
    var components: [(name: String, path: String)] = []
    let parts = currentPath.components(separatedBy: "/").filter { !$0.isEmpty }

    components.append((name: "/", path: "/"))

    var accumulatedPath = ""
    for part in parts {
      accumulatedPath += "/\(part)"
      components.append((name: part, path: accumulatedPath))
    }

    return components
  }

  private var fileListView: some View {
    List(files) { file in
      fileRowView(file)
    }
    .listStyle(.inset)
  }

  private func fileRowView(_ file: RemoteFileInfo) -> some View {
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
            Text(formatFileSize(file.size))
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
    .onTapGesture {
      if file.isDirectory {
        navigateToPath(file.path)
      }
    }
  }

  private func errorView(_ message: String) -> some View {
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

      Button("Retry") {
        Task {
          await loadDirectory(currentPath)
        }
      }
      .buttonStyle(.borderedProminent)
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func loadDirectory(_ path: String) async {
    isLoading = true
    errorMessage = nil

    do {
      let directoryFiles = try await sshClient.listDirectory(path, config: config)
      await MainActor.run {
        self.files = directoryFiles
        self.isLoading = false
      }
    } catch {
      await MainActor.run {
        self.errorMessage = error.localizedDescription
        self.isLoading = false
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
    guard currentPath != "/" else { return }

    let parentPath = (currentPath as NSString).deletingLastPathComponent
    let finalPath = parentPath.isEmpty ? "/" : parentPath
    navigateToPath(finalPath)
  }

  private func goHome() {
    let homePath = "/home/\(config.username)"
    navigateToPath(homePath)
  }

  private func formatFileSize(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter.string(fromByteCount: bytes)
  }
}

#Preview {
  RemotePathPickerView(
    config: SSHServerConfiguration(
      host: "example.com",
      username: "user",
      password: "password",
      useKeyAuthentication: false
    ),
    onPathSelected: { _ in },
    onCancel: {}
  )
}
