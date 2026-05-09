import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import 'settings_provider.dart';

/// Settings screen: theme, notifications toggle, camera resolution, About.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: Consumer<SettingsProvider>(
        builder: (context, settings, _) {
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              _SectionTitle(title: 'Appearance'),
              SwitchListTile(
                title: const Text('Dark theme'),
                value: settings.isDarkTheme,
                onChanged: (v) => settings.setDarkTheme(v),
              ),
              const Divider(height: 1),
              _SectionTitle(title: 'Alerts'),
              SwitchListTile(
                title: const Text('Notifications'),
                subtitle: const Text('Show detection alerts'),
                value: settings.notificationsEnabled,
                onChanged: (v) => settings.setNotificationsEnabled(v),
              ),
              const Divider(height: 1),
              _SectionTitle(title: 'Camera'),
              ListTile(
                title: const Text('Resolution'),
                subtitle: Text(
                  CameraResolutions.labels[settings.cameraResolutionIndex],
                ),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () => _showResolutionPicker(context, settings),
              ),
              const Divider(height: 1),
              _SectionTitle(title: 'About'),
              ListTile(
                title: const Text(AppInfo.name),
                subtitle: Text('Version ${AppInfo.version}'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showResolutionPicker(BuildContext context, SettingsProvider settings) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
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
                    ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary)
                    : null,
                onTap: () {
                  settings.setCameraResolutionIndex(i);
                  Navigator.pop(context);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}
