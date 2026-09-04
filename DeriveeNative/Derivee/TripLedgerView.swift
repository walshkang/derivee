import SwiftUI

struct TripLedgerView: View {
    let stopId: String
    let routeId: String
    let hourOfDay: Int
    let dayOfWeek: Int
    
    @State private var events: [SpatialDatabaseManager.StopEventRecord] = []
    @State private var isLoading: Bool = true
    @Environment(\.dismiss) private var dismiss
    
    private static let dayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    
    init(stopId: String, routeId: String, hourOfDay: Int, dayOfWeek: Int) {
        self.stopId = stopId
        self.routeId = routeId
        self.hourOfDay = hourOfDay
        self.dayOfWeek = dayOfWeek
    }
    
    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        formatter.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return formatter
    }
    
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                // Summary Bar
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(Self.dayNames[dayOfWeek % 7]) \(String(format: "%02d:00 – %02d:00", hourOfDay, (hourOfDay + 1) % 24))")
                            .font(.headline)
                            .foregroundColor(.primary)
                        Text("Stop ID: \(stopId) • Route \(routeId)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if !isLoading {
                        Text("\(events.count) TRIPS")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.primary.opacity(0.06))
                            .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                
                Divider()
                    .padding(.horizontal, 20)
                
                if isLoading {
                    Spacer()
                    ProgressView("Loading Trip Ledger...")
                        .frame(maxWidth: .infinity)
                    Spacer()
                } else if events.isEmpty {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "clock.badge.questionmark")
                            .font(.system(size: 36))
                            .foregroundColor(.secondary)
                        Text("No Trip Events Recorded")
                            .font(.headline)
                            .foregroundColor(.primary)
                        Text("No individual vehicle arrivals were observed during this operating hour.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .frame(maxWidth: .infinity)
                    Spacer()
                } else {
                    List {
                        ForEach(events) { event in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(alignment: .center) {
                                    // Actual arrival time
                                    Text(timeFormatter.string(from: event.actualTime))
                                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                                        .foregroundColor(.primary)
                                    
                                    if let sched = event.scheduledTime {
                                        Text("Sched: \(timeFormatter.string(from: sched))")
                                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    // Delay delta tag
                                    let delaySec = event.delaySeconds
                                    if delaySec <= 0 {
                                        Text(delaySec == 0 ? "ON TIME" : "\(abs(delaySec))s EARLY")
                                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                                            .foregroundColor(Color(hex: "#D4C84A"))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color(hex: "#D4C84A").opacity(0.15))
                                            .clipShape(RoundedRectangle(cornerRadius: 4))
                                    } else if delaySec <= 180 {
                                        Text(String(format: "+%dm %02ds", delaySec / 60, delaySec % 60))
                                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                                            .foregroundColor(Color(hex: "#FFB300"))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color(hex: "#FFB300").opacity(0.15))
                                            .clipShape(RoundedRectangle(cornerRadius: 4))
                                    } else {
                                        Text(String(format: "+%dm %02ds", delaySec / 60, delaySec % 60))
                                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                                            .foregroundColor(Color(hex: "#FF453A"))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color(hex: "#FF453A").opacity(0.15))
                                            .clipShape(RoundedRectangle(cornerRadius: 4))
                                    }
                                }
                                
                                HStack(spacing: 8) {
                                    Text(event.tripId)
                                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                                        .foregroundColor(.secondary)
                                    
                                    Text("•")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary.opacity(0.5))
                                    
                                    Text(event.directionId == 0 ? "Direction 0 (North/East)" : "Direction 1 (South/West)")
                                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .scrollBounceBehavior(.basedOnSize)
                }
            }
            .navigationTitle("Arrival Trip Ledger")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .task {
                do {
                    let loaded = try await SpatialDatabaseManager.shared.fetchStopEvents(
                        for: stopId,
                        hourOfDay: hourOfDay,
                        dayOfWeek: dayOfWeek
                    )
                    self.events = loaded
                    self.isLoading = false
                } catch {
                    self.isLoading = false
                }
            }
        }
    }
}

#Preview {
    TripLedgerView(stopId: "stop_bedford", routeId: "L", hourOfDay: 8, dayOfWeek: 3)
}
