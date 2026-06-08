import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/premium_widgets.dart';
import '../camera/system_camera_detection_screen.dart';
import 'settings_provider.dart';

/// Settings screen: theme, notifications toggle, camera resolution, About.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PremiumBackground(
        child: SafeArea(
          child: Consumer<SettingsProvider>(
            builder: (context, settings, _) {
              return CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                      child: AppBar(
                        title: const Text('Settings'),
                        backgroundColor: Colors.transparent,
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const PremiumSectionTitle(title: 'Appearance'),
                          PremiumCard(
                            padding: EdgeInsets.zero,
                            child: SwitchListTile(
                              title: const Text('Dark theme'),
                              subtitle: const Text('Switch between light and dark'),
                              value: settings.isDarkTheme,
                              onChanged: settings.setDarkTheme,
                            ),
                          ),
                          const SizedBox(height: 16),
                          const PremiumSectionTitle(title: 'Alerts'),
                          PremiumCard(
                            padding: EdgeInsets.zero,
                            child: SwitchListTile(
                              title: const Text('Notifications'),
                              subtitle: const Text('Show detection alerts'),
                              value: settings.notificationsEnabled,
                              onChanged: settings.setNotificationsEnabled,
                            ),
                          ),
                          const SizedBox(height: 16),
                          const PremiumSectionTitle(title: 'Camera'),
                          PremiumCard(
                            padding: EdgeInsets.zero,
                            child: Column(
                              children: [
                                ListTile(
                                  leading: const PremiumIconTile(
                                    icon: Icons.hd_rounded,
                                    size: 44,
                                  ),
                                  title: const Text('Resolution'),
                                  subtitle: Text(
                                    CameraResolutions
                                        .labels[settings.cameraResolutionIndex],
                                  ),
                                  trailing: const Icon(
                                    Icons.arrow_forward_ios_rounded,
                                    size: 16,
                                  ),
                                  onTap: () =>
                                      _showResolutionPicker(context, settings),
                                ),
                                Divider(
                                  height: 1,
                                  indent: 20,
                                  endIndent: 20,
                                  color: Theme.of(context).dividerColor,
                                ),
                                ListTile(
                                  leading: const PremiumIconTile(
                                    icon: Icons.center_focus_strong_rounded,
                                    size: 44,
                                    gradient: AppColors.accentGradient,
                                  ),
                                  title: const Text('Live camera detection'),
                                  subtitle: const Text(
                                    'Real-time object detection with bounding boxes',
                                  ),
                                  trailing: const Icon(
                                    Icons.arrow_forward_ios_rounded,
                                    size: 16,
                                  ),
                                  onTap: () => Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) =>
                                          const SystemCameraDetectionScreen(),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          const PremiumSectionTitle(title: 'About'),
                          PremiumCard(
                            child: Row(
                              children: [
                                const PremiumIconTile(
                                  icon: Icons.auto_awesome_rounded,
                                  size: 48,
                                  gradient: AppColors.heroGradient,
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        AppInfo.name,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Version ${AppInfo.version}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 32),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  void _showResolutionPicker(BuildContext context, SettingsProvider settings) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'Camera resolution',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            ...List.generate(
              CameraResolutions.labels.length,
              (i) => ListTile(
                title: Text(CameraResolutions.labels[i]),
                trailing: settings.cameraResolutionIndex == i
                    ? const Icon(Icons.check_circle_rounded,
                        color: AppColors.indigo)
                    : null,
                onTap: () {
                  settings.setCameraResolutionIndex(i);
                  Navigator.pop(context);
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
