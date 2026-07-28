import ExpoModulesCore
import UIKit

public class ExpoBackgroundAssertionModule: Module {
  private var backgroundTasks = [Int: UIBackgroundTaskIdentifier]()
  private var nextTaskId: Int = 1

  public func definition() -> ModuleDefinition {
    Name("ExpoBackgroundAssertion")

    Function("beginBackgroundTask") { (name: String?) -> Int in
      let taskName = name ?? "ExpoBackgroundAssertionTask"
      var identifier: UIBackgroundTaskIdentifier = .invalid
      let currentTaskId = self.nextTaskId
      self.nextTaskId += 1

      identifier = UIApplication.shared.beginBackgroundTask(withName: taskName) {
        // Expiration handler: clean up if iOS watchdog expires the task
        if identifier != .invalid {
          UIApplication.shared.endBackgroundTask(identifier)
          self.backgroundTasks.removeValue(forKey: currentTaskId)
        }
      }

      if identifier != .invalid {
        self.backgroundTasks[currentTaskId] = identifier
        return currentTaskId
      }

      return 0
    }

    Function("endBackgroundTask") { (taskId: Int) in
      if let identifier = self.backgroundTasks[taskId] {
        if identifier != .invalid {
          UIApplication.shared.endBackgroundTask(identifier)
        }
        self.backgroundTasks.removeValue(forKey: taskId)
      }
    }
  }
}
