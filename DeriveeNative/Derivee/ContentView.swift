import SwiftUI
import H3

struct ContentView: View {
    @State private var h3IndexResult: String = "Waiting for H3..."

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Derivee Native")
                .font(.title)
            
            Text(h3IndexResult)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .onAppear {
            testH3Interop()
        }
    }
    
    private func testH3Interop() {
        // Simple verification test as requested in Phase 1.1
        let lat = 37.7759
        let lon = -122.4179
        let resolution = 11
        
        do {
            let index = try H3.latLngToCell(latitude: lat, longitude: lon, resolution: resolution)
            let indexString = String(index, radix: 16)
            print("Successfully converted coordinate to H3 Index: \(indexString)")
            h3IndexResult = "H3 Index: \(indexString)"
        } catch {
            print("H3 Conversion failed: \(error)")
            h3IndexResult = "H3 Error: \(error.localizedDescription)"
        }
    }
}

#Preview {
    ContentView()
}
