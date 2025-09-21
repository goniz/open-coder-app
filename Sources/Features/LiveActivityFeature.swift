import ComposableArchitecture
import DependencyClients
import Foundation
import Models

#if canImport(ActivityKit)
  @preconcurrency import ActivityKit
#endif

@Reducer
package struct LiveActivityFeature {
  @ObservableState
  package struct State: Equatable {
    #if canImport(ActivityKit) && !os(macOS)
      package var currentActivity: Activity<CodingTaskAttributes>?
    #endif
    package var isActivityActive = false
    package var monitoringTasks: [CodingTask.ID: CodingTask] = [:]
    package var taskSessions: [CodingTask.ID: OpenCodeSession] = [:]

    package init() {}

    package static func == (lhs: State, rhs: State) -> Bool {
      lhs.isActivityActive == rhs.isActivityActive
        && lhs.monitoringTasks == rhs.monitoringTasks
        && lhs.taskSessions.keys == rhs.taskSessions.keys
    }
  }

  package enum Action: Equatable {
    case startActivity(CodingTask)
    case updateActivity(CodingTask)
    case stopActivity(CodingTask.ID)
    case backgroundRefresh
    case taskProgressUpdated(CodingTask.ID, Double, String, TaskStatus)
    case simulationCompleted(CodingTask.ID)
    case taskSessionEstablished(CodingTask.ID, OpenCodeSession)
    case taskFailed(CodingTask.ID, String)
  }

  @Dependency(\.backgroundTask) var backgroundTask
  @Dependency(\.openCodeAPI) var openCodeAPI

  package init() {}

  private enum CancelID: Hashable {
    case task(UUID)
  }

  package var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case let .startActivity(task):
        return handleStartActivity(state: &state, task: task)

      case let .updateActivity(task):
        return handleUpdateActivity(state: &state, task: task)

      case let .stopActivity(taskID):
        return handleStopActivity(state: &state, taskID: taskID)

      case .backgroundRefresh:
        return handleBackgroundRefresh(state: &state)

      case let .taskProgressUpdated(taskID, progress, step, status):
        return handleTaskProgressUpdated(
          state: &state,
          taskID: taskID,
          progress: progress,
          step: step,
          status: status
        )

      case let .simulationCompleted(taskID):
        return handleSimulationCompleted(state: &state, taskID: taskID)

      case let .taskSessionEstablished(taskID, session):
        return handleTaskSessionEstablished(state: &state, taskID: taskID, session: session)

      case let .taskFailed(taskID, message):
        return handleTaskFailed(state: &state, taskID: taskID, message: message)
      }
    }
  }

  private func handleStartActivity(state: inout State, task: CodingTask) -> Effect<Action> {
    var updatedTask = task
    updatedTask.startTime = Date()
    updatedTask.status = .running
    updatedTask.progress = 0
    state.monitoringTasks[task.id] = updatedTask

    prepareLiveActivity(state: &state, task: updatedTask)
    return monitorTaskEffect(for: updatedTask)
  }

  private func handleUpdateActivity(state: inout State, task: CodingTask) -> Effect<Action> {
    #if canImport(ActivityKit) && !os(macOS)
      guard let activity = state.currentActivity else { return .none }

      let contentState = CodingTaskAttributes.ContentState(
        taskName: task.name,
        progress: task.progress,
        currentStep: task.currentStep,
        status: task.status,
        elapsedTime: task.elapsedTime,
        estimatedTimeRemaining: task.estimatedTimeRemaining
      )

      return .run { _ in
        await activity.update(.init(state: contentState, staleDate: nil))
      }
    #else
      return .none
    #endif
  }

  private func handleStopActivity(state: inout State, taskID: CodingTask.ID) -> Effect<Action> {
    state.monitoringTasks.removeValue(forKey: taskID)
    state.taskSessions.removeValue(forKey: taskID)

    if state.monitoringTasks.isEmpty {
      state.isActivityActive = false
      #if canImport(ActivityKit) && !os(macOS)
        let currentActivity = state.currentActivity
        state.currentActivity = nil
        return .concatenate(
          .cancel(id: CancelID.task(taskID)),
          .run { _ in
            await currentActivity?.end(nil, dismissalPolicy: .after(Date().addingTimeInterval(5)))
          }
        )
      #else
        return .cancel(id: CancelID.task(taskID))
      #endif
    }

    return .cancel(id: CancelID.task(taskID))
  }

  private func handleBackgroundRefresh(state: inout State) -> Effect<Action> {
    let updateEffects = state.monitoringTasks.values.map { task in
      Effect<Action>.run { send in
        await send(.updateActivity(task))
      }
    }

    return .merge(updateEffects)
  }

  private func handleTaskProgressUpdated(
    state: inout State,
    taskID: CodingTask.ID,
    progress: Double,
    step: String,
    status: TaskStatus
  ) -> Effect<Action> {
    guard var task = state.monitoringTasks[taskID] else { return .none }

    task.progress = progress
    task.currentStep = step
    task.status = status

    if status == .completed || status == .failed {
      task.endTime = Date()
    }

    state.monitoringTasks[taskID] = task
    let updatedTask = task

    let updateEffect = Effect<Action>.run { send in
      await send(.updateActivity(updatedTask))
    }

    if status == .completed || status == .failed {
      return .concatenate(
        updateEffect,
        .run { send in
          try await Task.sleep(for: .seconds(2))
          await send(.simulationCompleted(taskID))
        }
      )
    }

    return updateEffect
  }

  private func handleSimulationCompleted(state: inout State, taskID: CodingTask.ID) -> Effect<Action> {
    .run { send in
      await send(.stopActivity(taskID))
    }
  }

  private func handleTaskSessionEstablished(
    state: inout State,
    taskID: CodingTask.ID,
    session: OpenCodeSession
  ) -> Effect<Action> {
    state.taskSessions[taskID] = session
    if var task = state.monitoringTasks[taskID] {
      task.sessionID = session.id
      state.monitoringTasks[taskID] = task
    }
    return .none
  }

  private func handleTaskFailed(
    state: inout State,
    taskID: CodingTask.ID,
    message: String
  ) -> Effect<Action> {
    let effect = handleTaskProgressUpdated(
      state: &state,
      taskID: taskID,
      progress: state.monitoringTasks[taskID]?.progress ?? 0,
      step: "Failed: \(message)",
      status: .failed
    )

    return effect
  }
}

