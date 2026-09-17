import XCTest
import CoreLocation
@testable import Derivee
import SwiftProtobuf

final class ComplexDirectionCanonicalizationTests: XCTestCase {
    
    // MARK: - 1. Complex Station Co-located Line Unification (Herald Square)
    
    @MainActor
    func testComplexStationDirectionClusteringHeraldSquare() {
        // Northbound arrivals at 34 St-Herald Sq
        let bNorth = SpatialDatabaseManager.ArrivalInfo(
            line: "B",
            destination: "Bedford Park Blvd",
            minutes: 2,
            direction: "Uptown & Queens / Bronx",
            distanceDescription: "1 stop away",
            corridorVector: .northbound
        )
        let dNorth = SpatialDatabaseManager.ArrivalInfo(
            line: "D",
            destination: "Norwood - 205 St",
            minutes: 5,
            direction: "Uptown & Queens / Bronx",
            distanceDescription: "3 stops away",
            corridorVector: .northbound
        )
        let nNorth = SpatialDatabaseManager.ArrivalInfo(
            line: "N",
            destination: "Astoria - Ditmars Blvd",
            minutes: 4,
            direction: "Uptown & Queens",
            distanceDescription: "2 stops away",
            corridorVector: .northbound
        )
        let qNorth = SpatialDatabaseManager.ArrivalInfo(
            line: "Q",
            destination: "96 St-2 Av",
            minutes: 7,
            direction: "Uptown & Queens",
            distanceDescription: "4 stops away",
            corridorVector: .northbound
        )
        
        // Southbound arrivals at 34 St-Herald Sq
        let bSouth = SpatialDatabaseManager.ArrivalInfo(
            line: "B",
            destination: "Brighton Beach",
            minutes: 3,
            direction: "Downtown & Brooklyn",
            distanceDescription: "2 stops away",
            corridorVector: .southbound
        )
        let wSouth = SpatialDatabaseManager.ArrivalInfo(
            line: "W",
            destination: "Whitehall St",
            minutes: 6,
            direction: "Downtown & Lower Manhattan",
            distanceDescription: "3 stops away",
            corridorVector: .southbound,
            terminalQualifier: "W to Whitehall St"
        )
        let rSouth = SpatialDatabaseManager.ArrivalInfo(
            line: "R",
            destination: "Bay Ridge - 95 St",
            minutes: 9,
            direction: "Downtown & Brooklyn",
            distanceDescription: "5 stops away",
            corridorVector: .southbound
        )
        
        let allArrivals = [bNorth, dNorth, nNorth, qNorth, bSouth, wSouth, rSouth]
        
        let details = SpatialDatabaseManager.StopDetails(
            stopId: "complex_herald_sq",
            name: "34 St-Herald Sq",
            routeId: "B",
            routeIds: ["B", "D", "F", "M", "N", "Q", "R", "W"],
            routeType: 1,
            modalClass: .subway,
            coordinate: CLLocationCoordinate2D(latitude: 40.7497, longitude: -73.9878),
            arrivals: allArrivals
        )
        
        let sheet = TransitRevealSheet(
            stopId: "complex_herald_sq",
            initialDetails: details,
            initialLiveArrivals: allArrivals
        )
        
        let groups = sheet.groupedArrivals
        
        // Assert exactly 2 unified direction groups (Northbound and Southbound)
        XCTAssertEqual(groups.count, 2, "Co-located lines at 34 St-Herald Sq must cluster into exactly 2 groups (Northbound & Southbound), not 4 fragmented groups")
        
        // Northbound Group check
        let nbGroup = groups.first(where: { $0.arrivals.contains(where: { $0.line == "B" && $0.corridorVector == .northbound }) })
        XCTAssertNotNil(nbGroup)
        XCTAssertEqual(nbGroup?.directionName.uppercased(), "UPTOWN & QUEENS / THE BRONX", "Northbound co-located lines at Herald Sq must unify under 'UPTOWN & QUEENS / THE BRONX'")
        XCTAssertEqual(nbGroup?.arrivals.count, 4, "Northbound group must contain all 4 arrivals (B, D, N, Q)")
        XCTAssertEqual(nbGroup?.arrivals.map { $0.minutes }, [2, 4, 5, 7], "Arrivals must be sorted ascending by minutes")
        
        // Southbound Group check
        let sbGroup = groups.first(where: { $0.arrivals.contains(where: { $0.line == "W" }) })
        XCTAssertNotNil(sbGroup)
        XCTAssertEqual(sbGroup?.directionName.uppercased(), "DOWNTOWN & BROOKLYN / LOWER MANHATTAN", "Southbound co-located lines with Whitehall St must unify under 'DOWNTOWN & BROOKLYN / LOWER MANHATTAN'")
        XCTAssertEqual(sbGroup?.arrivals.count, 3, "Southbound group must contain all 3 arrivals (B, W, R)")
        XCTAssertEqual(sbGroup?.arrivals.map { $0.minutes }, [3, 6, 9], "Arrivals must be sorted ascending by minutes")
    }
    
    // MARK: - 2. Lower Manhattan Terminal Disambiguation (W to Whitehall St)
    
