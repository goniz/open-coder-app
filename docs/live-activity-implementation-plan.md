# Live Activity Implementation Plan

## Overview
This document outlines the implementation plan for Live Activities that show progress of active coding tasks. The system maintains SSH connections alive in the background when tasks are active and uses the existing reconnection flow for inactive tasks.

## Architecture Principles
- **Active Task Connections**: Maintain persistent SSH connections only when tasks are actively running
- **Inactive Task Reconnection**: Use existing reconnection flow for servers without active tasks
- **Background Execution**: Leverage Live Activity background capabilities for real-time updates
- **Battery Efficiency**: Minimize background activity when no tasks are running

## Phase 1: Core Models & Infrastructure

### 1. Live Activity Models
**File: `Sources/Models/CodingTaskActivity.swift`**

```swift
import ActivityKit
import Foundation

// ActivityAttributes for Live Activity
struct CodingTaskAttributes: ActivityAttributes {
  struct ContentState: Codable, Hashable {
    var taskName: String
    var progress: Double // 0.0 to 1.0
    var currentStep: String
    var status: TaskStatus
    var elapsedTime: TimeInterval
    var estimatedTimeRemaining: TimeInterval?
  }
  
  var serverName: String
  var projectName: String
  var taskType: TaskType
}

enum TaskStatus: String, Codable, CaseIterable {
  case preparing
  case running
  case completing
  case completed
  case failed
  
  var displayName: String {
    switch self {
    case .preparing: return "Preparing"
    case .running: return "Running"
    case .completing: return "Completing"
    case .completed: return "Completed"
    case .failed: return "Failed"
    }
  }
}

enum TaskType: String, Codable, CaseIterable {
  case build
  case test
  case deploy
  case install
  
  var displayName: String {
    switch self {
    case .build: return "Build"
    case .test: return "Test"
    case .deploy: return "Deploy"
    case .install: return "Install"
    }
  }
  
  var systemImageName: String {
    switch self {
    case .build: return "hammer.fill"
    case .test: return "checkmark.circle.fill"
    case .deploy: return "arrow.up.circle.fill"
    case .install: return "square.and.arrow.down.fill"
    }
  }
}
```

### 2. Task Models (Stubs)
**File: `Sources/Models/CodingTask.swift`**

```swift
import Foundation

struct CodingTask: Identifiable, Equatable, Codable {
  let id = UUID()
  var serverID: ServerState.ID
  var name: String
  var type: TaskType
  var command: String
  var progress: Double = 0.0
  var currentStep: String = ""
  var status: TaskStatus = .preparing
  var startTime: Date?
  var endTime: Date?
  var estimatedDuration: TimeInterval?
  
  // Mock progress simulation
  var mockProgressSteps: [ProgressStep] = []
  var currentStepIndex: Int = 0
  
  var elapsedTime: TimeInterval {
    guard let startTime = startTime else { return 0 }
    let endTime = self.endTime ?? Date()
    return endTime.timeIntervalSince(startTime)
  }
  
  var estimatedTimeRemaining: TimeInterval? {
    guard let estimatedDuration = estimatedDuration, progress > 0 else { return nil }
    let elapsed = elapsedTime
    let totalEstimated = elapsed / progress
    return max(0, totalEstimated - elapsed)
  }
}

struct ProgressStep: Codable, Equatable {
  let progress: Double
  let stepName: String
  let duration: TimeInterval
}

// MARK: - Mock Data Extensions
extension CodingTask {
  static func mockBuildTask(serverID: ServerState.ID) -> CodingTask {
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
        ProgressStep(progress: 1.0, stepName: "Build complete", duration: 2)
      ],
      estimatedDuration: 35
    )
  }
  
  static func mockTestTask(serverID: ServerState.ID) -> CodingTask {
    CodingTask(
      serverID: serverID,
      name: "Run Unit Tests",
      type: .test,
      command: "swift test",
      mockProgressSteps: [
        ProgressStep(progress: 0.2, stepName: "Setting up test environment", duration: 3),
        ProgressStep(progress: 0.5, stepName: "Running model tests", duration: 10),
        ProgressStep(progress: 0.8, stepName: "Running feature tests", duration: 12),
        ProgressStep(progress: 1.0, stepName: "All tests passed", duration: 1)
      ],
      estimatedDuration: 26
    )
  }
  
  static func mockDeployTask(serverID: ServerState.ID) -> CodingTask {
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
        ProgressStep(progress: 1.0, stepName: "Deployment successful", duration: 2)
      ],
      estimatedDuration: 50
    )
  }
}
```

