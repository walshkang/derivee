import Foundation
import SwiftUI
import Observation

/// Observation-powered View Model managing multi-profile route comparison,
/// sorting strategies, deterministic multimodal test fixtures, and active journey selection.
@Observable
@MainActor
public final class RouteComparisonViewModel {
    public var selectedProfile: RoutingProfile = .mostReliable {
        didSet {
            recalculateFilteredJourneys()
        }
    }
    
    public var allJourneys: [JourneyItinerary] = []
    public var filteredJourneys: [JourneyItinerary] = []
    public var selectedItineraryId: UUID?
    public var isLoading: Bool = false
    public var executionLatencyMs: Double = 0.0
    
    public var originName: String = "Astor Place"
    public var destinationName: String = "Grand Central - 42 St"
    public var originLocation: RoutingLocation?
    public var destinationLocation: RoutingLocation?
    
    public private(set) var bridge: RoutingEngineBridge?
    public private(set) var planner: JourneyPlanner?
    
    public var selectedItinerary: JourneyItinerary? {
        guard let id = selectedItineraryId else {
            return filteredJourneys.first
        }
        return filteredJourneys.first(where: { $0.id == id }) ?? filteredJourneys.first
    }
    
    public init(
        bridge: RoutingEngineBridge? = nil,
        planner: JourneyPlanner? = nil,
        journeys: [JourneyItinerary]? = nil
    ) {
        self.planner = planner
        self.bridge = bridge ?? planner?.bridge
        if let custom = journeys {
            self.allJourneys = custom
            self.recalculateFilteredJourneys()
        } else {
            self.loadDefaultFixtures()
        }
    }
    
    // MARK: - Live Search via RoutingEngineBridge / JourneyPlanner
    
    /// Executes an async transit routing query via the injected JourneyPlanner or RoutingEngineBridge.
    public func searchJourneys(
        origin: RoutingLocation,
        destination: RoutingLocation,
        departureTime: Date = Date(),
        options: RoutingOptions = .default
    ) async {
        self.originLocation = origin
        self.destinationLocation = destination
        self.originName = origin.displayName
        self.destinationName = destination.displayName
        
        if let planner = self.planner, planner.isReady {
            let results = await planner.planJourneys(
                origin: origin,
                destination: destination,
                departureTime: departureTime,
                profile: selectedProfile,
                options: options
            )
            self.executionLatencyMs = planner.executionLatencyMs
            if !results.isEmpty {
                self.allJourneys = results
                self.recalculateFilteredJourneys()
            }
            return
        }
        
        guard let bridge = self.bridge, await bridge.isLoaded else {
            // If bridge is not loaded or unavailable, preserve or refresh default fixtures
            return
        }
        
        self.isLoading = true
        let startTime = CFAbsoluteTimeGetCurrent()
        
        let results = await bridge.computeJourneys(
            origin: origin,
            destination: destination,
            departureTime: departureTime,
            profile: selectedProfile,
            options: options
        )
        
        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
        self.executionLatencyMs = elapsed
        self.isLoading = false
        
        if !results.isEmpty {
            self.allJourneys = results
            self.recalculateFilteredJourneys()
        }
    }

    
    // MARK: - Profile Filtering & Sorting Logic
    
    public func selectProfile(_ profile: RoutingProfile) {
        self.selectedProfile = profile
    }
    
    public func selectItinerary(id: UUID) {
        self.selectedItineraryId = id
    }
    
