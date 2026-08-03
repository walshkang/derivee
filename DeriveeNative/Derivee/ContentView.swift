import SwiftUI

struct ContentView: View {
    @State private var isHydrationComplete = false
    @State private var isCheckingHydration = true
    @State private var spatialStore = SpatialStore()
    @State private var showTransitSheet = false
    @State private var selectedTransitStop: String? = nil
    
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
                ZStack {
                    MapView(spatialStore: spatialStore,
                            showTransitSheet: $showTransitSheet,
                            selectedTransitStop: $selectedTransitStop)
                        .ignoresSafeArea()
                    
                    VStack {
                        HStack {
                            Spacer()
                            ProfileFAB {
                                // Navigate to StatsView
                                print("Profile tapped")
                            }
                            .padding(.top, 50)
                            .padding(.trailing, 20)
                        }
                        
                        Spacer()
                        
                        HStack {
                            Spacer()
                            RecenterFAB(isCentered: false) {
                                // Action to re-center MapLibre camera
                                print("Recenter tapped")
                            }
                            .padding(.bottom, 40)
                            .padding(.trailing, 20)
                        }
                    }
                }
                .sheet(isPresented: $showTransitSheet) {
                    VStack {
                        Text("Transit Reveal")
                            .font(.title)
                            .bold()
                            .padding()
                        if let stop = selectedTransitStop {
                            Text("Stop ID: \(stop)")
                        }
                        Spacer()
                    }
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
