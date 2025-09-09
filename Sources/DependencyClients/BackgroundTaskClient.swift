import BackgroundTasks
import Dependencies
import Foundation

#if canImport(UIKit)
import UIKit
#endif

package struct BackgroundTaskClient: Sendable {
  package var registerAppRefresh: @Sendable () async -> Void
  package var scheduleAppRefresh: @Sendable () async -> Void
  #if canImport(UIKit) && !os(macOS)
  package var beginBackgroundTask: @Sendable (String) async -> UIBackgroundTaskIdentifier
  package var endBackgroundTask: @Sendable (UIBackgroundTaskIdentifier) async -> Void
  #else
  package var beginBackgroundTask: @Sendable (String) async -> Int
  package var endBackgroundTask: @Sendable (Int) async -> Void
  #endif

  #if canImport(UIKit) && !os(macOS)
  package init(
    registerAppRefresh: @escaping @Sendable () async -> Void,
    scheduleAppRefresh: @escaping @Sendable () async -> Void,
    beginBackgroundTask: @escaping @Sendable (String) async -> UIBackgroundTaskIdentifier,
    endBackgroundTask: @escaping @Sendable (UIBackgroundTaskIdentifier) async -> Void
  ) {
    self.registerAppRefresh = registerAppRefresh
    self.scheduleAppRefresh = scheduleAppRefresh
    self.beginBackgroundTask = beginBackgroundTask
    self.endBackgroundTask = endBackgroundTask
  }
  #else
  package init(
    registerAppRefresh: @escaping @Sendable () async -> Void,
    scheduleAppRefresh: @escaping @Sendable () async -> Void,
    beginBackgroundTask: @escaping @Sendable (String) async -> Int,
    endBackgroundTask: @escaping @Sendable (Int) async -> Void
  ) {
    self.registerAppRefresh = registerAppRefresh
    self.scheduleAppRefresh = scheduleAppRefresh
    self.beginBackgroundTask = beginBackgroundTask
    self.endBackgroundTask = endBackgroundTask
  }
  #endif
}

extension BackgroundTaskClient: DependencyKey {
  #if canImport(UIKit) && !os(macOS)
  package static let liveValue = BackgroundTaskClient(
    registerAppRefresh: {
      BGTaskScheduler.shared.register(
        forTaskWithIdentifier: "com.opencoder.task-monitor",
        using: nil
      ) { task in
        if let refreshTask = task as? BGAppRefreshTask {
          Task { @MainActor in
            await handleBackgroundTaskMonitoring(refreshTask)
          }
        }
      }
    },
    scheduleAppRefresh: {
      let request = BGAppRefreshTaskRequest(identifier: "com.opencoder.task-monitor")
      request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)

      try? BGTaskScheduler.shared.submit(request)
    },
    beginBackgroundTask: { name in
      await UIApplication.shared.beginBackgroundTask(withName: name) {

      }
    },
    endBackgroundTask: { taskID in
      await UIApplication.shared.endBackgroundTask(taskID)
    }
  )

  package static let testValue = BackgroundTaskClient(
    registerAppRefresh: {},
    scheduleAppRefresh: {},
    beginBackgroundTask: { _ in .invalid },
    endBackgroundTask: { _ in }
  )
  #else
  package static let liveValue = BackgroundTaskClient(
    registerAppRefresh: {},
    scheduleAppRefresh: {},
    beginBackgroundTask: { _ in 0 },
    endBackgroundTask: { _ in }
  )

  package static let testValue = BackgroundTaskClient(
    registerAppRefresh: {},
    scheduleAppRefresh: {},
    beginBackgroundTask: { _ in -1 },
    endBackgroundTask: { _ in }
  )
  #endif
}

extension DependencyValues {
  package var backgroundTask: BackgroundTaskClient {
    get { self[BackgroundTaskClient.self] }
    set { self[BackgroundTaskClient.self] = newValue }
  }
}

#if canImport(UIKit) && !os(macOS)
@MainActor
private func handleBackgroundTaskMonitoring(_ task: BGAppRefreshTask) async {
  let request = BGAppRefreshTaskRequest(identifier: "com.opencoder.task-monitor")
  request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
  try? BGTaskScheduler.shared.submit(request)

  task.setTaskCompleted(success: true)
}
#endif