    func testLowerManhattanTerminalDisambiguation() {
        var tripUpdate = TransitRealtime_TripUpdate()
        var trip = TransitRealtime_TripDescriptor()
        trip.routeID = "W"
        trip.directionID = 1 // Southbound
        tripUpdate.trip = trip
        
        var u1 = TransitRealtime_TripUpdate.StopTimeUpdate()
        u1.stopID = "R17S" // 34 St - Herald Sq
        var u2 = TransitRealtime_TripUpdate.StopTimeUpdate()
        u2.stopID = "R27S" // Whitehall St - South Ferry (Terminal)
        tripUpdate.stopTimeUpdate = [u1, u2]
        
        let classification = TransitRealtimeService.shared.classifyDirection(
            tripUpdate: tripUpdate,
            line: "W",
            stopId: "R17S",
            terminalName: "Whitehall St"
        )
        
        XCTAssertEqual(classification.corridorVector, .southbound)
        XCTAssertEqual(classification.displayDirection, "Downtown & Lower Manhattan", "W train terminating at Whitehall St must never be labeled as Brooklyn")
        XCTAssertFalse(classification.displayDirection.contains("Brooklyn"), "Lower Manhattan terminal must not contain 'Brooklyn'")
        XCTAssertEqual(classification.terminalQualifier, "Whitehall St")
        
        // Test resolveDirection string delegation
        let dirLabel = TransitRealtimeService.shared.resolveDirection(
            tripUpdate: tripUpdate,
            line: "W",
            stopId: "R17S"
        )
        XCTAssertEqual(dirLabel, "Downtown & Lower Manhattan")
        XCTAssertFalse(dirLabel.contains("Brooklyn"))
    }
    
    // MARK: - 3. Boston MBTA Green Line Branch Unification (Park St)
    
    @MainActor
    func testBostonGreenLineBranchUnificationParkStreet() {
        // Green Line branches inbound to Park St / downtown
        let greenBIn = SpatialDatabaseManager.ArrivalInfo(
            line: "Green-B",
            destination: "Government Center",
            minutes: 2,
            direction: "Inbound",
            distanceDescription: "1 stop away",
            corridorVector: .inbound,
            terminalQualifier: "Green Line B to Gov Center"
        )
        let greenCIn = SpatialDatabaseManager.ArrivalInfo(
            line: "Green-C",
            destination: "Government Center",
            minutes: 4,
            direction: "Inbound",
            distanceDescription: "2 stops away",
            corridorVector: .inbound,
            terminalQualifier: "Green Line C to Gov Center"
        )
        let greenDIn = SpatialDatabaseManager.ArrivalInfo(
            line: "Green-D",
            destination: "Union Square",
            minutes: 6,
            direction: "Inbound",
            distanceDescription: "4 stops away",
            corridorVector: .inbound,
            terminalQualifier: "Green Line D to Union Square"
        )
        let greenEIn = SpatialDatabaseManager.ArrivalInfo(
            line: "Green-E",
            destination: "Medford/Tufts",
            minutes: 8,
            direction: "Inbound",
            distanceDescription: "5 stops away",
            corridorVector: .inbound,
            terminalQualifier: "Green Line E to Medford/Tufts"
        )
        
        // Green Line branches outbound from Park St
        let greenBOut = SpatialDatabaseManager.ArrivalInfo(
            line: "Green-B",
            destination: "Boston College",
            minutes: 3,
            direction: "Outbound",
            distanceDescription: "Approaching",
            corridorVector: .outbound,
            terminalQualifier: "Green Line B to Boston College"
        )
        let greenCOut = SpatialDatabaseManager.ArrivalInfo(
            line: "Green-C",
            destination: "Cleveland Circle",
            minutes: 5,
            direction: "Outbound",
            distanceDescription: "2 stops away",
            corridorVector: .outbound,
            terminalQualifier: "Green Line C to Cleveland Circle"
        )
        
        let allArrivals = [greenBIn, greenCIn, greenDIn, greenEIn, greenBOut, greenCOut]
        
        let details = SpatialDatabaseManager.StopDetails(
            stopId: "place-park",
            name: "Park Street",
            routeId: "Green-B",
            routeIds: ["Green-B", "Green-C", "Green-D", "Green-E", "Red"],
            routeType: 0,
            modalClass: .lightRail,
            coordinate: CLLocationCoordinate2D(latitude: 42.3564, longitude: -71.0624),
            arrivals: allArrivals
        )
        
        let sheet = TransitRevealSheet(
            stopId: "place-park",
            initialDetails: details,
            initialLiveArrivals: allArrivals
        )
        
        let groups = sheet.groupedArrivals
        
        // Assert exactly 2 unified groups: INBOUND and OUTBOUND
        XCTAssertEqual(groups.count, 2, "MBTA Green Line branches at Park St must unify into INBOUND and OUTBOUND groups")
        
        let inboundGroup = groups.first(where: { $0.directionName.uppercased() == "INBOUND" })
        XCTAssertNotNil(inboundGroup)
        XCTAssertEqual(inboundGroup?.arrivals.count, 4, "All 4 inbound Green Line branches must cluster into the INBOUND group")
        XCTAssertEqual(inboundGroup?.arrivals.map { $0.minutes }, [2, 4, 6, 8])
        
        let outboundGroup = groups.first(where: { $0.directionName.uppercased() == "OUTBOUND" })
        XCTAssertNotNil(outboundGroup)
        XCTAssertEqual(outboundGroup?.arrivals.count, 2, "All outbound Green Line branches must cluster into the OUTBOUND group")
        XCTAssertEqual(outboundGroup?.arrivals.map { $0.minutes }, [3, 5])
    }
    
