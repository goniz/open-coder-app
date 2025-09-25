import Foundation

#if canImport(ActivityKit)
  import ActivityKit
#endif

#if canImport(ActivityKit) && !os(macOS)
  public struct CodingTaskAttributes: ActivityAttributes, Sendable {

    public var serverName: String
    public var projectName: String
    public var taskType: TaskType

    public init(serverName: String, projectName: String, taskType: TaskType) {
      self.serverName = serverName
      self.projectName = projectName
      self.taskType = taskType
    }

    public struct ContentState: Codable, Hashable, Sendable {

      public var taskName: String
      public var progress: Double
      public var currentStep: String
      public var status: TaskStatus
      public var elapsedTime: TimeInterval
      public var estimatedTimeRemaining: TimeInterval?

      public init(
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
  public struct CodingTaskAttributes: Codable, Sendable {

    public struct ContentState: Codable, Hashable, Sendable {

      public var taskName: String
      public var progress: Double
      public var currentStep: String
      public var status: TaskStatus
      public var elapsedTime: TimeInterval
      public var estimatedTimeRemaining: TimeInterval?

      public init(
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

    public var serverName: String
    public var projectName: String
    public var taskType: TaskType

    public init(serverName: String, projectName: String, taskType: TaskType) {
      self.serverName = serverName
      self.projectName = projectName
      self.taskType = taskType
    }
  }
#endif

public enum TaskStatus: String, Codable, CaseIterable, Sendable {

  case preparing
  case running
  case completing
  case completed
  case failed

  public var displayName: String {
    switch self {
    case .preparing: return "Preparing"
    case .running: return "Running"
    case .completing: return "Completing"
    case .completed: return "Completed"
    case .failed: return "Failed"
    }
  }
}

public enum TaskType: String, Codable, CaseIterable, Sendable {

  case build
  case test
  case deploy
  case install

  public var displayName: String {
    switch self {
    case .build: return "Build"
    case .test: return "Test"
    case .deploy: return "Deploy"
    case .install: return "Install"
    }
  }

  public var systemImageName: String {
    switch self {
    case .build: return "hammer.fill"
    case .test: return "checkmark.circle.fill"
    case .deploy: return "arrow.up.circle.fill"
    case .install: return "square.and.arrow.down.fill"
    }
  }
}
