import ComposableArchitecture
import Features
import Models
import SwiftUI

struct AddServerView: View {
  let onSave: (SSHServerConfiguration) -> Void
  let onCancel: () -> Void

  var body: some View {
    AddServerFlowView(onSave: onSave, onCancel: onCancel)
  }
}
