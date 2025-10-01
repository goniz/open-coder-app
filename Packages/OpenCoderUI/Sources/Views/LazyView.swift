import SwiftUI

struct LazyView<Content: View>: View {
  let build: () -> Content

  init(@ViewBuilder _ build: @escaping () -> Content) {
    self.build = build
  }

  var body: some View {
    build()
  }
}