## Phase 2: Background Connection Management

### 3. Background Task Client
**File: `Sources/DependencyClients/BackgroundTaskClient.swift`**

```swift
import BackgroundTasks
import UIKit
import Foundation

struct BackgroundTaskClient {
  var registerAppRefresh: () async -> Void
  var scheduleAppRefresh: () async -> Void
  var beginBackgroundTask: (String) async -> UIBackgroundTaskIdentifier
  var endBackgroundTask: (UIBackgroundTaskIdentifier) async -> Void
}

extension BackgroundTaskClient: DependencyKey {
  static let liveValue = BackgroundTaskClient(
    registerAppRefresh: {
      BGTaskScheduler.shared.register(
        forTaskWithIdentifier: "com.opencoder.task-monitor",
        using: nil
      ) { task in
        await handleBackgroundTaskMonitoring(task as! BGAppRefreshTask)
      }
    },
    scheduleAppRefresh: {
      let request = BGAppRefreshTaskRequest(identifier: "com.opencoder.task-monitor")
      request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // 15 minutes
      
      try? BGTaskScheduler.shared.submit(request)
    },
    beginBackgroundTask: { name in
      await UIApplication.shared.beginBackgroundTask(withName: name) {
        // Task expired
      }
    },
    endBackgroundTask: { taskID in
      await UIApplication.shared.endBackgroundTask(taskID)
    }
  )
  
  static let testValue = BackgroundTaskClient(
    registerAppRefresh: {},
    scheduleAppRefresh: {},
    beginBackgroundTask: { _ in .invalid },
    endBackgroundTask: { _ in }
  )
}

extension DependencyValues {
  var backgroundTask: BackgroundTaskClient {
    get { self[BackgroundTaskClient.self] }
    set { self[BackgroundTaskClient.self] = newValue }
  }
}

// Background task handler
private func handleBackgroundTaskMonitoring(_ task: BGAppRefreshTask) async {
  // Schedule next background refresh
  let request = BGAppRefreshTaskRequest(identifier: "com.opencoder.task-monitor")
  request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
  try? BGTaskScheduler.shared.submit(request)
  
  // Update active tasks
  // This will be handled by LiveActivityFeature
  task.setTaskCompleted(success: true)
}
```

### 4. Enhanced SSH Connection Pool
**Update File: `Sources/Features/ServersFeature.swift`**

Add the following to the existing `ServersFeature`:

```swift
// Add to State
var activeTaskConnections: [ServerState.ID: Date] = [:] // Track when connection was established
var activeTasks: [CodingTask.ID: CodingTask] = [:]
var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

// Add to Action
case startTaskMonitoring(CodingTask)
case stopTaskMonitoring(CodingTask.ID)
case taskProgressUpdate(CodingTask.ID, Double, String)
case updateLiveActivity(CodingTask)
case maintainActiveTaskConnections
```

## Phase 3: Live Activity Feature

### 5. Live Activity Feature Reducer
**File: `Sources/Features/LiveActivityFeature.swift`**

