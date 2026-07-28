package expo.modules.backgroundassertion

import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition

class ExpoBackgroundAssertionModule : Module() {
  override func definition() = ModuleDefinition {
    Name("ExpoBackgroundAssertion")

    Function("beginBackgroundTask") { name: String? ->
      // No-op stub for Android (UIBackgroundTaskIdentifier equivalent not needed)
      return@Function 0
    }

    Function("endBackgroundTask") { taskId: Int ->
      // No-op stub for Android
    }
  }
}
