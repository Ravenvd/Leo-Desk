import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'region_selection_screen.dart';

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
  bool _cropCompleted = false;

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
        _cropCompleted = false;
        _widthController.clear();
        _heightController.clear();
      });
    } on FormatException catch (error) {
      if (mounted) _showError(error.message);
    } catch (error) {
      if (mounted) {
        _showError('Unable to import this image. Please try another file.');
      }
      debugPrint('Artwork import failed: $error');
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  void _completeCropStep(int width, int height) {
    setState(() {
      _cropCompleted = true;
      _widthController.text = _formatInches(_initialWidthInches);
      _heightController.text =
          _formatInches(_initialWidthInches * height / width);
    });
  }

  Future<void> _cropArtwork() async {
    final bytes = _artworkBytes;
    if (bytes == null) return;

    final croppedBytes = await showDialog<Uint8List>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _ArtworkCropDialog(
        imageBytes: bytes,
        imageWidth: _imageWidth!,
        imageHeight: _imageHeight!,
      ),
    );

    if (croppedBytes == null || !mounted) return;

    try {
      final codec = await ui.instantiateImageCodec(croppedBytes);
      final frame = await codec.getNextFrame();
      final width = frame.image.width;
      final height = frame.image.height;
      frame.image.dispose();
      codec.dispose();

      if (!mounted) return;
      setState(() {
        _artworkBytes = croppedBytes;
        _fileName = _fileName == null ? 'Cropped artwork' : 'Cropped $_fileName';
        _imageWidth = width;
        _imageHeight = height;
        _fileSize = croppedBytes.length;
      });
      _completeCropStep(width, height);
    } catch (error) {
      if (mounted) _showError('The cropped image could not be created.');
      debugPrint('Artwork crop failed: $error');
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
      _cropCompleted = false;
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
        if (!_cropCompleted) ...[
          _buildCropStepPanel(compact),
          const SizedBox(height: 12),
        ] else ...[
          _buildPhysicalSizePanel(compact),
          const SizedBox(height: 12),
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

  Widget _buildCropStepPanel(bool compact) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Crop artwork', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Select the part of the image you want to embroider. '
              'Remove blank margins and unwanted background before setting its size.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _cropArtwork,
                  icon: const Icon(Icons.crop_rounded),
                  label: const Text('Crop artwork'),
                ),
                OutlinedButton(
                  onPressed: () => _completeCropStep(_imageWidth!, _imageHeight!),
                  child: const Text('Use original image'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhysicalSizePanel(bool compact) {
    final widthMm = _physicalWidthMm;
    final heightMm = _physicalHeightMm;
    final validSize = widthMm != null &&
        heightMm != null &&
        widthMm > 0 &&
        heightMm > 0 &&
        widthMm.isFinite &&
        heightMm.isFinite;

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
                      suffixText: 'in',
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
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: validSize ? _openRegionSelection : null,
                icon: const Icon(Icons.tune_rounded),
                label: const Text('Continue to region selection'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openRegionSelection() {
    final bytes = _artworkBytes;
    final widthMm = _physicalWidthMm;
    final heightMm = _physicalHeightMm;
    if (bytes == null || widthMm == null || heightMm == null) return;

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RegionSelectionScreen(
          imageBytes: bytes,
          physicalWidthMm: widthMm,
          physicalHeightMm: heightMm,
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

class _ArtworkCropDialog extends StatefulWidget {
  const _ArtworkCropDialog({
    required this.imageBytes,
    required this.imageWidth,
    required this.imageHeight,
  });

  final Uint8List imageBytes;
  final int imageWidth;
  final int imageHeight;

  @override
  State<_ArtworkCropDialog> createState() => _ArtworkCropDialogState();
}

class _ArtworkCropDialogState extends State<_ArtworkCropDialog> {
  Rect? _selection;
  Rect? _dragOrigin;
  Offset? _dragStart;
  String _dragMode = 'new';
  bool _isCropping = false;

  Rect _fittedImageRect(Size size) {
    final imageRatio = widget.imageWidth / widget.imageHeight;
    final viewRatio = size.width / size.height;
    late double width;
    late double height;
    if (imageRatio > viewRatio) {
      width = size.width;
      height = width / imageRatio;
    } else {
      height = size.height;
      width = height * imageRatio;
    }
    return Rect.fromLTWH(
      (size.width - width) / 2,
      (size.height - height) / 2,
      width,
      height,
    );
  }

  Offset? _normalisedPoint(Offset point, Rect imageRect) {
    if (!imageRect.contains(point)) return null;
    return Offset(
      ((point.dx - imageRect.left) / imageRect.width).clamp(0.0, 1.0),
      ((point.dy - imageRect.top) / imageRect.height).clamp(0.0, 1.0),
    );
  }

  Map<String, Offset> _handlePositions(Rect rect) => {
        'topLeft': rect.topLeft,
        'top': Offset(rect.center.dx, rect.top),
        'topRight': rect.topRight,
        'right': Offset(rect.right, rect.center.dy),
        'bottomRight': rect.bottomRight,
        'bottom': Offset(rect.center.dx, rect.bottom),
        'bottomLeft': rect.bottomLeft,
        'left': Offset(rect.left, rect.center.dy),
      };

  void _startSelection(
    DragStartDetails details,
    Rect imageRect,
    Rect? selectedRect,
  ) {
    final point = _normalisedPoint(details.localPosition, imageRect);
    if (point == null) return;

    var mode = 'new';
    if (selectedRect != null) {
      for (final entry in _handlePositions(selectedRect).entries) {
        if ((details.localPosition - entry.value).distance <= 22) {
          mode = entry.key;
          break;
        }
      }
      if (mode == 'new' && selectedRect.contains(details.localPosition)) {
        mode = 'move';
      }
    }

    setState(() {
      _dragStart = point;
      _dragOrigin = _selection;
      _dragMode = mode;
      if (mode == 'new') _selection = Rect.fromPoints(point, point);
    });
  }

  void _updateSelection(DragUpdateDetails details, Rect imageRect) {
    final start = _dragStart;
    if (start == null) return;
    final point = _normalisedPoint(
      Offset(
        details.localPosition.dx.clamp(imageRect.left, imageRect.right).toDouble(),
        details.localPosition.dy.clamp(imageRect.top, imageRect.bottom).toDouble(),
      ),
      imageRect,
    );
    if (point == null) return;

    const minimumSize = 0.01;
    final origin = _dragOrigin;
    Rect next;
    switch (_dragMode) {
      case 'move':
        if (origin == null) return;
        final dx = point.dx - start.dx;
        final dy = point.dy - start.dy;
        final left =
            (origin.left + dx).clamp(0.0, 1.0 - origin.width).toDouble();
        final top =
            (origin.top + dy).clamp(0.0, 1.0 - origin.height).toDouble();
        next = Rect.fromLTWH(left, top, origin.width, origin.height);
        break;
      case 'left':
        if (origin == null) return;
        next = Rect.fromLTRB(
          point.dx.clamp(0.0, origin.right - minimumSize).toDouble(),
          origin.top, origin.right, origin.bottom);
        break;
      case 'right':
        if (origin == null) return;
        next = Rect.fromLTRB(
          origin.left, origin.top,
          point.dx.clamp(origin.left + minimumSize, 1.0).toDouble(),
          origin.bottom);
        break;
      case 'top':
        if (origin == null) return;
        next = Rect.fromLTRB(
          origin.left,
          point.dy.clamp(0.0, origin.bottom - minimumSize).toDouble(),
          origin.right, origin.bottom);
        break;
      case 'bottom':
        if (origin == null) return;
        next = Rect.fromLTRB(
          origin.left, origin.top, origin.right,
          point.dy.clamp(origin.top + minimumSize, 1.0).toDouble());
        break;
      case 'topLeft':
        if (origin == null) return;
        next = Rect.fromLTRB(
          point.dx.clamp(0.0, origin.right - minimumSize).toDouble(),
          point.dy.clamp(0.0, origin.bottom - minimumSize).toDouble(),
          origin.right, origin.bottom);
        break;
      case 'topRight':
        if (origin == null) return;
        next = Rect.fromLTRB(
          origin.left,
          point.dy.clamp(0.0, origin.bottom - minimumSize).toDouble(),
          point.dx.clamp(origin.left + minimumSize, 1.0).toDouble(),
          origin.bottom);
        break;
      case 'bottomLeft':
        if (origin == null) return;
        next = Rect.fromLTRB(
          point.dx.clamp(0.0, origin.right - minimumSize).toDouble(),
          origin.top, origin.right,
          point.dy.clamp(origin.top + minimumSize, 1.0).toDouble());
        break;
      case 'bottomRight':
        if (origin == null) return;
        next = Rect.fromLTRB(
          origin.left, origin.top,
          point.dx.clamp(origin.left + minimumSize, 1.0).toDouble(),
          point.dy.clamp(origin.top + minimumSize, 1.0).toDouble());
        break;
      default:
        next = Rect.fromPoints(start, point);
        break;
    }
    setState(() => _selection = next);
  }

  void _finishSelection(DragEndDetails details) {
    _dragStart = null;
    _dragOrigin = null;
    _dragMode = 'new';
    final selection = _selection;
    if (selection == null ||
        selection.width < 0.01 ||
        selection.height < 0.01) {
      setState(() => _selection = null);
    }
  }

  Future<void> _applyCrop() async {
    final selection = _selection;
    if (selection == null || selection.width < 0.01 || selection.height < 0.01) {
      return;
    }

    setState(() => _isCropping = true);
    ui.Codec? codec;
    ui.Image? sourceImage;
    ui.Image? outputImage;
    try {
      codec = await ui.instantiateImageCodec(widget.imageBytes);
      final frame = await codec.getNextFrame();
      sourceImage = frame.image;

      final left = (selection.left * widget.imageWidth)
          .floor()
          .clamp(0, widget.imageWidth - 1);
      final top = (selection.top * widget.imageHeight)
          .floor()
          .clamp(0, widget.imageHeight - 1);
      final right = (selection.right * widget.imageWidth)
          .ceil()
          .clamp(left + 1, widget.imageWidth);
      final bottom = (selection.bottom * widget.imageHeight)
          .ceil()
          .clamp(top + 1, widget.imageHeight);
      final cropWidth = right - left;
      final cropHeight = bottom - top;

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawImageRect(
        sourceImage,
        Rect.fromLTWH(
          left.toDouble(),
          top.toDouble(),
          cropWidth.toDouble(),
          cropHeight.toDouble(),
        ),
        Rect.fromLTWH(0, 0, cropWidth.toDouble(), cropHeight.toDouble()),
        Paint()..filterQuality = FilterQuality.high,
      );
      final picture = recorder.endRecording();
      outputImage = await picture.toImage(cropWidth, cropHeight);
      picture.dispose();
      final data = await outputImage.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('Could not encode cropped image.');

      if (!mounted) return;
      Navigator.of(context).pop(data.buffer.asUint8List());
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to crop this image.')),
        );
      }
      debugPrint('Crop operation failed: $error');
    } finally {
      sourceImage?.dispose();
      outputImage?.dispose();
      codec?.dispose();
      if (mounted) setState(() => _isCropping = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000, maxHeight: 760),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('Crop artwork',
                        style: theme.textTheme.headlineSmall),
                  ),
                  IconButton(
                    tooltip: 'Close crop tool',
                    onPressed: _isCropping
                        ? null
                        : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Drag across the image to draw the crop area. '
                'Only the selected area will be kept.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              Flexible(
                child: Container(
                  constraints: const BoxConstraints(minHeight: 260),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final imageRect = _fittedImageRect(
                        Size(constraints.maxWidth, constraints.maxHeight),
                      );
                      final selectedRect = _selection == null
                          ? null
                          : Rect.fromLTRB(
                              imageRect.left + _selection!.left * imageRect.width,
                              imageRect.top + _selection!.top * imageRect.height,
                              imageRect.left + _selection!.right * imageRect.width,
                              imageRect.top + _selection!.bottom * imageRect.height,
                            );
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanStart: (details) =>
                            _startSelection(details, imageRect, selectedRect),
                        onPanUpdate: (details) =>
                            _updateSelection(details, imageRect),
                        onPanEnd: _finishSelection,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Positioned.fromRect(
                              rect: imageRect,
                              child: Image.memory(
                                widget.imageBytes,
                                fit: BoxFit.fill,
                                filterQuality: FilterQuality.high,
                              ),
                            ),
                            CustomPaint(
                              painter: _CropOverlayPainter(
                                imageRect: imageRect,
                                selectionRect: selectedRect,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  TextButton(
                    onPressed: _isCropping
                        ? null
                        : () => setState(() => _selection = null),
                    child: const Text('Reset selection'),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _isCropping
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _isCropping || _selection == null
                        ? null
                        : _applyCrop,
                    icon: _isCropping
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check_rounded),
                    label: Text(_isCropping ? 'Cropping...' : 'Apply crop'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CropOverlayPainter extends CustomPainter {
  const _CropOverlayPainter({
    required this.imageRect,
    required this.selectionRect,
  });

  final Rect imageRect;
  final Rect? selectionRect;

  @override
  void paint(Canvas canvas, Size size) {
    final dimPaint = Paint()..color = Colors.black.withValues(alpha: 0.58);
    final outside = Path()..addRect(imageRect);
    if (selectionRect != null) {
      outside.addRect(selectionRect!);
      outside.fillType = PathFillType.evenOdd;
    }
    canvas.drawPath(outside, dimPaint);

    if (selectionRect != null) {
      final border = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawRect(selectionRect!, border);

      final handleFill = Paint()..color = Colors.white;
      final handleBorder = Paint()
        ..color = Colors.black87
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      final handlePoints = [
        selectionRect!.topLeft,
        Offset(selectionRect!.center.dx, selectionRect!.top),
        selectionRect!.topRight,
        Offset(selectionRect!.right, selectionRect!.center.dy),
        selectionRect!.bottomRight,
        Offset(selectionRect!.center.dx, selectionRect!.bottom),
        selectionRect!.bottomLeft,
        Offset(selectionRect!.left, selectionRect!.center.dy),
      ];
      for (final point in handlePoints) {
        canvas.drawCircle(point, 6, handleFill);
        canvas.drawCircle(point, 6, handleBorder);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CropOverlayPainter oldDelegate) =>
      oldDelegate.imageRect != imageRect ||
      oldDelegate.selectionRect != selectionRect;
}
