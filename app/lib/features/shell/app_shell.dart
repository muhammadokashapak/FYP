import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../camera/camera_screen.dart';
import '../camera/gallery_detection_screen.dart';
import '../dashboard/dashboard_screen.dart';
import '../notifications/notifications_screen.dart';
import '../settings/settings_screen.dart';

/// Index for each tab (Dashboard = home).
const int _tabDashboard = 0;
const int _tabCamera = 1;
const int _tabGallery = 2;
const int _tabNotifications = 3;
const int _tabSettings = 4;

/// Root scaffold with bottom navigation.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _currentIndex = _tabDashboard;

  List<Widget> _buildScreens() {
    return [
      DashboardScreen(
        onOpenLiveView: () => setState(() => _currentIndex = _tabCamera),
        onOpenGallery: () => setState(() => _currentIndex = _tabGallery),
        onOpenNotifications: () =>
            setState(() => _currentIndex = _tabNotifications),
        onOpenSettings: () => setState(() => _currentIndex = _tabSettings),
      ),
      CameraScreen(isActive: _currentIndex == _tabCamera),
      const GalleryDetectionScreen(),
      const NotificationsScreen(),
      const SettingsScreen(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: _currentIndex == _tabDashboard,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _currentIndex != _tabDashboard) {
          setState(() => _currentIndex = _tabDashboard);
        }
      },
      child: Scaffold(
        body: IndexedStack(index: _currentIndex, children: _buildScreens()),
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
            border: Border(
              top: BorderSide(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : AppColors.indigo.withValues(alpha: 0.08),
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
                blurRadius: 20,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: NavigationBar(
            selectedIndex: _currentIndex,
            onDestinationSelected: (index) =>
                setState(() => _currentIndex = index),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.dashboard_outlined),
                selectedIcon: Icon(Icons.dashboard_rounded),
                label: 'Dashboard',
              ),
              NavigationDestination(
                icon: Icon(Icons.camera_alt_outlined),
                selectedIcon: Icon(Icons.camera_alt_rounded),
                label: 'Camera',
              ),
              NavigationDestination(
                icon: Icon(Icons.image_outlined),
                selectedIcon: Icon(Icons.image_rounded),
                label: 'Gallery',
              ),
              NavigationDestination(
                icon: Icon(Icons.notifications_outlined),
                selectedIcon: Icon(Icons.notifications_rounded),
                label: 'Notifications',
              ),
              NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings_rounded),
                label: 'Settings',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
