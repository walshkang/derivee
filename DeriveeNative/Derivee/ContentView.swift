import SwiftUI

struct ContentView: View {
    @State private var isHydrationComplete = false
    @State private var isCheckingHydration = true
    @State private var spatialStore = SpatialStore()
    @State private var showTransitSheet = false
    @State private var selectedTransitStop: String? = nil
    @State private var showGlow = false
    @State private var isMapCentered = true
    @State private var recenterTrigger = false
    @State private var showStatsView = false
    
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
                            fogShape: spatialStore.currentFogShape,
                            showTransitSheet: $showTransitSheet,
                            selectedTransitStop: $selectedTransitStop,
                            isCentered: $isMapCentered,
                            recenterTrigger: $recenterTrigger)
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
                                showStatsView = true
                            }
                            .padding(.top, 50)
                            .padding(.trailing, 20)
                        }
                        
                        Spacer()
                        
                        HStack {
                            Spacer()
                            RecenterFAB(isCentered: isMapCentered) {
                                recenterTrigger.toggle()
                                isMapCentered = true
                            }
                            .padding(.bottom, 40)
                            .padding(.trailing, 20)
                        }
                    }
                    
                    if let poiName = spatialStore.newlyDiscoveredPOIName {
                        VStack {
                            DiscoveryToast(stationName: poiName) {
                                spatialStore.newlyDiscoveredPOIName = nil
                            }
                            .transition(.move(edge: .top).combined(with: .opacity))
                            
                            Spacer()
                        }
                        .padding(.top, 50)
                        .zIndex(2)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                if spatialStore.newlyDiscoveredPOIName == poiName {
                                    withAnimation {
                                        spatialStore.newlyDiscoveredPOIName = nil
                                    }
                                }
                            }
                        }
                    }
                }
                .animation(.spring(), value: spatialStore.newlyDiscoveredPOIName)
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
                .sheet(isPresented: $showStatsView) {
                    StatsView()
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
