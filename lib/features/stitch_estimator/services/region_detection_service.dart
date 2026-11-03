import 'dart:typed_data';

import 'package:flutter/foundation.dart';

class RegionDetectionResult {
  const RegionDetectionResult({
    required this.width,
    required this.height,
    required this.rgbaPixels,
    required this.regions,
  });

  final int width;
  final int height;
  final Uint8List rgbaPixels;
  final List<DetectedColorRegion> regions;
}

class DetectedColorRegion {
  const DetectedColorRegion({
    required this.color,
    required this.pixelCount,
    required this.percentage,
  });

  final int color;
  final int pixelCount;
  final double percentage;
}

/// Groups pixels by their nearest representative colour.
/// This first pass groups disconnected areas of the same colour together.
class RegionDetectionService {
  static Future<RegionDetectionResult> detect({
    required Uint8List rgbaPixels,
    required int width,
    required int height,
    required int colorCount,
  }) async {
    final result = await compute<Map<String, Object>, Map<String, Object>>(
      _segmentPixels,
      {
        'pixels': rgbaPixels,
        'width': width,
        'height': height,
        'colorCount': colorCount,
      },
    );

    final rawRegions = result['regions']! as List<Map<String, Object>>;
    return RegionDetectionResult(
      width: result['width']! as int,
      height: result['height']! as int,
      rgbaPixels: result['pixels']! as Uint8List,
      regions: rawRegions
          .map(
            (region) => DetectedColorRegion(
              color: region['color']! as int,
              pixelCount: region['pixelCount']! as int,
              percentage: region['percentage']! as double,
            ),
          )
          .toList(growable: false),
    );
  }
}

Map<String, Object> _segmentPixels(Map<String, Object> args) {
  final source = args['pixels']! as Uint8List;
  final width = args['width']! as int;
  final height = args['height']! as int;
  final requestedColors = args['colorCount']! as int;
  final pixelCount = width * height;

  // Sample at most about 18,000 pixels to build a representative palette.
  final stride = (pixelCount / 18000).ceil().clamp(1, pixelCount);
  final samples = <List<double>>[];
  for (var index = 0; index < pixelCount; index += stride) {
    final offset = index * 4;
    if (source[offset + 3] < 24) continue;
    samples.add([
      source[offset].toDouble(),
      source[offset + 1].toDouble(),
      source[offset + 2].toDouble(),
    ]);
  }

  if (samples.isEmpty) {
    throw StateError('The image does not contain visible pixels.');
  }

  final clusterCount = requestedColors.clamp(2, 12).clamp(1, samples.length);
  final centroids = <List<double>>[];
  // Spread initial representatives through the sampled image.
  for (var i = 0; i < clusterCount; i++) {
    final sampleIndex = ((i + 0.5) * samples.length / clusterCount)
        .floor()
        .clamp(0, samples.length - 1);
    centroids.add(List<double>.from(samples[sampleIndex]));
  }

  final assignments = List<int>.filled(samples.length, 0);
  for (var iteration = 0; iteration < 6; iteration++) {
    final sums = List.generate(clusterCount, (_) => List<double>.filled(3, 0));
    final counts = List<int>.filled(clusterCount, 0);

    for (var i = 0; i < samples.length; i++) {
      final sample = samples[i];
      var bestCluster = 0;
      var bestDistance = double.infinity;
      for (var cluster = 0; cluster < clusterCount; cluster++) {
        final center = centroids[cluster];
        final dr = sample[0] - center[0];
        final dg = sample[1] - center[1];
        final db = sample[2] - center[2];
        final distance = dr * dr + dg * dg + db * db;
        if (distance < bestDistance) {
          bestDistance = distance;
          bestCluster = cluster;
        }
      }
      assignments[i] = bestCluster;
      counts[bestCluster]++;
      for (var channel = 0; channel < 3; channel++) {
        sums[bestCluster][channel] += sample[channel];
      }
    }

    for (var cluster = 0; cluster < clusterCount; cluster++) {
      if (counts[cluster] == 0) continue;
      for (var channel = 0; channel < 3; channel++) {
        centroids[cluster][channel] = sums[cluster][channel] / counts[cluster];
      }
    }
  }

  final output = Uint8List(source.length);
  final regionCounts = List<int>.filled(clusterCount, 0);
  for (var pixel = 0; pixel < pixelCount; pixel++) {
    final offset = pixel * 4;
    if (source[offset + 3] < 24) {
      output[offset + 3] = 0;
      continue;
    }

    var bestCluster = 0;
    var bestDistance = double.infinity;
    for (var cluster = 0; cluster < clusterCount; cluster++) {
      final center = centroids[cluster];
      final dr = source[offset] - center[0];
      final dg = source[offset + 1] - center[1];
      final db = source[offset + 2] - center[2];
      final distance = dr * dr + dg * dg + db * db;
      if (distance < bestDistance) {
        bestDistance = distance;
        bestCluster = cluster;
      }
    }

    final center = centroids[bestCluster];
    output[offset] = center[0].round().clamp(0, 255);
    output[offset + 1] = center[1].round().clamp(0, 255);
    output[offset + 2] = center[2].round().clamp(0, 255);
    output[offset + 3] = source[offset + 3];
    regionCounts[bestCluster]++;
  }

  final regions = <Map<String, Object>>[];
  for (var cluster = 0; cluster < clusterCount; cluster++) {
    if (regionCounts[cluster] == 0) continue;
    final center = centroids[cluster];
    final color = 0xFF000000 |
        (center[0].round().clamp(0, 255) << 16) |
        (center[1].round().clamp(0, 255) << 8) |
        center[2].round().clamp(0, 255);
    regions.add({
      'color': color,
      'pixelCount': regionCounts[cluster],
      'percentage': regionCounts[cluster] * 100 / pixelCount,
    });
  }
  regions.sort(
    (a, b) => (b['pixelCount']! as int).compareTo(a['pixelCount']! as int),
  );

  return {
    'width': width,
    'height': height,
    'pixels': output,
    'regions': regions,
  };
}
