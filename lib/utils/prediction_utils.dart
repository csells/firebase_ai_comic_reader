import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

// 241210: REST Wrapper: v-2: Now does in-memory image prep
Future<Map<String, dynamic>> getPanelsREST({
  required String accessToken,
  required String imageUrl,
  double confidenceThreshold = 0.5,
  int maxPredictions = 16,
}) async {
  // Vertex AI details
  // TODO: Replace with placeholder values:
  final projectId = 'smartreader-a35a4';
  final endpointId = '2737283675371601920';
  final location = 'us-central1';

  // 1. Download the image bytes
  final response = await http.get(Uri.parse(imageUrl));
  if (response.statusCode != 200) {
    throw Exception('Failed to load image from $imageUrl');
  }
  Uint8List imageBytes = response.bodyBytes;

  // 2. Decode image using `image` package
  img.Image? decodedImage = img.decodeImage(imageBytes);
  if (decodedImage == null) {
    throw Exception('Failed to decode image from $imageUrl');
  }

  // 3. Resize if needed to max 1024x1024 while preserving aspect ratio
  const maxDimension = 1024;
  if (decodedImage.width > maxDimension || decodedImage.height > maxDimension) {
    final aspectRatio = decodedImage.width / decodedImage.height;
    int newWidth, newHeight;
    if (aspectRatio > 1.0) {
      // Wider than tall
      newWidth = maxDimension;
      newHeight = (maxDimension / aspectRatio).round();
    } else {
      // Taller than wide
      newHeight = maxDimension;
      newWidth = (maxDimension * aspectRatio).round();
    }
    decodedImage = img.copyResize(
      decodedImage,
      width: newWidth,
      height: newHeight,
      interpolation: img.Interpolation.average,
    );
  }

  // 4. Compress image to under ~1.2MB by adjusting JPEG quality
  int quality = 100;
  Uint8List jpegBytes =
      Uint8List.fromList(img.encodeJpg(decodedImage, quality: quality));
  const maxBytes = 1200000; // ~1.2MB

  while (jpegBytes.lengthInBytes > maxBytes && quality > 0) {
    quality -= 10;
    jpegBytes =
        Uint8List.fromList(img.encodeJpg(decodedImage, quality: quality));
  }

  // 5. Base64-encode the compressed image
  final base64Image = base64Encode(jpegBytes);

  // Construct the endpoint URL
  final url =
      'https://$location-aiplatform.googleapis.com/v1/projects/$projectId/locations/$location/endpoints/$endpointId:predict';

  // Build the request body for Vertex AI
  final requestBody = {
    'instances': [
      {
        'content': base64Image,
      },
    ],
    'parameters': {
      'confidenceThreshold': confidenceThreshold,
      'maxPredictions': maxPredictions,
    },
  };

  // Send the POST request
  final apiResponse = await http.post(
    Uri.parse(url),
    headers: {
      'Authorization': 'Bearer $accessToken',
      'Content-Type': 'application/json',
    },
    body: jsonEncode(requestBody),
  );

  if (apiResponse.statusCode != 200) {
    throw Exception(
        'Request failed: ${apiResponse.statusCode} - ${apiResponse.body}');
  }

  debugPrint('getPanelsREST response: ${apiResponse.body}');

  // Parse and return JSON response
  return jsonDecode(apiResponse.body) as Map<String, dynamic>;
}
