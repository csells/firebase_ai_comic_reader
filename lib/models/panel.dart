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
  /// The coordinates are in the format: left = xMin, top = yMin, right = xMax, bottom = yMax
  Rect normalizedBox;

  /// Optional pixel-based bounding box coordinates.
  /// Only available after calling [convertToImageCoordinates].
  Rect? pixelBox;

  Panel({
    required this.id,
    required this.displayName,
    required this.confidence,
    required this.normalizedBox,
    this.pixelBox,
  });

  factory Panel.fromJson(Map<String, dynamic> json) {
    final bbox =
        (json['bbox'] as List).map((e) => (e as num).toDouble()).toList();
    // bbox: [xMin, xMax, yMin, yMax]
    return Panel(
      id: json['id'] as String,
      displayName: json['displayName'] as String,
      confidence: (json['confidence'] as num).toDouble(),
      normalizedBox: Rect.fromLTRB(
        bbox[0], // left (xMin)
        bbox[2], // top (yMin)
        bbox[1], // right (xMax)
        bbox[3], // bottom (yMax)
      ),
    );
  }

  /// Converts the normalized coordinates to pixel coordinates based on the image dimensions.
  ///
  /// [imageWidth] The width of the image in pixels.
  /// [imageHeight] The height of the image in pixels.
  void convertToImageCoordinates(double imageWidth, double imageHeight) {
    pixelBox = Rect.fromLTRB(
      normalizedBox.left * imageWidth,
      normalizedBox.top * imageHeight,
      normalizedBox.right * imageWidth,
      normalizedBox.bottom * imageHeight,
    );
  }

  /// Converts the panel data to a map for serialization.
  ///
  /// Returns a map containing all panel properties, suitable for storage or transmission.
  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'id': id,
      'displayName': displayName,
      'confidence': confidence,
      'normalizedBox': {
        'left': normalizedBox.left,
        'top': normalizedBox.top,
        'right': normalizedBox.right,
        'bottom': normalizedBox.bottom,
      },
    };

    if (pixelBox != null) {
      map['pixelBox'] = {
        'left': pixelBox!.left,
        'top': pixelBox!.top,
        'right': pixelBox!.right,
        'bottom': pixelBox!.bottom,
      };
    }

    return map;
  }

  /// Creates a Panel instance from a map representation.
  ///
  /// [map] A map containing panel properties, typically from deserialized data.
  factory Panel.fromMap(Map<String, dynamic> map) {
    final nb = map['normalizedBox'] as Map<String, dynamic>;
    final pBox = map['pixelBox'] as Map<String, dynamic>?;

    Rect? pixelRect;
    if (pBox != null) {
      pixelRect = Rect.fromLTRB(
        (pBox['left'] as num).toDouble(),
        (pBox['top'] as num).toDouble(),
        (pBox['right'] as num).toDouble(),
        (pBox['bottom'] as num).toDouble(),
      );
    }

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
      pixelBox: pixelRect,
    );
  }

  @override
  String toString() {
    return 'Panel(\n'
        '  id: $id,\n'
        '  displayName: $displayName,\n'
        '  confidence: $confidence,\n'
        '  normalizedBox: $normalizedBox,\n'
        '  pixelBox: $pixelBox\n'
        ')';
  }
}
