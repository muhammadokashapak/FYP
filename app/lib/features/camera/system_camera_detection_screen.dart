import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../widgets/detection_overlay.dart';
import '../../widgets/premium_widgets.dart';
import 'camera_provider.dart';

/// Live device-camera detection with bounding boxes (opened from Settings).
class SystemCameraDetectionScreen extends StatefulWidget {
  const SystemCameraDetectionScreen({super.key});

  @override
  State<SystemCameraDetectionScreen> createState() =>
      _SystemCameraDetectionScreenState();
}

class _SystemCameraDetectionScreenState
    extends State<SystemCameraDetectionScreen> {
  CameraProvider? _cameraProvider;
  bool _hasScheduledInit = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _cameraProvider ??= context.read<CameraProvider>();
    if (!_hasScheduledInit) {
      _hasScheduledInit = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _cameraProvider?.init();
      });
    }
  }

  @override
  void dispose() {
    _cameraProvider?.disposeCamera();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Live Detection'),
        backgroundColor: Colors.black.withValues(alpha: 0.35),
        foregroundColor: Colors.white,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.65),
                Colors.transparent,
              ],
            ),
          ),
        ),
        actions: [
          Consumer<CameraProvider>(
            builder: (context, provider, _) {
              if (!provider.hasFlash) return const SizedBox.shrink();
              return IconButton(
                tooltip: 'Toggle flash',
                onPressed: provider.isInitialized ? provider.toggleFlash : null,
                icon: Icon(_flashIcon(provider.flashMode), color: Colors.white),
              );
            },
          ),
        ],
      ),
      body: Consumer<CameraProvider>(
        builder: (context, provider, _) {
          if (provider.error != null && !provider.isInitialized) {
            return _ErrorView(
              message: provider.error!,
              onRetry: provider.init,
            );
          }

          if (!provider.isInitialized || provider.controller == null) {
            return const _LoadingView();
          }

          final topResults = provider.detections.take(3).toList();

          return Column(
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _CameraPreview(controller: provider.controller!),
                    DetectionOverlay(detections: provider.detections),
                    Positioned(
                      top: MediaQuery.paddingOf(context).top + 56,
                      left: 16,
                      right: 16,
                      child: Row(
                        children: [
                          _StatusBadge(
                            label: 'LIVE',
                            color: AppColors.emerald,
                            icon: Icons.sensors,
                          ),
                          const Spacer(),
                          if (provider.isCapturing)
                            _StatusBadge(
                              label: 'Analyzing',
                              color: AppColors.cyan,
                              icon: Icons.auto_awesome,
                            ),
                        ],
                      ),
                    ),
                    if (provider.detections.isEmpty)
                      const Center(
                        child: _ScanFrameHint(),
                      ),
                  ],
                ),
              ),
              GlassPanel(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 4,
                            height: 22,
                            decoration: BoxDecoration(
                              gradient: AppColors.primaryGradient,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            provider.detections.isEmpty
                                ? 'Scanning...'
                                : 'Detected Objects',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      if (topResults.isEmpty)
                        Text(
                          'Aim the camera at an object. Bounding boxes '
                          'appear when something is recognized.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        )
                      else
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: topResults
                              .map(
                                (r) => ConfidenceChip(
                                  label: r.label,
                                  confidence: r.confidence,
                                ),
                              )
                              .toList(),
                        ),
                      if (provider.captureError != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          provider.captureError!,
                          style: TextStyle(
                            fontSize: 13,
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  IconData _flashIcon(FlashMode mode) {
    switch (mode) {
      case FlashMode.auto:
        return Icons.flash_auto;
      case FlashMode.torch:
        return Icons.flash_on;
      case FlashMode.always:
        return Icons.flash_on;
      case FlashMode.off:
        return Icons.flash_off;
    }
  }
}

class _CameraPreview extends StatelessWidget {
  const _CameraPreview({required this.controller});

  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    final previewSize = controller.value.previewSize;
    if (previewSize == null) {
      return const ColoredBox(color: Colors.black);
    }

    return ClipRect(
      child: OverflowBox(
        alignment: Alignment.center,
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: previewSize.height,
            height: previewSize.width,
            child: CameraPreview(controller),
          ),
        ),
      ),
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.cyan.withValues(alpha: 0.4),
                width: 2,
              ),
            ),
            child: const SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: AppColors.cyan,
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Initializing camera...',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.videocam_off, size: 52, color: Colors.white38),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({
    required this.label,
    required this.color,
    required this.icon,
  });

  final String label;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanFrameHint extends StatelessWidget {
  const _ScanFrameHint();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        margin: const EdgeInsets.all(48),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.cyan.withValues(alpha: 0.35),
            width: 1.5,
          ),
        ),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'Align object inside frame',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
