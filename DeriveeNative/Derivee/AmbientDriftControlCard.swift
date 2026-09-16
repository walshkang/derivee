import SwiftUI
import CoreLocation

/// Crystalline quick-control sheet for Screen 1 (Wave PE.6 / design.md § 11 & DERIVEE_INVARIANTS.md).
/// Provides direct 0.0s agency over Ambient Drift (background GPS), Dynamic Island Live Activity,
/// and glanceable CoreLocation authorization status with inline permission escalation.
struct AmbientDriftControlCard: View {
    @ObservedObject var trackingEngine: AmbientTrackingEngine
    @Environment(\.dismiss) private var dismiss
    
    init(trackingEngine: AmbientTrackingEngine) {
        self.trackingEngine = trackingEngine
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color(hex: "#FFB300").opacity(0.15))
                        .frame(width: 38, height: 38)
                    
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(Color(hex: "#FFB300"))
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Location & Drift")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    
                    Text("Direct Commuter Agency")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: {
                    let impact = UIImpactFeedbackGenerator(style: .light)
                    impact.impactOccurred()
                    dismiss()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.secondary.opacity(0.5))
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel("Dismiss controls")
            }
            .padding(.top, 2)
            
            // Section 1 & 2: Direct Interactive Switches
            VStack(spacing: 12) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Ambient Drift")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundColor(.primary)
                        
                        Text(trackingEngine.isTracking ? "Active • Background GPS" : "Paused • Battery Preserved")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(trackingEngine.isTracking ? Color(hex: "#FFB300") : .secondary)
                    }
                    
                    Spacer()
                    
                    Toggle("", isOn: Binding(
                        get: { trackingEngine.isTracking },
                        set: { newValue in
                            let impact = UIImpactFeedbackGenerator(style: .light)
                            impact.impactOccurred()
                            if newValue {
                                trackingEngine.isTrackingEnabled = true
                                trackingEngine.startTracking()
                            } else {
                                trackingEngine.isTrackingEnabled = false
                                Task {
                                    await trackingEngine.stopTracking()
                                }
                            }
                        }
                    ))
                    .labelsHidden()
                    .tint(Color(hex: "#FFB300"))
                }
                
                Divider()
                    .opacity(0.6)
                
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Dynamic Island Glance")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundColor(.primary)
                        
                        Text("Live exploration telemetry on Lock Screen")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Toggle("", isOn: Binding(
                        get: { trackingEngine.isLiveActivityEnabled },
                        set: { newValue in
                            let impact = UIImpactFeedbackGenerator(style: .light)
                            impact.impactOccurred()
                            trackingEngine.updateLiveActivityPreference(enabled: newValue)
                        }
                    ))
                    .labelsHidden()
                    .tint(Color(hex: "#FFB300"))
                }
            }
            .padding(14)
            .background(Color.white.opacity(0.65))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
            )
            
            // Section 3: CoreLocation Authorization Status & Escalation
            VStack(spacing: 10) {
                HStack {
                    Text("Location Authorization")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    permissionBadge
                }
                
                if isDegradedAuthorization {
                    escalationBanner
                }
            }
            .padding(14)
            .background(Color.white.opacity(0.65))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
            )
            
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 16)
    }
    
    // MARK: - Subviews
    
    private var isDegradedAuthorization: Bool {
        trackingEngine.authorizationStatus != .authorizedAlways
    }
    
    @ViewBuilder
    private var permissionBadge: some View {
        switch trackingEngine.authorizationStatus {
        case .authorizedAlways:
            badgePill(text: "Always", color: Color(hex: "#FFB300"))
        case .authorizedWhenInUse:
            badgePill(text: "While Using", color: Color.orange)
        case .denied, .restricted:
            badgePill(text: "Denied", color: Color.red)
        case .notDetermined:
            badgePill(text: "Not Set", color: Color.secondary)
        @unknown default:
            badgePill(text: "Unknown", color: Color.secondary)
        }
    }
    
    private func badgePill(text: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            
            Text(text)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }
    
    @ViewBuilder
    private var escalationBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13))
                .foregroundColor(Color(hex: "#FFB300"))
            
            Text(escalationMessage)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .lineLimit(2)
            
            Spacer()
            
            Button(action: {
                let impact = UIImpactFeedbackGenerator(style: .light)
                impact.impactOccurred()
                trackingEngine.requestLocationPermissionEscalation()
            }) {
                Text(escalationButtonTitle)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.primary)
                    .clipShape(Capsule())
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(10)
        .background(Color.yellow.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
    
    private var escalationMessage: String {
        switch trackingEngine.authorizationStatus {
        case .authorizedWhenInUse:
            return "Background discovery requires 'Always' authorization."
        case .denied, .restricted:
            return "Location access is disabled in system settings."
        case .notDetermined:
            return "Location access is required to discover hexes."
        case .authorizedAlways:
            return ""
        @unknown default:
            return "Please check location permissions."
        }
    }
    
    private var escalationButtonTitle: String {
        switch trackingEngine.authorizationStatus {
        case .authorizedWhenInUse:
            return "Upgrade"
        case .denied, .restricted:
            return "Settings"
        case .notDetermined:
            return "Enable"
        case .authorizedAlways:
            return ""
        @unknown default:
            return "Fix"
        }
    }
}
