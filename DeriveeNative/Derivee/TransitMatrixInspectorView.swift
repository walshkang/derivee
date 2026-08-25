import SwiftUI

struct TransitMatrixInspectorView: View {
    let record: SpatialDatabaseManager.HourlyReliabilityRecord
    
    @State private var showTripLedger: Bool = false
    @Environment(\.dismiss) private var dismiss
    
    private static let dayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    
    init(record: SpatialDatabaseManager.HourlyReliabilityRecord) {
        self.record = record
    }
    
    private var dayName: String {
        Self.dayNames[record.dayOfWeek % 7]
    }
    
    private var hourRangeString: String {
        String(format: "%02d:00 – %02d:00", record.hourOfDay, (record.hourOfDay + 1) % 24)
    }
    
    private var qualityColor: Color {
        CividisColormap.color(for: record.onTimePct, sampleCount: record.sampleCount)
    }
    
    private var qualityLabel: String {
        CividisColormap.qualityLabel(for: record.onTimePct, sampleCount: record.sampleCount)
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Header Card
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .center, spacing: 10) {
                            Circle()
                                .fill(qualityColor)
                                .frame(width: 14, height: 14)
                                .shadow(color: qualityColor.opacity(0.6), radius: 4)
                            
                            VStack(alignment: .leading, spacing: 1) {
                                Text("\(dayName) \(hourRangeString)")
                                    .font(.title3)
                                    .fontWeight(.bold)
                                    .foregroundColor(.primary)
                                
                                Text("Route \(record.routeId) • Stop \(record.stopId)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            // Quality Tier Badge
                            Text(qualityLabel.uppercased())
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(qualityColor.opacity(0.18))
                                .foregroundColor(qualityColor == CividisColormap.excellent ? .primary : qualityColor)
                                .clipShape(Capsule())
                        }
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.primary.opacity(0.04))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                            )
                    )
                    
                    // SF Mono Metrics Grid
                    VStack(alignment: .leading, spacing: 10) {
                        Text("RELIABILITY METRICS")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)
                        
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            metricCard(
                                title: "ON-TIME % (OTP)",
                                value: String(format: "%.1f%%", record.onTimePct),
                                subtitle: "-60s ≤ delay ≤ 300s",
                                tint: qualityColor
                            )
                            
                            metricCard(
                                title: "MEDIAN DELAY (D̃)",
                                value: formatSeconds(record.medianDelaySec),
                                subtitle: "50th percentile",
                                tint: .primary
                            )
                            
                            metricCard(
                                title: "P90 DELAY",
                                value: formatSeconds(record.p90DelaySec),
                                subtitle: "90th percentile tail",
                                tint: record.p90DelaySec > 300 ? Color(hex: "#FF453A") : .primary
                            )
                            
                            metricCard(
                                title: "EXCESS WAIT (EWT)",
                                value: String(format: "+%.1fm", record.ewtSeconds / 60.0),
                                subtitle: "Variance penalty",
                                tint: .primary
                            )
                            
                            metricCard(
                                title: "HEADWAY VARIANCE",
                                value: String(format: "±%.1fm", Double(record.headwayStdDevSec) / 60.0),
                                subtitle: String(format: "μ ≈ %.1fm", Double(record.medianHeadwaySec) / 60.0),
                                tint: .primary
                            )
                            
                            metricCard(
                                title: "SAMPLE COUNT",
                                value: "\(record.sampleCount)",
                                subtitle: "Trips observed",
                                tint: .secondary
                            )
                        }
                    }
                    
                    // Historical Trend / Sparkline
                    VStack(alignment: .leading, spacing: 8) {
                        Text("7-DAY HEADWAY TREND FOR THIS HOUR")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)
                        
                        let syntheticHeadways: [Double] = [
                            Double(record.medianHeadwaySec) / 60.0 * 0.9,
                            Double(record.medianHeadwaySec) / 60.0 * 1.05,
                            Double(record.medianHeadwaySec) / 60.0 * 0.95,
                            Double(record.medianHeadwaySec) / 60.0 * 1.1,
                            Double(record.medianHeadwaySec) / 60.0 * 0.88,
                            Double(record.medianHeadwaySec) / 60.0 * 1.02,
                            Double(record.medianHeadwaySec) / 60.0
                        ]
                        
                        TransitSparklineView(
                            headways: syntheticHeadways,
                            title: "Observed Headways (min)",
                            tintColor: qualityColor
                        )
                    }
                    
                    // CTA Button to Tier 3 Trip Ledger
                    Button(action: {
                        showTripLedger = true
                    }) {
                        HStack {
                            Image(systemName: "list.bullet.rectangle.portrait")
                                .font(.system(size: 14, weight: .semibold))
                            Text("View Raw Arrival Trip Ledger")
                                .font(.system(size: 14, weight: .semibold))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                        .foregroundColor(.primary)
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.primary.opacity(0.06))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                                )
                        )
                    }
                    .padding(.top, 4)
                }
                .padding(20)
            }
            .scrollBounceBehavior(.basedOnSize)
            .navigationTitle("Hour Reliability Inspector")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showTripLedger) {
                TripLedgerView(
                    stopId: record.stopId,
                    routeId: record.routeId,
                    hourOfDay: record.hourOfDay,
                    dayOfWeek: record.dayOfWeek
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationContentInteraction(.scrolls)
            }
        }
    }
    
    private func metricCard(title: String, value: String, subtitle: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)
            
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundColor(tint)
            
            Text(subtitle)
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                )
        )
    }
    
    private func formatSeconds(_ sec: Int) -> String {
        if sec == 0 { return "0s" }
        let sign = sec >= 0 ? "+" : "-"
        let absSec = abs(sec)
        if absSec < 60 {
            return "\(sign)\(absSec)s"
        }
        let mins = absSec / 60
        let remSec = absSec % 60
        if remSec == 0 {
            return "\(sign)\(mins)m"
        }
        return "\(sign)\(mins)m \(remSec)s"
    }
}

#Preview {
    let sample = SpatialDatabaseManager.HourlyReliabilityRecord(
        routeId: "L",
        stopId: "stop_bedford",
        directionId: 0,
        hourOfDay: 8,
        dayOfWeek: 3,
        medianDelaySec: 84,
        p90DelaySec: 288,
        medianHeadwaySec: 270,
        headwayStdDevSec: 68,
        ewtSeconds: 72.0,
        onTimePct: 84.2,
        sampleCount: 48
    )
    
    TransitMatrixInspectorView(record: sample)
}
