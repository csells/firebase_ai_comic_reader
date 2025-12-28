import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:comic_reader/models/panel.dart';
import 'package:flutter/material.dart';

// When true, panel bounding boxes are drawn in red around panels. This is
// useful for testing the accuracy of your object detection model.
const bool kDebugPanelBoundaries = false;

class PanelView extends StatefulWidget {
  final String imageUrl;
  final List<Panel> panels;
  final int currentPanelIndex;
  final bool panelMode;

  const PanelView({
    super.key,
    required this.imageUrl,
    required this.panels,
    required this.currentPanelIndex,
    required this.panelMode,
  });

  @override
  State<PanelView> createState() => _PanelViewState();
}

class _PanelViewState extends State<PanelView> {
  final TransformationController _transformationController =
      TransformationController();

  ui.Image? _uiImage;
  Size? _imageSize;
  Size? _viewSize;

  @override
  void initState() {
    super.initState();
    _loadUiImage();
  }

  @override
  void didUpdateWidget(covariant PanelView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.panelMode != oldWidget.panelMode ||
        widget.currentPanelIndex != oldWidget.currentPanelIndex) {
      _scheduleJump();
    }
  }

  void _scheduleJump() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _jumpToPanel(widget.currentPanelIndex);
    });
  }

  Future<void> _loadUiImage() async {
    try {
      final completer = Completer<ui.Image>();
      final stream = Image.network(
        widget.imageUrl,
      ).image.resolve(const ImageConfiguration());
      late final ImageStreamListener listener;

      listener = ImageStreamListener(
        (info, _) {
          stream.removeListener(listener);
          completer.complete(info.image);
        },
        onError: (error, stack) {
          stream.removeListener(listener);
          completer.completeError(error, stack);
        },
      );
      stream.addListener(listener);

      final loadedImage = await completer.future;
      if (!mounted) return;

      final imageWidth = loadedImage.width.toDouble();
      final imageHeight = loadedImage.height.toDouble();

      setState(() {
        _uiImage = loadedImage;
        _imageSize = Size(imageWidth, imageHeight);
      });

      // Prepare panels for display
      for (var panel in widget.panels) {
        panel.convertToImageCoordinates(imageWidth, imageHeight);
      }

      if (widget.panelMode) {
        _scheduleJump();
      }
    } catch (e) {
      debugPrint('PanelView: Error loading image: $e');
    }
  }

  void _jumpToPanel(int index) {
    if (!widget.panelMode ||
        _uiImage == null ||
        _imageSize == null ||
        _viewSize == null ||
        widget.panels.isEmpty) {
      _transformationController.value = Matrix4.identity();
      return;
    }

    if (index < 0 || index >= widget.panels.length) {
      return;
    }

    final panel = widget.panels[index];
    final pixelBox = panel.pixelBox;
    if (pixelBox == null || pixelBox.width <= 0 || pixelBox.height <= 0) {
      return;
    }

    const double padding = 32.0;
    final viewWidth = _viewSize!.width - 2 * padding;
    final viewHeight = _viewSize!.height - 2 * padding;

    final scale = math.min(
      viewWidth / pixelBox.width,
      viewHeight / pixelBox.height,
    );

    final panelCenterX = pixelBox.left + pixelBox.width / 2;
    final panelCenterY = pixelBox.top + pixelBox.height / 2;

    final tx = (viewWidth / 2) - (panelCenterX * scale);
    final ty = (viewHeight / 2) - (panelCenterY * scale);

    _transformationController.value = Matrix4.identity()
      ..setTranslationRaw(tx, ty, 0.0)
      ..scaleByDouble(scale, scale, scale, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final newViewSize = Size(constraints.maxWidth, constraints.maxHeight);
        if (_viewSize != newViewSize) {
          _viewSize = newViewSize;
          if (widget.panelMode) {
            _scheduleJump();
          }
        }

        if (_uiImage == null || _imageSize == null) {
          return const Center(child: CircularProgressIndicator());
        }

        return Container(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: InteractiveViewer(
              transformationController: _transformationController,
              minScale: 1.0,
              maxScale: 5.0,
              boundaryMargin: const EdgeInsets.all(2000),
              clipBehavior: Clip.none,
              constrained: false,
              child: CustomPaint(
                size: _imageSize!,
                painter: widget.panelMode
                    ? _buildSmartModePainter(
                        Theme.of(context).scaffoldBackgroundColor,
                      )
                    : _buildNormalModePainter(),
              ),
            ),
          ),
        );
      },
    );
  }

  CustomPainter _buildNormalModePainter() {
    return PanelImagePainter(uiImage: _uiImage!, panels: widget.panels);
  }

  CustomPainter _buildSmartModePainter(Color backgroundColor) {
    if (widget.panels.isEmpty ||
        widget.currentPanelIndex < 0 ||
        widget.currentPanelIndex >= widget.panels.length) {
      return _buildNormalModePainter();
    }

    final panel = widget.panels[widget.currentPanelIndex];
    return SmartPanelImagePainter(
      uiImage: _uiImage!,
      panelRect: panel.pixelBox ?? Rect.zero,
      backgroundColor: backgroundColor,
    );
  }
}

class PanelImagePainter extends CustomPainter {
  final ui.Image uiImage;
  final List<Panel> panels;

  PanelImagePainter({required this.uiImage, required this.panels});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImage(uiImage, Offset.zero, Paint());

    if (kDebugPanelBoundaries) {
      final redPaint = Paint()
        ..color = Colors.red
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;

      for (final panel in panels) {
        final rect = panel.pixelBox;
        if (rect != null && !rect.isEmpty) {
          canvas.drawRect(rect, redPaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant PanelImagePainter oldDelegate) {
    return oldDelegate.uiImage != uiImage || oldDelegate.panels != panels;
  }
}

class SmartPanelImagePainter extends CustomPainter {
  final ui.Image uiImage;
  final Rect panelRect;
  final Color backgroundColor;

  SmartPanelImagePainter({
    required this.uiImage,
    required this.panelRect,
    required this.backgroundColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1) Paint entire image area with theme background color
    final backgroundPaint = Paint()..color = backgroundColor;
    final imageBounds = Rect.fromLTWH(
      0,
      0,
      uiImage.width.toDouble(),
      uiImage.height.toDouble(),
    );
    canvas.drawRect(imageBounds, backgroundPaint);

    // 2) Clip to the panelRect, then draw the image into that area
    canvas.save();
    canvas.clipRect(panelRect);
    canvas.drawImage(uiImage, Offset.zero, Paint());
    canvas.restore();

    if (kDebugPanelBoundaries) {
      final outline = Paint()
        ..color = Colors.red
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      canvas.drawRect(panelRect, outline);
    }
  }

  @override
  bool shouldRepaint(covariant SmartPanelImagePainter oldDelegate) {
    return oldDelegate.uiImage != uiImage || oldDelegate.panelRect != panelRect;
  }
}
