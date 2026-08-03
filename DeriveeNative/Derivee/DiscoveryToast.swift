import SwiftUI

struct DiscoveryToast: View {
    let stationName: String
    var onDismiss: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .foregroundColor(.yellow)
                .font(.title3)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("New Transit POI Discovered")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                
                Text(stationName)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
            
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 5)
        .padding(.horizontal, 24)
        .gesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    if value.translation.height < -20 {
                        withAnimation {
                            onDismiss()
                        }
                    }
                }
        )
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack {
            DiscoveryToast(stationName: "Bedford Ave") {
                print("Dismissed")
            }
            Spacer()
        }
        .padding(.top, 50)
    }
}
