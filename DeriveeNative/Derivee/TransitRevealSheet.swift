import SwiftUI

struct TransitRevealSheet: View {
    let stopId: String
    
    @State private var stopDetails: SpatialDatabaseManager.StopDetails?
    @State private var headways: [Double] = []
    @State private var liveArrivals: [SpatialDatabaseManager.ArrivalInfo] = []
    @State private var isLiveActive: Bool = false
    @State private var lastUpdated: Date? = nil
    
    var displayedArrivals: [SpatialDatabaseManager.ArrivalInfo] {
        if !liveArrivals.isEmpty {
            return liveArrivals
        }
        return stopDetails?.arrivals ?? []
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Header: Line Badge + Station Name
            if let details = stopDetails {
                let routeInfo = TransitRouteData.lineInfo(for: details.routeId)
                let isBus = details.routeType == 3
                
                HStack(alignment: .center, spacing: 12) {
                    if isBus {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(hex: "#00A1DE"))
                            .frame(width: 42, height: 38)
                            .overlay(
                                Image(systemName: "bus.fill")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(.white)
                            )
                    } else {
                        Circle()
                            .fill(routeInfo.color)
                            .frame(width: 38, height: 38)
                            .overlay(
                                Text(routeInfo.name)
                                    .font(.system(size: 18, weight: .bold, design: .rounded))
                                    .foregroundColor(Color(hex: routeInfo.textColorHex))
                            )
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(details.name)
                            .font(.title2)
                            .bold()
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        Text(isBus ? "MTA Bus Stop" : "MTA Subway Station")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
                .padding(.top, 8)
                
                Divider()
                
                // Real-time Arrivals List
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("NEXT ARRIVALS")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        if isLiveActive {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color(hex: "#FFB300"))
                                    .frame(width: 6, height: 6)
                                Text("LIVE")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundColor(Color(hex: "#FFB300"))
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(hex: "#FFB300").opacity(0.12))
                            .clipShape(Capsule())
                        }
                    }
                    
                    if displayedArrivals.isEmpty {
                        Text("No scheduled arrivals in the next 30 minutes")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.vertical, 6)
                    } else {
                        ForEach(displayedArrivals) { arrival in
                            HStack(alignment: .center, spacing: 10) {
                                let arrivalInfo = TransitRouteData.lineInfo(for: arrival.line)
                                
                                if arrival.line.hasPrefix("M") || arrival.line.hasPrefix("B") || arrival.line.hasPrefix("Q") || arrival.line.hasPrefix("Bx") || arrival.line.hasPrefix("S") {
                                    Text(arrival.line)
                                        .font(.system(size: 11, weight: .bold, design: .rounded))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(Color(hex: "#00A1DE").opacity(0.15))
                                        .foregroundColor(Color(hex: "#00A1DE"))
                                        .clipShape(Capsule())
                                } else {
                                    Circle()
                                        .fill(arrivalInfo.color)
                                        .frame(width: 22, height: 22)
                                        .overlay(
                                            Text(arrivalInfo.name)
                                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                                .foregroundColor(Color(hex: arrivalInfo.textColorHex))
                                        )
                                }
                                
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(arrival.destination)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                    
                                    if let dir = arrival.direction ?? arrival.distanceDescription {
                                        Text(dir)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                
                                Spacer()
                                
                                HStack(spacing: 3) {
                                    Text("\(arrival.minutes)")
                                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                                        .foregroundColor(Color(hex: "#FFB300"))
                                    Text("min")
                                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }
                
                Divider()
                
                // Historical Reliability Sparkline
                TransitSparklineView(headways: headways, title: "7-Day Headway Reliability (min)", tintColor: isBus ? Color(hex: "#00A1DE") : routeInfo.color)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 180)
            }
            
            Spacer()
        }
        .padding(20)
        .task(id: stopId) {
            await startPollingLifecycle()
        }
    }
    
    @MainActor
    private func startPollingLifecycle() async {
        // 1. Initial base load from local SQLite
        let details = try? await SpatialDatabaseManager.shared.fetchStopDetails(for: stopId)
        let hw = try? await SpatialDatabaseManager.shared.fetchHeadwayData(for: stopId)
        
        self.stopDetails = details
        if let hw = hw {
            self.headways = hw
        }
        
        guard let routeId = details?.routeId else { return }
        
        // 2. Sheet-Scoped Polling Loop (15s cadence, cancelled on dismiss)
        while !Task.isCancelled {
            do {
                let live = try await TransitRealtimeService.shared.fetchLiveArrivals(for: stopId, routeId: routeId)
                if !Task.isCancelled {
                    if !live.isEmpty {
                        self.liveArrivals = live
                    }
                    self.isLiveActive = true
                    self.lastUpdated = Date()
                }
            } catch {
                if !Task.isCancelled {
                    self.isLiveActive = false
                }
            }
            
            do {
                try await Task.sleep(nanoseconds: 15_000_000_000)
            } catch {
                break
            }
        }
    }
}

#Preview {
    TransitRevealSheet(stopId: "stop_columbus")
}

