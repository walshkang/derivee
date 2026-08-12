import SwiftUI
import CoreLocation

struct ContentView: View {
    @State private var isHydrationComplete = false
    @State private var isCheckingHydration = true
    @StateObject private var trackingEngine = AmbientTrackingEngine()
    @State private var spatialStore = SpatialStore()
    @State private var showTransitSheet = false
    @State private var selectedTransitStop: String? = nil
    @State private var isMapCentered = true
    @State private var recenterTrigger = false
    @State private var showStatsView = false
    @State private var userScreenPosition: CGPoint? = nil
    @State private var targetCoordinate: CLLocationCoordinate2D? = nil
    
    @State private var glowScale: CGFloat = 1.0
    @State private var glowOpacity: Double = 0.0
    
    var body: some View {
        Group {
            if isCheckingHydration {
                Color.black.ignoresSafeArea()
                    .task {
                        isHydrationComplete = (try? await SpatialDatabaseManager.shared.isHydrationComplete()) ?? false
                        isCheckingHydration = false
                    }
            } else if !isHydrationComplete {
                OnboardingView(trackingEngine: trackingEngine, isHydrationComplete: $isHydrationComplete)
            } else {
                ZStack {
                    MapView(trackingEngine: trackingEngine,
                            spatialStore: spatialStore,
                            fogShape: spatialStore.currentFogShape,
                            showTransitSheet: $showTransitSheet,
                            selectedTransitStop: $selectedTransitStop,
                            isCentered: $isMapCentered,
                            recenterTrigger: $recenterTrigger,
                            userScreenPosition: $userScreenPosition,
                            targetCoordinate: $targetCoordinate,
                            transientHexShape: spatialStore.transientHexShape)
                        .ignoresSafeArea()
                    
                    GeometryReader { geo in
                        Circle()
                            .strokeBorder(Color.white, lineWidth: 4)
                            .frame(width: 80, height: 80)
                            .shadow(color: .white, radius: 10)
                            .scaleEffect(glowScale)
                            .opacity(glowOpacity)
                            .position(userScreenPosition ?? CGPoint(x: geo.size.width / 2, y: geo.size.height / 2))
                    }
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    
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
                        glowScale = 1.0
                        glowOpacity = 0.8
                        
                        withAnimation(.easeOut(duration: 1.5)) {
                            glowScale = 4.0
                            glowOpacity = 0.0
                        }
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            spatialStore.newlyUnlockedHexLocation = nil
                        }
                    }
                }
                .sheet(isPresented: $showTransitSheet, onDismiss: {
                    selectedTransitStop = nil
                }) {
                    if let stopId = selectedTransitStop {
                        TransitRevealSheet(stopId: stopId)
                            .presentationDetents([.medium, .large])
                            .presentationDragIndicator(.visible)
                    }
                }
                .sheet(isPresented: $showStatsView) {
                    StatsView(trackingEngine: trackingEngine, spatialStore: spatialStore, targetCoordinate: $targetCoordinate)
                }
                .onOpenURL { url in
                    guard url.scheme == "derivee" && url.host == "progress" else { return }
                    
                    // If the app was already actively running in the foreground, present the Stats sheet.
                    // If it was tapped from the background/lock screen, the state will be .inactive or .background,
                    // so we do nothing and let it default to the Map View (Screen 1).
                    if UIApplication.shared.applicationState == .active {
                        showStatsView = true
                    } else {
                        showStatsView = false
                    }
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
