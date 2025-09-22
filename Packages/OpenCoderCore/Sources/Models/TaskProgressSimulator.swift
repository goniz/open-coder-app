import Foundation

package actor TaskProgressSimulator {
  private var isRunning = false

  package init() {}

  package func startSimulation(
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

      let duration = step.duration / 10
      let progressIncrement =
        (step.progress - (index > 0 ? task.mockProgressSteps[index - 1].progress : 0.0)) / 10
      let baseProgress = index > 0 ? task.mockProgressSteps[index - 1].progress : 0.0

      for stepIndex in 0..<10 {
        guard isRunning else { break }

        let currentProgress = baseProgress + (progressIncrement * Double(stepIndex + 1))
        await progressCallback(currentProgress, step.stepName, .running)

        try? await Task.sleep(for: .seconds(duration))
      }
    }

    if isRunning {
      await progressCallback(1.0, "Completed successfully!", .completed)
    }

    isRunning = false
  }

  package func stopSimulation() {
    isRunning = false
  }
}
