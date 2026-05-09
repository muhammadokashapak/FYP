import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';

/// Estimates real-world distance from bounding box dimensions.
/// Uses pinhole camera model with focal length calibrated for OV2640 at QVGA (320x240).
///
/// Formula:
///   distance_cm = (known_real_width_cm × focal_length_px) / bbox_width_px
///
/// This class provides static methods only — no instantiation needed.
class DistanceEstimator {
  DistanceEstimator._(); // prevent instantiation

  /// Focal length in pixels, calibrated for OV2640 camera at QVGA resolution.
  /// This value was determined empirically and should be adjusted based on
  /// your specific camera and lens. Typical range: 200-400 pixels.
  static const double focalLengthPx = 280.0;

  /// Known real-world widths of objects for distance estimation.
  /// Map: object label -> approximate width in centimeters.
  /// These are typical values and should be calibrated for your use case.
  static const Map<String, double> knownWidths = {
    'person': 50.0,    // shoulder width in cm
    'chair': 55.0,     // seat width
    'table': 120.0,    // typical table width
    'obstacle': 40.0,  // generic obstacle width
  };

  /// Estimate distance in meters from a normalized bounding box.
  ///
  /// Parameters:
  ///   label: object class name (must exist in [knownWidths] map)
  ///   normalizedBbox: Rect with coordinates normalized 0.0-1.0
  ///   frameSize: actual frame size in pixels (e.g., Size(320, 240))
  ///
  /// Returns:
  ///   Distance in meters, or null if:
  ///   - Object class is unknown
  ///   - Bounding box width is too small (< 5 pixels)
  ///   - Distance calculation produces invalid result
  static double? estimateMeters(
    String label,
    ui.Rect normalizedBbox,
    ui.Size frameSize,
  ) {
    // Check if label has a known width
    if (!knownWidths.containsKey(label)) {
      debugPrint('[DistanceEstimator] Unknown label: $label');
      return null;
    }

    final knownWidthCm = knownWidths[label]!;

    // Convert normalized bbox width to pixel width
    final bboxWidthPx = normalizedBbox.width * frameSize.width;

    // Reject if box is too small (noise or measurement error)
    if (bboxWidthPx < 5.0) {
      debugPrint(
        '[DistanceEstimator] Bounding box too small for $label: ${bboxWidthPx.toStringAsFixed(1)}px',
      );
      return null;
    }

    // Apply pinhole camera model
    final distanceCm = (knownWidthCm * focalLengthPx) / bboxWidthPx;

    // Reject unreasonable distances (e.g., < 10cm or > 50m)
    if (distanceCm < 10.0 || distanceCm > 5000.0) {
      debugPrint(
        '[DistanceEstimator] Unreasonable distance for $label: ${distanceCm.toStringAsFixed(0)}cm',
      );
      return null;
    }

    return distanceCm / 100.0; // Convert cm to meters
  }

  /// Determine directional description based on bounding box horizontal position.
  ///
  /// Divides the frame into three zones:
  ///   [0.0 - 0.33]  -> 'on your left'
  ///   [0.33 - 0.66] -> 'directly ahead'
  ///   [0.66 - 1.0]  -> 'on your right'
  ///
  /// Uses the center of the bounding box for determining direction.
  static String toDirection(ui.Rect normalizedBbox) {
    final centerX = normalizedBbox.center.dx;

    if (centerX < 0.33) {
      return 'on your left';
    } else if (centerX > 0.66) {
      return 'on your right';
    } else {
      return 'directly ahead';
    }
  }

  /// Format a complete announcement string from detection data.
  ///
  /// Format varies based on whether distance estimation succeeded:
  ///   - With distance: "[Label] detected, [X.X] meters [direction]"
  ///   - Without distance: "[Label] detected, [direction]"
  ///
  /// Example outputs:
  ///   "Chair detected, 1.8 meters directly ahead"
  ///   "Obstacle detected, on your left"
  static String formatAnnouncement(
    String label,
    double? metersDistance,
    String direction,
  ) {
    if (metersDistance != null) {
      return '$label detected at ${metersDistance.toStringAsFixed(1)} meters $direction';
    } else {
      return '$label detected $direction';
    }
  }

  /// Debug helper: log distance estimation details for a detection.
  /// Useful for tuning focal length and known widths.
  static void debugEstimate(
    String label,
    ui.Rect normalizedBbox,
    ui.Size frameSize,
  ) {
    final distance = estimateMeters(label, normalizedBbox, frameSize);
    final direction = toDirection(normalizedBbox);
    final bboxWidthPx = normalizedBbox.width * frameSize.width;

    debugPrint(
      '[DistanceEstimator] $label: bbox=${normalizedBbox.toString()}, '
      'widthPx=${bboxWidthPx.toStringAsFixed(1)}, '
      'distance=${distance != null ? '${distance.toStringAsFixed(2)}m' : 'unknown'}, '
      'direction=$direction',
    );
  }
}
