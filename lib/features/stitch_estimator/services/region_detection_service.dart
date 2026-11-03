import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

class RegionDetectionResult {
  const RegionDetectionResult({
    required this.width,
    required this.height,
    required this.rgbaPixels,
    required this.regions,
    required this.regionLabels,
  });

  final int width;
  final int height;
  final Uint8List rgbaPixels;
  final List<DetectedColorRegion> regions;

  /// For each source pixel, the index of its connected region.
  /// 0xFFFFFFFF marks transparent/background pixels.
  final Uint32List regionLabels;
}

class DetectedColorRegion {
  const DetectedColorRegion({
    required this.id,
    required this.color,
    required this.pixelCount,
    required this.percentage,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.holeCount,
    required this.touchesImageEdge,
  });

  final int id;
  final int color;
  final int pixelCount;
  final double percentage;
  final int left;
  final int top;
  final int width;
  final int height;
  final int holeCount;
  final bool touchesImageEdge;
}

/// Calls the same Qt-independent C++ region analyzer used by LeoStitch.
class RegionDetectionService {
  static Future<RegionDetectionResult> detect({
    required Uint8List rgbaPixels,
    required int width,
    required int height,
    required int colorCount,
    int mergeFragmentsUpToPixelCount = 2,
  }) async {
    if (!Platform.isWindows) {
      throw UnsupportedError(
        'The LeoStitch region engine is currently available in the Windows '
        'desktop build of Leo Desk.',
      );
    }

    final result = await compute<Map<String, Object>, Map<String, Object>>(
      _detectWithNativeEngine,
      {
        'pixels': rgbaPixels,
        'width': width,
        'height': height,
        'colorCount': colorCount,
        'mergeLimit': mergeFragmentsUpToPixelCount,
      },
    );

    final rawRegions = result['regions']! as List<Map<String, Object>>;
    return RegionDetectionResult(
      width: result['width']! as int,
      height: result['height']! as int,
      rgbaPixels: result['pixels']! as Uint8List,
      regionLabels: result['labels']! as Uint32List,
      regions: rawRegions
          .map(
            (region) => DetectedColorRegion(
              id: region['id']! as int,
              color: region['color']! as int,
              pixelCount: region['pixelCount']! as int,
              percentage: region['percentage']! as double,
              left: region['left']! as int,
              top: region['top']! as int,
              width: region['width']! as int,
              height: region['height']! as int,
              holeCount: region['holeCount']! as int,
              touchesImageEdge: region['touchesImageEdge']! as bool,
            ),
          )
          .toList(growable: false),
    );
  }
}

Map<String, Object> _detectWithNativeEngine(Map<String, Object> args) {
  final pixels = args['pixels']! as Uint8List;
  final width = args['width']! as int;
  final height = args['height']! as int;
  final colorCount = args['colorCount']! as int;
  final mergeLimit = args['mergeLimit']! as int;

  final library = DynamicLibrary.open('leo_region_engine.dll');
  final analyze = library.lookupFunction<
      Pointer<Void> Function(
        Pointer<Uint8>, Int32, Int32, Uint32, Uint32, Uint8,
      ),
      Pointer<Void> Function(
        Pointer<Uint8>, int, int, int, int, int,
      )>('leo_region_analyze');
  final getCount = library.lookupFunction<
      Uint32 Function(Pointer<Void>),
      int Function(Pointer<Void>)>('leo_region_result_count');
  final getRegion = library.lookupFunction<
      Int32 Function(Pointer<Void>, Uint32, Pointer<_NativeRegionInfo>),
      int Function(Pointer<Void>, int, Pointer<_NativeRegionInfo>)>(
    'leo_region_result_get_region',
  );
  final copyLabels = library.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint32>, Uint64),
      int Function(Pointer<Void>, Pointer<Uint32>, int)>(
    'leo_region_result_copy_labels',
  );
  final freeResult = library.lookupFunction<
      Void Function(Pointer<Void>),
      void Function(Pointer<Void>)>('leo_region_result_free');

  final nativePixels = calloc<Uint8>(pixels.length);
  final nativeInfo = calloc<_NativeRegionInfo>();
  final nativeResult = calloc<Uint32>(width * height);
  Pointer<Void> handle = nullptr;

  try {
    nativePixels.asTypedList(pixels.length).setAll(0, pixels);
    handle = analyze(
      nativePixels,
      width,
      height,
      colorCount,
      mergeLimit,
      8,
    );
    if (handle == nullptr) {
      throw StateError('LeoStitch could not analyse the supplied artwork.');
    }

    final count = getCount(handle);
    final regions = <Map<String, Object>>[];
    for (var index = 0; index < count; index++) {
      if (getRegion(handle, index, nativeInfo) == 0) {
        throw StateError('LeoStitch returned incomplete region information.');
      }
      final info = nativeInfo.ref;
      final color = 0xFF000000 |
          (info.red << 16) |
          (info.green << 8) |
          info.blue;
      regions.add({
        'id': info.id,
        'color': color,
        'pixelCount': info.pixelCount,
        'percentage': info.pixelCount * 100 / (width * height),
        'left': info.left,
        'top': info.top,
        'width': info.width,
        'height': info.height,
        'holeCount': info.holeCount,
        'touchesImageEdge': info.touchesImageEdge != 0,
      });
    }

    if (copyLabels(handle, nativeResult, width * height) == 0) {
      throw StateError('LeoStitch could not return the region pixel map.');
    }

    return {
      'width': width,
      'height': height,
      'pixels': pixels,
      'labels': Uint32List.fromList(
        nativeResult.asTypedList(width * height),
      ),
      'regions': regions,
    };
  } finally {
    if (handle != nullptr) freeResult(handle);
    calloc.free(nativeResult);
    calloc.free(nativeInfo);
    calloc.free(nativePixels);
  }
}

final class _NativeRegionInfo extends Struct {
  @Uint32()
  external int id;

  @Uint8()
  external int red;

  @Uint8()
  external int green;

  @Uint8()
  external int blue;

  @Uint8()
  external int alpha;

  @Int32()
  external int left;

  @Int32()
  external int top;

  @Int32()
  external int width;

  @Int32()
  external int height;

  @Uint32()
  external int pixelCount;

  @Uint32()
  external int holeCount;

  @Uint8()
  external int touchesImageEdge;
}
