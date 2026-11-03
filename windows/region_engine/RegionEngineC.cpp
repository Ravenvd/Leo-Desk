#include "ArtworkRegionAnalysis.h"

#include <algorithm>
#include <cstdint>
#include <limits>
#include <memory>
#include <new>
#include <vector>

#if defined(_WIN32)
#define LEO_REGION_API __declspec(dllexport)
#else
#define LEO_REGION_API
#endif

struct LeoRegionInfo {
    std::uint32_t id;
    std::uint8_t red;
    std::uint8_t green;
    std::uint8_t blue;
    std::uint8_t alpha;
    std::int32_t left;
    std::int32_t top;
    std::int32_t width;
    std::int32_t height;
    std::uint32_t pixel_count;
    std::uint32_t hole_count;
    std::uint8_t touches_image_edge;
};

struct LeoRegionResult {
    LeoStitch::Core::RegionAnalysisResult analysis;
};

extern "C" {

LEO_REGION_API void* leo_region_analyze(
    const std::uint8_t* rgba,
    std::int32_t width,
    std::int32_t height,
    std::uint32_t requested_colour_count,
    std::uint32_t merge_fragments_up_to_pixel_count,
    std::uint8_t transparent_alpha_threshold) {
    if (rgba == nullptr || width <= 0 || height <= 0) {
        return nullptr;
    }

    const auto pixel_count = static_cast<std::uint64_t>(width) *
                             static_cast<std::uint64_t>(height);
    if (pixel_count > std::numeric_limits<std::uint32_t>::max() ||
        pixel_count > std::numeric_limits<std::size_t>::max() / 4) {
        return nullptr;
    }

    try {
        LeoStitch::Core::RasterImage image;
        image.width = width;
        image.height = height;
        image.pixels.resize(static_cast<std::size_t>(pixel_count));
        for (std::size_t index = 0; index < image.pixels.size(); ++index) {
            const std::size_t offset = index * 4;
            image.pixels[index] = {
                rgba[offset],
                rgba[offset + 1],
                rgba[offset + 2],
                rgba[offset + 3]
            };
        }

        LeoStitch::Core::RegionAnalysisOptions options;
        options.requestedColourCount = requested_colour_count;
        options.mergeFragmentsUpToPixelCount = merge_fragments_up_to_pixel_count;
        options.transparentAlphaThreshold = transparent_alpha_threshold;

        auto result = std::make_unique<LeoRegionResult>();
        result->analysis = LeoStitch::Core::ArtworkRegionAnalyzer::analyze(
            image, options);
        return result.release();
    } catch (...) {
        return nullptr;
    }
}

LEO_REGION_API std::uint32_t leo_region_result_count(const void* handle) {
    if (handle == nullptr) return 0;
    const auto* result = static_cast<const LeoRegionResult*>(handle);
    return static_cast<std::uint32_t>(result->analysis.regions.size());
}

LEO_REGION_API std::int32_t leo_region_result_width(const void* handle) {
    if (handle == nullptr) return 0;
    return static_cast<const LeoRegionResult*>(handle)->analysis.imageWidth;
}

LEO_REGION_API std::int32_t leo_region_result_height(const void* handle) {
    if (handle == nullptr) return 0;
    return static_cast<const LeoRegionResult*>(handle)->analysis.imageHeight;
}

LEO_REGION_API std::int32_t leo_region_result_get_region(
    const void* handle,
    std::uint32_t index,
    LeoRegionInfo* output) {
    if (handle == nullptr || output == nullptr) return 0;
    const auto* result = static_cast<const LeoRegionResult*>(handle);
    if (index >= result->analysis.regions.size()) return 0;

    const auto& region = result->analysis.regions[index];
    *output = {
        region.id,
        region.representativeColor.red,
        region.representativeColor.green,
        region.representativeColor.blue,
        region.representativeColor.alpha,
        region.left,
        region.top,
        region.width,
        region.height,
        region.pixelCount,
        region.holeCount,
        static_cast<std::uint8_t>(region.touchesImageEdge ? 1 : 0)
    };
    return 1;
}

LEO_REGION_API std::int32_t leo_region_result_copy_labels(
    const void* handle,
    std::uint32_t* output,
    std::uint64_t output_length) {
    if (handle == nullptr || output == nullptr) return 0;
    const auto* result = static_cast<const LeoRegionResult*>(handle);
    const auto expected = static_cast<std::uint64_t>(result->analysis.imageWidth) *
                          static_cast<std::uint64_t>(result->analysis.imageHeight);
    if (output_length < expected) return 0;

    std::fill(output, output + expected, std::numeric_limits<std::uint32_t>::max());
    for (std::size_t region_index = 0;
         region_index < result->analysis.regions.size(); ++region_index) {
        for (const std::uint32_t pixel_index :
             result->analysis.regions[region_index].pixelIndices) {
            if (pixel_index < expected) {
                output[pixel_index] = static_cast<std::uint32_t>(region_index);
            }
        }
    }
    return 1;
}

LEO_REGION_API void leo_region_result_free(void* handle) {
    delete static_cast<LeoRegionResult*>(handle);
}

} // extern "C"
