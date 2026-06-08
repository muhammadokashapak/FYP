import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/alert_card.dart';
import '../../widgets/premium_widgets.dart';
import '../notifications/notifications_provider.dart';

/// Home dashboard for Smart Glasses Assistant.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({
    super.key,
    required this.onOpenLiveView,
    required this.onOpenGallery,
    required this.onOpenNotifications,
    required this.onOpenSettings,
  });

  final VoidCallback onOpenLiveView;
  final VoidCallback onOpenGallery;
  final VoidCallback onOpenNotifications;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: PremiumBackground(
        child: SafeArea(
          bottom: false,
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                  child: _HeroHeader(),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: _LiveViewCard(onTap: onOpenLiveView),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
                  child: _GalleryCard(onTap: onOpenGallery),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Recent Alerts',
                        style: theme.textTheme.titleMedium,
                      ),
                      TextButton(
                        onPressed: onOpenNotifications,
                        child: const Text('See all'),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Consumer<NotificationsProvider>(
                  builder: (context, provider, _) {
                    final recent = provider.items.take(3).toList();
                    if (recent.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: PremiumCard(
                          padding: const EdgeInsets.all(28),
                          child: Column(
                            children: [
                              Icon(
                                Icons.notifications_none_rounded,
                                size: 48,
                                color: theme.colorScheme.outline,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'No alerts yet',
                                style: theme.textTheme.titleMedium,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Detection alerts will appear here.',
                                style: theme.textTheme.bodyMedium,
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                    return Column(
                      children: recent
                          .map(
                            (alert) => AlertCard(
                              alert: alert,
                              onTap: () {
                                provider.markAsRead(alert.id);
                                onOpenNotifications();
                              },
                            ),
                          )
                          .toList(),
                    );
                  },
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
                  child: _QuickSettingsCard(onOpenSettings: onOpenSettings),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: AppColors.heroGradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.indigo.withValues(alpha: 0.35),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'AI VISION ASSISTANT',
              style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            AppInfo.name,
            style: theme.textTheme.headlineSmall?.copyWith(
              color: Colors.white,
              fontSize: 28,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'See smarter. Detect faster. Stay aware.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.88),
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveViewCard extends StatelessWidget {
  const _LiveViewCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PremiumCard(
      onTap: onTap,
      gradient: AppColors.primaryGradient,
      child: Row(
        children: [
          const PremiumIconTile(
            icon: Icons.videocam_rounded,
            gradient: AppColors.accentGradient,
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Live View', style: theme.textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                  'Stream from smart glasses camera',
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          Icon(
            Icons.arrow_forward_ios_rounded,
            size: 18,
            color: AppColors.indigo.withValues(alpha: 0.7),
          ),
        ],
      ),
    );
  }
}

class _GalleryCard extends StatelessWidget {
  const _GalleryCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PremiumCard(
      onTap: onTap,
      child: Row(
        children: [
          PremiumIconTile(
            icon: Icons.image_rounded,
            gradient: LinearGradient(
              colors: [
                AppColors.violet,
                AppColors.violet.withValues(alpha: 0.7),
              ],
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Gallery Upload', style: theme.textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                  'Classify images from your gallery',
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          Icon(
            Icons.arrow_forward_ios_rounded,
            size: 18,
            color: AppColors.indigo.withValues(alpha: 0.7),
          ),
        ],
      ),
    );
  }
}

class _QuickSettingsCard extends StatelessWidget {
  const _QuickSettingsCard({required this.onOpenSettings});

  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PremiumCard(
      onTap: onOpenSettings,
      child: Row(
        children: [
          PremiumIconTile(
            icon: Icons.tune_rounded,
            size: 48,
            gradient: LinearGradient(
              colors: [
                theme.colorScheme.onSurface.withValues(alpha: 0.15),
                theme.colorScheme.onSurface.withValues(alpha: 0.08),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Settings', style: theme.textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(
                  'Theme, alerts, camera & live detection',
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: theme.colorScheme.outline),
        ],
      ),
    );
  }
}
