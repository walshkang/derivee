import SwiftUI

struct TransitRevealSheet: View {
    let stopId: String
    
    @State private var stopDetails: SpatialDatabaseManager.StopDetails?
    @State private var headways: [Double] = []
    
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Header: Line Badge + Station Name
            if let details = stopDetails {
                HStack(alignment: .center, spacing: 12) {
                    let info = TransitRouteData.lineInfo(for: details.routeId)
                    
                    Circle()
                        .fill(info.color)
                        .frame(width: 38, height: 38)
                        .overlay(
                            Text(info.name)
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundColor(Color(hex: info.textColorHex))
                        )
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(details.name)
                            .font(.title2)
                            .bold()
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        Text(details.routeType == 3 ? "Bus Stop" : "Subway Station")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
                .padding(.top, 8)
                
                Divider()
                
                // Real-time Arrivals List
                VStack(alignment: .leading, spacing: 10) {
                    Text("NEXT ARRIVALS")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                    
                    ForEach(details.arrivals) { arrival in
                        HStack {
                            let arrivalInfo = TransitRouteData.lineInfo(for: arrival.line)
                            
                            Circle()
                                .fill(arrivalInfo.color)
                                .frame(width: 22, height: 22)
                                .overlay(
                                    Text(arrivalInfo.name)
                                        .font(.system(size: 11, weight: .bold, design: .rounded))
                                        .foregroundColor(Color(hex: arrivalInfo.textColorHex))
                                )
                            
                            Text(arrival.destination)
                                .font(.subheadline)
                                .foregroundColor(.primary)
                            
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
                        .padding(.vertical, 4)
                    }
                }
                
                Divider()
                
                // Historical Reliability Sparkline
                TransitSparklineView(headways: headways, title: "7-Day Headway Reliability (min)")
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 180)
            }
            
            Spacer()
        }
        .padding(20)
        .onAppear {
            loadData()
        }
    }
    
    private func loadData() {
        let details = SpatialDatabaseManager.shared.fetchStopDetails(for: stopId)
        let hw = SpatialDatabaseManager.shared.fetchHeadwayData(for: stopId)
        
        self.stopDetails = details
        self.headways = hw
    }
}

#Preview {
    TransitRevealSheet(stopId: "stop_columbus")
}
