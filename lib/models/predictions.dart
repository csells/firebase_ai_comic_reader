import 'dart:ui';

import 'panel.dart';

/// Represents the results of panel detection from the AI model.
///
/// This class contains both the detected panels and metadata about the model that performed the detection.
/// It can be serialized to and from JSON for storage or transmission.
class Predictions {
  /// List of detected panels in the image.
  final List<Panel> panels;

  /// The ID of the deployed model that performed the detection.
  final String? deployedModelId;

  /// The full path to the model.
  final String? model;

  /// The display name of the model.
  final String? modelDisplayName;

  /// The version ID of the model.
  final String? modelVersionId;

  Predictions({
    required this.panels,
    this.deployedModelId,
    this.model,
    this.modelDisplayName,
    this.modelVersionId,
  });

  /// Creates a Predictions instance from JSON data received from the AI.
  factory Predictions.fromJson(Map<String, dynamic> json) {
    final List<dynamic> predictionsJson = json['predictions'] as List;

    if (predictionsJson.isEmpty) {
      return Predictions(
        panels: [],
        deployedModelId: json['deployedModelId'] as String?,
        model: json['model'] as String?,
        modelDisplayName: json['modelDisplayName'] as String?,
        modelVersionId: json['modelVersionId'] as String?,
      );
    }

    final firstPrediction = predictionsJson[0];
    final List<dynamic> bboxes = firstPrediction['bboxes'] as List;
    final List<dynamic> ids = firstPrediction['ids'] as List;
    final List<dynamic> confidences = firstPrediction['confidences'] as List;
    final List<dynamic> displayNames = firstPrediction['displayNames'] as List;

    final panels = <Panel>[];
    for (var i = 0; i < bboxes.length; i++) {
      final List<double> bbox = (bboxes[i] as List)
          .map((e) => (e as num).toDouble())
          .toList();
      // bbox order: [xMin, xMax, yMin, yMax]

      panels.add(
        Panel(
          id: ids[i] as String,
          displayName: displayNames[i] as String,
          confidence: (confidences[i] as num).toDouble(),
          normalizedBox: Rect.fromLTRB(
            bbox[0], // xMin
            bbox[2], // yMin
            bbox[1], // xMax
            bbox[3], // yMax
          ),
        ),
      );
    }

    return Predictions(
      panels: panels,
      deployedModelId: json['deployedModelId'] as String?,
      model: json['model'] as String?,
      modelDisplayName: json['modelDisplayName'] as String?,
      modelVersionId: json['modelVersionId'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'deployedModelId': deployedModelId,
      'model': model,
      'modelDisplayName': modelDisplayName,
      'modelVersionId': modelVersionId,
      'panels': panels.map((panel) => panel.toMap()).toList(),
    };
  }

  factory Predictions.fromMap(Map<String, dynamic> map) {
    final panelsData = map['panels'] as List<dynamic>? ?? [];
    final panels = panelsData.map((panelData) {
      return Panel.fromMap(panelData as Map<String, dynamic>);
    }).toList();

    return Predictions(
      panels: panels,
      deployedModelId: map['deployedModelId'] as String?,
      model: map['model'] as String?,
      modelDisplayName: map['modelDisplayName'] as String?,
      modelVersionId: map['modelVersionId'] as String?,
    );
  }

  @override
  String toString() => 'Predictions(panels: ${panels.length})';
}
