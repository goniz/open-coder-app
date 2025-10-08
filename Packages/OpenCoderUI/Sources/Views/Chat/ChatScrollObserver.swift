import SwiftUI
import UIKit

/// Tracks the underlying chat table's scroll position so we can disable auto-scroll
/// while the user is browsing older messages.
struct ChatScrollObserver: UIViewRepresentable {
  @Binding var isAutoScrollEnabled: Bool

  func makeCoordinator() -> Coordinator {
    Coordinator(isAutoScrollEnabled: $isAutoScrollEnabled)
  }

  func makeUIView(context: Context) -> ObserverView {
    let view = ObserverView()
    view.coordinator = context.coordinator
    return view
  }

  func updateUIView(_ uiView: ObserverView, context: Context) {
    uiView.coordinator = context.coordinator
    context.coordinator.attachIfNeeded(from: uiView)
  }
}

extension ChatScrollObserver.Coordinator: @unchecked Sendable {
}

extension ChatScrollObserver {
  final class ObserverView: UIView {
    weak var coordinator: Coordinator?

    override func didMoveToSuperview() {
      super.didMoveToSuperview()
      coordinator?.attachIfNeeded(from: self)
    }

    override func didMoveToWindow() {
      super.didMoveToWindow()
      coordinator?.attachIfNeeded(from: self)
    }

    override func willMove(toSuperview newSuperview: UIView?) {
      if newSuperview == nil {
        coordinator?.detach()
      }
      super.willMove(toSuperview: newSuperview)
    }
  }

  final class Coordinator {
    @Binding private var isAutoScrollEnabled: Bool
    private weak var scrollView: UIScrollView?
    private var contentOffsetObservation: NSKeyValueObservation?
    private let tolerance: CGFloat = 28
    private var isInverted = false

    init(isAutoScrollEnabled: Binding<Bool>) {
      _isAutoScrollEnabled = isAutoScrollEnabled
    }

    deinit {
      contentOffsetObservation?.invalidate()
    }

    @MainActor
    func attachIfNeeded(from view: UIView) {
      guard scrollView == nil else { return }

      DispatchQueue.main.async { [weak self, weak view] in
        guard let self, let rootView = view else { return }
        guard let tableView = self.findTableView(startingAt: rootView) else { return }
        self.observe(scrollView: tableView)
      }
    }

    @MainActor
    func detach() {
      contentOffsetObservation?.invalidate()
      contentOffsetObservation = nil
      scrollView = nil
    }

    @MainActor
    private func observe(scrollView: UIScrollView) {
      self.scrollView = scrollView
      // Detect inverted (rotated) chat lists used by ExyteChat for `.conversation`
      let transform = scrollView.transform
      isInverted = abs(transform.a + 1) < 0.001 && abs(transform.d + 1) < 0.001 &&
                   abs(transform.b) < 0.001 && abs(transform.c) < 0.001
      contentOffsetObservation = scrollView.observe(
        \.contentOffset,
        options: [.new]
      ) { [weak self, weak scrollView] _, _ in
        Task { @MainActor [weak self, weak scrollView] in
          guard let self, let scrollView = scrollView else { return }
          self.handleScrollChange(scrollView)
        }
      }
      // Evaluate initial position
      handleScrollChange(scrollView)
    }

    @MainActor
    private func handleScrollChange(_ scrollView: UIScrollView) {
      let contentHeight = scrollView.contentSize.height
      let visibleHeight = scrollView.bounds.height
      let topInset = scrollView.adjustedContentInset.top
      let bottomInset = scrollView.adjustedContentInset.bottom

      // If content fits entirely, always consider we're at bottom.
      if contentHeight + topInset + bottomInset <= visibleHeight + 1 {
        updateAutoScroll(true)
        return
      }

      let isNearBottom: Bool
      if isInverted {
        // ExyteChat inverted table uses y ~= 0 as the bottom-of-chat
        isNearBottom = scrollView.contentOffset.y <= tolerance
      } else {
        // Standard table: bottom Y = contentHeight - visibleHeight + bottomInset
        let bottomY = max(-topInset, contentHeight - visibleHeight + bottomInset)
        isNearBottom = scrollView.contentOffset.y >= bottomY - tolerance
      }

      if isNearBottom {
        if !scrollView.isDragging && !scrollView.isDecelerating {
          updateAutoScroll(true)
        }
      } else {
        updateAutoScroll(false)
      }
    }

    @MainActor
    private func updateAutoScroll(_ newValue: Bool) {
      guard isAutoScrollEnabled != newValue else { return }
      isAutoScrollEnabled = newValue
    }

    @MainActor
    private func findTableView(startingAt view: UIView) -> UIScrollView? {
      if let tableView = searchDescendants(of: view) {
        return tableView
      }

      var ancestor = view.superview
      while let current = ancestor {
        if let tableView = searchDescendants(of: current) {
          return tableView
        }
        ancestor = current.superview
      }

      return nil
    }

    @MainActor
    private func searchDescendants(of view: UIView) -> UIScrollView? {
      if let tableView = view as? UITableView {
        return tableView
      }

      for subview in view.subviews {
        if let tableView = searchDescendants(of: subview) {
          return tableView
        }
      }

      return nil
    }
  }
}
