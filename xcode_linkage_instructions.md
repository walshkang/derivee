# Xcode Linkage Instructions for HybridTracker Nitro Module

Follow these step-by-step instructions to manually link the generated Nitro Module in Xcode, as required by the brownfield architecture.

### Step 1: Open the Workspace
Open the iOS workspace in Xcode. Do not open the bare `.xcodeproj`.
```bash
open ios/Derivee.xcworkspace
```

### Step 2: Import Generated Nitrogen Files
1. In the Xcode Project Navigator (left sidebar), locate the main `Derivee` project folder.
2. Open a Finder window and navigate to `nitrogen/generated/ios/`.
3. Drag the entire `ios` folder from Finder into the Xcode Project Navigator under the `Derivee` group.
4. A prompt will appear. **Crucially**, ensure you select **"Create groups"** (not "Create folder references").
5. Ensure the `Derivee` target is checked under "Add to targets".
6. Click **Finish**.

### Step 3: Create the Swift Implementation File
1. Right-click on the `Derivee` group in the Project Navigator and select **New File...**
2. Choose **Swift File** and click **Next**.
3. Name the file `HybridTracker.swift`.
4. Ensure the `Derivee` target is checked.
5. Click **Create**.

### Step 4: Configure the Bridging Header
Because a Swift file (`noop-file.swift`) already exists in the project, Xcode has already created and configured `Derivee-Bridging-Header.h`. You do not need to create a new header!

I have already updated `ios/Derivee/Derivee-Bridging-Header.h` with the required imports:
```objc
#import "h3api.h"
#import <sqlite3.h>
```


### Step 5: Verify the Build
Build the project (`Cmd + B`) to verify that the C++ translation layers and the `HybridTrackingSpec.swift` protocol compile successfully. You are now ready for Wave C to implement the Swift service!