    public func recalculateFilteredJourneys() {
        switch selectedProfile {
        case .mostReliable:
            // Sort by arrival uncertainty (P90 - P10) ascending, then by arrival time
            filteredJourneys = allJourneys.sorted { a, b in
                if a.uncertaintyMinutes == b.uncertaintyMinutes {
                    return a.arrivalTimeSec < b.arrivalTimeSec
                }
                return a.uncertaintyMinutes < b.uncertaintyMinutes
            }
            
        case .fastest:
            // Sort by earliest raw arrival time ascending
            filteredJourneys = allJourneys.sorted { a, b in
                a.arrivalTimeSec < b.arrivalTimeSec
            }
            
        case .fewestTransfers:
            // Sort by fewest transfers ascending, then by arrival time
            filteredJourneys = allJourneys.sorted { a, b in
                if a.transferCount == b.transferCount {
                    return a.arrivalTimeSec < b.arrivalTimeSec
                }
                return a.transferCount < b.transferCount
            }
            
        case .stepFree:
            // Filter to step-free accessible itineraries (no stairs, only elevator/ramp stations)
            let stepFreeRoutes = allJourneys.filter { itinerary in
                itinerary.profile == .stepFree || !itinerary.legs.contains(where: { $0.isTransferWalk && $0.distanceMeters > 300 })
            }
            filteredJourneys = (stepFreeRoutes.isEmpty ? allJourneys : stepFreeRoutes).sorted { a, b in
                a.arrivalTimeSec < b.arrivalTimeSec
            }
            
        case .multiModalBikeRail:
            // Prioritize journeys with bike-share or micro-mobility legs
            filteredJourneys = allJourneys.sorted { a, b in
                let aHasBike = a.bikingDistanceMeters > 0
                let bHasBike = b.bikingDistanceMeters > 0
                if aHasBike != bHasBike {
                    return aHasBike && !bHasBike
                }
                return a.arrivalTimeSec < b.arrivalTimeSec
            }
        }
        
        // Preserve or auto-select top candidate
        if let currentId = selectedItineraryId, filteredJourneys.contains(where: { $0.id == currentId }) {
            // Keep current selection
        } else {
            selectedItineraryId = filteredJourneys.first?.id
        }
    }
    
    // MARK: - NYC Realistic Multimodal Fixtures
    
