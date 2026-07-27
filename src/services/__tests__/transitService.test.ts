import { transitService } from '../transitService';
import { transit_realtime } from '../../proto/gtfs.js';

describe('transitService', () => {
  const originalFetch = global.fetch;

  afterEach(() => {
    global.fetch = originalFetch;
    jest.clearAllMocks();
  });

  describe('fetchSubwayFeed', () => {
    it('decodes GTFS-RT protobuf payload correctly', async () => {
      const feedMessage = transit_realtime.FeedMessage.create({
        header: {
          gtfsRealtimeVersion: '2.0',
          timestamp: 1600000000,
        },
        entity: [
          {
            id: '1',
            tripUpdate: {
              trip: {
                routeId: 'L',
              },
              stopTimeUpdate: [
                {
                  stopId: 'L10',
                  arrival: { time: 1600000300 },
                  departure: { time: 1600000330 },
                },
              ],
            },
          },
          {
            id: '2',
            vehicle: {
              trip: { routeId: 'L' },
              position: {
                latitude: 40.7128,
                longitude: -73.956,
                bearing: 90,
              },
            },
          },
        ],
      });

      const buffer = transit_realtime.FeedMessage.encode(feedMessage).finish();

      global.fetch = jest.fn().mockResolvedValue({
        ok: true,
        arrayBuffer: async () => buffer.buffer.slice(buffer.byteOffset, buffer.byteOffset + buffer.byteLength),
      } as any);

      const result = await transitService.fetchSubwayFeed('L');

      expect(result.arrivals).toHaveLength(1);
      expect(result.arrivals[0]).toMatchObject({
        routeId: 'L',
        stopId: 'L10',
        arrivalTime: 1600000300,
      });

      expect(result.vehicles).toHaveLength(1);
      expect(result.vehicles[0].routeId).toBe('L');
      expect(result.vehicles[0].latitude).toBeCloseTo(40.7128);
      expect(result.vehicles[0].longitude).toBeCloseTo(-73.956);
      expect(result.vehicles[0].bearing).toBe(90);
    });

    it('handles network/http errors gracefully', async () => {
      global.fetch = jest.fn().mockResolvedValue({
        ok: false,
        statusText: 'Internal Server Error',
      } as any);

      const result = await transitService.fetchSubwayFeed('ACE');
      expect(result).toEqual({ arrivals: [], vehicles: [], alerts: [] });
    });
  });

  describe('fetchBusLive (Vehicle Monitoring SIRI)', () => {
    it('parses SIRI vehicle monitoring payload correctly', async () => {
      const mockSiriResponse = {
        Siri: {
          ServiceDelivery: {
            VehicleMonitoringDelivery: [
              {
                VehicleActivity: [
                  {
                    MonitoredVehicleJourney: {
                      LineRef: 'MTA NYCT_B63',
                      VehicleLocation: {
                        Latitude: 40.67215,
                        Longitude: -73.97805,
                      },
                      Bearing: 180,
                      MonitoredCall: {
                        StopPointRef: 'MTA_308214',
                        ExpectedArrivalTime: '2026-07-27T12:00:00.000Z',
                      },
                      OnwardCalls: {
                        OnwardCall: [
                          {
                            StopPointRef: 'MTA_308215',
                            ExpectedArrivalTime: '2026-07-27T12:05:00.000Z',
                          },
                        ],
                      },
                    },
                  },
                ],
              },
            ],
          },
        },
      };

      global.fetch = jest.fn().mockResolvedValue({
        ok: true,
        json: async () => mockSiriResponse,
      } as any);

      const result = await transitService.fetchBusLive('B63');

      expect(result.vehicles).toHaveLength(1);
      expect(result.vehicles[0]).toMatchObject({
        routeId: 'MTA NYCT_B63',
        latitude: 40.67215,
        longitude: -73.97805,
        bearing: 180,
      });

      expect(result.arrivals).toHaveLength(2);
      expect(result.arrivals[0].stopId).toBe('MTA_308214');
      expect(result.arrivals[1].stopId).toBe('MTA_308215');
    });
  });

  describe('fetchBusStopLive (Stop Monitoring SIRI)', () => {
    it('parses SIRI stop monitoring payload correctly', async () => {
      const mockSiriResponse = {
        Siri: {
          ServiceDelivery: {
            StopMonitoringDelivery: [
              {
                MonitoredStopVisit: [
                  {
                    MonitoredVehicleJourney: {
                      LineRef: 'MTA NYCT_B63',
                      VehicleLocation: {
                        Latitude: 40.67215,
                        Longitude: -73.97805,
                      },
                      MonitoredCall: {
                        StopPointRef: 'MTA_308214',
                        ExpectedArrivalTime: '2026-07-27T12:00:00.000Z',
                      },
                    },
                  },
                ],
              },
            ],
          },
        },
      };

      global.fetch = jest.fn().mockResolvedValue({
        ok: true,
        json: async () => mockSiriResponse,
      } as any);

      const result = await transitService.fetchBusStopLive('308214');

      expect(result.arrivals).toHaveLength(1);
      expect(result.arrivals[0].stopId).toBe('MTA_308214');
      expect(result.vehicles).toHaveLength(1);
    });
  });
});
