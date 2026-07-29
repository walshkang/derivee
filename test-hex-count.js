const h3 = require("h3-js");
const destination = require("@turf/destination").default;

const center = [-73.9599, 40.7180];
const BBOX_HALF_WIDTH_KM = 25;

const ptNorth = destination(center, BBOX_HALF_WIDTH_KM, 0, { units: 'kilometers' });
const ptEast = destination(center, BBOX_HALF_WIDTH_KM, 90, { units: 'kilometers' });
const ptSouth = destination(center, BBOX_HALF_WIDTH_KM, 180, { units: 'kilometers' });
const ptWest = destination(center, BBOX_HALF_WIDTH_KM, -90, { units: 'kilometers' });

const minX = ptWest.geometry.coordinates[0];
const minY = ptSouth.geometry.coordinates[1];
const maxX = ptEast.geometry.coordinates[0];
const maxY = ptNorth.geometry.coordinates[1];

const bboxRing = [
  [minX, maxY],
  [maxX, maxY],
  [maxX, minY],
  [minX, minY],
  [minX, maxY],
];

console.log("Generating hexes...");
const start = Date.now();
const hexes = h3.polygonToCells(bboxRing, 11, true);
console.log("Time:", Date.now() - start, "ms");
console.log("Count:", hexes.length);
