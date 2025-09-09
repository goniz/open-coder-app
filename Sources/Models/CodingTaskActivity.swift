import Foundation

#if canImport(ActivityKit)
import ActivityKit
#endif

#if canImport(ActivityKit) && !os(macOS)
package struct CodingTaskAttributes: ActivityAttributes {
  package struct ContentState: Codable, Hashable {
    package var taskName: String
    package var progress: Double
    package var currentStep: String
    package var status: TaskStatus
    package var elapsedTime: TimeInterval
    package var estimatedTimeRemaining: TimeInterval?

    package init(
      taskName: String,
      progress: Double,
      currentStep: String,
      status: TaskStatus,
      elapsedTime: TimeInterval,
      estimatedTimeRemaining: TimeInterval? = nil
    ) {
      self.taskName = taskName
      self.progress = progress
      self.currentStep = currentStep
      self.status = status
      self.elapsedTime = elapsedTime
      self.estimatedTimeRemaining = estimatedTimeRemaining
    }
  }
}
#else
package struct CodingTaskAttributes: Codable {
  package struct ContentState: Codable, Hashable {
    package var taskName: String
    package var progress: Double
    package var currentStep: String
    package var status: TaskStatus
    package var elapsedTime: TimeInterval
    package var estimatedTimeRemaining: TimeInterval?

    package init(
      taskName: String,
      progress: Double,
      currentStep: String,
      status: TaskStatus,
      elapsedTime: TimeInterval,
      estimatedTimeRemaining: TimeInterval? = nil
    ) {
      self.taskName = taskName
      self.progress = progress
      self.currentStep = currentStep
      self.status = status
      self.elapsedTime = elapsedTime
      self.estimatedTimeRemaining = estimatedTimeRemaining
    }
  }

  package var serverName: String
  package var projectName: String
  package var taskType: TaskType

  package init(serverName: String, projectName: String, taskType: TaskType) {
    self.serverName = serverName
    self.projectName = projectName
    self.taskType = taskType
  }
}
#endif

package enum TaskStatus: String, Codable, CaseIterable {
  case preparing
  case running
  case completing
  case completed
  case failed

  package var displayName: String {
    switch self {
    case .preparing: return "Preparing"
    case .running: return "Running"
    case .completing: return "Completing"
    case .completed: return "Completed"
    case .failed: return "Failed"
    }
  }
}

package enum TaskType: String, Codable, CaseIterable {
  case build
  case test
  case deploy
  case install

  package var displayName: String {
    switch self {
    case .build: return "Build"
    case .test: return "Test"
    case .deploy: return "Deploy"
    case .install: return "Install"
    }
  }

  package var systemImageName: String {
    switch self {
    case .build: return "hammer.fill"
    case .test: return "checkmark.circle.fill"
    case .deploy: return "arrow.up.circle.fill"
    case .install: return "square.and.arrow.down.fill"
    }
  }
}
