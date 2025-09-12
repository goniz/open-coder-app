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
    @ObservationStateIgnored package var progressSimulators:
      [CodingTask.ID: TaskProgressSimulator] = [:]

    package init() {}

    package static func == (lhs: State, rhs: State) -> Bool {
      lhs.isActivityActive == rhs.isActivityActive && lhs.monitoringTasks == rhs.monitoringTasks
    }
  }

  package enum Action: Equatable {
    case startActivity(CodingTask)
    case updateActivity(CodingTask)
    case stopActivity(CodingTask.ID)
    case backgroundRefresh
    case taskProgressUpdated(CodingTask.ID, Double, String, TaskStatus)
    case simulationCompleted(CodingTask.ID)
  }

  package init() {}

  @Dependency(\.backgroundTask) var backgroundTask

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
          state: &state, taskID: taskID, progress: progress, step: step, status: status)
      case let .simulationCompleted(taskID):
        return handleSimulationCompleted(state: &state, taskID: taskID)
      }
    }
  }

  private func handleStartActivity(state: inout State, task: CodingTask) -> Effect<Action> {
    var updatedTask = task
    updatedTask.startTime = Date()
    updatedTask.status = .running
    state.monitoringTasks[task.id] = updatedTask

    #if canImport(ActivityKit) && !os(macOS)
      let attributes = CodingTaskAttributes(
        serverName: "Development Server",
        projectName: "OpenCoder",
        taskType: task.type
      )

      let contentState = CodingTaskAttributes.ContentState(
        taskName: task.name,
        progress: 0.0,
        currentStep: "Starting...",
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

    let simulator = TaskProgressSimulator()
    state.progressSimulators[task.id] = simulator
    let taskId = updatedTask.id
    let taskCopy = updatedTask

    return .run { send in
      await simulator.startSimulation(task: taskCopy) { progress, step, status in
        await send(.taskProgressUpdated(taskId, progress, step, status))
      }
    }
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
    state.progressSimulators.removeValue(forKey: taskID)

    if state.monitoringTasks.isEmpty {
      state.isActivityActive = false
      #if canImport(ActivityKit) && !os(macOS)
        let currentActivity = state.currentActivity
        return .run { _ in
          await currentActivity?.end(nil, dismissalPolicy: .after(Date().addingTimeInterval(5)))
        }
      #endif
    }

    return .none
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

  private func handleSimulationCompleted(state: inout State, taskID: CodingTask.ID) -> Effect<
    Action
  > {
    return .run { send in
      await send(.stopActivity(taskID))
    }
  }
}