private extension LiveActivityFeature {
  func prepareLiveActivity(state: inout State, task: CodingTask) {
    #if canImport(ActivityKit) && !os(macOS)
      let attributes = CodingTaskAttributes(
        serverName: "Development Server",
        projectName: "OpenCoder",
        taskType: task.type
      )

      let contentState = CodingTaskAttributes.ContentState(
        taskName: task.name,
        progress: 0.0,
        currentStep: "Initializing...",
        status: .running,
        elapsedTime: 0,
        estimatedTimeRemaining: task.estimatedDuration
      )

      do {
        let activity = try Activity<CodingTaskAttributes>.request(
          attributes: attributes,
          content: .init(state: contentState, staleDate: nil)
        )
        state.currentActivity = activity
        state.isActivityActive = true
      } catch {
        print("Failed to start Live Activity: \(error)")
      }
    #else
      state.isActivityActive = true
    #endif
  }

  func monitorTaskEffect(for task: CodingTask) -> Effect<Action> {
    let command = task.command
    let taskID = task.id

    return .run { send in
      do {
        let session = try await openCodeAPI.createSession()
        await send(.taskSessionEstablished(taskID, session))
        await send(.taskProgressUpdated(taskID, 0.2, "Session ready", .running))

        let response = try await openCodeAPI.runShellCommand(
          sessionID: session.id,
          command: command
        )

        let summary = summarizeResponse(response)
        await send(.taskProgressUpdated(taskID, 1.0, summary, .completed))
        try await Task.sleep(for: .seconds(1))
        await send(.simulationCompleted(taskID))
      } catch {
        await send(.taskFailed(taskID, error.localizedDescription))
      }
    }
    .cancellable(id: CancelID.task(task.id), cancelInFlight: true)
  }
}

private func summarizeResponse(_ message: OpenCodeMessage) -> String {
  for part in message.parts {
    if case let .text(content) = part {
      return content
    }
  }
  return "Command completed"
}
