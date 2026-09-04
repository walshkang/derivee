import SwiftUI

/// Standardized 3-tier ergonomic bottom sheet detents for multimodal transit navigation (Wave N-D.5).
/// Built according to Research Doc 14 (§5) and Derivée navigation ergonomics:
/// - `peek` (15%): Glanceable next upcoming maneuver / next step, maximizing background map visibility.
/// - `half` (50%): Step-by-step navigation guidance and route itinerary timeline.
/// - `expanded` (90%): Full-screen expanded timetables, alternative itineraries, and departure frequency matrix.
public enum NavigationSheetDetent: CGFloat, CaseIterable, Sendable {
    case peek = 0.15
    case half = 0.50
    case expanded = 0.90
    
    /// The fractional height of the screen bounds.
    public var fraction: CGFloat {
        rawValue
    }
    
    /// Native SwiftUI `PresentationDetent` representation.
    public var presentationDetent: PresentationDetent {
        .fraction(rawValue)
    }
    
    /// The standardized set of 3 ergonomic detents for all navigation sheets.
    public static var standardSet: Set<PresentationDetent> {
        Set(allCases.map { $0.presentationDetent })
    }
    
    /// Converts a native SwiftUI `PresentationDetent` back to `NavigationSheetDetent` if matching.
    public static func from(detent: PresentationDetent) -> NavigationSheetDetent? {
        if detent == NavigationSheetDetent.peek.presentationDetent {
            return .peek
        } else if detent == NavigationSheetDetent.half.presentationDetent {
            return .half
        } else if detent == NavigationSheetDetent.expanded.presentationDetent {
            return .expanded
        }
        return nil
    }
}

/// View modifier applying the standardized 3-tier navigation detents, background interaction,
/// drag indicator, and high-contrast 3-tier glassmorphic material (Doc 18).
public struct StandardNavigationSheetModifier: ViewModifier {
    @Binding public var selectedDetent: PresentationDetent
    public var interactiveUpThrough: PresentationDetent
    public var cornerRadius: CGFloat
    
    public init(
        selectedDetent: Binding<PresentationDetent>,
        interactiveUpThrough: PresentationDetent = NavigationSheetDetent.half.presentationDetent,
        cornerRadius: CGFloat = 28
    ) {
        self._selectedDetent = selectedDetent
        self.interactiveUpThrough = interactiveUpThrough
        self.cornerRadius = cornerRadius
    }
    
    public func body(content: Content) -> some View {
        content
            .presentationDetents(NavigationSheetDetent.standardSet, selection: $selectedDetent)
            .presentationDragIndicator(.visible)
            .presentationBackgroundInteraction(.enabled(upThrough: interactiveUpThrough))
            .presentationContentInteraction(.scrolls)
            .transitSheetGlassBackground(cornerRadius: cornerRadius)
    }
}

public struct StandardNavigationSheetStaticModifier: ViewModifier {
    public var interactiveUpThrough: PresentationDetent
    public var cornerRadius: CGFloat
    
    public init(
        interactiveUpThrough: PresentationDetent = NavigationSheetDetent.half.presentationDetent,
        cornerRadius: CGFloat = 28
    ) {
        self.interactiveUpThrough = interactiveUpThrough
        self.cornerRadius = cornerRadius
    }
    
    public func body(content: Content) -> some View {
        content
            .presentationDetents(NavigationSheetDetent.standardSet)
            .presentationDragIndicator(.visible)
            .presentationBackgroundInteraction(.enabled(upThrough: interactiveUpThrough))
            .presentationContentInteraction(.scrolls)
            .transitSheetGlassBackground(cornerRadius: cornerRadius)
    }
}

public extension View {
    /// Applies standardized 3-tier navigation sheet detents (15%, 50%, 90%),
    /// preserving floating hero map interactivity up through the half detent (50%),
    /// with the high-contrast 3-tier glassmorphic backdrop.
    func standardNavigationDetents(
        selectedDetent: Binding<PresentationDetent>,
        interactiveUpThrough: PresentationDetent = NavigationSheetDetent.half.presentationDetent,
        cornerRadius: CGFloat = 28
    ) -> some View {
        modifier(
            StandardNavigationSheetModifier(
                selectedDetent: selectedDetent,
                interactiveUpThrough: interactiveUpThrough,
                cornerRadius: cornerRadius
            )
        )
    }
    
    /// Applies standardized 3-tier navigation sheet detents without explicit binding tracking,
    /// with the high-contrast 3-tier glassmorphic backdrop.
    func standardNavigationDetents(
        interactiveUpThrough: PresentationDetent = NavigationSheetDetent.half.presentationDetent,
        cornerRadius: CGFloat = 28
    ) -> some View {
        modifier(
            StandardNavigationSheetStaticModifier(
                interactiveUpThrough: interactiveUpThrough,
                cornerRadius: cornerRadius
            )
        )
    }
}
