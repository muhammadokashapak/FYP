import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme/app_colors.dart';
import '../../services/inference_service.dart';
import '../../widgets/detection_overlay.dart';
import '../../widgets/premium_widgets.dart';

/// Gallery upload + ImageNet classification (bottom nav Gallery tab).
class GalleryDetectionScreen extends StatefulWidget {
  const GalleryDetectionScreen({super.key});

  @override
  State<GalleryDetectionScreen> createState() => _GalleryDetectionScreenState();
}

class _GalleryDetectionScreenState extends State<GalleryDetectionScreen> {
  final ImagePicker _picker = ImagePicker();
  final InferenceService _inference = InferenceService.instance;

  File? _imageFile;
  List<DetectionResult> _results = [];
  bool _isLoading = false;
  bool _modelReady = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initModel();
  }

  Future<void> _initModel() async {
    try {
      await _inference.initialize();
      if (mounted) setState(() => _modelReady = true);
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Model failed to load: $e');
      }
    }
  }

  Future<void> _pickFromGallery() async {
    if (!_modelReady || _isLoading) return;
    await _pickImage(ImageSource.gallery);
  }

  Future<void> _pickFromCamera() async {
    if (!_modelReady || _isLoading) return;
    await _pickImage(ImageSource.camera);
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        imageQuality: 95,
      );
      if (picked == null) return;

      setState(() {
        _imageFile = File(picked.path);
        _results = [];
        _isLoading = true;
        _error = null;
      });

      final bytes = await _imageFile!.readAsBytes();
      final results = await _inference.runInference(bytes);

      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _results = results;
        if (results.isEmpty) {
          _error =
              'Could not classify this image. Try a clearer, centered photo.';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final topResults = _results.take(3).toList();
    final theme = Theme.of(context);
    final actionsEnabled = _modelReady && !_isLoading;
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: PremiumBackground(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                child: AppBar(
                  title: const Text('Image Classification'),
                  backgroundColor: Colors.transparent,
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _imageFile == null
                      ? const _ImagePlaceholder()
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.file(_imageFile!, fit: BoxFit.contain),
                              if (_results.isNotEmpty)
                                DetectionOverlay(detections: _results),
                              if (_isLoading)
                                Container(
                                  color: Colors.black26,
                                  child: const Center(
                                    child: CircularProgressIndicator(
                                      color: AppColors.cyan,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
              if (topResults.isNotEmpty) ...[
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: topResults
                        .map(
                          (r) => ConfidenceChip(
                            label: r.label,
                            confidence: r.confidence,
                          ),
                        )
                        .toList(),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(48, 18, 48, 24),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkSurface : Colors.white,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(28)),
                  border: Border(
                    top: BorderSide(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.06)
                          : AppColors.indigo.withValues(alpha: 0.08),
                    ),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.05),
                      blurRadius: 20,
                      offset: const Offset(0, -6),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _ActionButton(
                      onPressed: actionsEnabled ? _pickFromGallery : null,
                      isLoading: _isLoading && !_modelReady,
                      icon: Icons.photo_library_rounded,
                      isRound: false,
                      gradient: AppColors.primaryGradient,
                    ),
                    _ActionButton(
                      onPressed: actionsEnabled ? _pickFromCamera : null,
                      icon: Icons.camera_alt_rounded,
                      isRound: true,
                      gradient: AppColors.accentGradient,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: Container(
        width: 220,
        height: 220,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [
                    AppColors.darkSurfaceVariant,
                    AppColors.darkSurface,
                  ]
                : [
                    AppColors.lightSurfaceVariant,
                    Colors.white,
                  ],
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: AppColors.indigo.withValues(alpha: 0.12),
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.indigo.withValues(alpha: 0.1),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Icon(
          Icons.image_rounded,
          size: 96,
          color: AppColors.indigo.withValues(alpha: 0.35),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.onPressed,
    required this.icon,
    required this.isRound,
    required this.gradient,
    this.isLoading = false,
  });

  final VoidCallback? onPressed;
  final IconData icon;
  final bool isRound;
  final Gradient gradient;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(isRound ? 32 : 16),
        child: Opacity(
          opacity: onPressed == null ? 0.4 : 1,
          child: Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              gradient: gradient,
              borderRadius: BorderRadius.circular(isRound ? 32 : 16),
              boxShadow: [
                BoxShadow(
                  color: AppColors.indigo.withValues(alpha: 0.3),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: isLoading
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Icon(icon, color: Colors.white, size: 28),
          ),
        ),
      ),
    );
  }
}
