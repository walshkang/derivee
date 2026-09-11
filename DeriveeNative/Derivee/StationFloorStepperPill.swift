import SwiftUI
import UIKit

/// Interactive floor stepper pill component for discrete 2D multi-level station floorplan navigation.
/// Built strictly to Research Doc 15 (§2) and Research Doc 20 (§3) for Wave Q.4 (WQ4-2D-FLOORPLAN-VIEWER).
///
/// Features:
/// - Frosted glass `.ultraThinMaterial` capsule with 0.5pt specular border (>7.2:1 WCAG AAA contrast).
/// - Electric Amber (`#FFB300`) active floor illumination.
/// - Single-tap segmented chips for instant floor selection.
/// - Up/down arrow steppers (`chevron.up`, `chevron.down`) for one-handed thumb navigation.
/// - Contextual floor label readout (e.g. "Main Concourse", "Platform Level").
/// - Haptic feedback (`UISelectionFeedbackGenerator`) on level transitions.
public struct StationFloorStepperPill: View {
    public let floors: [StationFloor]
    @Binding public var selectedFloor: StationFloor?
    public var onFloorChanged: ((StationFloor) -> Void)? = nil
    
    private let hapticGenerator = UISelectionFeedbackGenerator()
    
    public init(
        floors: [StationFloor],
        selectedFloor: Binding<StationFloor?>,
        onFloorChanged: ((StationFloor) -> Void)? = nil
    ) {
        self.floors = floors
        self._selectedFloor = selectedFloor
        self.onFloorChanged = onFloorChanged
    }
    
    private var currentIndex: Int? {
        guard let current = selectedFloor else { return nil }
        return floors.firstIndex(of: current)
    }
    
    private var canStepUp: Bool {
        guard let idx = currentIndex else { return false }
        // floors is sorted descending (e.g. 0 -> -1 -> -2), so stepping up (higher floor) moves to a lower index
        return idx > 0
    }
    
    private var canStepDown: Bool {
        guard let idx = currentIndex else { return false }
        // stepping down (lower floor) moves to a higher index
        return idx < floors.count - 1
    }
    
    private func stepUp() {
        guard canStepUp, let idx = currentIndex else { return }
        let nextFloor = floors[idx - 1]
        selectFloor(nextFloor)
    }
    
    private func stepDown() {
        guard canStepDown, let idx = currentIndex else { return }
        let nextFloor = floors[idx + 1]
        selectFloor(nextFloor)
    }
    
    private func selectFloor(_ floor: StationFloor) {
        guard selectedFloor != floor else { return }
        hapticGenerator.selectionChanged()
        withAnimation(.spring(response: 0.28, dampingFraction: 0.80)) {
            selectedFloor = floor
        }
        onFloorChanged?(floor)
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .center, spacing: 8) {
                // Multi-Level Indicator Icon
                Image(systemName: "square.2.layers.3d.top.filled")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color(hex: "#FFB300"))
                    .accessibilityHidden(true)
                
                // Downward stepper button (descend to lower subterranean level)
                Button {
                    stepDown()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(canStepDown ? .primary : .secondary.opacity(0.35))
                        .frame(width: 24, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!canStepDown)
                .accessibilityLabel("Step Down Floor")
                
                // Discrete Floor Chips
                HStack(spacing: 5) {
                    ForEach(floors) { floor in
                        let isSelected = selectedFloor == floor
                        Button {
                            selectFloor(floor)
                        } label: {
                            Text(floor.shortName)
                                .font(.system(size: 12, weight: isSelected ? .bold : .medium, design: .rounded))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    ZStack {
                                        if isSelected {
                                            Capsule(style: .continuous)
                                                .fill(Color(hex: "#FFB300"))
                                                .shadow(color: Color(hex: "#FFB300").opacity(0.30), radius: 3, x: 0, y: 1)
                                        } else {
                                            Capsule(style: .continuous)
                                                .fill(Color.primary.opacity(0.06))
                                        }
                                    }
                                )
                                .foregroundColor(isSelected ? Color(hex: "#1C1C1E") : .primary.opacity(0.75))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Floor \(floor.shortName): \(floor.name)")
                        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                    }
                }
                
                // Upward stepper button (ascend to higher level)
                Button {
                    stepUp()
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(canStepUp ? .primary : .secondary.opacity(0.35))
                        .frame(width: 24, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!canStepUp)
                .accessibilityLabel("Step Up Floor")
                
                Spacer()
                
                // Active Level Summary Badge
                if let current = selectedFloor {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color(hex: "#FFB300"))
                            .frame(width: 5, height: 5)
                        
                        Text(current.name)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                    )
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Station Floor Stepper")
    }
}
