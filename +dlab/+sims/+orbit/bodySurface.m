function s = bodySurface(name, baseColor, folder)
%BODYSURFACE A central body's surface map and elevation.
%   s = dlab.sims.orbit.bodySurface("Earth", color) returns a struct:
%     Map          H×W×3 image (doubles 0–1): north at the top, longitude
%                  −180° (left) to 180°; drape it on a sphere as a texture
%     Elevation    180×360 heights in metres on the same layout (pixel
%                  centres), or [] when the body has no elevation data
%     Kind         "imagery" (a photographic map), "elevation" (colored
%                  from its heights), or "procedural" (no data: bands,
%                  clouds, or mottling from the body's catalog color)
%     Source       where the data comes from ("" for procedural surfaces)
%
%   Data files live in resources/bodies (see manifest.json there and
%   tools/build_body_textures.py). A missing or unreadable file falls
%   back to a procedural surface; it never throws. FOLDER overrides the
%   data folder (tests). Results are cached per body.
arguments
    name (1,1) string
    baseColor (1,3) double
    folder (1,1) string = fullfile(dlab.core.Paths.resources(), "bodies")
end
persistent cache
if isempty(cache)
    cache = dictionary(string.empty, cell.empty);
end
key = folder + "|" + name + "|" + strjoin(string(baseColor), ",");
if isKey(cache, key)
    s = cache{key};
    return
end

s = struct("Map", [], "Elevation", [], "Kind", "procedural", "Source", "");
entry = manifestEntry(folder, name);
try
    if isfield(entry, "elevation")
        e = entry.elevation;
        raw = double(imread(fullfile(folder, e.file)));
        s.Elevation = raw * e.scale + e.offset;
        s.Source = string(e.source);
    end
    if isfield(entry, "color")
        s.Map = double(imread(fullfile(folder, entry.color.file))) / 255;
        s.Kind = "imagery";
        s.Source = strjoin([string(entry.color.source), s.Source(s.Source ~= "")], "; ");
    elseif ~isempty(s.Elevation)
        s.Map = elevationColors(s.Elevation, baseColor);
        s.Kind = "elevation";
    end
catch
    s = struct("Map", [], "Elevation", [], "Kind", "procedural", "Source", "");
end
if isempty(s.Map)
    s.Map = proceduralMap(name, baseColor);
end
cache(key) = {s};
end

% ----------------------------------------------------------------- data
function entry = manifestEntry(folder, name)
entry = struct();
file = fullfile(folder, "manifest.json");
if ~isfile(file)
    return
end
try
    manifest = jsondecode(fileread(file));
    if isfield(manifest, "bodies") && isfield(manifest.bodies, name)
        entry = manifest.bodies.(name);
    end
catch
    entry = struct();
end
end

function map = elevationColors(heights, baseColor)
% The body's color, lighter on high ground and darker in basins, with a
% little hill shading from the east-west slope.
low = prctile2(heights, 0.02);
high = prctile2(heights, 0.98);
level = min(max((heights - low) / max(high - low, eps), 0), 1);
slope = [diff(heights, 1, 2), heights(:, 1) - heights(:, end)];
shade = 1 + 0.25 * tanh(-slope / max(std(slope(:)), eps));
light = (0.55 + 0.6 * level) .* shade;
map = min(max(light .* reshape(baseColor, 1, 1, 3), 0), 1);
end

function value = prctile2(x, p)
% Percentile without the Statistics Toolbox.
x = sort(x(:));
value = x(max(1, round(p * numel(x))));
end

function map = proceduralMap(name, baseColor)
% 180×360 surface made from the catalog color: latitude bands for the
% giant planets, swirls for Venus, granules for the Sun, and mottled
% "highlands and maria" for rocky bodies.
[lon, lat] = meshgrid(deg2rad(-179.5:179.5), deg2rad(89.5:-1:-89.5));
stream = RandStream("mt19937ar", Seed=sum(double(char(name))));
switch name
    case {"Jupiter", "Saturn"}
        bands = 0.16 * sin(14 * lat) + 0.08 * sin(31 * lat + 0.7) + 0.04 * sin(57 * lat);
        swirl = 0.03 * sin(5 * lon + 9 * lat);
        light = 0.9 + bands + swirl;
    case {"Uranus", "Neptune"}
        light = 0.95 + 0.05 * sin(10 * lat) + 0.02 * sin(23 * lat);
    case "Venus"
        light = 0.92 + 0.06 * sin(3 * lon + 8 * sin(2 * lat)) + 0.04 * sin(7 * lat + 2 * lon);
    case "Sun"
        light = 0.95 + 0.05 * smoothNoise(stream, size(lon), 4);
    otherwise
        light = 0.85 + 0.25 * smoothNoise(stream, size(lon), 12) + 0.08 * smoothNoise(stream, size(lon), 3);
end
map = min(max(light .* reshape(baseColor, 1, 1, 3), 0), 1);
end

function field = smoothNoise(stream, sz, width)
% Random field smoothed over about WIDTH pixels, scaled to [−1, 1].
field = randn(stream, sz);
kernel = exp(-((-2 * width:2 * width) / width).^2);
kernel = kernel / sum(kernel);
field = conv2(kernel, kernel, [field(:, end - 2 * width + 1:end), field, field(:, 1:2 * width)], "same");
field = field(:, 2 * width + 1:end - 2 * width);
field = field / max(abs(field(:)));
end
