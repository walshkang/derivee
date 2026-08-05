import SwiftUI

struct PhilosophyView: View {
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Dérivée")
                        .font(.system(.largeTitle, design: .default))
                        .fontWeight(.heavy)
                    
                    Text("Unlearn your commute.")
                        .font(.system(.title3, design: .default))
                        .fontWeight(.semibold)
                        .foregroundColor(Color(hex: "FFB300"))
                }
                .padding(.bottom, 8)
                
                Text("**Dérivée** — a double-entendre combining the mathematical derivative (the rate of change at a specific point on a curve) with the Situationist *dérive* (an unplanned drift through an urban landscape). This app is literally the intersection: **calculating the rate of change of your physical presence across the city map.**")
                    .font(.body)
                    .lineSpacing(6)
                
                Text("An ambient, offline-first application that transforms your daily commute and neighborhood walks into a quiet journey of discovery. It rejects the aggressive completionism of traditional mapping games.")
                    .font(.body)
                    .lineSpacing(6)
                
                Text("Instead, it offers a calm, translucent environment — a harness for real life — that teases discovery through a volumetric fog-of-war and provides commuter-grade transit data *only* when you explicitly ask for it.")
                    .font(.body)
                    .lineSpacing(6)
                
                Text("The map gets out of your way. Points of interest and transit nodes do not permanently clutter the map with pins. Once an area is cleared, they become invisible. They are only revealed if you are physically standing in that hex and tap to pull up a minimalist data sheet.")
                    .font(.body)
                    .lineSpacing(6)
            }
            .padding(24)
        }
        .navigationTitle("The Philosophy")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(UIColor.systemGroupedBackground))
    }
}

#Preview {
    NavigationView {
        PhilosophyView()
    }
}
