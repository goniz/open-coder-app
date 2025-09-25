import BackgroundTasks
import Dependencies
import Foundation

#if canImport(UIKit)
  import UIKit
#endif

public struct BackgroundTaskClient: Sendable {
  public var registerAppRefresh: @Sendable () async -> Void
  public var scheduleAppRefresh: @Sendable () async -> Void
  #if canImport(UIKit) && !os(macOS)
    public var beginBackgroundTask: @Sendable (String) async -> UIBackgroundTaskIdentifier
    public var endBackgroundTask: @Sendable (UIBackgroundTaskIdentifier) async -> Void
  #else
    public var beginBackgroundTask: @Sendable (String) async -> Int
    public var endBackgroundTask: @Sendable (Int) async -> Void
  #endif

  #if canImport(UIKit) && !os(macOS)
    public init(
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
    public init(
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
    public static let liveValue = BackgroundTaskClient(
      registerAppRefresh: {
        BGTaskScheduler.shared.register(
          forTaskWithIdentifier: "com.opencoder.task-monitor",
          using: nil
        ) { task in
          if let refreshTask = task as? BGAppRefreshTask {
            handleBackgroundTaskMonitoringSync(refreshTask)
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

    public static let testValue = BackgroundTaskClient(
      registerAppRefresh: {},
      scheduleAppRefresh: {},
      beginBackgroundTask: { _ in .invalid },
      endBackgroundTask: { _ in }
    )
  #else
    public static let liveValue = BackgroundTaskClient(
      registerAppRefresh: {},
      scheduleAppRefresh: {},
      beginBackgroundTask: { _ in 0 },
      endBackgroundTask: { _ in }
    )

    public static let testValue = BackgroundTaskClient(
      registerAppRefresh: {},
      scheduleAppRefresh: {},
      beginBackgroundTask: { _ in -1 },
      endBackgroundTask: { _ in }
    )
  #endif
}

extension DependencyValues {
  public var backgroundTask: BackgroundTaskClient {
    get { self[BackgroundTaskClient.self] }
    set { self[BackgroundTaskClient.self] = newValue }
  }
}

#if canImport(UIKit) && !os(macOS)
  private func handleBackgroundTaskMonitoringSync(_ task: BGAppRefreshTask) {
    let request = BGAppRefreshTaskRequest(identifier: "com.opencoder.task-monitor")
    request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
    try? BGTaskScheduler.shared.submit(request)

    task.setTaskCompleted(success: true)
  }
#endif
