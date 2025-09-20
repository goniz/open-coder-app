import Models
import SwiftUI

struct ConnectionStatusStepsView: View {
  enum Presentation {
    case card
    case inline
  }

  let onlineState: WorkspaceOnlineState
  var presentation: Presentation = .card

  private let phases = SpawnPhase.allCases

  var body: some View {
    let content = VStack(alignment: .leading, spacing: rowSpacing) {
      ForEach(phases, id: \.self) { phase in
        HStack(alignment: .top, spacing: 10) {
          statusIcon(for: status(for: phase))
            .frame(width: iconSize, height: iconSize)

          VStack(alignment: .leading, spacing: 2) {
            Text(phase.rawValue)
              .font(titleFont)
              .fontWeight(.semibold)
            Text(phase.description)
              .font(subtitleFont)
              .foregroundStyle(.secondary)
          }
        }
      }
    }

    switch presentation {
    case .card:
      content
        .padding(12)
        .background(
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.secondary.opacity(0.12))
        )
    case .inline:
      content
    }
  }

  private enum StepState {
    case completed
    case active
    case pending
  }

  private func status(for phase: SpawnPhase) -> StepState {
    switch onlineState {
    case .online:
      return .completed

    case .idle:
      return .pending

    case .error:
      return .pending

    case .spawning(let currentPhase):
      let ordered = phases
      guard
        let currentIndex = ordered.firstIndex(of: currentPhase),
        let phaseIndex = ordered.firstIndex(of: phase)
      else {
        return .pending
      }

      if phaseIndex < currentIndex {
        return .completed
      } else if phaseIndex == currentIndex {
        return .active
      } else {
        return .pending
      }
    }
  }

  @ViewBuilder
  private func statusIcon(for state: StepState) -> some View {
    switch state {
    case .completed:
      Image(systemName: "checkmark.circle.fill")
        .foregroundStyle(.green)
    case .active:
      ProgressView()
        .progressViewStyle(.circular)
        .scaleEffect(0.7)
    case .pending:
      Image(systemName: "circle")
        .foregroundStyle(.secondary)
    }
  }

  private var rowSpacing: CGFloat {
    switch presentation {
    case .card: return 12
    case .inline: return 8
    }
  }

  private var iconSize: CGFloat {
    switch presentation {
    case .card: return 18
    case .inline: return 14
    }
  }

  private var titleFont: Font {
    switch presentation {
    case .card: return .subheadline
    case .inline: return .caption
    }
  }

  private var subtitleFont: Font {
    switch presentation {
    case .card: return .caption
    case .inline: return .caption2
    }
  }
}
