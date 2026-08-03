import SwiftUI

struct ContentView: View {
    @State private var isHydrationComplete = false
    @State private var isCheckingHydration = true
    
    var body: some View {
        Group {
            if isCheckingHydration {
                Color.black.ignoresSafeArea()
                    .onAppear {
                        isHydrationComplete = SpatialDatabaseManager.shared.isHydrationComplete()
                        isCheckingHydration = false
                    }
            } else if !isHydrationComplete {
                OnboardingView(isHydrationComplete: $isHydrationComplete)
            } else {
                // Main Map View (Placeholder for Wave F)
                VStack(spacing: 20) {
                    Image(systemName: "map")
                        .imageScale(.large)
                        .foregroundStyle(.tint)
                    Text("Derivee Native Map")
                        .font(.title)
                    Text("Ready to explore. Hydration complete.")
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
