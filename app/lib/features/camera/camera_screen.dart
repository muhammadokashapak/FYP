import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/detection_provider.dart';
import '../../widgets/detection_overlay.dart';
import '../../widgets/premium_widgets.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key, this.isActive = true});

  final bool isActive;

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  late final String _streamUrl;
  late DetectionProvider _detectionProvider;
  bool _hasInitialized = false;
  bool _hasDetectionProvider = false;
  bool _hasPendingLifecycleUpdate = false;

  @override
  void initState() {
    super.initState();
    // Use the configured ESP32 stream URL or default
    _streamUrl = ESP32Config.streamUrl;
    _scheduleStreamLifecycleUpdate();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _detectionProvider = context.read<DetectionProvider>();
    _hasDetectionProvider = true;
  }

  @override
  void didUpdateWidget(covariant CameraScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive != widget.isActive) {
      _scheduleStreamLifecycleUpdate();
    }
  }

  void _scheduleStreamLifecycleUpdate() {
    if (_hasPendingLifecycleUpdate) return;

    _hasPendingLifecycleUpdate = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _hasPendingLifecycleUpdate = false;
      if (!mounted) return;

      if (widget.isActive) {
        _initializeStream();
      } else {
        _stopStream();
      }
    });
  }

  Future<void> _initializeStream() async {
    if (!mounted) return;

    try {
      await _detectionProvider.startStream(_streamUrl);
      if (mounted && widget.isActive) {
        setState(() {
          _hasInitialized = true;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to start stream: $e')));
      }
    }
  }

  @override
  void dispose() {
    _stopStream();
    super.dispose();
  }

  void _stopStream() {
    if (!_hasDetectionProvider) return;

    _detectionProvider.stopStream();
    _hasInitialized = false;
  }

  /// Decode JPEG bytes to ui.Image for display.
  Future<ui.Image?> _decodeFrame(Uint8List jpegBytes) async {
    try {
      return await decodeImageFromList(jpegBytes);
    } catch (e) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PremiumBackground(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
              child: AppBar(
                title: const Text('Smart Glasses Stream'),
                backgroundColor: Colors.transparent,
              ),
            ),
            Expanded(
              child: Consumer<DetectionProvider>(
        builder: (context, provider, _) {
          return Column(
            children: [
              // Live stream preview with detection overlay
              Expanded(
                flex: 2,
                child: Container(
                  color: Colors.black,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Frame display
                      if (provider.currentFrameBytes != null)
                        FutureBuilder<ui.Image?>(
                          future: _decodeFrame(provider.currentFrameBytes!),
                          builder: (context, snapshot) {
                            if (snapshot.hasData && snapshot.data != null) {
                              return RawImage(image: snapshot.data!);
                            } else {
                              return Container(
                                color: Colors.black,
                                child: const Center(
                                  child: Text(
                                    'Decoding frame...',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              );
                            }
                          },
                        )
                      else if (provider.isStreaming)
                        Container(
                          color: Colors.black,
                          child: const Center(
                            child: CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          ),
                        )
                      else
                        _buildNoStreamPlaceholder(),

                      // Detection overlay
                      DetectionOverlay(detections: provider.detections),

                      if (provider.errorMessage != null)
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          child: Container(
                            color: Colors.red.shade800.withValues(alpha: 0.9),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            child: Text(
                              '⚠ ${provider.errorMessage}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),

                      // Status indicators
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: provider.isStreaming
                                ? Colors.green.withValues(alpha: 0.8)
                                : Colors.red.withValues(alpha: 0.8),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            provider.isStreaming ? '● Live' : '⊙ Offline',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),

                      // FPS and detection count
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${provider.fps} fps | ${provider.detections.length} detected',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Status and information panel
              Expanded(
                flex: 1,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: PremiumCard(
                    padding: const EdgeInsets.all(16),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return SingleChildScrollView(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minHeight: constraints.maxHeight,
                            ),
                            child: Center(child: _buildStatusPanel(provider)),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.darkSurface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'URL: ${provider.currentStreamUrl ?? "not set"}  '
                    'Status: ${provider.isStreaming ? "live" : "offline"}',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 10,
                      fontFamily: 'monospace',
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          );
        },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showSettingsDialog,
        tooltip: 'Stream Settings',
        backgroundColor: AppColors.indigo,
        child: const Icon(Icons.settings_rounded),
      ),
    );
  }

  Widget _buildStatusPanel(DetectionProvider provider) {
    if (provider.errorMessage != null) {
      return _buildErrorStatus(provider);
    }

    if (!provider.isStreaming && !_hasInitialized) {
      return const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 8),
          Text('Initializing services...', style: TextStyle(fontSize: 14)),
        ],
      );
    }

    if (!provider.isStreaming) {
      return const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.videocam_off, size: 32),
          SizedBox(height: 8),
          Text('Stream disconnected', style: TextStyle(fontSize: 14)),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          provider.detections.isEmpty
              ? 'Scanning for objects...'
              : 'Detected objects:',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        if (provider.detections.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: provider.detections
                .take(3)
                .map(
                  (det) => ConfidenceChip(
                    label: det.label,
                    confidence: det.confidence,
                  ),
                )
                .toList(),
          ),
        const SizedBox(height: 8),
        Text(
          'Total detections: ${provider.detectionCount}',
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
      ],
    );
  }

  Widget _buildErrorStatus(DetectionProvider provider) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 24),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'Error: ${provider.errorMessage}',
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  color: Colors.red,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 4,
          children: [
            ElevatedButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('Retry Stream'),
              onPressed: () {
                provider.stopStream();
                _initializeStream();
              },
            ),
            TextButton(
              onPressed: () {
                provider.startStream(ESP32Config.baseUrl);
              },
              child: Text(
                'Try base URL',
                style: TextStyle(color: Colors.grey[600], fontSize: 11),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildNoStreamPlaceholder() {
    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.videocam_off, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'Tap the settings button to start',
              style: TextStyle(fontSize: 14, color: Colors.grey[400]),
            ),
          ],
        ),
      ),
    );
  }

  void _showSettingsDialog() {
    final provider = context.read<DetectionProvider>();
    final controller = TextEditingController(
      text: provider.currentStreamUrl ?? _streamUrl,
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Stream Settings'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Stream URL',
                hintText: 'http://192.168.137.176/',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: Navigator.of(context).pop,
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final provider = context.read<DetectionProvider>();
              provider.stopStream();
              provider.startStream(controller.text);
              Navigator.of(context).pop();
            },
            child: const Text('Connect'),
          ),
        ],
      ),
    );
  }
}
