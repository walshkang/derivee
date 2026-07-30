export const MTA_SUBWAY_FEEDS = {
  ACE: 'https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-ace',
  BDFM: 'https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-bdfm',
  G: 'https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-g',
  JZ: 'https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-jz',
  NQRW: 'https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-nqrw',
  L: 'https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-l',
  NUMBERED: 'https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs',
  SIR: 'https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-si',
};

export const MTA_BUS_SIRI_STOP_MONITORING_URL = 'https://bustime.mta.info/api/siri/stop-monitoring.json';
export const MTA_BUS_SIRI_VEHICLE_MONITORING_URL = 'https://bustime.mta.info/api/siri/vehicle-monitoring.json';
export const ONE_BUS_AWAY_BASE_URL = 'https://bustime.mta.info/api/where';

export const getRouteColor = (routeId) => {
  if (!routeId) return '#FFB300';
  const r = routeId.toUpperCase();
  if (['A','C','E'].includes(r)) return '#0039A6';
  if (['B','D','F','M'].includes(r)) return '#FF6319';
  if (['G'].includes(r)) return '#6CBE45';
  if (['J','Z'].includes(r)) return '#996633';
  if (['L'].includes(r)) return '#A7A9AC';
  if (['N','Q','R','W'].includes(r)) return '#FCCC0A';
  if (['1','2','3'].includes(r)) return '#EE352E';
  if (['4','5','6'].includes(r)) return '#00933C';
  if (['7'].includes(r)) return '#B933AD';
  if (['S'].includes(r)) return '#808183';
  return '#FFB300'; // Default Electric Amber
};

export const hexToRgb = (hex) => {
  const cleanHex = hex.replace('#', '');
  const r = parseInt(cleanHex.substring(0, 2), 16);
  const g = parseInt(cleanHex.substring(2, 4), 16);
  const b = parseInt(cleanHex.substring(4, 6), 16);
  return [r, g, b];
};