```swift
import ComposableArchitecture
import ActivityKit
import DependencyClients
import Models

@Reducer
struct LiveActivityFeature {
  @ObservableState
  struct State: Equatable {
    var currentActivity: Activity<CodingTaskAttributes>?
    var isActivityActive = false
    var monitoringTasks: [CodingTask.ID: CodingTask] = [:]
    var progressSimulators: [CodingTask.ID: TaskProgressSimulator] = [:]
  }
  
  enum Action: Equatable {
    case startActivity(CodingTask)
    case updateActivity(CodingTask)
    case stopActivity(CodingTask.ID)
    case backgroundRefresh
    case taskProgressUpdated(CodingTask.ID, Double, String, TaskStatus)
    case simulationCompleted(CodingTask.ID)
  }
  
  @Dependency(\.backgroundTask) var backgroundTask
  
  var body: some ReducerOf<Self> {
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
        return handleTaskProgressUpdated(state: &state, taskID: taskID, progress: progress, step: step, status: status)
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
    
    let attributes = CodingTaskAttributes(
      serverName: "Development Server", // TODO: Get from server state
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
      
      // Start progress simulation
      let simulator = TaskProgressSimulator()
      state.progressSimulators[task.id] = simulator
      
      return .run { send in
        await simulator.startSimulation(task: updatedTask) { progress, step, status in
          await send(.taskProgressUpdated(task.id, progress, step, status))
        }
      }
    } catch {
      print("Failed to start Live Activity: \(error)")
      return .none
    }
  }
  
  private func handleUpdateActivity(state: inout State, task: CodingTask) -> Effect<Action> {
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
  }
  
  private func handleStopActivity(state: inout State, taskID: CodingTask.ID) -> Effect<Action> {
    state.monitoringTasks.removeValue(forKey: taskID)
    state.progressSimulators.removeValue(forKey: taskID)
    
    if state.monitoringTasks.isEmpty {
      state.isActivityActive = false
      return .run { _ in
        await state.currentActivity?.end(nil, dismissalPolicy: .after(.seconds(5)))
      }
    }
    
    return .none
  }
  
  private func handleBackgroundRefresh(state: inout State) -> Effect<Action> {
    // Update all active tasks
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
    
    let updateEffect = Effect<Action>.run { send in
      await send(.updateActivity(task))
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
    return .run { send in
      await send(.stopActivity(taskID))
    }
  }
}
```

## Phase 4: Task Monitoring & Progress

### 6. Task Progress Simulator (Stub)
**File: `Sources/Models/TaskProgressSimulator.swift`**

```swift
import Foundation

actor TaskProgressSimulator {
  private var isRunning = false
  
  func startSimulation(
    task: CodingTask,
    progressCallback: @escaping (Double, String, TaskStatus) async -> Void
  ) async {
    guard !isRunning else { return }
    isRunning = true
    
    await progressCallback(0.0, "Initializing...", .preparing)
    
    try? await Task.sleep(for: .seconds(2))
    
    await progressCallback(0.0, task.mockProgressSteps.first?.stepName ?? "Starting...", .running)
    
    for (index, step) in task.mockProgressSteps.enumerated() {
      guard isRunning else { break }
      
      let duration = step.duration / 10 // Split into smaller updates
      let progressIncrement = (step.progress - (index > 0 ? task.mockProgressSteps[index - 1].progress : 0.0)) / 10
      let baseProgress = index > 0 ? task.mockProgressSteps[index - 1].progress : 0.0
      
      for i in 0..<10 {
        guard isRunning else { break }
        
        let currentProgress = baseProgress + (progressIncrement * Double(i + 1))
        await progressCallback(currentProgress, step.stepName, .running)
        
        try? await Task.sleep(for: .seconds(duration))
      }
    }
    
    if isRunning {
      await progressCallback(1.0, "Completed successfully!", .completed)
    }
    
    isRunning = false
  }
  
  func stopSimulation() {
    isRunning = false
  }
}
```

### 7. Connection Strategy Implementation

Update the `ServersFeature` with enhanced connection management:

