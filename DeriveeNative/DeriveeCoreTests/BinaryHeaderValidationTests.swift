import XCTest
@testable import DeriveeCore

final class BinaryHeaderValidationTests: XCTestCase {
    
    func testConstantsMatchResearchSpec() {
        XCTAssertEqual(observer.format.MAGIC_TIMETABLE, 0x31565244, "MAGIC_TIMETABLE must be 'DRV1'")
        XCTAssertEqual(observer.format.MAGIC_ULTRA_TRANSFERS, 0x41525455, "MAGIC_ULTRA_TRANSFERS must be 'UTRA'")
        XCTAssertEqual(observer.format.MAGIC_WALK_GRAPH, 0x4B4C4157, "MAGIC_WALK_GRAPH must be 'WALK'")
        XCTAssertEqual(observer.format.MAGIC_WALK_OFFSETS, 0x53464F57, "MAGIC_WALK_OFFSETS must be 'WOFS'")
        XCTAssertEqual(observer.format.MAGIC_WALK_EDGES, 0x47444557, "MAGIC_WALK_EDGES must be 'WEDG'")
        XCTAssertEqual(observer.format.MAGIC_WALK_RTREE, 0x54524C57, "MAGIC_WALK_RTREE must be 'WLRT'")
        XCTAssertEqual(observer.format.ENDIAN_MARKER, 0x01020304, "ENDIAN_MARKER must be 0x01020304")
        XCTAssertEqual(observer.format.MASTER_HEADER_SIZE, 232, "Master header must be 232 bytes")
        
        XCTAssertEqual(MemoryLayout<observer.format.RTreeNodeItem>.size, 24, "RTreeNodeItem must be exactly 24 bytes")
        XCTAssertEqual(MemoryLayout<observer.format.RTreeMetadata>.size, 32, "RTreeMetadata must be exactly 32 bytes")
    }
    
    func testHeaderConstructionAndOffsets() {
        var header = observer.format.MasterHeader()
        header.magic = observer.format.MAGIC_TIMETABLE
        header.schema_version = 1
        header.endian_marker = observer.format.ENDIAN_MARKER
        header.header_size = 232
        header.file_size = 1024
        header.num_sections = 2
        
        // TOC section 0: Stops at offset 256 (64-byte aligned)
        header.toc[0] = observer.format.SectionDesc(256, 240, 10)
        // TOC section 1: Routes at offset 496
        header.toc[1] = observer.format.SectionDesc(496, 120, 10)
        
        XCTAssertEqual(header.magic, observer.format.MAGIC_TIMETABLE)
        XCTAssertEqual(header.schema_version, 1)
        XCTAssertEqual(header.toc[0].offset, 256)
        XCTAssertEqual(header.toc[0].item_count, 10)
        XCTAssertEqual(header.toc[1].offset, 496)
        XCTAssertEqual(header.toc[1].item_count, 10)
    }
}
