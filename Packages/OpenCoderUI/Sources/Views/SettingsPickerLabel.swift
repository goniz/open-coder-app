import SwiftUI

struct SettingsPickerLabel: View {
  let title: String
  let displayText: String
  var isPlaceholder: Bool = false
  var isLoading: Bool = false
  var iconName: String?
  var isActive: Bool = false

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title.uppercased())
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)

      HStack(spacing: 8) {
        if let iconName, !iconName.isEmpty {
          Image(systemName: iconName)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
        }

        if isLoading {
          ProgressView()
            .scaleEffect(0.6, anchor: .center)
        }

        Text(displayText)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(isPlaceholder ? Color.secondary : Color.primary)
          .multilineTextAlignment(.leading)
          .lineLimit(2)
          .fixedSize(horizontal: false, vertical: true)

        Spacer(minLength: 0)

        Image(systemName: "chevron.down")
          .font(.footnote.weight(.semibold))
          .foregroundStyle(.tertiary)
      }
      .padding(.vertical, 10)
      .padding(.horizontal, 12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(Color(.systemBackground).opacity(0.7))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .stroke(
            isActive ? Color.accentColor : Color(.systemGray4),
            lineWidth: isActive ? 2 : 1
          )
      )
      .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
