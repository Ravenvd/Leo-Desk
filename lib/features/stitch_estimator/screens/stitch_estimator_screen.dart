import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class StitchEstimatorScreen extends StatefulWidget {
  const StitchEstimatorScreen({super.key});

  @override
  State<StitchEstimatorScreen> createState() => _StitchEstimatorScreenState();
}

class _StitchEstimatorScreenState extends State<StitchEstimatorScreen> {
  static const _supportedExtensions = ['png', 'jpg', 'jpeg', 'bmp'];
  static const double _initialWidthInches = 4.0;
  static const double _millimetresPerInch = 25.4;

  final TextEditingController _widthController = TextEditingController();
  final TextEditingController _heightController = TextEditingController();

  Uint8List? _artworkBytes;
  String? _fileName;
  int? _imageWidth;
  int? _imageHeight;
  int? _fileSize;
  bool _isImporting = false;
  bool _lockAspectRatio = true;

  double? get _aspectRatio {
    if (_imageWidth == null || _imageHeight == null || _imageHeight == 0) {
      return null;
    }
    return _imageWidth! / _imageHeight!;
  }

  double? get _physicalWidthInches => double.tryParse(_widthController.text);
  double? get _physicalHeightInches => double.tryParse(_heightController.text);

  // Keep the estimator's internal physical dimensions in millimetres.
  double? get _physicalWidthMm =>
      _physicalWidthInches == null ? null : _physicalWidthInches! * _millimetresPerInch;
  double? get _physicalHeightMm =>
      _physicalHeightInches == null ? null : _physicalHeightInches! * _millimetresPerInch;

  Future<void> _importArtwork() async {
    if (_isImporting) return;
    setState(() => _isImporting = true);

    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: _supportedExtensions,
        allowMultiple: false,
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.single;
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) {
        throw const FormatException('The selected image could not be read.');
      }

      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final width = frame.image.width;
      final height = frame.image.height;
      frame.image.dispose();
      codec.dispose();

      if (!mounted) return;
      setState(() {
        _artworkBytes = bytes;
        _fileName = file.name;
        _imageWidth = width;
        _imageHeight = height;
        _fileSize = file.size;
        _widthController.text = _formatInches(_initialWidthInches);
        _heightController.text =
            _formatInches(_initialWidthInches * height / width);
      });
    } on FormatException catch (error) {
      if (mounted) _showError(error.message);
    } catch (error) {
      if (mounted) _showError('Unable to import this image. Please try another file.');
      debugPrint('Artwork import failed: $error');
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  void _updateWidth(String value) {
    final width = double.tryParse(value);
    final ratio = _aspectRatio;
    if (!_lockAspectRatio || width == null || width <= 0 || ratio == null) {
      setState(() {});
      return;
    }

    _heightController.text = _formatInches(width / ratio);
    setState(() {});
  }

  void _updateHeight(String value) {
    final height = double.tryParse(value);
    final ratio = _aspectRatio;
    if (!_lockAspectRatio || height == null || height <= 0 || ratio == null) {
      setState(() {});
      return;
    }

    _widthController.text = _formatInches(height * ratio);
    setState(() {});
  }

  String _formatInches(double value) => value.toStringAsFixed(2);

  void _clearArtwork() {
    setState(() {
      _artworkBytes = null;
      _fileName = null;
      _imageWidth = null;
      _imageHeight = null;
      _fileSize = null;
      _widthController.clear();
      _heightController.clear();
    });
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _formatFileSize(int? bytes) {
    if (bytes == null) return 'Size unavailable';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  @override
  void dispose() {
    _widthController.dispose();
    _heightController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasArtwork = _artworkBytes != null;
    final compact = MediaQuery.sizeOf(context).width < 700;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.all(compact ? 16 : 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(compact),
            const SizedBox(height: 24),
            Expanded(
              child: hasArtwork
                  ? _buildArtworkWorkspace(compact)
                  : _buildEmptyWorkspace(compact),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(bool compact) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Stitch Estimator',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 6),
              Text(
                'Import artwork and set its intended embroidery size.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ],
          ),
        ),
        if (_artworkBytes != null && !compact)
          OutlinedButton.icon(
            onPressed: _isImporting ? null : _importArtwork,
            icon: const Icon(Icons.swap_horiz_rounded),
            label: const Text('Replace artwork'),
          ),
      ],
    );
  }

  Widget _buildEmptyWorkspace(bool compact) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: Card(
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 24 : 56,
              vertical: compact ? 36 : 64,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Icon(
                    Icons.image_outlined,
                    size: 42,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Import your artwork',
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  'Choose an image to begin preparing your embroidery design. '
                  'You can review it here before moving on to region selection.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _isImporting ? null : _importArtwork,
                  icon: _isImporting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.upload_file_rounded),
                  label: Text(_isImporting ? 'Importing...' : 'Import artwork'),
                ),
                const SizedBox(height: 16),
                Text(
                  'Supported formats: PNG, JPG, JPEG, BMP',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildArtworkWorkspace(bool compact) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (compact) ...[
          Row(
            children: [
              Expanded(child: _buildFileDetails()),
              IconButton(
                tooltip: 'Replace artwork',
                onPressed: _isImporting ? null : _importArtwork,
                icon: const Icon(Icons.swap_horiz_rounded),
              ),
              IconButton(
                tooltip: 'Remove artwork',
                onPressed: _clearArtwork,
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ],
          ),
          const SizedBox(height: 10),
        ] else ...[
          Row(
            children: [
              Expanded(child: _buildFileDetails()),
              TextButton.icon(
                onPressed: _clearArtwork,
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('Remove'),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        _buildPhysicalSizePanel(compact),
        const SizedBox(height: 12),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
            ),
            clipBehavior: Clip.antiAlias,
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 5,
              child: Center(
                child: Image.memory(
                  _artworkBytes!,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                  errorBuilder: (_, _, _) => const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('This image could not be displayed.'),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Artwork preview · Use the mouse wheel or pinch to zoom',
          style: Theme.of(context).textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildPhysicalSizePanel(bool compact) {
    final width = _physicalWidthInches;
    final height = _physicalHeightInches;
    final validSize = width != null &&
        height != null &&
        width > 0 &&
        height > 0 &&
        width.isFinite &&
        height.isFinite;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Embroidery size',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Set the real-world size you want the finished design to be. '
              'The initial width is 4 inches.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: compact ? 125 : 150,
                  child: TextField(
                    controller: _widthController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Width (in)',
                      isDense: true,
                      suffixText: 'in',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: _updateWidth,
                  ),
                ),
                SizedBox(
                  width: compact ? 125 : 150,
                  child: TextField(
                    controller: _heightController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Height (in)',
                      isDense: true,
                      suffixText: 'mm',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: _updateHeight,
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Checkbox(
                      value: _lockAspectRatio,
                      onChanged: (value) {
                        setState(() => _lockAspectRatio = value ?? false);
                      },
                    ),
                    const Text('Keep proportions'),
                  ],
                ),
              ],
            ),
            if (!validSize)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Enter a width and height greater than zero.',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFileDetails() {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(Icons.image_rounded, color: theme.colorScheme.primary, size: 28),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _fileName ?? 'Artwork',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 3),
              Text(
                '$_imageWidth × $_imageHeight px  ·  ${_formatFileSize(_fileSize)}',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
