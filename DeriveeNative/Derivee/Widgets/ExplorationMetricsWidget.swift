import WidgetKit
import SwiftUI

// MARK: - Timeline Entry & Provider

public struct ExplorationWidgetEntry: TimelineEntry {
    public let date: Date
    public let status: AmbientTrackingStatus
    
    public init(date: Date, status: AmbientTrackingStatus) {
        self.date = date
        self.status = status
    }
}

public struct ExplorationTimelineProvider: TimelineProvider {
    public init() {}
    
    public static var defaultPlaceholder: ExplorationWidgetEntry {
        ExplorationWidgetEntry(
            date: Date(),
            status: AmbientTrackingStatus(
                isEnabled: true,
                isActive: true,
                sessionHexCount: 12,
                sessionDistanceMeters: 1450.0,
                activeNeighborhood: "SoHo",
                lastUpdated: Date()
            )
        )
    }
    
    public func placeholder(in context: Context) -> ExplorationWidgetEntry {
        Self.defaultPlaceholder
    }
    
    public func createSnapshot() -> ExplorationWidgetEntry {
        let status = AmbientTrackingIPCService.shared.currentStatus()
        return ExplorationWidgetEntry(date: Date(), status: status)
    }
    
    public func createTimeline() -> Timeline<ExplorationWidgetEntry> {
        let entry = createSnapshot()
        return Timeline(entries: [entry], policy: .never)
    }
    
    public func getSnapshot(in context: Context, completion: @escaping (ExplorationWidgetEntry) -> Void) {
        completion(createSnapshot())
    }
    
    public func getTimeline(in context: Context, completion: @escaping (Timeline<ExplorationWidgetEntry>) -> Void) {
        completion(createTimeline())
    }
}

// MARK: - Widget View

