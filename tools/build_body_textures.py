"""Build the Orbit simulator's planet surfaces (resources/bodies/).

Developer tool, not part of the app. It turns public map data into small
equirectangular files the app loads with imread:

  earth-color.jpg       1024 x 512 colour image, longitude -180..180, latitude 90..-90
  earth-elevation.png   360 x 180 16-bit elevation, metres = value * scale + offset
  mars-elevation.png    360 x 180 16-bit elevation (relative to a spheroid)
  manifest.json         sizes, encodings, and sources of every file

Sources (download them first and pass their paths):
  bmng.jpg              NASA Blue Marble Next Generation (public domain), as shipped
                        in the basemap-data Python package (pip download basemap-data)
  srtmp300.msl          Earth topography relative to sea level, spherical-harmonic
                        model to degree 300 (Wieczorek; from SRTM, public domain), in
                        the SHTOOLS example data (BSD-3-Clause):
                        https://raw.githubusercontent.com/SHTOOLS/SHTOOLS/master/examples/ExampleDataFiles/srtmp300.msl
  MarsTopo719.shape     Mars shape model to degree 719 (Wieczorek 2015; from MOLA,
                        public domain), same location as above

Usage (needs numpy, pillow, and pyshtools):
  python tools/build_body_textures.py bmng.jpg srtmp300.msl MarsTopo719.shape
"""
import json
import sys
from pathlib import Path

import numpy as np
import pyshtools as pysh
from PIL import Image

OUT = Path(__file__).resolve().parent.parent / "resources" / "bodies"
LMAX = 90                    # 2-degree grid: degree 90 is all it can show
WIDTH, HEIGHT = 360, 180


def grid_lat_lon():
    lon = -180 + (np.arange(WIDTH) + 0.5) * 360 / WIDTH
    lat = 90 - (np.arange(HEIGHT) + 0.5) * 180 / HEIGHT
    return np.meshgrid(lat, lon, indexing="ij")


def synthesize(coefficients):
    lat, lon = grid_lat_lon()
    values = coefficients.expand(lat=lat.ravel(), lon=lon.ravel())
    return np.asarray(values).reshape(HEIGHT, WIDTH)


def write_elevation(name, heights, offset):
    encoded = np.round(heights - offset)
    if encoded.min() < 0 or encoded.max() > 65535:
        raise ValueError(f"{name}: elevations do not fit the 16-bit encoding")
    Image.fromarray(encoded.astype(np.uint16)).save(OUT / f"{name}-elevation.png")
    return {"file": f"{name}-elevation.png", "width": WIDTH, "height": HEIGHT,
            "scale": 1, "offset": offset,
            "min": float(heights.min()), "max": float(heights.max())}


def main(bmng, earth_topo, mars_shape):
    OUT.mkdir(parents=True, exist_ok=True)
    manifest = {"format": "dynamicslab-bodies", "formatVersion": 1, "bodies": {}}

    image = Image.open(bmng).convert("RGB").resize((1024, 512), Image.LANCZOS)
    image.save(OUT / "earth-color.jpg", quality=85, optimize=True)

    earth = pysh.SHCoeffs.from_file(earth_topo, lmax=LMAX)
    earth_heights = synthesize(earth)
    manifest["bodies"]["Earth"] = {
        "color": {"file": "earth-color.jpg", "width": 1024, "height": 512,
                  "source": "NASA Blue Marble Next Generation (public domain), via the basemap-data package"},
        "elevation": dict(write_elevation("earth", earth_heights, -11000),
                          source="SRTMP topography to degree 90 (Wieczorek; SRTM, public domain), "
                                 "SHTOOLS example data (BSD-3-Clause)",
                          reference="mean sea level"),
    }

    mars = pysh.SHCoeffs.from_file(mars_shape, lmax=LMAX)
    mars.coeffs[0, 0, 0] = 0          # mean radius
    mars.coeffs[0, 2, 0] = 0          # rotational flattening: show topography, not the bulge
    mars_heights = synthesize(mars)
    manifest["bodies"]["Mars"] = {
        "elevation": dict(write_elevation("mars", mars_heights, -12000),
                          source="MarsTopo719 to degree 90 (Wieczorek 2015; MOLA, public domain), "
                                 "SHTOOLS example data (BSD-3-Clause)",
                          reference="mean radius, without the degree-2 zonal flattening"),
    }
    (OUT / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")


if __name__ == "__main__":
    main(*sys.argv[1:4])