    // MARK: - 4. 2-Tier Direction Classifier Across Modes
    
    func testTwoTierDirectionClassificationAcrossModes() {
        let service = TransitRealtimeService.shared
        var tu = TransitRealtime_TripUpdate()
        
        // L Train: East-West
        let lWest = service.classifyDirection(tripUpdate: tu, line: "L", stopId: "L08N")
        XCTAssertEqual(lWest.corridorVector, .westbound)
        XCTAssertEqual(lWest.displayDirection, "Manhattan-bound")
        
        let lEast = service.classifyDirection(tripUpdate: tu, line: "L", stopId: "L08S")
        XCTAssertEqual(lEast.corridorVector, .eastbound)
        XCTAssertEqual(lEast.displayDirection, "Brooklyn-bound")
        
        // 7 Train: East-West
        let sevenEast = service.classifyDirection(tripUpdate: tu, line: "7", stopId: "725N")
        XCTAssertEqual(sevenEast.corridorVector, .eastbound)
        XCTAssertEqual(sevenEast.displayDirection, "Queens-bound")
        
        let sevenWest = service.classifyDirection(tripUpdate: tu, line: "7", stopId: "725S")
        XCTAssertEqual(sevenWest.corridorVector, .westbound)
        XCTAssertEqual(sevenWest.displayDirection, "Manhattan-bound")
        
        // SIR: Radial
        let sirIn = service.classifyDirection(tripUpdate: tu, line: "SIR", stopId: "S31N")
        XCTAssertEqual(sirIn.corridorVector, .inbound)
        XCTAssertEqual(sirIn.displayDirection, "Inbound (St George)")
        
        let sirOut = service.classifyDirection(tripUpdate: tu, line: "SIR", stopId: "S09S")
        XCTAssertEqual(sirOut.corridorVector, .outbound)
        XCTAssertEqual(sirOut.displayDirection, "Outbound (Tottenville)")
        
        // Subway Trunk Lines: North-South
        let fourNorth = service.classifyDirection(tripUpdate: tu, line: "4", stopId: "128N")
        XCTAssertEqual(fourNorth.corridorVector, .northbound)
        XCTAssertEqual(fourNorth.displayDirection, "Uptown & Bronx")
        
        let fourSouth = service.classifyDirection(tripUpdate: tu, line: "4", stopId: "128S")
        XCTAssertEqual(fourSouth.corridorVector, .southbound)
        XCTAssertEqual(fourSouth.displayDirection, "Downtown & Brooklyn")
    }
    
    // MARK: - 5. Backward-Compatible Vector Inference from Legacy Direction Strings
    
    func testArrivalInfoResolvedCorridorVectorInference() {
        // Without explicit corridorVector parameter:
        let arrUptown = SpatialDatabaseManager.ArrivalInfo(
            line: "6",
            destination: "Pelham Bay Park",
            minutes: 3,
            direction: "Uptown & Bronx"
        )
        XCTAssertEqual(arrUptown.resolvedCorridorVector, .northbound)
        
        let arrDowntown = SpatialDatabaseManager.ArrivalInfo(
            line: "5",
            destination: "Flatbush Ave",
            minutes: 5,
            direction: "Downtown & Brooklyn"
        )
        XCTAssertEqual(arrDowntown.resolvedCorridorVector, .southbound)
        
        let arrLManhattan = SpatialDatabaseManager.ArrivalInfo(
            line: "L",
            destination: "8th Ave",
            minutes: 2,
            direction: "Manhattan-bound"
        )
        XCTAssertEqual(arrLManhattan.resolvedCorridorVector, .westbound)
        
        let arrLBrooklyn = SpatialDatabaseManager.ArrivalInfo(
            line: "L",
            destination: "Canarsie",
            minutes: 4,
            direction: "Brooklyn-bound"
        )
        XCTAssertEqual(arrLBrooklyn.resolvedCorridorVector, .eastbound)
        
        let arrSIRInbound = SpatialDatabaseManager.ArrivalInfo(
            line: "SIR",
            destination: "St George",
            minutes: 6,
            direction: "Inbound (St George)"
        )
        XCTAssertEqual(arrSIRInbound.resolvedCorridorVector, .inbound)
        
        let arrSIROutbound = SpatialDatabaseManager.ArrivalInfo(
            line: "SIR",
            destination: "Tottenville",
            minutes: 11,
            direction: "Outbound (Tottenville)"
        )
        XCTAssertEqual(arrSIROutbound.resolvedCorridorVector, .outbound)
    }
}
