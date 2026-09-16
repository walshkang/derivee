import XCTest
import CoreLocation
@testable import Derivee

final class BusStopChronologicalDeparturesTests: XCTestCase {
    
    // MARK: - 1. Unified Chronological Stream for Bus Stops
    
    @MainActor
    func testBusStopUnifiedChronologicalStream() {
        let arr1 = SpatialDatabaseManager.ArrivalInfo(
            line: "M9",
            destination: "1 Av & 24 St",
            minutes: 8,
            direction: "Northbound",
            distanceDescription: "0.9 mi away"
        )
        let arr2 = SpatialDatabaseManager.ArrivalInfo(
            line: "M9",
            destination: "1 Av & 24 St",
            minutes: 2,
            direction: "Northbound",
            distanceDescription: "0.2 mi away"
        )
        let arr3 = SpatialDatabaseManager.ArrivalInfo(
            line: "M15",
            destination: "East Harlem - 125 St",
            minutes: 14,
            direction: "Northbound",
            distanceDescription: "1.5 mi away"
        )
        
        let details = SpatialDatabaseManager.StopDetails(
            stopId: "BUS_M9_01",
            name: "1 Av & E 14 St",
            routeId: "M9",
            routeIds: ["M9", "M15"],
            routeType: 3,
            modalClass: .bus,
            coordinate: CLLocationCoordinate2D(latitude: 40.7314, longitude: -73.9818),
            arrivals: [arr1, arr2, arr3]
        )
        
        let sheet = TransitRevealSheet(
            stopId: "BUS_M9_01",
            initialDetails: details,
            initialLiveArrivals: [arr1, arr2, arr3]
        )
        
        XCTAssertTrue(sheet.isBusStop, "Stop with modalClass == .bus must be recognized as isBusStop")
        XCTAssertTrue(sheet.groupedArrivals.isEmpty, "Bus stops must eliminate subway-style DirectionalArrivalGroup headers")
        
        let unified = sheet.unifiedBusArrivals
        XCTAssertEqual(unified.count, 3, "Unified stream must contain all 3 arrivals")
        XCTAssertEqual(unified.map { $0.minutes }, [2, 8, 14], "Unified bus arrivals must be sorted strictly by ETA ascending")
    }
    
    // MARK: - 2. Terminal Branch Variants and Short-Turns
    
    @MainActor
    func testTerminalBranchVariantsAndShortTurnsInSingleQueue() {
        let fullRoute = SpatialDatabaseManager.ArrivalInfo(
            line: "M9",
            destination: "24th St",
            minutes: 6,
            direction: "Northbound",
            distanceDescription: "0.7 mi away"
        )
        let shortTurn = SpatialDatabaseManager.ArrivalInfo(
            line: "M9",
            destination: "E 20th St Loop",
            minutes: 3,
            direction: "Northbound",
            distanceDescription: "0.3 mi away"
        )
        
        let details = SpatialDatabaseManager.StopDetails(
            stopId: "BUS_M9_02",
            name: "Avenue C & E 10 St",
            routeId: "M9",
            routeIds: ["M9"],
            routeType: 3,
            modalClass: .bus,
            coordinate: CLLocationCoordinate2D(latitude: 40.7262, longitude: -73.9782),
            arrivals: [fullRoute, shortTurn]
        )
        
        let sheet = TransitRevealSheet(
            stopId: "BUS_M9_02",
            initialDetails: details,
            initialLiveArrivals: [fullRoute, shortTurn]
        )
        
        let unified = sheet.unifiedBusArrivals
        XCTAssertEqual(unified.count, 2)
        XCTAssertEqual(unified[0].destination, "E 20th St Loop", "Short-turn approaching in 3 min must lead the chronological queue")
        XCTAssertEqual(unified[1].destination, "24th St", "Full-route approaching in 6 min must follow in the same unified stream")
    }
    
    // MARK: - 3. Multi-Route Bus Hub Filter Chips
    
