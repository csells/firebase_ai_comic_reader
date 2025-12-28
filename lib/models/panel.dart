import 'dart:ui';

/// Represents a detected panel in a comic page, with both normalized and pixel-based coordinates.
///
/// A panel is a rectangular region in a comic page that contains a single scene or frame.
/// The coordinates can be represented in both normalized form (0.0 to 1.0) and pixel form.
class Panel {
  /// Unique identifier for the panel.
  final String id;

  /// Display name or label for the panel (e.g., "panel").
  final String displayName;

  /// Confidence score of the panel detection (0.0 to 1.0).
  final double confidence;

  /// Normalized bounding box coordinates (values between 0.0 and 1.0).
  /// [left, top, right, bottom]
  final Rect normalizedBox;

  /// Optional pixel-based bounding box coordinates.
  /// This is typically derived from [normalizedBox] and image dimensions.
  Rect? pixelBox;

  Panel({
    required this.id,
    required this.displayName,
    required this.confidence,
    required this.normalizedBox,
    this.pixelBox,
  });

  /// The horizontal center of the panel in normalized coordinates.
  double get normalizedCenterX => normalizedBox.left + normalizedBox.width / 2;

  /// The vertical center of the panel in normalized coordinates.
  double get normalizedCenterY => normalizedBox.top + normalizedBox.height / 2;

  factory Panel.fromJson(Map<String, dynamic> json) {
    final bbox = (json['bbox'] as List)
        .map((e) => (e as num).toDouble())
        .toList();
    // bbox order: [xMin, xMax, yMin, yMax]
    return Panel(
      id: json['id'] as String,
      displayName: json['displayName'] as String,
      confidence: (json['confidence'] as num).toDouble(),
      normalizedBox: Rect.fromLTRB(
        bbox[0], // xMin
        bbox[2], // yMin
        bbox[1], // xMax
        bbox[3], // yMax
      ),
    );
  }

  /// Converts the normalized coordinates to pixel coordinates for a given image size.
  void convertToImageCoordinates(double imageWidth, double imageHeight) {
    pixelBox = Rect.fromLTRB(
      normalizedBox.left * imageWidth,
      normalizedBox.top * imageHeight,
      normalizedBox.right * imageWidth,
      normalizedBox.bottom * imageHeight,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'displayName': displayName,
      'confidence': confidence,
      'normalizedBox': {
        'left': normalizedBox.left,
        'top': normalizedBox.top,
        'right': normalizedBox.right,
        'bottom': normalizedBox.bottom,
      },
      if (pixelBox != null)
        'pixelBox': {
          'left': pixelBox!.left,
          'top': pixelBox!.top,
          'right': pixelBox!.right,
          'bottom': pixelBox!.bottom,
        },
    };
  }

  factory Panel.fromMap(Map<String, dynamic> map) {
    final nb = map['normalizedBox'] as Map<String, dynamic>;
    final pb = map['pixelBox'] as Map<String, dynamic>?;

    return Panel(
      id: map['id'] as String,
      displayName: map['displayName'] as String,
      confidence: (map['confidence'] as num).toDouble(),
      normalizedBox: Rect.fromLTRB(
        (nb['left'] as num).toDouble(),
        (nb['top'] as num).toDouble(),
        (nb['right'] as num).toDouble(),
        (nb['bottom'] as num).toDouble(),
      ),
      pixelBox: pb == null
          ? null
          : Rect.fromLTRB(
              (pb['left'] as num).toDouble(),
              (pb['top'] as num).toDouble(),
              (pb['right'] as num).toDouble(),
              (pb['bottom'] as num).toDouble(),
            ),
    );
  }

  @override
  String toString() => 'Panel(id: $id, box: $normalizedBox)';
}
