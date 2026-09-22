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
    
    // MARK: - 6. Wave Pre-T.2: 3-Tier Direction Hierarchy & Single-Tracking Immunity
    
    func testPreT2_SingleTrackingImmunity_LTrainReversePlatform() {
        let service = TransitRealtimeService.shared
        
        // Scenario 1: Brooklyn-bound (dirId = 1) train arriving at Manhattan-bound platform (L08N) during single-tracking
        var tuEast = TransitRealtime_TripUpdate()
        tuEast.trip.directionID = 1
        let lEastOnNorthPlatform = service.classifyDirection(tripUpdate: tuEast, line: "L", stopId: "L08N")
        XCTAssertEqual(lEastOnNorthPlatform.corridorVector, .eastbound, "Tier 1 directionID=1 must override platform suffix N")
        XCTAssertEqual(lEastOnNorthPlatform.displayDirection, "Brooklyn-bound")
        XCTAssertEqual(lEastOnNorthPlatform.directionId, 1)
        
        // Scenario 2: Manhattan-bound (dirId = 0) train arriving at Brooklyn-bound platform (L08S) during single-tracking
        var tuWest = TransitRealtime_TripUpdate()
        tuWest.trip.directionID = 0
        let lWestOnSouthPlatform = service.classifyDirection(tripUpdate: tuWest, line: "L", stopId: "L08S")
        XCTAssertEqual(lWestOnSouthPlatform.corridorVector, .westbound, "Tier 1 directionID=0 must override platform suffix S")
        XCTAssertEqual(lWestOnSouthPlatform.displayDirection, "Manhattan-bound")
        XCTAssertEqual(lWestOnSouthPlatform.directionId, 0)
    }
    
    func testPreT2_SingleTrackingImmunity_7TrainReversePlatform() {
        let service = TransitRealtimeService.shared
        
        // Queens-bound (dirId = 0) train arriving at 725S (Manhattan platform)
        var tuQueens = TransitRealtime_TripUpdate()
        tuQueens.trip.directionID = 0
        let sevenQueensOnSouth = service.classifyDirection(tripUpdate: tuQueens, line: "7", stopId: "725S")
        XCTAssertEqual(sevenQueensOnSouth.corridorVector, .eastbound, "Tier 1 directionID=0 must override platform suffix S for 7 line")
        XCTAssertEqual(sevenQueensOnSouth.displayDirection, "Queens-bound")
        XCTAssertEqual(sevenQueensOnSouth.directionId, 0)
        
        // Manhattan-bound (dirId = 1) train arriving at 725N (Queens platform)
        var tuManhattan = TransitRealtime_TripUpdate()
        tuManhattan.trip.directionID = 1
        let sevenManhattanOnNorth = service.classifyDirection(tripUpdate: tuManhattan, line: "7", stopId: "725N")
        XCTAssertEqual(sevenManhattanOnNorth.corridorVector, .westbound, "Tier 1 directionID=1 must override platform suffix N for 7 line")
        XCTAssertEqual(sevenManhattanOnNorth.displayDirection, "Manhattan-bound")
        XCTAssertEqual(sevenManhattanOnNorth.directionId, 1)
    }
    
    func testPreT2_SingleTrackingImmunity_GTrainReversePlatform() {
        let service = TransitRealtimeService.shared
        
        // Church Ave Brooklyn-bound (dirId = 1) train arriving at G22N (Queens platform)
        var tuSouth = TransitRealtime_TripUpdate()
        tuSouth.trip.directionID = 1
        let gSouthOnNorth = service.classifyDirection(tripUpdate: tuSouth, line: "G", stopId: "G22N")
        XCTAssertEqual(gSouthOnNorth.corridorVector, .southbound, "Tier 1 directionID=1 must override platform suffix N for G line")
        XCTAssertEqual(gSouthOnNorth.displayDirection, "Brooklyn-bound")
        XCTAssertEqual(gSouthOnNorth.directionId, 1)
        
        // Court Sq Queens-bound (dirId = 0) train arriving at G22S (Brooklyn platform)
        var tuNorth = TransitRealtime_TripUpdate()
        tuNorth.trip.directionID = 0
        let gNorthOnSouth = service.classifyDirection(tripUpdate: tuNorth, line: "G", stopId: "G22S")
        XCTAssertEqual(gNorthOnSouth.corridorVector, .northbound, "Tier 1 directionID=0 must override platform suffix S for G line")
        XCTAssertEqual(gNorthOnSouth.displayDirection, "Queens-bound")
        XCTAssertEqual(gNorthOnSouth.directionId, 0)
    }
    
    func testPreT2_SingleTrackingImmunity_TrunkReversePlatform() {
        let service = TransitRealtimeService.shared
        
        // Downtown 4 train (dirId = 1) arriving on 128N (Uptown platform)
        var tuSouth = TransitRealtime_TripUpdate()
        tuSouth.trip.directionID = 1
        let fourSouthOnNorth = service.classifyDirection(tripUpdate: tuSouth, line: "4", stopId: "128N")
        XCTAssertEqual(fourSouthOnNorth.corridorVector, .southbound, "Tier 1 directionID=1 must override platform suffix N on trunk lines")
        XCTAssertEqual(fourSouthOnNorth.displayDirection, "Downtown & Brooklyn")
        XCTAssertEqual(fourSouthOnNorth.directionId, 1)
        
        // Uptown 4 train (dirId = 0) arriving on 128S (Downtown platform)
        var tuNorth = TransitRealtime_TripUpdate()
        tuNorth.trip.directionID = 0
        let fourNorthOnSouth = service.classifyDirection(tripUpdate: tuNorth, line: "4", stopId: "128S")
        XCTAssertEqual(fourNorthOnSouth.corridorVector, .northbound, "Tier 1 directionID=0 must override platform suffix S on trunk lines")
        XCTAssertEqual(fourNorthOnSouth.displayDirection, "Uptown & Bronx")
        XCTAssertEqual(fourNorthOnSouth.directionId, 0)
    }
    
    func testPreT2_SingleTrackingImmunity_SIRReversePlatform() {
        let service = TransitRealtimeService.shared
        
        // Outbound Tottenville train (dirId = 1) departing from St George S31N (Inbound platform)
        var tuOutbound = TransitRealtime_TripUpdate()
        tuOutbound.trip.directionID = 1
        let sirOutOnNorth = service.classifyDirection(tripUpdate: tuOutbound, line: "SIR", stopId: "S31N")
        XCTAssertEqual(sirOutOnNorth.corridorVector, .outbound, "Tier 1 directionID=1 must override platform suffix N for SIR")
        XCTAssertEqual(sirOutOnNorth.displayDirection, "Outbound (Tottenville)")
        XCTAssertEqual(sirOutOnNorth.directionId, 1)
        
        // Inbound St George train (dirId = 0) arriving at Tottenville S09S (Outbound platform)
        var tuInbound = TransitRealtime_TripUpdate()
        tuInbound.trip.directionID = 0
        let sirInOnSouth = service.classifyDirection(tripUpdate: tuInbound, line: "SIR", stopId: "S09S")
        XCTAssertEqual(sirInOnSouth.corridorVector, .inbound, "Tier 1 directionID=0 must override platform suffix S for SIR")
        XCTAssertEqual(sirInOnSouth.displayDirection, "Inbound (St George)")
        XCTAssertEqual(sirInOnSouth.directionId, 0)
    }
    
    func testPreT2_Tier2HeadsignTerminalMatching_OverridesPlatformSuffix() {
        let service = TransitRealtimeService.shared
        let tuWithoutDir = TransitRealtime_TripUpdate() // hasDirectionID == false
        
        // L train with Canarsie terminal at L08N (platform N)
        let lCanarsieOnNorth = service.classifyDirection(
            tripUpdate: tuWithoutDir,
            line: "L",
            stopId: "L08N",
            terminalName: "Canarsie - Rockaway Pkwy"
        )
        XCTAssertEqual(lCanarsieOnNorth.corridorVector, .eastbound, "Tier 2 headsign matching must override platform suffix when directionID is absent")
        XCTAssertEqual(lCanarsieOnNorth.displayDirection, "Brooklyn-bound")
        XCTAssertEqual(lCanarsieOnNorth.directionId, 1)
        
        // 4 train with Brooklyn College terminal at 128N (platform N)
        let fourFlatbushOnNorth = service.classifyDirection(
            tripUpdate: tuWithoutDir,
            line: "4",
            stopId: "128N",
            terminalName: "Flatbush Ave - Brooklyn College"
        )
        XCTAssertEqual(fourFlatbushOnNorth.corridorVector, .southbound, "Tier 2 southern terminal matching must override platform suffix N")
        XCTAssertEqual(fourFlatbushOnNorth.displayDirection, "Downtown & Brooklyn")
        XCTAssertEqual(fourFlatbushOnNorth.directionId, 1)
    }
    
    func testPreT2_ArrivalInfoCanonicalDirectionStorage() {
        // Explicit directionId = 1 stored canonically
        let arr1 = SpatialDatabaseManager.ArrivalInfo(
            line: "L",
            destination: "Canarsie",
            minutes: 4,
            direction: "Brooklyn-bound",
            directionId: 1
        )
        XCTAssertEqual(arr1.directionId, 1)
        XCTAssertEqual(arr1.resolvedDirectionId, 1)
        
        // Explicit directionId = 0 stored canonically
        let arr0 = SpatialDatabaseManager.ArrivalInfo(
            line: "L",
            destination: "8th Ave",
            minutes: 2,
            direction: "Manhattan-bound",
            directionId: 0
        )
        XCTAssertEqual(arr0.directionId, 0)
        XCTAssertEqual(arr0.resolvedDirectionId, 0)
        
        // Fallback inference when directionId is nil
        let arrInferredSouth = SpatialDatabaseManager.ArrivalInfo(
            line: "4",
            destination: "Crown Hts",
            minutes: 6,
            direction: "Downtown & Brooklyn"
        )
        XCTAssertEqual(arrInferredSouth.directionId, 1)
        XCTAssertEqual(arrInferredSouth.resolvedDirectionId, 1)
        
        let arrInferredNorth = SpatialDatabaseManager.ArrivalInfo(
            line: "4",
            destination: "Woodlawn",
            minutes: 3,
            direction: "Uptown & Bronx"
        )
        XCTAssertEqual(arrInferredNorth.directionId, 0)
        XCTAssertEqual(arrInferredNorth.resolvedDirectionId, 0)
    }
    
    // MARK: - 8. Wave Pre-T.3: Gated Terminal Arrival Suppression & Short-Turn Safety
    
    func testPreT3_VettedTerminals_StandardTerminalCompleteness() {
        // Assert vetted terminal detection
        XCTAssertTrue(SubwayStationRegistry.isVettedTerminalStop("601"), "Pelham Bay Park (601) must be recognized as vetted terminal")
        XCTAssertTrue(SubwayStationRegistry.isVettedTerminalStop("640"), "Brooklyn Bridge (640) must be recognized as vetted terminal")
        XCTAssertTrue(SubwayStationRegistry.isVettedTerminalStop("142"), "South Ferry (142) must be recognized as vetted terminal")
        XCTAssertTrue(SubwayStationRegistry.isVettedTerminalStop("701"), "Flushing-Main St (701) must be recognized as vetted terminal")
        XCTAssertTrue(SubwayStationRegistry.isVettedTerminalStop("726"), "34 St-Hudson Yards (726) must be recognized as vetted terminal")
        XCTAssertTrue(SubwayStationRegistry.isVettedTerminalStop("L01"), "8 Av (L01) must be recognized as vetted terminal")
        XCTAssertTrue(SubwayStationRegistry.isVettedTerminalStop("L29"), "Canarsie-Rockaway Pkwy (L29) must be recognized as vetted terminal")
        XCTAssertTrue(SubwayStationRegistry.isVettedTerminalStop("S31"), "St George (S31) must be recognized as vetted terminal")
        XCTAssertTrue(SubwayStationRegistry.isVettedTerminalStop("S09"), "Tottenville (S09) must be recognized as vetted terminal")
        
        // Assert direction-aware termination
        XCTAssertTrue(SubwayStationRegistry.isTerminatingDirection(stopId: "601", route: "6", directionId: 0), "Uptown 6 terminates at 601")
        XCTAssertFalse(SubwayStationRegistry.isTerminatingDirection(stopId: "601", route: "6", directionId: 1), "Downtown 6 departs from 601")
        XCTAssertTrue(SubwayStationRegistry.isTerminatingDirection(stopId: "142", route: "1", directionId: 1), "Downtown 1 terminates at 142")
        XCTAssertFalse(SubwayStationRegistry.isTerminatingDirection(stopId: "142", route: "1", directionId: 0), "Uptown 1 departs from 142")
        
        // Assert intermediate stations are NOT vetted terminals
        XCTAssertFalse(SubwayStationRegistry.isVettedTerminalStop("608"), "Parkchester (608) must NOT be a vetted terminal")
        XCTAssertFalse(SubwayStationRegistry.isVettedTerminalStop("611"), "Elder Av (611) must NOT be a vetted terminal")
        XCTAssertFalse(SubwayStationRegistry.isVettedTerminalStop("635"), "Union Sq (635) must NOT be a vetted terminal")
        XCTAssertFalse(SubwayStationRegistry.isVettedTerminalStop("631"), "Grand Central (631) must NOT be a vetted terminal")
        XCTAssertFalse(SubwayStationRegistry.isTerminatingDirection(stopId: "608", route: "6", directionId: 0), "Parkchester cannot be terminating direction for 6")
        XCTAssertFalse(SubwayStationRegistry.isTerminatingDirection(stopId: "608", route: "6", directionId: 1), "Parkchester cannot be terminating direction for 6")
    }
    
    func testPreT3_PelhamBayPark_NorthboundArrivalSuppression() throws {
        let service = TransitRealtimeService.shared
        let refDate = Date(timeIntervalSince1970: 1720000000)
        
        // Construct mock feed message with:
        // 1. Terminating arrival at Pelham Bay Park (601N): Northbound 6 train arriving at 601N (idx == count - 1)
        // 2. Outgoing departure from Pelham Bay Park (601S): Southbound 6 train departing 601S (idx == 0) heading to Brooklyn Bridge
        var feed = TransitRealtime_FeedMessage()
        var header = TransitRealtime_FeedHeader()
        header.gtfsRealtimeVersion = "2.0"
        header.timestamp = UInt64(refDate.timeIntervalSince1970)
        feed.header = header
        
        // Entity 1: Inbound terminating arrival (6 to Pelham Bay Park EXP)
        var entity1 = TransitRealtime_FeedEntity()
        entity1.id = "TRIP_TERMINATING_601"
        var tu1 = TransitRealtime_TripUpdate()
        tu1.trip.tripID = "6_ARRIVING_AT_PELHAM"
        tu1.trip.routeID = "6"
        tu1.trip.directionID = 0
        
        var stu1 = TransitRealtime_TripUpdate.StopTimeUpdate()
        stu1.stopID = "601N"
        stu1.arrival = TransitRealtime_TripUpdate.StopTimeEvent()
        stu1.arrival.time = Int64(refDate.timeIntervalSince1970 + 120) // In 2 min
        tu1.stopTimeUpdate = [stu1] // idx == 0 and count == 1, so idx == count - 1
        entity1.tripUpdate = tu1
        
        // Entity 2: Outgoing departure (6 to Brooklyn Bridge)
        var entity2 = TransitRealtime_FeedEntity()
        entity2.id = "TRIP_DEPARTING_601"
        var tu2 = TransitRealtime_TripUpdate()
        tu2.trip.tripID = "6_DEPARTING_FROM_PELHAM"
        tu2.trip.routeID = "6"
        tu2.trip.directionID = 1
        
        var stu2_origin = TransitRealtime_TripUpdate.StopTimeUpdate()
        stu2_origin.stopID = "601S"
        stu2_origin.departure = TransitRealtime_TripUpdate.StopTimeEvent()
        stu2_origin.departure.time = Int64(refDate.timeIntervalSince1970 + 300) // In 5 min
        
        var stu2_dest = TransitRealtime_TripUpdate.StopTimeUpdate()
        stu2_dest.stopID = "640S"
        stu2_dest.arrival = TransitRealtime_TripUpdate.StopTimeEvent()
        stu2_dest.arrival.time = Int64(refDate.timeIntervalSince1970 + 3600)
        tu2.stopTimeUpdate = [stu2_origin, stu2_dest]
        entity2.tripUpdate = tu2
        
        feed.entity = [entity1, entity2]
        let data = try feed.serializedData()
        
        let arrivals = try service.parseFeedMessage(
            data: data,
            stopId: "601",
            targetRouteId: "6",
            targetRouteIds: ["6"],
            referenceDate: refDate
        )
        
        // Assert: The terminating arrival in direction 0 (Uptown) MUST be suppressed!
        XCTAssertFalse(
            arrivals.contains(where: { $0.directionId == 0 }),
            "Terminating arrival at Pelham Bay Park (601) in Direction 0 must be suppressed from departures"
        )
        XCTAssertFalse(
            arrivals.contains(where: { $0.destination.lowercased().contains("pelham") }),
            "Arrivals terminating at Pelham Bay Park must not appear on departure board"
        )
        
        // Assert: The outgoing departure in direction 1 (Downtown) MUST be retained!
        let departures = arrivals.filter { $0.directionId == 1 }
        XCTAssertEqual(departures.count, 1, "Outgoing Southbound departure from Pelham Bay Park must be retained")
        XCTAssertTrue(
            departures.first?.destination.contains("Brooklyn Bridge") == true,
            "Departure destination must reflect Brooklyn Bridge"
        )
    }
    
    func testPreT3_Parkchester_ShortTurnAndFeedWindowProtection() throws {
        let service = TransitRealtimeService.shared
        let refDate = Date(timeIntervalSince1970: 1720000000)
        
        // Construct mock feed at intermediate station Parkchester (608):
        // 1. Short-turn 6 train ending at Parkchester (idx == count - 1, destination matches Parkchester)
        var feed = TransitRealtime_FeedMessage()
        var header = TransitRealtime_FeedHeader()
        header.gtfsRealtimeVersion = "2.0"
        header.timestamp = UInt64(refDate.timeIntervalSince1970)
        feed.header = header
        
        // Entity 1: Short-turn 6 train ending at Parkchester (608N)
        var entity1 = TransitRealtime_FeedEntity()
        entity1.id = "TRIP_SHORT_TURN_608"
        var tu1 = TransitRealtime_TripUpdate()
        tu1.trip.tripID = "6_SHORT_TURN_PARKCHESTER"
        tu1.trip.routeID = "6"
        tu1.trip.directionID = 0
        
        var stu1 = TransitRealtime_TripUpdate.StopTimeUpdate()
        stu1.stopID = "608N"
        stu1.arrival = TransitRealtime_TripUpdate.StopTimeEvent()
        stu1.arrival.time = Int64(refDate.timeIntervalSince1970 + 180)
        tu1.stopTimeUpdate = [stu1] // idx == 0, count == 1, so idx == count - 1
        entity1.tripUpdate = tu1
        
        feed.entity = [entity1]
        let data = try feed.serializedData()
        
        let arrivals = try service.parseFeedMessage(
            data: data,
            stopId: "608",
            targetRouteId: "6",
            targetRouteIds: ["6"],
            referenceDate: refDate
        )
        
        // Invariant: At intermediate non-terminal stations like Parkchester (608),
        // short-turns MUST NOT be suppressed, because Parkchester is not a vetted terminal!
        XCTAssertEqual(
            arrivals.count, 1,
            "Short-turn 6 train at Parkchester (608) must NOT be suppressed by terminal gating rule"
        )
        XCTAssertEqual(arrivals.first?.directionId, 0)
    }
}