```swift
// Add these methods to ServersFeature

private func handleStartTaskMonitoring(state: inout State, task: CodingTask) -> Effect<Action> {
  state.activeTasks[task.id] = task
  state.activeTaskConnections[task.serverID] = Date()
  
  // Begin background task to maintain connection
  return .run { send in
    let backgroundTaskID = await backgroundTask.beginBackgroundTask("task-monitoring-\(task.id)")
    
    // Maintain connection while task is active
    while state.activeTasks[task.id] != nil {
      try? await sshClient.sendKeepAlive(task.serverID)
      try? await Task.sleep(for: .seconds(30))
    }
    
    await backgroundTask.endBackgroundTask(backgroundTaskID)
  }
}

private func handleStopTaskMonitoring(state: inout State, taskID: CodingTask.ID) -> Effect<Action> {
  guard let task = state.activeTasks[taskID] else { return .none }
  
  state.activeTasks.removeValue(forKey: taskID)
  
  // Check if server has any other active tasks
  let hasOtherActiveTasks = state.activeTasks.values.contains { $0.serverID == task.serverID }
  
  if !hasOtherActiveTasks {
    state.activeTaskConnections.removeValue(forKey: task.serverID)
    // Connection will be handled by existing reconnection flow
  }
  
  return .none
}

private func handleMaintainActiveTaskConnections(state: inout State) -> Effect<Action> {
  let connectionEffects = state.activeTaskConnections.keys.map { serverID in
    Effect<Action>.run { _ in
      // Send keep-alive to maintain connection
      try? await sshClient.sendKeepAlive(serverID)
    }
  }
  
  return .merge(connectionEffects)
}
```

## Phase 5: Integration Points

### 8. App Integration
**Update `Sources/Features/AppFeature.swift`:**

```swift
// Add LiveActivityFeature to AppFeature
@Reducer
struct AppFeature {
  @ObservableState
  struct State: Equatable {
    var servers = ServersFeature.State()
    var liveActivity = LiveActivityFeature.State()
    // ... existing state
  }
  
  enum Action: Equatable {
    case servers(ServersFeature.Action)
    case liveActivity(LiveActivityFeature.Action)
    // ... existing actions
  }
  
  var body: some ReducerOf<Self> {
    Scope(state: \.servers, action: \.servers) {
      ServersFeature()
    }
    
    Scope(state: \.liveActivity, action: \.liveActivity) {
      LiveActivityFeature()
    }
    
    // ... existing reducers
  }
}
```

### 9. UI Integration Points

Add task control capabilities to existing views:

**Update `Sources/Views/ServersView.swift`:**
- Add "Start Task" buttons for connected servers
- Show active task indicators
- Display Live Activity status

**Update `Sources/Views/ChatView.swift`:**
- Add quick task commands
- Show task progress in chat interface

## Configuration Requirements

### 10. App Capabilities
**Add to `Xcode/OpenCoder/OpenCoder.entitlements`:**

```xml
<key>com.apple.developer.ActivityKit</key>
<true/>
<key>com.apple.developer.background-modes</key>
<array>
    <string>background-app-refresh</string>
    <string>background-processing</string>
</array>
```

**Add to `Info.plist`:**

```xml
<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
    <string>com.opencoder.task-monitor</string>
</array>
<key>NSSupportsLiveActivities</key>
<true/>
```

## Implementation Order

1. ✅ **Start with models** (CodingTask, ActivityAttributes)
2. ✅ **Add background task client** with stubs  
3. ✅ **Enhance ServersFeature** with active task connection pooling
4. ✅ **Create LiveActivityFeature** with mock progress
5. **Integrate with existing UI**
6. **Add background refresh scheduling**
7. **Test Live Activity updates**
8. **Add real SSH task monitoring** (future phase)

## Key Benefits

- **Selective Connection Management**: Only maintains connections for servers with active tasks
- **Battery Efficient**: Uses existing reconnection for inactive servers
- **Real-time Updates**: Live Activities update in real-time during task execution
- **Graceful Degradation**: Falls back to reconnection flow when tasks complete
- **Extensible**: Easy to replace stubs with real SSH task monitoring later

## Future Enhancements

- Replace progress simulators with real SSH command monitoring
- Add push notification support for remote task updates  
- Implement task queuing and scheduling
- Add task history and analytics
- Support for multiple concurrent tasks per server