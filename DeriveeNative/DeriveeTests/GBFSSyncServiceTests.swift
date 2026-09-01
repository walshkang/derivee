import XCTest
import CoreLocation
@testable import Derivee

// MARK: - Mock URL Protocol for GBFS Tests

final class MockGBFSURLProtocol: URLProtocol {
    static var mockHandlers: [String: (URLRequest) throws -> (HTTPURLResponse, Data)] = [:]
    
    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }
    
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }
    
    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        
        let path = url.absoluteString
        let handler = MockGBFSURLProtocol.mockHandlers.first { path.contains($0.key) }?.value
        
        if let handler = handler {
            do {
                let (response, data) = try handler(request)
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        } else {
            let errorResponse = HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: errorResponse, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data())
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    
    override func stopLoading() {}
}

final class GBFSSyncServiceTests: XCTestCase {
    var dbManager: GBFSDatabaseManager!
    var session: URLSession!
    var service: GBFSSyncService!
    
    override func setUpWithError() throws {
        super.setUp()
        MockGBFSURLProtocol.mockHandlers.removeAll()
        
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockGBFSURLProtocol.self]
        session = URLSession(configuration: config)
        
        dbManager = GBFSDatabaseManager.makeForTesting(inMemory: true)
        
        let gbfsConfig = GBFSConfig(
            systemId: "test_citi_bike",
            stationInfoUrl: "https://mock.gbfs/station_information.json",
            stationStatusUrl: "https://mock.gbfs/station_status.json",
            pollIntervalSeconds: 1.0,
            stalenessThresholdSeconds: 600.0
        )
        
        service = GBFSSyncService.makeForTesting(
            config: gbfsConfig,
            databaseManager: dbManager,
            session: session
        )
    }
    
    override func tearDown() async throws {
        if let s = service {
            await s.stopPolling()
        }
        MockGBFSURLProtocol.mockHandlers.removeAll()
        dbManager?.releaseMemory()
        session = nil
        dbManager = nil
        service = nil
        try await super.tearDown()
    }
    
    // MARK: - Ingestion & HTTP Lifecycle Tests
    
    func testFetchAndIngest200OK() async throws {
        let infoJSON = """
        {
            "last_updated": 1725000000,
            "ttl": 60,
            "data": {
                "stations": [
                    {
                        "station_id": "MOCK_S1",
                        "name": "Columbus Circle",
                        "lat": 40.7680,
                        "lon": -73.9819,
                        "capacity": 50,
                        "has_kiosk": true
                    }
                ]
            }
        }
        """.data(using: .utf8)!
        
        let statusJSON = """
        {
            "last_updated": 1725000000,
            "ttl": 30,
            "data": {
                "stations": [
                    {
                        "station_id": "MOCK_S1",
                        "num_bikes_available": 15,
                        "num_ebikes_available": 6,
                        "num_docks_available": 35,
                        "is_installed": 1,
                        "is_renting": 1,
                        "is_returning": 1,
                        "last_reported": 1725000000
                    }
                ]
            }
        }
        """.data(using: .utf8)!
        
        MockGBFSURLProtocol.mockHandlers["station_information.json"] = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "https://mock.gbfs/station_information.json")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["ETag": "W/\"info-123\""]
            )!
            return (response, infoJSON)
        }
        
        MockGBFSURLProtocol.mockHandlers["station_status.json"] = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "https://mock.gbfs/station_status.json")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["ETag": "W/\"status-123\""]
            )!
            return (response, statusJSON)
        }
        
        let success = await service.fetchAndIngestLatest()
        XCTAssertTrue(success)
        
        let station = try await dbManager.fetchStation(by: "MOCK_S1")
        XCTAssertNotNil(station)
        XCTAssertEqual(station?.name, "Columbus Circle")
        XCTAssertEqual(station?.numBikesAvailable, 15)
        XCTAssertEqual(station?.numEbikesAvailable, 6)
        XCTAssertEqual(station?.numDocksAvailable, 35)
    }
    
    func testHTTP304NotModifiedHandling() async throws {
        var ifNoneMatchReceived: String? = nil
        
        MockGBFSURLProtocol.mockHandlers["station_status.json"] = { request in
            ifNoneMatchReceived = request.value(forHTTPHeaderField: "If-None-Match")
            if ifNoneMatchReceived == "W/\"status-etag-1\"" {
                let response = HTTPURLResponse(
                    url: URL(string: "https://mock.gbfs/station_status.json")!,
                    statusCode: 304,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return (response, Data())
            } else {
                let statusJSON = """
                {"data": {"stations": [{"station_id": "S1", "num_bikes_available": 10, "num_docks_available": 20, "is_installed": 1, "is_renting": 1, "is_returning": 1, "last_reported": 1725000000}]}}
                """.data(using: .utf8)!
                let response = HTTPURLResponse(
                    url: URL(string: "https://mock.gbfs/station_status.json")!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["ETag": "W/\"status-etag-1\""]
                )!
                return (response, statusJSON)
            }
        }
        
        // 1st Fetch: Returns 200 and records ETag
        let firstSuccess = await service.fetchAndIngestStationStatus(urlStr: "https://mock.gbfs/station_status.json")
        XCTAssertTrue(firstSuccess)
        
        // 2nd Fetch: Should send If-None-Match header and receive 304
        let secondSuccess = await service.fetchAndIngestStationStatus(urlStr: "https://mock.gbfs/station_status.json")
        XCTAssertTrue(secondSuccess)
        XCTAssertEqual(ifNoneMatchReceived, "W/\"status-etag-1\"")
    }
    
    // MARK: - Polling Lifecycle Tests
    
    func testPollingStartAndStop() async throws {
        var isPolling = await service.isPolling
        XCTAssertFalse(isPolling)
        
        await service.startPolling()
        isPolling = await service.isPolling
        XCTAssertTrue(isPolling)
        
        await service.stopPolling()
        isPolling = await service.isPolling
        XCTAssertFalse(isPolling)
    }
    
    func testPrepareForCitySwapSafety() async throws {
        await service.startPolling()
        var isPolling = await service.isPolling
        XCTAssertTrue(isPolling)
        
        await service.prepareForCitySwap()
        isPolling = await service.isPolling
        XCTAssertFalse(isPolling)
    }
    
    func testBackoffIntervalCalculation() async {
        let baseNanos: UInt64 = 30_000_000_000 // 30s
        
        // Success resets to base interval
        let intervalSuccess = await service.calculateNextInterval(success: true, targetIntervalNanos: baseNanos)
        XCTAssertEqual(intervalSuccess, baseNanos)
        
        // Error increases backoff
        let intervalError = await service.calculateNextInterval(success: false, targetIntervalNanos: baseNanos)
        XCTAssertGreaterThan(intervalError, 15_000_000_000)
    }
}