    @MainActor
    func testMultiRouteBusHubFilterChips() {
        let bm1Arr = SpatialDatabaseManager.ArrivalInfo(
            line: "BM1",
            destination: "Downtown / Lower Manhattan",
            minutes: 4,
            direction: "Inbound (Manhattan)"
        )
        let bm2Arr = SpatialDatabaseManager.ArrivalInfo(
            line: "BM2",
            destination: "Downtown / Lower Manhattan",
            minutes: 9,
            direction: "Inbound (Manhattan)"
        )
        let m22Arr = SpatialDatabaseManager.ArrivalInfo(
            line: "M22",
            destination: "Battery Park City",
            minutes: 2,
            direction: "Westbound"
        )
        
        let details = SpatialDatabaseManager.StopDetails(
            stopId: "BUS_HUB_01",
            name: "Battery Pl & Greenwich St",
            routeId: "BM1",
            routeIds: ["BM1", "BM2", "M22"],
            routeType: 3,
            modalClass: .bus,
            coordinate: CLLocationCoordinate2D(latitude: 40.7058, longitude: -74.0152),
            arrivals: [bm1Arr, bm2Arr, m22Arr]
        )
        
        let sheet = TransitRevealSheet(
            stopId: "BUS_HUB_01",
            initialDetails: details,
            initialLiveArrivals: [bm1Arr, bm2Arr, m22Arr]
        )
        
        // Initial state: No filter (all oncoming buses)
        XCTAssertEqual(sheet.unifiedBusArrivals.count, 3)
        XCTAssertEqual(sheet.unifiedBusArrivals.map { $0.minutes }, [2, 4, 9])
        
        // Filter to BM1
        XCTAssertEqual(sheet.filteredBusArrivals(for: "BM1").count, 1)
        XCTAssertEqual(sheet.filteredBusArrivals(for: "BM1").first?.line, "BM1")
        
        // Filter to M22
        XCTAssertEqual(sheet.filteredBusArrivals(for: "M22").count, 1)
        XCTAssertEqual(sheet.filteredBusArrivals(for: "M22").first?.line, "M22")
        
        // Reset to ALL / nil
        XCTAssertEqual(sheet.filteredBusArrivals(for: nil).count, 3)
        
        // Verify initialBusRouteFilter via unifiedBusArrivals
        let filteredSheet = TransitRevealSheet(
            stopId: "BUS_HUB_01",
            initialDetails: details,
            initialLiveArrivals: [bm1Arr, bm2Arr, m22Arr],
            initialBusRouteFilter: "BM1"
        )
        XCTAssertEqual(filteredSheet.unifiedBusArrivals.count, 1)
        XCTAssertEqual(filteredSheet.unifiedBusArrivals.first?.line, "BM1")
    }
    
    // MARK: - 4. Decouple Direction from Destination
    
    func testDecoupleDirectionFromDestinationVectors() {
        // Express buses
        let bmDir0 = TransitRealtimeService.resolveBusDirectionVector(routeId: "BM1", directionId: 0)
        XCTAssertEqual(bmDir0, "Inbound (Manhattan)")
        XCTAssertFalse(bmDir0.contains("To "))
        
        let bmDir1 = TransitRealtimeService.resolveBusDirectionVector(routeId: "BM1", directionId: 1)
        XCTAssertEqual(bmDir1, "Outbound (Brooklyn)")
        XCTAssertFalse(bmDir1.contains("To "))
        
        // Staten Island routes
        let s51Dir0 = TransitRealtimeService.resolveBusDirectionVector(routeId: "S51", directionId: 0)
        XCTAssertEqual(s51Dir0, "Inbound (St George)")
        XCTAssertFalse(s51Dir0.contains("To "))
        
        let s51Dir1 = TransitRealtimeService.resolveBusDirectionVector(routeId: "S51", directionId: 1)
        XCTAssertEqual(s51Dir1, "Outbound")
        XCTAssertFalse(s51Dir1.contains("To "))
        
        // Crosstown routes
        let m14Dir0 = TransitRealtimeService.resolveBusDirectionVector(routeId: "M14A-SBS", directionId: 0)
        XCTAssertEqual(m14Dir0, "Eastbound")
        XCTAssertFalse(m14Dir0.contains("To "))
        
        let m14Dir1 = TransitRealtimeService.resolveBusDirectionVector(routeId: "M14A-SBS", directionId: 1)
        XCTAssertEqual(m14Dir1, "Westbound")
        XCTAssertFalse(m14Dir1.contains("To "))
        
        // Interborough routes
        let q54Dir0 = TransitRealtimeService.resolveBusDirectionVector(routeId: "Q54", directionId: 0)
        XCTAssertEqual(q54Dir0, "Queens-bound")
        XCTAssertFalse(q54Dir0.contains("To "))
        
        let q54Dir1 = TransitRealtimeService.resolveBusDirectionVector(routeId: "Q54", directionId: 1)
        XCTAssertEqual(q54Dir1, "Brooklyn-bound")
        XCTAssertFalse(q54Dir1.contains("To "))
    }
    
    // MARK: - 5. Single-Direction Timetable Consistency
    
    func testSingleDirectionTimetableConsistency() {
        let view = DepartureMatrixView(
            records: [],
            routeId: "B32",
            routeIds: ["B32"],
            stopId: "BUS_B32_ONEWAY",
            availableDirections: [0],
            selectedDirection: .constant(0)
        )
        
        XCTAssertEqual(view.availableDirections, [0])
        XCTAssertFalse(view.availableDirections.contains(1), "One-way bus curb must only have direction 0")
    }
}
