import SwiftUI

struct ContentView: View {
    @State private var isHydrationComplete = false
    @State private var isCheckingHydration = true
    @State private var spatialStore = SpatialStore()
    @State private var showTransitSheet = false
    @State private var selectedTransitStop: String? = nil
    @State private var showGlow = false
    
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
                    
                    if showGlow {
                        Circle()
                            .strokeBorder(Color.white.opacity(0.8), lineWidth: 4)
                            .frame(width: 80, height: 80)
                            .shadow(color: .white, radius: 10)
                            .transition(.scale.combined(with: .opacity))
                    }
                    
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
                .onChange(of: spatialStore.newlyUnlockedHexLocation != nil) {
                    if spatialStore.newlyUnlockedHexLocation != nil {
                        withAnimation(.easeOut(duration: 0.1)) {
                            showGlow = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            withAnimation {
                                showGlow = false
                            }
                            spatialStore.newlyUnlockedHexLocation = nil
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
