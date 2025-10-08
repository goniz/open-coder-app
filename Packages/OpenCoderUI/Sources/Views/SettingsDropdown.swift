import SwiftUI

struct SettingsDropdown<Label: View, Content: View>: View {
  @Binding var isExpanded: Bool
  var isDisabled: Bool = false
  @ViewBuilder var label: () -> Label
  @ViewBuilder var content: (_ dismiss: @escaping () -> Void) -> Content

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Button {
        guard !isDisabled else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
          isExpanded.toggle()
        }
      } label: {
        label()
          .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
      }
      .buttonStyle(.plain)
      .disabled(isDisabled)

      if isExpanded {
        content {
          withAnimation(.easeInOut(duration: 0.2)) {
            isExpanded = false
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color(.systemBackground))
        )
        .overlay(
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(Color(.systemGray4))
        )
        .shadow(color: Color.black.opacity(0.12), radius: 16, y: 8)
        .transition(.opacity.combined(with: .move(edge: .top)))
        .padding(.top, 4)
      }
    }
    .animation(.easeInOut(duration: 0.2), value: isExpanded)
  }
}
