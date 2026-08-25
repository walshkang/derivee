import SwiftUI

public struct TransitAttributionsView: View {
    @Environment(\.colorScheme) private var colorScheme
    private let attributionsByAgency: [String: [String]]
    
    public init(attributionsByAgency: [String: [String]]? = nil) {
        if let custom = attributionsByAgency {
            self.attributionsByAgency = custom
        } else {
            self.attributionsByAgency = CityPackManager.shared.allInstalledAttributions()
        }
    }
    
    public var body: some View {
        List {
            Section(
                header: Text("Transit Agencies"),
                footer: Text("Timetable data, line shapes, and real-time feeds are parsed directly from official GTFS and GTFS-RT APIs.")
            ) {
                if attributionsByAgency.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Metropolitan Transportation Authority")
                            .font(.headline)
                        Text("• MTA New York City Transit\n• Port Authority of NY & NJ\n• NYC Ferry by Hornblower")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                } else {
                    ForEach(attributionsByAgency.keys.sorted(), id: \.self) { agency in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(agency)
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            if let citations = attributionsByAgency[agency] {
                                ForEach(citations, id: \.self) { citation in
                                    Text("• \(citation)")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            
            Section(
                header: Text("Base Mapping & Spatial Data"),
                footer: Text("Map vector rendering provided by MapLibre Native. Hexagonal spatial partitioning powered by Uber H3.")
            ) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("OpenStreetMap")
                        .font(.headline)
                    Text("© OpenStreetMap contributors, licensed under the Open Database License (ODbL).")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("MapLibre Native")
                        .font(.headline)
                    Text("Vector tile rendering engine licensed under BSD 2-Clause.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Uber H3")
                        .font(.headline)
                    Text("Discrete global grid system licensed under Apache 2.0.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Open Data & Attributions")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        TransitAttributionsView(attributionsByAgency: [
            "Metropolitan Transportation Authority": [
                "MTA New York City Transit",
                "Port Authority of NY & NJ",
                "NYC Ferry by Hornblower"
            ],
            "Massachusetts Bay Transportation Authority": [
                "MBTA Subway, Bus & Commuter Rail",
                "MassDOT Ferry Operations"
            ]
        ])
    }
}
