import SwiftUI

@main
struct DeriveeApp: App {
    var body: some Scene {
        WindowGroup {
            if NSClassFromString("XCTestCase") != nil {
                EmptyView()
            } else {
                ContentView()
            }
        }
    }
}
