import XCTest
import CxxStdlib
@testable import DeriveeCore

final class ParetoDominanceTests: XCTestCase {
    
    func testPareto4DStrictDominance() {
        // Label A is strictly better in all dimensions compared to Label B
        let labelA = ParetoLabel(3600, 1, 400, 10)
        let labelB = ParetoLabel(3800, 2, 500, 12)
        
        XCTAssertTrue(labelA.dominates(labelB))
        XCTAssertFalse(labelB.dominates(labelA))
    }
    
    func testPareto4DWeakDominance() {
        // Label A matches Label B in 3 dimensions but is strictly better in 1
        let labelA = ParetoLabel(3600, 1, 400, 10)
        let labelB = ParetoLabel(3600, 1, 500, 10) // 100m longer walk
        
        XCTAssertTrue(labelA.dominates(labelB))
        XCTAssertFalse(labelB.dominates(labelA))
    }
    
    func testPareto4DIdenticalNonDominance() {
        // Identical labels do not dominate each other (must be strictly better in >=1 dimension)
        let labelA = ParetoLabel(3600, 1, 400, 10)
        let labelB = ParetoLabel(3600, 1, 400, 10)
        
        XCTAssertFalse(labelA.dominates(labelB))
        XCTAssertFalse(labelB.dominates(labelA))
    }
    
    func testPareto4DMultiCriteriaTradeOff() {
        // Label A: earlier arrival, but more transfers
        // Label C: later arrival, but zero transfers (direct trip)
        let labelA = ParetoLabel(3400, 2, 400, 20)
        let labelC = ParetoLabel(3600, 0, 400, 10)
        
        // Neither label dominates the other; both are Pareto optimal trade-offs
        XCTAssertFalse(labelA.dominates(labelC))
        XCTAssertFalse(labelC.dominates(labelA))
    }

    func testPareto5DCostDominance() {
        // 5D Cost vector: (arrival_time, transfer_count, effort_duration, layover_penalty, variance_disutility)
        let costA = ParetoCost(3600, 1, 180, 10, 5)
        let costB = ParetoCost(3800, 2, 240, 50, 12) // strictly worse in all 5 criteria
        let costC = ParetoCost(3600, 1, 180, 10, 5)  // identical

        XCTAssertTrue(costA.dominates(costB))
        XCTAssertFalse(costB.dominates(costA))
        XCTAssertFalse(costA.dominates(costC))
        XCTAssertFalse(costC.dominates(costA))

        // Weak dominance in single criterion
        let costD = ParetoCost(3600, 1, 180, 10, 8) // only worse in variance
        XCTAssertTrue(costA.dominates(costD))
        XCTAssertFalse(costD.dominates(costA))
    }

    func testParetoSetInsertionAndPruning() {
        var set = ParetoSet()
        XCTAssertTrue(set.empty())
        XCTAssertEqual(set.size(), 0)

        // Option 1: Fast journey with 1 transfer
        let cost1 = ParetoCost(3600, 1, 120, 15, 10)
        let journey1 = ParetoJourney(cost1, 3000, [])
        XCTAssertTrue(set.insert(journey1))
        XCTAssertEqual(set.size(), 1)

        // Option 2: Dominated journey (slower, more transfers, more effort) -> should be rejected
        let costDominated = ParetoCost(3900, 2, 300, 80, 25)
        let journeyDominated = ParetoJourney(costDominated, 3000, [])
        XCTAssertFalse(set.insert(journeyDominated), "Dominated journey must be rejected")
        XCTAssertEqual(set.size(), 1)

        // Option 3: Direct journey (zero transfers) but arrives later -> non-dominated trade-off
        let costDirect = ParetoCost(3750, 0, 0, 0, 5)
        let journeyDirect = ParetoJourney(costDirect, 3100, [])
        XCTAssertTrue(set.insert(journeyDirect), "Non-dominated direct journey must be accepted")
        XCTAssertEqual(set.size(), 2)

        // Option 4: Superior journey that dominates Option 1 (faster arrival, same transfer, lower penalty)
        let costSuperior = ParetoCost(3500, 1, 100, 10, 8)
        let journeySuperior = ParetoJourney(costSuperior, 3050, [])
        XCTAssertTrue(set.insert(journeySuperior))
        // Option 1 should have been evicted, leaving Option 4 and Option 3 (direct)
        XCTAssertEqual(set.size(), 2)
        XCTAssertEqual(set[0].cost.arrival_time_sec, 3750)
        XCTAssertEqual(set[1].cost.arrival_time_sec, 3500)
    }
}
