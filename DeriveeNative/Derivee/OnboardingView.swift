import SwiftUI
import Network

struct OnboardingView: View {
    @ObservedObject var trackingEngine: AmbientTrackingEngine
    @State private var hydrationManager = HydrationManager()
    @State private var networkStatus: NWPath.Status = .requiresConnection
    @Binding var isHydrationComplete: Bool
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            Circle()
                .fill(Color.gray.opacity(0.3))
                .blur(radius: 50)
                .scaleEffect(hydrationManager.isDownloading ? 1.2 : 1.0)
                .animation(.easeInOut(duration: 2).repeatForever(), value: hydrationManager.isDownloading)
            
            VStack(spacing: 30) {
                Text("Dérivée")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                if networkStatus == .satisfied {
                    if hydrationManager.isDownloading {
                        ProgressView(value: hydrationManager.progress)
                            .progressViewStyle(.linear)
                            .tint(.white)
                            .padding(.horizontal, 40)
                        
                        Text("Downloading initial data...")
                            .foregroundColor(.white.opacity(0.8))
                    } else if let error = hydrationManager.error {
                        Text("Failed: \(error.localizedDescription)")
                            .foregroundColor(.red)
                        
                        Button("Retry") {
                            Task { await startHydration() }
                        }
                        .buttonStyle(.borderedProminent)
                    } else if hydrationManager.progress >= 1.0 {
                        Button("Start Exploring") {
                            trackingEngine.requestPermissions()
                            trackingEngine.startTracking()
                            withAnimation {
                                isHydrationComplete = true
                            }
                        }
                        .font(.headline)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.white)
                        .foregroundColor(.black)
                        .cornerRadius(24)
                    } else {
                        ProgressView()
                            .tint(.white)
                    }
                } else {
                    Text("Connect to the internet to set up Dérivée")
                        .foregroundColor(.orange)
                        .multilineTextAlignment(.center)
                        .padding()
                }
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
