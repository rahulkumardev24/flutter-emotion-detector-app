import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/cupertino.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

/// Custom painter that draws face detection results (boxes, landmarks, and emotions)
/// on top of the camera preview while handling different camera orientations.
class FaceDetectionPainter extends CustomPainter {
  final List<Face> faces; // Detected faces from ML Kit
  final Size imageSize; // Original image size from camera
  final CameraLensDirection cameraLensDirection; // Front/back camera
  final bool absoluteSize; // Whether to use raw coordinates

  FaceDetectionPainter({
    required this.faces,
    required this.imageSize,
    required this.cameraLensDirection,
    this.absoluteSize = false, // Default to scaled coordinates
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Paint configuration for face bounding boxes
    final Paint boxPaint =
        Paint()
          ..style =
              PaintingStyle
                  .stroke // Outline style
          ..strokeWidth =
              2.0 // Line thickness
          ..color = CupertinoColors.systemGreen; // Green border color

    // Paint for text background (semi-transparent gray)
    final Paint textBgPaint =
        Paint()
          ..style = PaintingStyle.fill
          ..color = CupertinoColors.systemGrey.withOpacity(0.7);

    // Text style for emotion/eye state information
    final textStyle = TextStyle(
      color: CupertinoColors.white, // White text
      fontSize: 14,
      fontWeight: FontWeight.bold,
    );

    // Calculate how to scale and position camera image to display size
    double scaleX, scaleY; // Scaling factors
    double offsetX = 0, offsetY = 0; // Positioning offsets

    if (absoluteSize) {
      // Use raw coordinates without scaling
      scaleX = 1.0;
      scaleY = 1.0;
    } else {
      // Calculate scaling while maintaining aspect ratio
      scaleX = size.width / imageSize.width;
      scaleY = size.height / imageSize.height;

      // Use uniform scaling to prevent distortion
      final scale = math.min(scaleX, scaleY);
      // Center the image in the available space
      offsetX = (size.width - (imageSize.width * scale)) / 2;
      offsetY = (size.height - (imageSize.height * scale)) / 2;
      scaleX = scaleY = scale; // Apply uniform scaling
    }

    // Process each detected face
    for (final Face face in faces) {
      final boundingBox = face.boundingBox;

      // Calculate display coordinates for face rectangle
      double left, top, right, bottom;
      if (cameraLensDirection == CameraLensDirection.front) {
        // Mirror coordinates for front camera
        left = (imageSize.width - boundingBox.right) * scaleX + offsetX;
        right = (imageSize.width - boundingBox.left) * scaleX + offsetX;
      } else {
        // Standard coordinates for back camera
        left = boundingBox.left * scaleX + offsetX;
        right = boundingBox.right * scaleX + offsetX;
      }
      top = boundingBox.top * scaleY + offsetY;
      bottom = boundingBox.bottom * scaleY + offsetY;

      /// 1. Draw bounding box around detected face
      canvas.drawRect(Rect.fromLTRB(left, top, right, bottom), boxPaint);

      /// 2. Draw facial landmarks (eyes, nose, mouth, etc.)
      _drawLandmarks(canvas, face, scaleX, scaleY, offsetX, offsetY);

      /// 3. Draw face information (emotions/eye states) if available
      if (face.smilingProbability != null ||
          face.leftEyeOpenProbability != null ||
          face.rightEyeOpenProbability != null) {
        // Prepare text with face information
        final textSpan = TextSpan(
          style: textStyle,
          children: _buildEmotionTextSpans(face), // Build multi-style text
        );

        // Layout and measure text
        final textPainter = TextPainter(
          text: textSpan,
          textDirection: TextDirection.ltr,
        );
        textPainter.layout();

        // Position text above face box (clamped to screen bounds)
        final textX = left;
        final textY = (top - textPainter.height - 5).clamp(
          0.0, // Prevent going above top edge
          size.height - textPainter.height, // Prevent going below bottom
        );

        // Draw semi-transparent background behind text
        canvas.drawRect(
          Rect.fromLTWH(
            textX - 2, // Add small padding
            textY - 2,
            textPainter.width + 4,
            textPainter.height + 4,
          ),
          textBgPaint,
        );

        // Draw the text itself
        textPainter.paint(canvas, Offset(textX, textY));
      }
    }
  }

  /// Builds formatted text spans showing facial expressions and eye states
  List<TextSpan> _buildEmotionTextSpans(Face face) {
    final spans = <TextSpan>[];

    // 1. Add smiling probability (if available)
    if (face.smilingProbability != null) {
      final smilePercent = (face.smilingProbability! * 100).round();
      String smileText;
      Color smileColor;
      // Classify smile level with appropriate emoji and color
      if (smilePercent > 70) {
        smileText = '😊 Happy ($smilePercent%)';
        smileColor = CupertinoColors.systemGreen;
      } else if (smilePercent > 40) {
        smileText = '😐 Neutral ($smilePercent%)';
        smileColor = CupertinoColors.systemYellow;
      } else {
        smileText = '😞 Sad ($smilePercent%)';
        smileColor = CupertinoColors.systemRed;
      }
      spans.add(TextSpan(text: smileText, style: TextStyle(color: smileColor)));
    }

    // 2. Add eye states (if available)
    if (face.leftEyeOpenProbability != null ||
        face.rightEyeOpenProbability != null) {
      // Add line break if we already have smile text
      if (spans.isNotEmpty) spans.add(TextSpan(text: '\n'));

      // Left eye state
      if (face.leftEyeOpenProbability != null) {
        final leftOpen = face.leftEyeOpenProbability! > 0.5;
        spans.add(
          TextSpan(
            text: 'Left Eye: ${leftOpen ? '👀 Open' : '😑 Closed'}',
            style: TextStyle(
              color:
                  leftOpen
                      ? CupertinoColors.systemGreen
                      : CupertinoColors.systemRed,
            ),
          ),
        );
      }

      // Right eye state (with spacing if left eye exists)
      if (face.rightEyeOpenProbability != null) {
        if (face.leftEyeOpenProbability != null) {
          spans.add(TextSpan(text: '  ')); // Add spacing between eye info
        }
        final rightOpen = face.rightEyeOpenProbability! > 0.5;
        spans.add(
          TextSpan(
            text: 'Right Eye: ${rightOpen ? '👀 Open' : '😑 Closed'}',
            style: TextStyle(
              color:
                  rightOpen
                      ? CupertinoColors.systemGreen
                      : CupertinoColors.systemRed,
            ),
          ),
        );
      }
    }
    return spans;
  }

  /// Draws facial landmarks (eyes, ears, nose, mouth) as small circles
  void _drawLandmarks(
    Canvas canvas,
    Face face,
    double scaleX,
    double scaleY,
    double offsetX,
    double offsetY,
  ) {
    final Paint landmarkPaint =
        Paint()
          ..style = PaintingStyle.fill
          ..color = CupertinoColors.systemRed; // Red dots for landmarks

    // All landmark types we want to visualize
    final landmarkTypes = [
      FaceLandmarkType.leftEar,
      FaceLandmarkType.rightEar,
      FaceLandmarkType.leftEye,
      FaceLandmarkType.rightEye,
      FaceLandmarkType.noseBase,
      FaceLandmarkType.leftCheek,
      FaceLandmarkType.rightCheek,
      FaceLandmarkType.leftMouth,
      FaceLandmarkType.rightMouth,
      FaceLandmarkType.bottomMouth,
    ];

    // Draw each available landmark
    for (final type in landmarkTypes) {
      final landmark = face.landmarks[type];
      if (landmark != null) {
        // Calculate position with mirroring for front camera
        double x = landmark.position.x * scaleX;
        if (cameraLensDirection == CameraLensDirection.front) {
          x = (imageSize.width - landmark.position.x) * scaleX;
        }
        x += offsetX; // Apply horizontal centering offset
        final y = landmark.position.y * scaleY + offsetY; // Vertical position

        // Draw small circle at landmark position
        canvas.drawCircle(Offset(x, y), 4.0, landmarkPaint);
      }
    }
  }

  /// Determines when repainting is needed (when face data or camera changes)
  @override
  bool shouldRepaint(FaceDetectionPainter oldDelegate) {
    return oldDelegate.imageSize != imageSize || // Image dimensions changed
        oldDelegate.faces != faces || // New face detection data
        oldDelegate.cameraLensDirection !=
            cameraLensDirection; // Camera flipped
  }
}
