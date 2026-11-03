#include "ArtworkRegionAnalysis.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <limits>
#include <queue>
#include <utility>
#include <unordered_map>
#include <vector>

namespace LeoStitch::Core {
namespace {

// Six bits per channel retain finer logo shades than a coarse 5-bit cube.
constexpr int kHistogramSide = 65;
constexpr int kHistogramBins = 64;

struct ColourMoment {
    double weight = 0.0;
    double red = 0.0;
    double green = 0.0;
    double blue = 0.0;
    double squares = 0.0;

    ColourMoment& operator+=(const ColourMoment& other) {
        weight += other.weight;
        red += other.red;
        green += other.green;
        blue += other.blue;
        squares += other.squares;
        return *this;
    }

    ColourMoment& operator-=(const ColourMoment& other) {
        weight -= other.weight;
        red -= other.red;
        green -= other.green;
        blue -= other.blue;
        squares -= other.squares;
        return *this;
    }
};

struct ColourBox {
    std::array<int, 3> low{0, 0, 0};
    std::array<int, 3> high{kHistogramBins, kHistogramBins, kHistogramBins};
};

struct PaletteColour {
    RgbaPixel rgb;
    std::array<double, 3> lab{};
};

std::size_t histogramIndex(int red, int green, int blue) {
    return (static_cast<std::size_t>(red) * kHistogramSide +
            static_cast<std::size_t>(green)) * kHistogramSide +
           static_cast<std::size_t>(blue);
}

ColourMoment boxMoment(const std::vector<ColourMoment>& cube,
                       const ColourBox& box) {
    // Box bounds are histogram boundaries: bins in (low, high] belong
    // to the box, so zero is a valid lower summed-volume boundary.
    const int r0 = box.low[0];
    const int g0 = box.low[1];
    const int b0 = box.low[2];
    const int r1 = box.high[0];
    const int g1 = box.high[1];
    const int b1 = box.high[2];

    const auto at = [&](int r, int g, int b) -> const ColourMoment& {
        return cube[histogramIndex(r, g, b)];
    };

    ColourMoment result = at(r1, g1, b1);
    result -= at(r0, g1, b1);
    result -= at(r1, g0, b1);
    result -= at(r1, g1, b0);
    result += at(r0, g0, b1);
    result += at(r0, g1, b0);
    result += at(r1, g0, b0);
    result -= at(r0, g0, b0);
    return result;
}

double boxVariance(const ColourMoment& moment) {
    if (moment.weight <= 0.0)
        return 0.0;
    const double channelMeans =
        (moment.red * moment.red + moment.green * moment.green +
         moment.blue * moment.blue) / moment.weight;
    return std::max(0.0, moment.squares - channelMeans);
}

struct SplitResult {
    bool valid = false;
    int axis = 0;
    int cut = 0;
    double reduction = 0.0;
};

SplitResult findBestSplit(const std::vector<ColourMoment>& cube,
                          const ColourBox& box) {
    SplitResult best;
    const ColourMoment parent = boxMoment(cube, box);
    const double parentVariance = boxVariance(parent);
    if (parent.weight <= 1.0 || parentVariance <= 1e-9)
        return best;

    for (int axis = 0; axis < 3; ++axis) {
        for (int cut = box.low[axis] + 1; cut < box.high[axis]; ++cut) {
            ColourBox first = box;
            ColourBox second = box;
            first.high[axis] = cut;
            second.low[axis] = cut;
            const ColourMoment firstMoment = boxMoment(cube, first);
            const ColourMoment secondMoment = boxMoment(cube, second);
            if (firstMoment.weight <= 0.0 || secondMoment.weight <= 0.0)
                continue;

            const double reduction = parentVariance -
                boxVariance(firstMoment) - boxVariance(secondMoment);
            if (reduction > best.reduction) {
                best.valid = true;
                best.axis = axis;
                best.cut = cut;
                best.reduction = reduction;
            }
        }
    }
    return best;
}

std::array<double, 3> rgbToLab(const RgbaPixel& pixel) {
    const auto linearise = [](double value) {
        value /= 255.0;
        return value <= 0.04045 ? value / 12.92
                                : std::pow((value + 0.055) / 1.055, 2.4);
    };

    const double red = linearise(pixel.red);
    const double green = linearise(pixel.green);
    const double blue = linearise(pixel.blue);

    const double x = (red * 0.4124564 + green * 0.3575761 + blue * 0.1804375) /
                     0.95047;
    const double y = red * 0.2126729 + green * 0.7151522 + blue * 0.0721750;
    const double z = (red * 0.0193339 + green * 0.1191920 + blue * 0.9503041) /
                     1.08883;

    const auto labCurve = [](double value) {
        constexpr double delta = 6.0 / 29.0;
        constexpr double deltaCubed = delta * delta * delta;
        return value > deltaCubed
            ? std::cbrt(value)
            : value / (3.0 * delta * delta) + 4.0 / 29.0;
    };

    const double fx = labCurve(x);
    const double fy = labCurve(y);
    const double fz = labCurve(z);
    return {
        116.0 * fy - 16.0,
        500.0 * (fx - fy),
        200.0 * (fy - fz)
    };
}

double labDistanceSquared(const std::array<double, 3>& a,
                          const std::array<double, 3>& b) {
    const double dl = a[0] - b[0];
    const double da = a[1] - b[1];
    const double db = a[2] - b[2];
    return dl * dl + da * da + db * db;
}

std::vector<PaletteColour> buildWuPalette(const RasterImage& image,
                                          const RegionAnalysisOptions& options) {
    std::vector<ColourMoment> cube(
        static_cast<std::size_t>(kHistogramSide) * kHistogramSide * kHistogramSide);

    // Build a 6-bit-per-channel RGB histogram and its statistical moments.
    for (const RgbaPixel& pixel : image.pixels) {
        if (pixel.alpha <= options.transparentAlphaThreshold)
            continue;
        const int redBin = (pixel.red >> 2) + 1;
        const int greenBin = (pixel.green >> 2) + 1;
        const int blueBin = (pixel.blue >> 2) + 1;
        ColourMoment& moment = cube[histogramIndex(redBin, greenBin, blueBin)];
        moment.weight += 1.0;
        moment.red += pixel.red;
        moment.green += pixel.green;
        moment.blue += pixel.blue;
        moment.squares += static_cast<double>(pixel.red) * pixel.red +
                          static_cast<double>(pixel.green) * pixel.green +
                          static_cast<double>(pixel.blue) * pixel.blue;
    }

    // Convert the histogram into a 3D summed-volume table.
    for (int red = 1; red <= kHistogramBins; ++red) {
        for (int green = 1; green <= kHistogramBins; ++green) {
            for (int blue = 1; blue <= kHistogramBins; ++blue) {
                ColourMoment value = cube[histogramIndex(red, green, blue)];
                value += cube[histogramIndex(red - 1, green, blue)];
                value += cube[histogramIndex(red, green - 1, blue)];
                value += cube[histogramIndex(red, green, blue - 1)];
                value -= cube[histogramIndex(red - 1, green - 1, blue)];
                value -= cube[histogramIndex(red - 1, green, blue - 1)];
                value -= cube[histogramIndex(red, green - 1, blue - 1)];
                value += cube[histogramIndex(red - 1, green - 1, blue - 1)];
                cube[histogramIndex(red, green, blue)] = value;
            }
        }
    }

    const std::size_t requestedCount =
        std::clamp<std::size_t>(options.requestedColourCount, 1, 32);
    std::vector<ColourBox> boxes(1);
    while (boxes.size() < requestedCount) {
        std::size_t selectedBox = boxes.size();
        SplitResult selectedSplit;
        for (std::size_t i = 0; i < boxes.size(); ++i) {
            const SplitResult candidate = findBestSplit(cube, boxes[i]);
            if (candidate.valid &&
                (selectedBox == boxes.size() ||
                 candidate.reduction > selectedSplit.reduction)) {
                selectedBox = i;
                selectedSplit = candidate;
            }
        }
        if (selectedBox == boxes.size())
            break;

        ColourBox first = boxes[selectedBox];
        ColourBox second = boxes[selectedBox];
        first.high[selectedSplit.axis] = selectedSplit.cut;
        second.low[selectedSplit.axis] = selectedSplit.cut;
        boxes[selectedBox] = first;
        boxes.push_back(second);
    }

    std::vector<PaletteColour> palette;
    palette.reserve(boxes.size());
    for (const ColourBox& box : boxes) {
        const ColourMoment moment = boxMoment(cube, box);
        if (moment.weight <= 0.0)
            continue;
        PaletteColour colour;
        colour.rgb = {
            static_cast<std::uint8_t>(std::clamp(
                std::lround(moment.red / moment.weight), 0L, 255L)),
            static_cast<std::uint8_t>(std::clamp(
                std::lround(moment.green / moment.weight), 0L, 255L)),
            static_cast<std::uint8_t>(std::clamp(
                std::lround(moment.blue / moment.weight), 0L, 255L)),
            255
        };
        colour.lab = rgbToLab(colour.rgb);
        palette.push_back(colour);
    }
    return palette;
}

std::uint32_t countEnclosedHoles(const ArtworkRegion& region,
                                 int imageWidth) {
    if (region.pixelIndices.empty() || region.width <= 2 || region.height <= 2)
        return 0;

    const int left = region.left;
    const int top = region.top;
    const int right = left + region.width;
    const int bottom = top + region.height;
    const int localWidth = region.width;
    const int localHeight = region.height;
    const std::size_t localSize =
        static_cast<std::size_t>(localWidth) * static_cast<std::size_t>(localHeight);

    std::vector<std::uint8_t> isRegion(localSize, 0);
    for (const std::uint32_t index : region.pixelIndices) {
        const int x = static_cast<int>(index % static_cast<std::uint32_t>(imageWidth));
        const int y = static_cast<int>(index / static_cast<std::uint32_t>(imageWidth));
        if (x >= left && x < right && y >= top && y < bottom) {
            const std::size_t localIndex =
                static_cast<std::size_t>(y - top) * static_cast<std::size_t>(localWidth) +
                static_cast<std::size_t>(x - left);
            isRegion[localIndex] = 1;
        }
    }

    std::vector<std::uint8_t> visited(localSize, 0);
    std::queue<std::size_t> pending;
    const auto enqueueIfBackground = [&](int x, int y, auto& queue) {
        const std::size_t index =
            static_cast<std::size_t>(y) * static_cast<std::size_t>(localWidth) +
            static_cast<std::size_t>(x);
        if (!isRegion[index] && !visited[index]) {
            visited[index] = 1;
            queue.push(index);
        }
    };

    for (int x = 0; x < localWidth; ++x) {
        enqueueIfBackground(x, 0, pending);
        enqueueIfBackground(x, localHeight - 1, pending);
    }
    for (int y = 0; y < localHeight; ++y) {
        enqueueIfBackground(0, y, pending);
        enqueueIfBackground(localWidth - 1, y, pending);
    }

    constexpr std::array<int, 4> dx{-1, 1, 0, 0};
    constexpr std::array<int, 4> dy{0, 0, -1, 1};
    while (!pending.empty()) {
        const std::size_t index = pending.front();
        pending.pop();
        const int x = static_cast<int>(index % static_cast<std::size_t>(localWidth));
        const int y = static_cast<int>(index / static_cast<std::size_t>(localWidth));
        for (std::size_t direction = 0; direction < dx.size(); ++direction) {
            const int nx = x + dx[direction];
            const int ny = y + dy[direction];
            if (nx >= 0 && nx < localWidth && ny >= 0 && ny < localHeight)
                enqueueIfBackground(nx, ny, pending);
        }
    }

    std::uint32_t holes = 0;
    for (std::size_t start = 0; start < localSize; ++start) {
        if (isRegion[start] || visited[start])
            continue;
        ++holes;
        visited[start] = 1;
        pending.push(start);
        while (!pending.empty()) {
            const std::size_t index = pending.front();
            pending.pop();
            const int x = static_cast<int>(index % static_cast<std::size_t>(localWidth));
            const int y = static_cast<int>(index / static_cast<std::size_t>(localWidth));
            for (std::size_t direction = 0; direction < dx.size(); ++direction) {
                const int nx = x + dx[direction];
                const int ny = y + dy[direction];
                if (nx < 0 || nx >= localWidth || ny < 0 || ny >= localHeight)
                    continue;
                const std::size_t neighbour =
                    static_cast<std::size_t>(ny) * static_cast<std::size_t>(localWidth) +
                    static_cast<std::size_t>(nx);
                if (!isRegion[neighbour] && !visited[neighbour]) {
                    visited[neighbour] = 1;
                    pending.push(neighbour);
                }
            }
        }
    }
    return holes;
}

} // namespace

bool RasterImage::isValid() const {
    if (width <= 0 || height <= 0)
        return false;
    const auto expected = static_cast<std::uint64_t>(width) *
                          static_cast<std::uint64_t>(height);
    return expected == pixels.size() &&
           expected <= std::numeric_limits<std::uint32_t>::max();
}

RegionAnalysisResult ArtworkRegionAnalyzer::analyze(
    const RasterImage& image, const RegionAnalysisOptions& options) {
    RegionAnalysisResult result;
    result.imageWidth = image.width;
    result.imageHeight = image.height;
    if (!image.isValid())
        return result;

    const std::vector<PaletteColour> palette = buildWuPalette(image, options);
    if (palette.empty())
        return result;

    const std::size_t pixelTotal = image.pixels.size();
    std::vector<std::int16_t> pixelClusters(pixelTotal, -1);

    // Map source pixels to the nearest palette colour in perceptual Lab space.
    for (std::size_t index = 0; index < pixelTotal; ++index) {
        const RgbaPixel& pixel = image.pixels[index];
        if (pixel.alpha <= options.transparentAlphaThreshold)
            continue;
        const auto lab = rgbToLab(pixel);
        double bestDistance = std::numeric_limits<double>::max();
        std::size_t bestCluster = 0;
        for (std::size_t cluster = 0; cluster < palette.size(); ++cluster) {
            const double distance = labDistanceSquared(lab, palette[cluster].lab);
            if (distance < bestDistance) {
                bestDistance = distance;
                bestCluster = cluster;
            }
        }
        pixelClusters[index] = static_cast<std::int16_t>(bestCluster);
    }

    // First label the raw connected components so tiny palette speckles can
    // be reassigned to a neighbouring, larger component before final regions
    // are generated. This merges pixels; it never deletes them.
    struct ComponentInfo {
        std::vector<std::uint32_t> pixels;
        std::int16_t paletteIndex = -1;
    };
    std::vector<ComponentInfo> components;
    std::vector<std::int32_t> componentLabels(pixelTotal, -1);
    std::queue<std::uint32_t> componentQueue;
    constexpr std::array<int, 8> componentDx{-1, 0, 1, -1, 1, -1, 0, 1};
    constexpr std::array<int, 8> componentDy{-1, -1, -1, 0, 0, 1, 1, 1};

    for (std::size_t start = 0; start < pixelTotal; ++start) {
        if (pixelClusters[start] < 0 || componentLabels[start] >= 0)
            continue;
        const auto componentId = static_cast<std::int32_t>(components.size());
        ComponentInfo component;
        component.paletteIndex = pixelClusters[start];
        componentLabels[start] = componentId;
        componentQueue.push(static_cast<std::uint32_t>(start));
        while (!componentQueue.empty()) {
            const std::uint32_t index = componentQueue.front();
            componentQueue.pop();
            component.pixels.push_back(index);
            const int x = static_cast<int>(index % static_cast<std::uint32_t>(image.width));
            const int y = static_cast<int>(index / static_cast<std::uint32_t>(image.width));
            for (std::size_t direction = 0; direction < componentDx.size(); ++direction) {
                const int nx = x + componentDx[direction];
                const int ny = y + componentDy[direction];
                if (nx < 0 || nx >= image.width || ny < 0 || ny >= image.height)
                    continue;
                const std::size_t neighbour =
                    static_cast<std::size_t>(ny) * static_cast<std::size_t>(image.width) +
                    static_cast<std::size_t>(nx);
                if (pixelClusters[neighbour] != component.paletteIndex ||
                    componentLabels[neighbour] >= 0)
                    continue;
                componentLabels[neighbour] = componentId;
                componentQueue.push(static_cast<std::uint32_t>(neighbour));
            }
        }
        components.push_back(std::move(component));
    }

    const std::uint32_t mergeLimit = options.mergeFragmentsUpToPixelCount;
    if (mergeLimit > 0 && components.size() > 1) {
        // Process the smallest fragments first. A fragment is absorbed by the
        // adjacent component with the longest shared 8-neighbour boundary;
        // palette colour distance breaks ties.
        std::vector<std::size_t> order(components.size());
        for (std::size_t i = 0; i < order.size(); ++i)
            order[i] = i;
        std::sort(order.begin(), order.end(), [&](std::size_t a, std::size_t b) {
            return components[a].pixels.size() < components[b].pixels.size();
        });

        for (const std::size_t componentId : order) {
            const ComponentInfo& component = components[componentId];
            if (component.pixels.size() > mergeLimit)
                break;

            std::unordered_map<std::int32_t, std::uint32_t> boundaryCounts;
            for (const std::uint32_t index : component.pixels) {
                const int x = static_cast<int>(index % static_cast<std::uint32_t>(image.width));
                const int y = static_cast<int>(index / static_cast<std::uint32_t>(image.width));
                for (std::size_t direction = 0; direction < componentDx.size(); ++direction) {
                    const int nx = x + componentDx[direction];
                    const int ny = y + componentDy[direction];
                    if (nx < 0 || nx >= image.width || ny < 0 || ny >= image.height)
                        continue;
                    const std::size_t neighbour =
                        static_cast<std::size_t>(ny) * static_cast<std::size_t>(image.width) +
                        static_cast<std::size_t>(nx);
                    const std::int32_t neighbourId = componentLabels[neighbour];
                    if (neighbourId < 0 || neighbourId == static_cast<std::int32_t>(componentId))
                        continue;
                    if (components[static_cast<std::size_t>(neighbourId)].pixels.size() <=
                        mergeLimit)
                        continue;
                    ++boundaryCounts[neighbourId];
                }
            }

            std::int32_t bestNeighbour = -1;
            std::uint32_t bestBoundary = 0;
            double bestColourDistance = std::numeric_limits<double>::max();
            for (const auto& [neighbourId, boundary] : boundaryCounts) {
                const auto neighbourPalette =
                    components[static_cast<std::size_t>(neighbourId)].paletteIndex;
                const double colourDistance = labDistanceSquared(
                    palette[static_cast<std::size_t>(component.paletteIndex)].lab,
                    palette[static_cast<std::size_t>(neighbourPalette)].lab);
                if (boundary > bestBoundary ||
                    (boundary == bestBoundary && colourDistance < bestColourDistance)) {
                    bestNeighbour = neighbourId;
                    bestBoundary = boundary;
                    bestColourDistance = colourDistance;
                }
            }

            if (bestNeighbour >= 0) {
                const auto targetPalette =
                    components[static_cast<std::size_t>(bestNeighbour)].paletteIndex;
                for (const std::uint32_t index : component.pixels)
                    pixelClusters[index] = targetPalette;
            }
        }
    }

    // Split each palette colour into separate spatially connected shapes.
    std::vector<std::uint8_t> visited(pixelTotal, 0);
    std::queue<std::uint32_t> pending;
    constexpr std::array<int, 8> dx{-1, 0, 1, -1, 1, -1, 0, 1};
    constexpr std::array<int, 8> dy{-1, -1, -1, 0, 0, 1, 1, 1};
    for (std::size_t start = 0; start < pixelTotal; ++start) {
        if (image.pixels[start].alpha <= options.transparentAlphaThreshold ||
            visited[start])
            continue;

        const std::int16_t cluster = pixelClusters[start];
        ArtworkRegion region;
        int minX = image.width;
        int minY = image.height;
        int maxX = -1;
        int maxY = -1;
        std::uint64_t redTotal = 0;
        std::uint64_t greenTotal = 0;
        std::uint64_t blueTotal = 0;
        std::uint64_t alphaTotal = 0;

        visited[start] = 1;
        pending.push(static_cast<std::uint32_t>(start));
        while (!pending.empty()) {
            const std::uint32_t index = pending.front();
            pending.pop();
            const RgbaPixel& pixel = image.pixels[index];
            region.pixelIndices.push_back(index);
            redTotal += pixel.red;
            greenTotal += pixel.green;
            blueTotal += pixel.blue;
            alphaTotal += pixel.alpha;

            const int x = static_cast<int>(index % static_cast<std::uint32_t>(image.width));
            const int y = static_cast<int>(index / static_cast<std::uint32_t>(image.width));
            if (x == 0 || y == 0 || x == image.width - 1 || y == image.height - 1)
                region.touchesImageEdge = true;
            minX = std::min(minX, x);
            minY = std::min(minY, y);
            maxX = std::max(maxX, x);
            maxY = std::max(maxY, y);

            for (std::size_t direction = 0; direction < dx.size(); ++direction) {
                const int nx = x + dx[direction];
                const int ny = y + dy[direction];
                if (nx < 0 || nx >= image.width || ny < 0 || ny >= image.height)
                    continue;
                const std::size_t neighbour =
                    static_cast<std::size_t>(ny) * static_cast<std::size_t>(image.width) +
                    static_cast<std::size_t>(nx);
                if (visited[neighbour] || pixelClusters[neighbour] != cluster)
                    continue;
                visited[neighbour] = 1;
                pending.push(static_cast<std::uint32_t>(neighbour));
            }
        }

        region.pixelCount = static_cast<std::uint32_t>(region.pixelIndices.size());
        region.id = static_cast<std::uint32_t>(result.regions.size() + 1);
        region.sourceRegionIds.push_back(region.id);
        region.left = minX;
        region.top = minY;
        region.width = maxX - minX + 1;
        region.height = maxY - minY + 1;
        region.representativeColor = {
            static_cast<std::uint8_t>(redTotal / region.pixelCount),
            static_cast<std::uint8_t>(greenTotal / region.pixelCount),
            static_cast<std::uint8_t>(blueTotal / region.pixelCount),
            static_cast<std::uint8_t>(alphaTotal / region.pixelCount)
        };
        region.holeCount = countEnclosedHoles(region, image.width);
        result.regions.push_back(std::move(region));
    }

    return result;
}

} // namespace LeoStitch::Core
