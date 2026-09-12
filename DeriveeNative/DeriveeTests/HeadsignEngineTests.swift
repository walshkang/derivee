import XCTest
@testable import Derivee
import SwiftProtobuf

final class HeadsignEngineTests: XCTestCase {
    
    // MARK: - Tier 1: GTFS-RT Live Stream Terminal Inference
    
    func testTier1LiveStreamBusTerminalInference() throws {
        var tripUpdate = TransitRealtime_TripUpdate()
        var trip = TransitRealtime_TripDescriptor()
        trip.routeID = "S51"
        trip.directionID = 0
        tripUpdate.trip = trip
        
        var u1 = TransitRealtime_TripUpdate.StopTimeUpdate()
        u1.stopID = "200099" // Midland Av & Olympia Blvd
        
        var u2 = TransitRealtime_TripUpdate.StopTimeUpdate()
        u2.stopID = "200097" // Midland Av & Kiswick St (Terminal in this update)
        
        tripUpdate.stopTimeUpdate = [u1, u2]
        
        let destination = TransitRealtimeService.shared.resolveDestination(
            tripUpdate: tripUpdate,
            line: "S51",
            stopId: "200099",
            matchingUpdate: u1
        )
        
        XCTAssertEqual(destination, "Midland Av & Kiswick St")
    }
    
    // MARK: - Tier 2: SQLite route_directions Pre-compiled Headsigns
    
    func testTier2RouteDirectionsHeadsignLookup() {
        // Direct SpatialDatabaseManager route direction lookup
        let s51Dir0 = SpatialDatabaseManager.shared.resolveRouteDirection(routeId: "S51", directionId: 0)
        XCTAssertNotNil(s51Dir0)
        XCTAssertEqual(s51Dir0?.headsign, "St George Ferry")
        
        let s51Dir1 = SpatialDatabaseManager.shared.resolveRouteDirection(routeId: "S51", directionId: 1)
        XCTAssertNotNil(s51Dir1)
        XCTAssertEqual(s51Dir1?.headsign, "Midland Beach")
        
        let s81Dir0 = SpatialDatabaseManager.shared.resolveRouteDirection(routeId: "S81", directionId: 0)
        XCTAssertNotNil(s81Dir0)
        XCTAssertEqual(s81Dir0?.headsign, "St George Ferry")
        
        let s81Dir1 = SpatialDatabaseManager.shared.resolveRouteDirection(routeId: "S81", directionId: 1)
        XCTAssertNotNil(s81Dir1)
        XCTAssertEqual(s81Dir1?.headsign, "Midland Beach")
        
        // resolveBusDestination Tier 2 integration
        let bus0 = TransitRealtimeService.resolveBusDestination(routeId: "S51", directionId: 0)
        XCTAssertEqual(bus0.destination, "St George Ferry")
        XCTAssertEqual(bus0.direction, "To St George Ferry")
        
        let bus1 = TransitRealtimeService.resolveBusDestination(routeId: "S51", directionId: 1)
        XCTAssertEqual(bus1.destination, "Midland Beach")
        XCTAssertEqual(bus1.direction, "To Midland Beach")
    }
    
    // MARK: - Tier 3: Spatial Corridor Extrema Fallback
    
    func testTier3CorridorExtremaProjectionFallback() {
        let extremaDir0 = SpatialDatabaseManager.shared.resolveCorridorExtrema(routeId: "S51", directionId: 0)
        XCTAssertNotNil(extremaDir0)
        XCTAssertFalse(extremaDir0?.isEmpty ?? true)
        
        let extremaDir1 = SpatialDatabaseManager.shared.resolveCorridorExtrema(routeId: "S51", directionId: 1)
        XCTAssertNotNil(extremaDir1)
        XCTAssertFalse(extremaDir1?.isEmpty ?? true)
    }
    
    // MARK: - Direction Label Normalization (Surface Buses vs Manhattan Subway)
    
    func testSurfaceBusDirectionLabelNormalization() {
        var tripUpdate = TransitRealtime_TripUpdate()
        var trip = TransitRealtime_TripDescriptor()
        trip.routeID = "S51"
        trip.directionID = 0
        tripUpdate.trip = trip
        
        var u1 = TransitRealtime_TripUpdate.StopTimeUpdate()
        u1.stopID = "200099"
        var u2 = TransitRealtime_TripUpdate.StopTimeUpdate()
        u2.stopID = "200097" // Midland Av & Kiswick St
        tripUpdate.stopTimeUpdate = [u1, u2]
        
        let dirLabel = TransitRealtimeService.shared.resolveDirection(
            tripUpdate: tripUpdate,
            line: "S51",
            stopId: "200099"
        )
        
        XCTAssertEqual(dirLabel, "To Midland Av & Kiswick St")
        XCTAssertFalse(dirLabel.contains("Uptown"))
        XCTAssertFalse(dirLabel.contains("Downtown"))
        
        // Unlisted / Tier 2 surface bus route
        let s40Dir0 = TransitRealtimeService.resolveBusDestination(routeId: "S40", directionId: 0)
        XCTAssertEqual(s40Dir0.direction, "To St George Ferry")
        XCTAssertFalse(s40Dir0.direction.contains("Uptown"))
        
        let s40Dir1 = TransitRealtimeService.resolveBusDestination(routeId: "S40", directionId: 1)
        XCTAssertEqual(s40Dir1.direction, "To Matrix Global Park")
        XCTAssertFalse(s40Dir1.direction.contains("Downtown"))
    }
    
    // MARK: - Corridor Note Deduplication
    
    func testCorridorNoteDeduplication() {
        let arr1 = SpatialDatabaseManager.ArrivalInfo(
            line: "S51",
            destination: "St George Ferry",
            minutes: 3,
            direction: "To St George Ferry",
            distanceDescription: "1 stop away"
        )
        
        // 1. Header already contains destination
        let note1 = TransitRevealSheet.computeCorridorNote(for: "TO ST GEORGE FERRY", items: [arr1])
        XCTAssertNil(note1, "Corridor note must be suppressed when direction header contains destination verbatim")
        
        // 2. All arrivals in group share destination (verbatim duplicate of arrival row)
        let note2 = TransitRevealSheet.computeCorridorNote(for: "NORTHBOUND", items: [arr1])
        XCTAssertNil(note2, "Corridor note must be suppressed when arrival row already displays destination verbatim")
        
        // 3. Multiple arrivals with different destinations
        let arr2 = SpatialDatabaseManager.ArrivalInfo(
            line: "4",
            destination: "Woodlawn EXP",
            minutes: 5,
            direction: "Uptown & The Bronx",
            distanceDescription: "3 stops away"
        )
        let arr3 = SpatialDatabaseManager.ArrivalInfo(
            line: "5",
            destination: "Eastchester-Dyre Av",
            minutes: 8,
            direction: "Uptown & The Bronx",
            distanceDescription: "5 stops away"
        )
        let note3 = TransitRevealSheet.computeCorridorNote(for: "Uptown & The Bronx", items: [arr2, arr3])
        XCTAssertNil(note3, "Corridor note must be nil when arrivals have multiple disparate destinations")
    }
}
