#pragma once

#include <cstdint>
#include <vector>

namespace LeoStitch::Core {

struct RgbaPixel {
    std::uint8_t red = 0;
    std::uint8_t green = 0;
    std::uint8_t blue = 0;
    std::uint8_t alpha = 0;
};

struct RasterImage {
    int width = 0;
    int height = 0;
    std::vector<RgbaPixel> pixels;

    bool isValid() const;
};

struct RegionAnalysisOptions {
    // Requested number of dominant RGB colour clusters (clamped to 1..32).
    std::uint32_t requestedColourCount = 5;
    // Reassign components up to this size to an adjacent larger component.
    // Zero disables fragment merging.
    std::uint32_t mergeFragmentsUpToPixelCount = 0;
    std::uint8_t transparentAlphaThreshold = 8;
};

struct ArtworkRegion {
    std::uint32_t id = 0;
    RgbaPixel representativeColor;
    int left = 0;
    int top = 0;
    int width = 0;
    int height = 0;
    std::uint32_t pixelCount = 0;
    std::uint32_t holeCount = 0;
    bool touchesImageEdge = false;
    bool excludedFromStitching = false;
    // Row-major pixel indices into the source RasterImage.
    std::vector<std::uint32_t> pixelIndices;
    std::vector<std::uint32_t> sourceRegionIds;
};

struct RegionAnalysisResult {
    int imageWidth = 0;
    int imageHeight = 0;
    std::vector<ArtworkRegion> regions;
};

class ArtworkRegionAnalyzer final {
public:
    static RegionAnalysisResult analyze(
        const RasterImage& image,
        const RegionAnalysisOptions& options = {});
};

} // namespace LeoStitch::Core
