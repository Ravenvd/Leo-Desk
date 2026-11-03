import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

class StitchEstimatorScreen extends StatefulWidget {
  const StitchEstimatorScreen({super.key});

  @override
  State<StitchEstimatorScreen> createState() => _StitchEstimatorScreenState();
}

class _StitchEstimatorScreenState extends State<StitchEstimatorScreen> {
  static const _supportedExtensions = ['png', 'jpg', 'jpeg', 'bmp'];

  Uint8List? _artworkBytes;
  String? _fileName;
  int? _imageWidth;
  int? _imageHeight;
  int? _fileSize;
  bool _isImporting = false;

  Future<void> _importArtwork() async {
    if (_isImporting) return;
    setState(() => _isImporting = true);

    try {
      final result = await FilePicker.platform.pickFiles(
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

  void _clearArtwork() {
    setState(() {
      _artworkBytes = null;
      _fileName = null;
      _imageWidth = null;
      _imageHeight = null;
      _fileSize = null;
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
                'Start by importing the artwork you want to estimate.',
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
          const SizedBox(height: 12),
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
          const SizedBox(height: 16),
        ],
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
                  errorBuilder: (_, __, ___) => const Padding(
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
