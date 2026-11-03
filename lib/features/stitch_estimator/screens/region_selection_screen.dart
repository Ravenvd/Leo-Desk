import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../services/region_detection_service.dart';

class RegionSelectionScreen extends StatefulWidget {
  const RegionSelectionScreen({
    super.key,
    required this.imageBytes,
    required this.physicalWidthMm,
    required this.physicalHeightMm,
  });

  final Uint8List imageBytes;
  final double physicalWidthMm;
  final double physicalHeightMm;

  @override
  State<RegionSelectionScreen> createState() => _RegionSelectionScreenState();
}

class _RegionSelectionScreenState extends State<RegionSelectionScreen> {
  int _colorCount = 5;
  int _fragmentMergeSize = 2;
  bool _isDetecting = false;
  String? _errorMessage;
  RegionDetectionResult? _detection;
  ui.Image? _previewImage;
  int? _selectedRegionIndex;
  final Map<int, bool> _includedRegions = {};

  Future<void> _detectRegions() async {
    if (_isDetecting) return;
    setState(() {
      _isDetecting = true;
      _errorMessage = null;
    });

    ui.Codec? codec;
    ui.Image? sourceImage;
    try {
      codec = await ui.instantiateImageCodec(
        widget.imageBytes,
      );
      final frame = await codec.getNextFrame();
      sourceImage = frame.image;
      final pixelData = await sourceImage.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (pixelData == null) {
        throw StateError('Could not read the artwork pixels.');
      }

      final result = await RegionDetectionService.detect(
        rgbaPixels: pixelData.buffer.asUint8List(),
        width: sourceImage.width,
        height: sourceImage.height,
        colorCount: _colorCount,
        mergeFragmentsUpToPixelCount: _fragmentMergeSize,
      );

      if (!mounted) return;
      _detection = result;
      _includedRegions
        ..clear()
        ..addEntries(
          result.regions.asMap().entries.map((entry) => MapEntry(entry.key, true)),
        );
      _selectedRegionIndex = result.regions.isEmpty ? null : 0;
      await _refreshPreview();
    } catch (error) {
      if (mounted) {
        setState(() {
          _errorMessage = error is UnsupportedError
              ? error.message.toString()
              : 'LeoStitch could not identify regions in this artwork. $error';
        });
      }
      debugPrint('Region detection failed: $error');
    } finally {
      sourceImage?.dispose();
      codec?.dispose();
      if (mounted) setState(() => _isDetecting = false);
    }
  }

  Future<void> _refreshPreview() async {
    final result = _detection;
    if (result == null) return;

    final pixels = Uint8List.fromList(result.rgbaPixels);
    final selected = _selectedRegionIndex;
    final included = _includedRegions;

    for (var pixel = 0; pixel < result.regionLabels.length; pixel++) {
      final regionIndex = result.regionLabels[pixel];
      if (regionIndex == 0xFFFFFFFF) continue;
      final offset = pixel * 4;
      final isIncluded = included[regionIndex] ?? true;
      final isSelected = selected == regionIndex;
      final factor =
          !isIncluded ? 0.08 : (selected == null || isSelected ? 1.0 : 0.34);
      if (factor < 1) {
        pixels[offset] = (pixels[offset] * factor).round();
        pixels[offset + 1] = (pixels[offset + 1] * factor).round();
        pixels[offset + 2] = (pixels[offset + 2] * factor).round();
      }
    }

    ui.decodeImageFromPixels(
      pixels,
      result.width,
      result.height,
      ui.PixelFormat.rgba8888,
      (image) {
        if (!mounted) {
          image.dispose();
          return;
        }
        setState(() {
          _previewImage?.dispose();
          _previewImage = image;
        });
      },
    );
  }

  void _selectRegion(int regionIndex) {
    setState(() => _selectedRegionIndex = regionIndex);
    _refreshPreview();
  }

  void _toggleRegion(int regionIndex, bool included) {
    setState(() => _includedRegions[regionIndex] = included);
    _refreshPreview();
  }


