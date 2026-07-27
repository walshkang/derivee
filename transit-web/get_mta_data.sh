#!/bin/bash
# Download subway lines and stops
curl -sL "https://data.cityofnewyork.us/api/geospatial/3qz8-muuu?method=export&format=GeoJSON" > public/subway-lines.geojson
curl -sL "https://data.cityofnewyork.us/api/geospatial/kk4q-3rt2?method=export&format=GeoJSON" > public/subway-stops.geojson