public struct ExplorationWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    public let entry: ExplorationWidgetEntry
    
    public init(entry: ExplorationWidgetEntry) {
        self.entry = entry
    }
    
    public var body: some View {
        switch family {
        case .accessoryInline:
            inlineAccessoryView
                .containerBackground(.clear, for: .widget)
        case .accessoryCircular:
            circularAccessoryView
                .containerBackground(.clear, for: .widget)
        case .accessoryRectangular:
            rectangularAccessoryView
                .containerBackground(.clear, for: .widget)
        case .systemMedium:
            mediumSystemView
                .containerBackground(Color.midnightSlate, for: .widget)
        default:
            smallSystemView
                .containerBackground(Color.midnightSlate, for: .widget)
        }
    }
    
    // MARK: - Accessory Views (Lock Screen)
    
    private var inlineAccessoryView: some View {
        ViewThatFits {
            if entry.status.isActive {
                if let nbhd = entry.status.activeNeighborhood, !nbhd.isEmpty {
                    Label("\(entry.status.sessionHexCount) hexes in \(nbhd)", systemImage: "location.fill")
                } else {
                    Label("\(entry.status.sessionHexCount) hexes cleared", systemImage: "location.fill")
                }
            } else {
                Label("Derivee Paused", systemImage: "location.slash")
            }
        }
    }
    
    private var circularAccessoryView: some View {
        ZStack {
            ApertureShape()
                .stroke(entry.status.isActive ? Color.electricAmber : Color.secondary.opacity(0.6), lineWidth: 1.5)
            
            VStack(spacing: 0) {
                Text("\(entry.status.sessionHexCount)")
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundColor(entry.status.isActive ? .primary : .secondary)
                
                Text("HEX")
                    .font(.system(size: 8, weight: .bold, design: .default))
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var rectangularAccessoryView: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                ApertureMicroGlyph(size: 12, strokeWidth: 1.0)
                Text("DERIVEE")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                HStack(spacing: 3) {
                    Circle()
                        .fill(entry.status.isActive ? Color.electricAmber : Color.secondary)
                        .frame(width: 5, height: 5)
                    Text(entry.status.isActive ? "ACTIVE" : "PAUSED")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(entry.status.isActive ? Color.electricAmber : Color.secondary)
                }
            }
            
            Text("\(entry.status.sessionHexCount) hexes cleared")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(.primary)
                .lineLimit(1)
            
            HStack(spacing: 4) {
                if let nbhd = entry.status.activeNeighborhood, !nbhd.isEmpty {
                    Text(nbhd)
                        .lineLimit(1)
                    Text("•")
                }
                Text(formatDistance(entry.status.sessionDistanceMeters))
            }
            .font(.system(size: 10, weight: .medium, design: .default))
            .foregroundColor(.secondary)
        }
    }
    
    // MARK: - System Views (Home Screen)
    
    private var smallSystemView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                ApertureMicroGlyph(size: 24, strokeWidth: 1.5)
                Spacer()
                Text(entry.status.isActive ? "ACTIVE" : "PAUSED")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(entry.status.isActive ? Color.electricAmber.opacity(0.18) : Color.white.opacity(0.1))
                    .foregroundColor(entry.status.isActive ? Color.electricAmber : .secondary)
                    .clipShape(Capsule())
            }
            
            Spacer()
            
            Text("\(entry.status.sessionHexCount)")
                .font(.system(size: 32, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
            
            Text("hexes uncovered")
                .font(.system(size: 11, weight: .medium, design: .default))
                .foregroundColor(.white.opacity(0.7))
            
            HStack(spacing: 4) {
                if let nbhd = entry.status.activeNeighborhood, !nbhd.isEmpty {
                    Text(nbhd)
                        .lineLimit(1)
                    Text("•")
                }
                Text(formatDistance(entry.status.sessionDistanceMeters))
            }
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundColor(Color.electricAmber)
        }
        .padding(4)
    }
    
    private var mediumSystemView: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    ApertureMicroGlyph(size: 20, strokeWidth: 1.4)
                    Text("DERIVEE")
                        .font(.system(size: 12, weight: .heavy, design: .monospaced))
                        .foregroundColor(.white.opacity(0.85))
                }
                
                Spacer()
                
                Text("\(entry.status.sessionHexCount)")
                    .font(.system(size: 34, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                
                Text("hexes uncovered")
                    .font(.system(size: 12, weight: .medium, design: .default))
                    .foregroundColor(.white.opacity(0.7))
            }
            
            Divider()
                .background(Color.white.opacity(0.2))
            
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(entry.status.isActive ? Color.electricAmber : Color.secondary)
                        .frame(width: 7, height: 7)
                    Text(entry.status.isActive ? "Drift Active" : "Exploration Paused")
                        .font(.system(size: 12, weight: .semibold, design: .default))
                        .foregroundColor(entry.status.isActive ? Color.electricAmber : .secondary)
                }
                
                if let nbhd = entry.status.activeNeighborhood, !nbhd.isEmpty {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("NEIGHBORHOOD")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.5))
                        Text(nbhd)
                            .font(.system(size: 13, weight: .semibold, design: .default))
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }
                }
                
                VStack(alignment: .leading, spacing: 1) {
                    Text("DISTANCE")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                    Text(formatDistance(entry.status.sessionDistanceMeters))
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(4)
    }
    
    private func formatDistance(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.1f km", meters / 1000.0)
        } else {
            return "\(Int(meters)) m"
        }
    }
}

// MARK: - Widget Configuration

public struct ExplorationMetricsWidget: Widget {
    public static let kind: String = "com.derivee.ExplorationMetricsWidget"
    
    public init() {}
    
    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: ExplorationTimelineProvider()) { entry in
            ExplorationWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Exploration Metrics")
        .description("Track uncovered hexes and active neighborhood progression in real time.")
        .supportedFamilies([
            .accessoryInline,
            .accessoryCircular,
            .accessoryRectangular,
            .systemSmall,
            .systemMedium
        ])
    }
}