  @override
  void dispose() {
    _previewImage?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = _detection;
    final includedCount =
        _includedRegions.values.where((included) => included).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Assisted Region Selection'),
        leading: IconButton(
          tooltip: 'Back to artwork',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Identify colour regions',
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 6),
              Text(
                'Choose the colour count and small-fragment threshold, then let '
                'the LeoStitch engine identify individual connected regions.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 4),
              Text(
                'Target size: ${widget.physicalWidthMm.toStringAsFixed(1)} × '
                '${widget.physicalHeightMm.toStringAsFixed(1)} mm',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Wrap(
                    spacing: 16,
                    runSpacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: 230,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Number of colours: $_colorCount',
                              style: theme.textTheme.titleSmall,
                            ),
                            Slider(
                              min: 1,
                              max: 32,
                              divisions: 31,
                              value: _colorCount.toDouble(),
                              label: '$_colorCount',
                              onChanged: _isDetecting
                                  ? null
                                  : (value) => setState(
                                        () => _colorCount = value.round(),
                                      ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 230,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Merge fragments up to: $_fragmentMergeSize px',
                              style: theme.textTheme.titleSmall,
                            ),
                            Slider(
                              min: 0,
                              max: 100,
                              divisions: 100,
                              value: _fragmentMergeSize.toDouble(),
                              label: '$_fragmentMergeSize px',
                              onChanged: _isDetecting
                                  ? null
                                  : (value) => setState(
                                        () => _fragmentMergeSize = value.round(),
                                      ),
                            ),
                          ],
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: _isDetecting ? null : _detectRegions,
                        icon: _isDetecting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.auto_awesome_rounded),
                        label: Text(
                          _isDetecting ? 'Detecting...' : 'Detect regions',
                        ),
                      ),
                      if (result != null)
                        Text(
                          '$includedCount of ${result.regions.length} regions included',
                          style: theme.textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  _errorMessage!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ],
              const SizedBox(height: 14),
              Expanded(
                child: result == null
                    ? _buildInitialPreview(theme)
                    : _buildDetectedWorkspace(theme, result),
              ),
              if (result != null) ...[
                const SizedBox(height: 12),
                Text(
                  'LeoStitch identifies separate connected shapes. Small fragments '
                  'are merged using the selected pixel threshold.',
                  style: theme.textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInitialPreview(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(
            child: Image.memory(widget.imageBytes, fit: BoxFit.contain),
          ),
          if (_isDetecting)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black.withValues(alpha: 0.35),
                child: const Center(child: CircularProgressIndicator()),
              ),
            ),
          if (!_isDetecting)
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Your artwork will appear here with the detected regions.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface,
                    backgroundColor: theme.colorScheme.surface.withValues(alpha: 0.9),
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDetectedWorkspace(
    ThemeData theme,
    RegionDetectionResult result,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;
        final preview = Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          child: Center(
            child: _previewImage == null
                ? const CircularProgressIndicator()
                : RawImage(
                    image: _previewImage,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.none,
                  ),
          ),
        );
        final regions = _buildRegionList(theme, result);

        if (compact) {
          return Column(
            children: [
              Expanded(flex: 3, child: preview),
              const SizedBox(height: 12),
              Expanded(flex: 2, child: regions),
            ],
          );
        }
        return Row(
          children: [
            Expanded(flex: 3, child: preview),
            const SizedBox(width: 16),
            SizedBox(width: 320, child: regions),
          ],
        );
      },
    );
  }

  Widget _buildRegionList(ThemeData theme, RegionDetectionResult result) {
    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Text(
              'Detected regions',
              style: theme.textTheme.titleMedium,
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
              itemCount: result.regions.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final region = result.regions[index];
                final regionIndex = index;
                final included = _includedRegions[regionIndex] ?? true;
                final selected = _selectedRegionIndex == regionIndex;
                return ListTile(
                  selected: selected,
                  onTap: () => _selectRegion(regionIndex),
                  leading: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Color(region.color),
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(color: theme.colorScheme.outline),
                    ),
                  ),
                  title: Text('Region ${region.id}'),
                  subtitle: Text(
                    '${region.percentage.toStringAsFixed(1)}% · '
                    '${region.pixelCount} px · ${region.width} × ${region.height} px'
                    '${region.holeCount > 0 ? ' · ${region.holeCount} holes' : ''}'
                    '${region.touchesImageEdge ? ' · touches edge' : ''}',
                  ),
                  trailing: Checkbox(
                    value: included,
                    onChanged: (value) =>
                        _toggleRegion(regionIndex, value ?? false),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
