import ComposableArchitecture
import Features
import SwiftUI

struct ProjectsView: View {
  let store: StoreOf<ProjectsFeature>

  var body: some View {
    VStack {
      Text("Projects", bundle: Bundle.module)
      if store.isLoading {
        ProgressView()
      } else {
        List {
          ForEach(store.projects) { project in
            Text(project.name)
          }
        }
        Button("Add Project") {
          store.send(.addProject)
        }
      }
    }
    .task {
      await store.send(.task).finish()
    }
  }
}
