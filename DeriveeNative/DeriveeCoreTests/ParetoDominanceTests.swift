import XCTest
@testable import DeriveeCore

final class ParetoDominanceTests: XCTestCase {
    
    func testParetoStrictDominance() {
        // Label A is strictly better in all dimensions compared to Label B
        let labelA = ParetoLabel(3600, 1, 400, 10)
        let labelB = ParetoLabel(3800, 2, 500, 12)
        
        XCTAssertTrue(labelA.dominates(labelB))
        XCTAssertFalse(labelB.dominates(labelA))
    }
    
    func testParetoWeakDominance() {
        // Label A matches Label B in 3 dimensions but is strictly better in 1
        let labelA = ParetoLabel(3600, 1, 400, 10)
        let labelB = ParetoLabel(3600, 1, 500, 10) // 100m longer walk
        
        XCTAssertTrue(labelA.dominates(labelB))
        XCTAssertFalse(labelB.dominates(labelA))
    }
    
    func testParetoIdenticalNonDominance() {
        // Identical labels do not dominate each other (must be strictly better in >=1 dimension)
        let labelA = ParetoLabel(3600, 1, 400, 10)
        let labelB = ParetoLabel(3600, 1, 400, 10)
        
        XCTAssertFalse(labelA.dominates(labelB))
        XCTAssertFalse(labelB.dominates(labelA))
    }
    
    func testParetoMultiCriteriaTradeOff() {
        // Label A: earlier arrival, but more transfers
        // Label C: later arrival, but zero transfers (direct trip)
        let labelA = ParetoLabel(3400, 2, 400, 20)
        let labelC = ParetoLabel(3600, 0, 400, 10)
        
        // Neither label dominates the other; both are Pareto optimal trade-offs
        XCTAssertFalse(labelA.dominates(labelC))
        XCTAssertFalse(labelC.dominates(labelA))
    }
}
