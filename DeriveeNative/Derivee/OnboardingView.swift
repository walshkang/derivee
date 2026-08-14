import SwiftUI
import Network

struct OnboardingView: View {
    @ObservedObject var trackingEngine: AmbientTrackingEngine
    @State private var hydrationManager = HydrationManager()
    @State private var networkStatus: NWPath.Status = .requiresConnection
    @Binding var isHydrationComplete: Bool
    
    @State private var fogDrift: CGFloat = -20
    
    var body: some View {
        ZStack {
            Color(hex: "#09090D").ignoresSafeArea()
            
            // Atmospheric Ambient Fog Layer
            RadialGradient(
                gradient: Gradient(colors: [
                    Color(hex: "#1C1C28").opacity(0.8),
                    Color(hex: "#12121A").opacity(0.5),
                    Color.clear
                ]),
                center: .center,
                startRadius: 40,
                endRadius: 280
            )
            .blur(radius: 40)
            .offset(x: fogDrift, y: -fogDrift * 0.5)
            .ignoresSafeArea()
            
            VStack(spacing: 36) {
                Spacer()
                
                // Centered Full-Vector Crystalline Aperture
                AperturePulsingView(size: 180, isHydrating: hydrationManager.isDownloading || hydrationManager.progress < 1.0)
                
                // Brand Manifesto Typography
                VStack(spacing: 6) {
                    Text("Dérivée")
                        .font(.system(size: 34, weight: .bold, design: .default))
                        .foregroundColor(.white)
                    
                    Text("Unlearn your commute.")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                }
                
                Spacer()
                
                // Hydration & Network Gate
                VStack(spacing: 16) {
                    if networkStatus == .satisfied {
                        if hydrationManager.isDownloading {
                            VStack(spacing: 10) {
                                ProgressView(value: hydrationManager.progress)
                                    .progressViewStyle(.linear)
                                    .tint(Color(hex: "#FFB300"))
                                    .padding(.horizontal, 48)
                                
                                Text("Hydrating offline cartography & transit grid...")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        } else if let error = hydrationManager.error {
                            VStack(spacing: 12) {
                                Text("Hydration interrupted: \(error.localizedDescription)")
                                    .font(.caption)
                                    .foregroundColor(.red)
                                
                                Button("Retry") {
                                    Task { await startHydration() }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(Color(hex: "#FFB300"))
                            }
                        } else if hydrationManager.progress >= 1.0 {
                            Text("Map Ready")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(Color(hex: "#FFB300"))
                        } else {
                            ProgressView()
                                .tint(Color(hex: "#FFB300"))
                        }
                    } else {
                        Text("Connect to the internet to set up Dérivée")
                            .font(.subheadline)
                            .foregroundColor(Color(hex: "#FFB300"))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }
                .frame(height: 70)
                .padding(.bottom, 48)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 6.0).repeatForever(autoreverses: true)) {
                fogDrift = 20
            }
        }
        .task {
            await monitorNetwork()
        }
        .onChange(of: networkStatus) { oldValue, newValue in
            if newValue == .satisfied && !hydrationManager.isDownloading && hydrationManager.progress < 1.0 {
                Task {
                    await startHydration()
                }
            }
        }
        .onChange(of: hydrationManager.progress) { oldValue, newValue in
            if newValue >= 1.0 {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    trackingEngine.requestPermissions()
                    trackingEngine.startTracking()
                    withAnimation(.easeOut(duration: 0.4)) {
                        isHydrationComplete = true
                    }
                }
            }
        }
    }
    
    private func startHydration() async {
        await hydrationManager.hydrate()
    }
    
    private func monitorNetwork() async {
        let monitor = NWPathMonitor()
        let stream = AsyncStream<NWPath.Status> { continuation in
            monitor.pathUpdateHandler = { path in
                continuation.yield(path.status)
            }
            monitor.start(queue: DispatchQueue.global(qos: .background))
            
            continuation.onTermination = { _ in
                monitor.cancel()
            }
        }
        
        for await status in stream {
            await MainActor.run {
                self.networkStatus = status
            }
        }
    }
}