    public func loadDefaultFixtures() {
        let baseDepTime: UInt32 = 31320 // 8:42 AM (31,320 seconds past midnight)
        
        // 1. Direct Subway 6 (Most Reliable & Direct)
        let directSubwayLegs = [
            JourneyLeg(
                mode: .walk,
                originName: "Astor Place & 4th Ave",
                destinationName: "Astor Pl Station",
                departureTimeSec: baseDepTime,
                arrivalTimeSec: baseDepTime + 120, // +2m
                distanceMeters: 140,
                landmarkCue: "Enter subway entrance next to Kmart plaza",
                exitCode: "Exit NE"
            ),
            JourneyLeg(
                mode: .subway,
                originName: "Astor Pl",
                destinationName: "Grand Central - 42 St",
                departureTimeSec: baseDepTime + 180, // 3m wait
                arrivalTimeSec: baseDepTime + 780,  // 10m ride (8:55 AM)
                routeId: "6",
                headsign: "Uptown & The Bronx",
                stopCount: 5,
                confidenceTier: .verified,
                recommendedCarPosition: "Board middle car (Cars 4–6) for direct 42nd St exits"
            ),
            JourneyLeg(
                mode: .walk,
                originName: "Grand Central - 42 St Platform",
                destinationName: "Grand Central Terminal",
                departureTimeSec: baseDepTime + 780,
                arrivalTimeSec: baseDepTime + 900, // +2m
                distanceMeters: 160,
                exitCode: "Exit 4B - NW Corner 42nd & Lexington Ave"
            )
        ]
        
        let directSubwayItinerary = JourneyItinerary(
            profile: .mostReliable,
            departureTimeSec: baseDepTime,
            arrivalTimeSec: baseDepTime + 900, // 8:57 AM (15m total)
            p10ArrivalSec: baseDepTime + 840,  // 8:56 AM
            p50ArrivalSec: baseDepTime + 900,  // 8:57 AM
            p90ArrivalSec: baseDepTime + 1020, // 8:59 AM (±1.5m)
            totalCost: 2.90,
            legs: directSubwayLegs,
            disruptions: [],
            confidenceTier: .verified
        )
        
        // 2. Express Transfer: 6 -> 4/5 at 14th St-Union Sq (Fastest)
        let expressTransferLegs = [
            JourneyLeg(
                mode: .walk,
                originName: "Astor Place",
                destinationName: "Astor Pl Station",
                departureTimeSec: baseDepTime,
                arrivalTimeSec: baseDepTime + 120,
                distanceMeters: 140
            ),
            JourneyLeg(
                mode: .subway,
                originName: "Astor Pl",
                destinationName: "14 St - Union Sq",
                departureTimeSec: baseDepTime + 180,
                arrivalTimeSec: baseDepTime + 300, // 2m ride
                routeId: "6",
                headsign: "Uptown",
                stopCount: 1,
                confidenceTier: .verified,
                recommendedCarPosition: "Board front car for cross-platform express"
            ),
            JourneyLeg(
                mode: .walk,
                originName: "14 St - Union Sq Local Platform",
                destinationName: "14 St - Union Sq Express Platform",
                departureTimeSec: baseDepTime + 300,
                arrivalTimeSec: baseDepTime + 360, // 1m cross-platform transfer
                distanceMeters: 30,
                isTransferWalk: true
            ),
            JourneyLeg(
                mode: .subway,
                originName: "14 St - Union Sq",
                destinationName: "Grand Central - 42 St",
                departureTimeSec: baseDepTime + 420,
                arrivalTimeSec: baseDepTime + 660, // 4m express ride
                routeId: "4",
                headsign: "Woodlawn",
                stopCount: 1,
                confidenceTier: .verified,
                recommendedCarPosition: "Board middle car"
            ),
            JourneyLeg(
                mode: .walk,
                originName: "Grand Central Platform",
                destinationName: "Grand Central Main Concourse",
                departureTimeSec: baseDepTime + 660,
                arrivalTimeSec: baseDepTime + 780, // +2m
                distanceMeters: 160,
                exitCode: "Exit 4B"
            )
        ]
        
        let expressItinerary = JourneyItinerary(
            profile: .fastest,
            departureTimeSec: baseDepTime,
            arrivalTimeSec: baseDepTime + 780, // 8:55 AM (13m total)
            p10ArrivalSec: baseDepTime + 720,  // 8:54 AM
            p50ArrivalSec: baseDepTime + 780,  // 8:55 AM
            p90ArrivalSec: baseDepTime + 960,  // 8:58 AM (±2m)
            totalCost: 2.90,
            legs: expressTransferLegs,
            disruptions: [],
            confidenceTier: .verified
        )
        
        // 3. Multimodal: Citi Bike E-Bike + 4 Express at Union Sq (Bike + Rail)
        let bikeMetadata = BikeLegMetadata(
            originStationName: "Lafayette St & E 8th St",
            destinationStationName: "Broadway & E 14th St (Union Sq)",
            availableBikesAtOrigin: 7,
            availableDocksAtDest: 12,
            isEBike: true,
            batterySocPercent: 92,
            estimatedRangeMiles: 18.0,
            dockGatingRisk: .low
        )
        
        let bikeRailLegs = [
            JourneyLeg(
                mode: .walk,
                originName: "Origin",
                destinationName: "Citi Bike: Lafayette St & E 8th St",
                departureTimeSec: baseDepTime,
                arrivalTimeSec: baseDepTime + 60, // 1m walk
                distanceMeters: 60
            ),
            JourneyLeg(
                mode: .bikeShare,
                originName: "Lafayette St & E 8th St",
                destinationName: "Broadway & E 14th St",
                departureTimeSec: baseDepTime + 90,
                arrivalTimeSec: baseDepTime + 270, // 3m bike ride
                distanceMeters: 750,
                bikeMetadata: bikeMetadata
            ),
            JourneyLeg(
                mode: .walk,
                originName: "Broadway & E 14th St Dock",
                destinationName: "14 St - Union Sq Subway",
                departureTimeSec: baseDepTime + 270,
                arrivalTimeSec: baseDepTime + 360,
                distanceMeters: 80,
                isTransferWalk: true
            ),
            JourneyLeg(
                mode: .subway,
                originName: "14 St - Union Sq",
                destinationName: "Grand Central - 42 St",
                departureTimeSec: baseDepTime + 420,
                arrivalTimeSec: baseDepTime + 660,
                routeId: "5",
                headsign: "Eastchester - Dyre Av",
                stopCount: 1,
                confidenceTier: .verified
            ),
            JourneyLeg(
                mode: .walk,
                originName: "Grand Central",
                destinationName: "Main Concourse",
                departureTimeSec: baseDepTime + 660,
                arrivalTimeSec: baseDepTime + 780,
                distanceMeters: 160
            )
        ]
        
        let bikeRailItinerary = JourneyItinerary(
            profile: .multiModalBikeRail,
            departureTimeSec: baseDepTime,
            arrivalTimeSec: baseDepTime + 780, // 8:55 AM
            p10ArrivalSec: baseDepTime + 720,
            p50ArrivalSec: baseDepTime + 780,
            p90ArrivalSec: baseDepTime + 900,
            totalCost: 4.95, // $2.05 Citi Bike + $2.90 MTA
            legs: bikeRailLegs,
            disruptions: [],
            confidenceTier: .verified
        )
        
        // 4. Step-Free Accessible Route (Elevator-Equipped Stations)
        let stepFreeLegs = [
            JourneyLeg(
                mode: .walk,
                originName: "Astor Place",
                destinationName: "Astor Pl Station Elevator",
                departureTimeSec: baseDepTime,
                arrivalTimeSec: baseDepTime + 180,
                distanceMeters: 200,
                landmarkCue: "Use street elevator at 8th St & Lafayette"
            ),
            JourneyLeg(
                mode: .subway,
                originName: "Astor Pl",
                destinationName: "Grand Central - 42 St",
                departureTimeSec: baseDepTime + 240,
                arrivalTimeSec: baseDepTime + 840,
                routeId: "6",
                headsign: "Pelham Bay Park",
                stopCount: 5,
                confidenceTier: .verified,
                recommendedCarPosition: "Board Car 2 for Grand Central street elevator access"
            ),
            JourneyLeg(
                mode: .walk,
                originName: "Grand Central Accessible Exit",
                destinationName: "Grand Central Terminal Concourse",
                departureTimeSec: baseDepTime + 840,
                arrivalTimeSec: baseDepTime + 990,
                distanceMeters: 180,
                exitCode: "Elevator to Street Level (Pershing Square)"
            )
        ]
        
        let stepFreeItinerary = JourneyItinerary(
            profile: .stepFree,
            departureTimeSec: baseDepTime,
            arrivalTimeSec: baseDepTime + 990, // 8:58 AM (16.5m total)
            p10ArrivalSec: baseDepTime + 900,
            p50ArrivalSec: baseDepTime + 990,
            p90ArrivalSec: baseDepTime + 1080,
            totalCost: 2.90,
            legs: stepFreeLegs,
            disruptions: [],
            confidenceTier: .verified
        )
        
        // 5. Route with Service Disruption Alert (M15-SBS Bus Fallback)
        let busDisruption = JourneyDisruption(
            routeId: "M15-SBS",
            affectedStopIds: ["10023", "10024"],
            severity: .minorDelay,
            headline: "Traffic Congestion on 1st Ave",
            detailText: "M15-SBS experiencing +5m delays due to construction near 23rd St.",
            isActionable: true,
            rerouteSuggested: true
        )
        
        let busLegs = [
            JourneyLeg(
                mode: .walk,
                originName: "Astor Place",
                destinationName: "1st Ave & E 9th St",
                departureTimeSec: baseDepTime,
                arrivalTimeSec: baseDepTime + 360,
                distanceMeters: 420,
                landmarkCue: "Walk east along St Marks Pl"
            ),
            JourneyLeg(
                mode: .bus,
                originName: "1st Ave & E 9th St",
                destinationName: "1st Ave & E 42nd St",
                departureTimeSec: baseDepTime + 480,
                arrivalTimeSec: baseDepTime + 1380, // 15m bus ride
                routeId: "M15-SBS",
                headsign: "125 St Select Bus",
                stopCount: 7,
                confidenceTier: .estimated,
                disruption: busDisruption
            ),
            JourneyLeg(
                mode: .walk,
                originName: "1st Ave & E 42nd St",
                destinationName: "Grand Central Terminal",
                departureTimeSec: baseDepTime + 1380,
                arrivalTimeSec: baseDepTime + 1800,
                distanceMeters: 550
            )
        ]
        
        let busItinerary = JourneyItinerary(
            profile: .fewestTransfers,
            departureTimeSec: baseDepTime,
            arrivalTimeSec: baseDepTime + 1800, // 9:12 AM (30m)
            p10ArrivalSec: baseDepTime + 1680,
            p50ArrivalSec: baseDepTime + 1800,
            p90ArrivalSec: baseDepTime + 2100, // ±3.5m uncertainty
            totalCost: 2.90,
            legs: busLegs,
            disruptions: [busDisruption],
            confidenceTier: .estimated
        )
        
        self.allJourneys = [
            directSubwayItinerary,
            expressItinerary,
            bikeRailItinerary,
            stepFreeItinerary,
            busItinerary
        ]
        
        self.recalculateFilteredJourneys()
    }
}
