export const MTA_SUBWAY_FEEDS: Record<string, string> = {
  // A, C, E, SR (Rockaway Shuttle)
  ACE: 'https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-ace',
  // B, D, F, M, SF (Franklin Shuttle)
  BDFM: 'https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-bdfm',
  // G
  G: 'https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-g',
  // J, Z
  JZ: 'https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-jz',
  // N, Q, R, W
  NQRW: 'https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-nqrw',
  // L
  L: 'https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-l',
  // 1, 2, 3, 4, 5, 6, 7, S (42nd St Shuttle)
  NUMBERED: 'https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs',
  // SIR (Staten Island Railway)
  SIR: 'https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-si',
};

export const MTA_BUS_SIRI_STOP_MONITORING_URL = 'https://bustime.mta.info/api/siri/stop-monitoring.json';
export const MTA_BUS_SIRI_VEHICLE_MONITORING_URL = 'https://bustime.mta.info/api/siri/vehicle-monitoring.json';
export const ONE_BUS_AWAY_BASE_URL = 'https://bustime.mta.info/api/where';
