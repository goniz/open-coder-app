import Foundation

package struct CodingTask: Identifiable, Equatable, Codable {
  package let id: UUID
  package var serverID: UUID
  package var name: String
  package var type: TaskType
  package var command: String
  package var progress: Double = 0.0
  package var currentStep: String = ""
  package var status: TaskStatus = .preparing
  package var startTime: Date?
  package var endTime: Date?
  package var estimatedDuration: TimeInterval?

  package var mockProgressSteps: [ProgressStep] = []
  package var currentStepIndex: Int = 0

  package var elapsedTime: TimeInterval {
    guard let startTime = startTime else { return 0 }
    let endTime = self.endTime ?? Date()
    return endTime.timeIntervalSince(startTime)
  }

  package var estimatedTimeRemaining: TimeInterval? {
    guard estimatedDuration != nil, progress > 0 else { return nil }
    let elapsed = elapsedTime
    let totalEstimated = elapsed / progress
    return max(0, totalEstimated - elapsed)
  }

  package init(
    id: UUID = UUID(),
    serverID: UUID,
    name: String,
    type: TaskType,
    command: String,
    mockProgressSteps: [ProgressStep] = [],
    estimatedDuration: TimeInterval? = nil
  ) {
    self.id = id
    self.serverID = serverID
    self.name = name
    self.type = type
    self.command = command
    self.mockProgressSteps = mockProgressSteps
    self.estimatedDuration = estimatedDuration
  }
}

package struct ProgressStep: Codable, Equatable {
  package let progress: Double
  package let stepName: String
  package let duration: TimeInterval

  package init(progress: Double, stepName: String, duration: TimeInterval) {
    self.progress = progress
    self.stepName = stepName
    self.duration = duration
  }
}

extension CodingTask {
  package static func mockBuildTask(serverID: UUID) -> CodingTask {
    CodingTask(
      serverID: serverID,
      name: "Build iOS App",
      type: .build,
      command: "xcodebuild -scheme OpenCoder build",
      mockProgressSteps: [
        ProgressStep(progress: 0.1, stepName: "Initializing build system", duration: 5),
        ProgressStep(progress: 0.3, stepName: "Compiling Swift sources", duration: 15),
        ProgressStep(progress: 0.6, stepName: "Linking frameworks", duration: 8),
        ProgressStep(progress: 0.8, stepName: "Processing resources", duration: 5),
        ProgressStep(progress: 1.0, stepName: "Build complete", duration: 2),
      ],
      estimatedDuration: 35
    )
  }

  package static func mockTestTask(serverID: UUID) -> CodingTask {
    CodingTask(
      serverID: serverID,
      name: "Run Unit Tests",
      type: .test,
      command: "swift test",
      mockProgressSteps: [
        ProgressStep(progress: 0.2, stepName: "Setting up test environment", duration: 3),
        ProgressStep(progress: 0.5, stepName: "Running model tests", duration: 10),
        ProgressStep(progress: 0.8, stepName: "Running feature tests", duration: 12),
        ProgressStep(progress: 1.0, stepName: "All tests passed", duration: 1),
      ],
      estimatedDuration: 26
    )
  }

  package static func mockDeployTask(serverID: UUID) -> CodingTask {
    CodingTask(
      serverID: serverID,
      name: "Deploy to Production",
      type: .deploy,
      command: "./deploy.sh production",
      mockProgressSteps: [
        ProgressStep(progress: 0.1, stepName: "Validating deployment", duration: 5),
        ProgressStep(progress: 0.3, stepName: "Building production assets", duration: 20),
        ProgressStep(progress: 0.6, stepName: "Uploading to server", duration: 15),
        ProgressStep(progress: 0.9, stepName: "Running health checks", duration: 8),
        ProgressStep(progress: 1.0, stepName: "Deployment successful", duration: 2),
      ],
      estimatedDuration: 50
    )
  }
}
