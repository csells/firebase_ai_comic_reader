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
  final bool smartMode;

  const PanelView({
    super.key,
    required this.imageUrl,
    required this.panels,
    required this.currentPanelIndex,
    required this.smartMode,
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
  bool _panelsConverted = false;

  @override
  void initState() {
    super.initState();
    _loadUiImage();
  }

  @override
  void didUpdateWidget(covariant PanelView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.smartMode != oldWidget.smartMode ||
        widget.currentPanelIndex != oldWidget.currentPanelIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _jumpToPanel(widget.currentPanelIndex);
      });
    }
  }

  Future<void> _loadUiImage() async {
    final completer = Completer<ui.Image>();
    final stream = Image.network(widget.imageUrl)
        .image
        .resolve(const ImageConfiguration());
    late final ImageStreamListener listener;

    listener = ImageStreamListener((info, _) {
      stream.removeListener(listener);
      completer.complete(info.image);
    }, onError: (error, stack) {
      stream.removeListener(listener);
      completer.completeError(error, stack);
    });
    stream.addListener(listener);

    final loadedImage = await completer.future;
    final imageWidth = loadedImage.width.toDouble();
    final imageHeight = loadedImage.height.toDouble();

    if (!mounted) return;

    setState(() {
      _uiImage = loadedImage;
      _imageSize = Size(imageWidth, imageHeight);
    });

    _convertPanelsToPixelCoordinates(imageWidth, imageHeight);
    _sortPanelsInReadingOrder();

    if (widget.smartMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _jumpToPanel(widget.currentPanelIndex);
      });
    }
  }

  void _convertPanelsToPixelCoordinates(double imageW, double imageH) {
    if (_panelsConverted) return;
    for (var panel in widget.panels) {
      panel.convertToImageCoordinates(imageW, imageH);
    }
    _panelsConverted = true;
  }

  void _sortPanelsInReadingOrder() {
    if (widget.panels.isEmpty) return;

    const rowTolerance = 50.0;
    final panelsWithCenter = widget.panels.map((p) {
      final box = p.pixelBox!;
      return (
        panel: p,
        centerX: box.left + box.width / 2,
        centerY: box.top + box.height / 2
      );
    }).toList();

    // Sort top-to-bottom by centerY
    panelsWithCenter.sort((a, b) => a.centerY.compareTo(b.centerY));

    final rows = <List<(Panel, double)>>[];
    var currentRow = <(Panel, double)>[];

    for (var item in panelsWithCenter) {
      if (currentRow.isEmpty) {
        currentRow.add((item.panel, item.centerX));
      } else {
        final firstRect = currentRow.first.$1.pixelBox!;
        final firstCenterY = firstRect.top + firstRect.height / 2;
        if ((item.centerY - firstCenterY).abs() <= rowTolerance) {
          currentRow.add((item.panel, item.centerX));
        } else {
          rows.add(currentRow);
          currentRow = [(item.panel, item.centerX)];
        }
      }
    }
    if (currentRow.isNotEmpty) rows.add(currentRow);

    final sortedPanels = <Panel>[];
    for (final row in rows) {
      row.sort((a, b) => a.$2.compareTo(b.$2)); // left-to-right
      sortedPanels.addAll(row.map((e) => e.$1));
    }

    widget.panels
      ..clear()
      ..addAll(sortedPanels);
  }

  void _jumpToPanel(int index) {
    if (!widget.smartMode ||
        _uiImage == null ||
        _imageSize == null ||
        widget.panels.isEmpty ||
        _viewSize == null) {
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

    final viewWidth = _viewSize!.width;
    final viewHeight = _viewSize!.height;
    final scale =
        math.min(viewWidth / pixelBox.width, viewHeight / pixelBox.height);

    final panelCenterX = pixelBox.left + pixelBox.width / 2;
    final panelCenterY = pixelBox.top + pixelBox.height / 2;

    final tx = viewWidth / 2 - (panelCenterX * scale);
    final ty = viewHeight / 2 - (panelCenterY * scale);

    _transformationController.value = Matrix4.identity()
      ..setTranslationRaw(tx, ty, 0.0)
      ..scaleByDouble(scale, scale, scale, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _viewSize = Size(constraints.maxWidth, constraints.maxHeight);

        if (_uiImage == null || _imageSize == null) {
          return const Center(child: CircularProgressIndicator());
        }

        // NOTE: Wrap in a black Container so that, when in smart mode,
        // the image is clipped to the current panel.
        return Container(
          color: Colors.black,
          child: InteractiveViewer(
            transformationController: _transformationController,
            minScale: 1.0,
            maxScale: 5.0,
            boundaryMargin: const EdgeInsets.all(2000),
            clipBehavior: Clip.none,
            constrained: false,
            child: CustomPaint(
              size: _imageSize!,
              painter: widget.smartMode
                  ? _buildSmartModePainter()
                  : _buildNormalModePainter(),
            ),
          ),
        );
      },
    );
  }

  CustomPainter _buildNormalModePainter() {
    return PanelImagePainter(
      uiImage: _uiImage!,
      panels: widget.panels,
    );
  }

  CustomPainter _buildSmartModePainter() {
    if (widget.panels.isEmpty ||
        widget.currentPanelIndex < 0 ||
        widget.currentPanelIndex >= widget.panels.length) {
      return _buildNormalModePainter();
    }

    final panel = widget.panels[widget.currentPanelIndex];
    return SmartPanelImagePainter(
      uiImage: _uiImage!,
      panelRect: panel.pixelBox ?? Rect.zero,
    );
  }
}

class PanelImagePainter extends CustomPainter {
  final ui.Image uiImage;
  final List<Panel> panels;

  PanelImagePainter({required this.uiImage, required this.panels});

  @override
  void paint(Canvas canvas, Size size) {
    // Draw the entire image.
    canvas.drawImage(uiImage, Offset.zero, Paint());

    // Only draw debug boxes if debug mode is enabled
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

  SmartPanelImagePainter({
    required this.uiImage,
    required this.panelRect,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1) Paint entire image area black
    final blackPaint = Paint()..color = Colors.black;
    final imageBounds = Rect.fromLTWH(
      0,
      0,
      uiImage.width.toDouble(),
      uiImage.height.toDouble(),
    );
    canvas.drawRect(imageBounds, blackPaint);

    // 2) Clip to the panelRect, then draw the image into that area
    canvas.save();
    canvas.clipRect(panelRect);
    canvas.drawImage(uiImage, Offset.zero, Paint());
    canvas.restore();

    // Only draw debug box if debug mode is enabled
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
