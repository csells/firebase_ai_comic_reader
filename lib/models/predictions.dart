import 'dart:ui';

import 'panel.dart';

/// Represents the results of panel detection from Vertex AI's object detection model.
///
/// This class contains both the detected panels and metadata about the model that performed the detection.
/// It can be serialized to and from JSON for storage or transmission.
class Predictions {
  /// List of detected panels in the image.
  final List<Panel> panels;

  /// The ID of the deployed model that performed the detection.
  final String? deployedModelId;

  /// The full path to the model in Vertex AI.
  final String? model;

  /// The display name of the model.
  final String? modelDisplayName;

  /// The version ID of the model.
  final String? modelVersionId;

  Predictions({
    required List<Panel> panels,
    this.deployedModelId,
    this.model,
    this.modelDisplayName,
    this.modelVersionId,
  }) : panels = _sortPanelsInReadingOrder(panels);

  /// Creates a Predictions instance from JSON data received from Vertex AI.
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

  /// Sorts panels in reading order: top-to-bottom first, then left-to-right within rows.
  static List<Panel> _sortPanelsInReadingOrder(List<Panel> panels) {
    if (panels.isEmpty) return [];

    // Working copies for sorting
    final workingList = List<Panel>.from(panels);

    // Grouping by "rows" based on vertical overlap/proximity
    const rowTolerance = 0.05; // 5% of height

    // Sort top-to-bottom by vertical center
    workingList.sort(
      (a, b) => a.normalizedCenterY.compareTo(b.normalizedCenterY),
    );

    final sorted = <Panel>[];
    final currentRow = <Panel>[];

    for (final panel in workingList) {
      if (currentRow.isEmpty) {
        currentRow.add(panel);
      } else {
        final rowReferenceY = currentRow.first.normalizedCenterY;
        if ((panel.normalizedCenterY - rowReferenceY).abs() <= rowTolerance) {
          currentRow.add(panel);
        } else {
          // Finish current row
          currentRow.sort(
            (a, b) => a.normalizedCenterX.compareTo(b.normalizedCenterX),
          );
          sorted.addAll(currentRow);
          currentRow.clear();
          currentRow.add(panel);
        }
      }
    }
    // Add last row
    currentRow.sort(
      (a, b) => a.normalizedCenterX.compareTo(b.normalizedCenterX),
    );
    sorted.addAll(currentRow);

    return sorted;
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
