import SwiftUI

/// Download state machine for the city pack installer.
public enum CityDownloadState: Equatable, Sendable {
    case idle
    case downloading(progress: Double, receivedBytes: Int64, totalBytes: Int64)
    case extracting
    case completed
    case failed(error: String)
}

/// Non-blocking bottom sheet prompting the user to download a newly detected city pack.
public struct CityDownloadPromptSheet: View {
    public let city: CityManifestEntry
    public var onDownloadComplete: ((CityManifestEntry) -> Void)? = nil
    public var onDismiss: (() -> Void)? = nil
    public var onSnooze: ((CityManifestEntry) -> Void)? = nil
    
    // Injectable download handler for realistic or mock downloads
    public var downloadHandler: ((CityManifestEntry, @escaping @Sendable (Double, Int64, Int64) -> Void) async throws -> Void)? = nil
    
    @State private var downloadState: CityDownloadState = .idle
    @Environment(\.dismiss) private var dismiss
    
    public init(
        city: CityManifestEntry,
        onDownloadComplete: ((CityManifestEntry) -> Void)? = nil,
        onDismiss: (() -> Void)? = nil,
        onSnooze: ((CityManifestEntry) -> Void)? = nil,
        downloadHandler: ((CityManifestEntry, @escaping @Sendable (Double, Int64, Int64) -> Void) async throws -> Void)? = nil
    ) {
        self.city = city
        self.onDownloadComplete = onDownloadComplete
        self.onDismiss = onDismiss
        self.onSnooze = onSnooze
        self.downloadHandler = downloadHandler
    }
    
    public var body: some View {
        VStack(spacing: 20) {
            // Header Section
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color(hex: "#FFB300").opacity(0.15))
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: "map.circle.fill")
                        .font(.system(size: 26))
                        .foregroundColor(Color(hex: "#FFB300"))
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    Text("Exploring \(city.displayName)?")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    Text(city.region)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(.top, 6)
            
            // Description Body
            Text("Download transit routes, stations, and offline timetable data (≈\(city.formattedDownloadSize)). Zero network needed once installed.")
                .font(.body)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)
            
            // Dynamic State View
            switch downloadState {
            case .idle:
                HStack(spacing: 12) {
                    Button(action: handleNotNow) {
                        Text("Not Now")
                            .font(.headline)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    
                    Button(action: startDownload) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.down.circle.fill")
                            Text("Download Now")
                        }
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color(hex: "#FFB300"))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .shadow(color: Color(hex: "#FFB300").opacity(0.3), radius: 6, x: 0, y: 3)
                    }
                }
                
            case .downloading(let progress, let receivedBytes, let totalBytes):
                VStack(spacing: 10) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color(.systemGray5))
                                .frame(height: 10)
                            
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color(hex: "#FFB300"))
                                .frame(width: max(geo.size.width * CGFloat(progress), 8), height: 10)
                                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: progress)
                        }
                    }
                    .frame(height: 10)
                    
                    HStack {
                        Text("\(CityManifest.formatBytes(receivedBytes)) of \(CityManifest.formatBytes(totalBytes))")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text("\(Int(progress * 100))%")
                            .font(.system(.caption, design: .monospaced))
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                    }
                }
                .padding(.vertical, 4)
                
            case .extracting:
                HStack(spacing: 12) {
                    ProgressView()
                        .tint(Color(hex: "#FFB300"))
                    Text("Unpacking city assets...")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                
            case .completed:
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.title3)
                    Text("Ready! City pack installed.")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                
            case .failed(let error):
                VStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .lineLimit(2)
                    }
                    
                    HStack(spacing: 12) {
                        Button("Dismiss", action: { dismiss() })
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Button("Retry", action: startDownload)
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(Color(hex: "#FFB300"))
                    }
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 28)
        .background(.ultraThinMaterial)
    }
    
    private func handleNotNow() {
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
        onSnooze?(city)
        onDismiss?()
        dismiss()
    }
    
    private func startDownload() {
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()
        
        let total = city.compressedSizeBytes > 0 ? city.compressedSizeBytes : 9_400_000
        downloadState = .downloading(progress: 0.05, receivedBytes: Int64(Double(total) * 0.05), totalBytes: total)
        
        Task {
            if let customHandler = downloadHandler {
                do {
                    try await customHandler(city) { progress, received, total in
                        Task { @MainActor in
                            self.downloadState = .downloading(progress: progress, receivedBytes: received, totalBytes: total)
                        }
                    }
                    await finishInstallation()
                } catch {
                    await MainActor.run {
                        self.downloadState = .failed(error: error.localizedDescription)
                    }
                }
            } else {
                // Default animated download simulation for demo / first pass
                await runSimulatedDownload(totalBytes: total)
            }
        }
    }
    
    private func runSimulatedDownload(totalBytes: Int64) async {
        let steps = 10
        for i in 1...steps {
            let progress = Double(i) / Double(steps)
            let received = Int64(Double(totalBytes) * progress)
            try? await Task.sleep(nanoseconds: 120_000_000)
            await MainActor.run {
                self.downloadState = .downloading(progress: progress, receivedBytes: received, totalBytes: totalBytes)
            }
        }
        
        await MainActor.run {
            self.downloadState = .extracting
        }
        
        try? await Task.sleep(nanoseconds: 300_000_000)
        await finishInstallation()
    }
    
    private func finishInstallation() async {
        await MainActor.run {
            let success = UINotificationFeedbackGenerator()
            success.notificationOccurred(.success)
            self.downloadState = .completed
        }
        
        try? await Task.sleep(nanoseconds: 800_000_000)
        await MainActor.run {
            self.onDownloadComplete?(self.city)
            self.dismiss()
        }
    }
}

#Preview {
    CityDownloadPromptSheet(
        city: CityManifest.defaultManifest.cities[1]
    )
}
