import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'detection_service.dart' show ObjectDetectionResult;
import 'distance_estimator.dart';
import 'inference_service.dart';

/// Wrapper around FlutterTts that announces object detections with distance
/// and direction information. Implements per-label cooldown to prevent
/// repetitive speech, and enforces max 2 announcements per frame.
class TtsService {
  TtsService._();

  static final TtsService instance = TtsService._();

  final FlutterTts _tts = FlutterTts();
  String _currentLanguage = 'en-US';

  // Per-label cooldown tracking: prevents announcing the same object repeatedly
  final Map<String, DateTime> _lastSpoken = {};
  static const Duration _cooldown = Duration(seconds: 4);

  Future<void> init() async {
    // Configure TTS with optimal settings for accessibility
    await _tts.setLanguage(_currentLanguage);
    await _tts.setSpeechRate(0.50); // slower is easier to understand
    await _tts.setPitch(1.0);
    await _tts.setVolume(1.0);
    debugPrint('[TtsService] Initialized with language: $_currentLanguage');
  }

  Future<void> setLanguage(String languageCode) async {
    if (languageCode == _currentLanguage) return;
    _currentLanguage = languageCode;
    await _tts.setLanguage(languageCode);
    debugPrint('[TtsService] Language set to: $languageCode');
  }

  /// Announce detections from the inference pipeline.
  /// Takes up to 2 highest-confidence detections and speaks them if not
  /// within the per-label cooldown period.
  ///
  /// Parameters:
  ///   detections: List of [DetectionResult] from inference
  ///   frameSize: actual frame size in pixels (e.g., Size(320, 240)) for distance estimation
  Future<void> announceDetections(
    List<DetectionResult> detections,
    ui.Size frameSize,
  ) async {
    if (detections.isEmpty) return;

    // Sort by confidence (highest first) and take top 2
    final topDetections = detections
        .toList()
        ..sort((a, b) => b.confidence.compareTo(a.confidence));
    final announceable = topDetections.take(2).toList();

    final now = DateTime.now();

    for (final detection in announceable) {
      // Check per-label cooldown
      final lastSpokenTime = _lastSpoken[detection.label];
      if (lastSpokenTime != null &&
          now.difference(lastSpokenTime) < _cooldown) {
        debugPrint(
          '[TtsService] Skipping ${detection.label} (within 4s cooldown)',
        );
        continue;
      }

      // Estimate distance and direction
      final distance = DistanceEstimator.estimateMeters(
        detection.label,
        detection.boundingBox,
        frameSize,
      );
      final direction = DistanceEstimator.toDirection(detection.boundingBox);

      // Format announcement
      final announcement = DistanceEstimator.formatAnnouncement(
        detection.label,
        distance,
        direction,
      );

      debugPrint('[TtsService] Speaking: $announcement');

      try {
        await _tts.speak(announcement);
      } catch (e) {
        debugPrint('[TtsService] Error speaking: $e');
      }

      // Update cooldown for this label
      _lastSpoken[detection.label] = now;
    }
  }

  /// Legacy method for backward compatibility: speak generic text with global cooldown.
  Future<void> speakText(
    String text, {
    String? languageCode,
    Duration cooldown = const Duration(seconds: 3),
  }) async {
    if (languageCode != null) {
      await setLanguage(languageCode);
    }

    try {
      await _tts.stop();
    } catch (_) {
      // Ignore stop errors
    }

    debugPrint('[TtsService] Speaking: $text');
    await _tts.speak(text);
  }

  /// Legacy method for backward compatibility: speak generic detection (text-only).
  /// Use announceDetections() for modern distance/direction feedback.
  @Deprecated('Use announceDetections() for distance+direction.')
  Future<void> speakDetection(String detectionText) async {
    try {
      await _tts.stop();
    } catch (_) {
      // Ignore stop errors
    }

    debugPrint('[TtsService] Speaking detection: $detectionText');
    await _tts.speak(detectionText);
  }

  /// Legacy bridge for the old `DetectionService` API that returns
  /// [ObjectDetectionResult]. Prefer [announceDetections] for distance+direction.
  @Deprecated('Use announceDetections() for distance+direction.')
  Future<void> speakObjectDetectionResult(ObjectDetectionResult result) async {
    await speakDetection(result.toSpokenSentence());
  }

  /// Stop any ongoing speech.
  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {
      // Ignore errors
    }
  }
}

