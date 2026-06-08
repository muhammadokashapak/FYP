import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../camera/camera_screen.dart';
import '../dashboard/dashboard_screen.dart';
import '../notifications/notifications_screen.dart';
import '../settings/settings_screen.dart';
import '../camera/camera_provider.dart';

/// Index for each tab (Dashboard = home).
const int _tabDashboard = 0;
const int _tabCamera = 1;
const int _tabNotifications = 2;
const int _tabSettings = 3;

/// Root scaffold with bottom navigation: Dashboard, Camera, Notifications, Settings.
/// Disposes camera when app is paused to avoid FlutterJNI crash on exit.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  int _currentIndex = _tabDashboard;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Dispose camera when shell is disposed (app exit)
    final camera = context.read<CameraProvider>();
    camera.disposeCamera();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      context.read<CameraProvider>().disposeCamera();
    } else if (state == AppLifecycleState.resumed &&
        _currentIndex == _tabCamera) {
      context.read<CameraProvider>().init();
    }
  }

  List<Widget> _buildScreens() {
    return [
      DashboardScreen(
        onOpenLiveView: () => setState(() => _currentIndex = _tabCamera),
        onOpenNotifications: () => setState(() => _currentIndex = _tabNotifications),
        onOpenSettings: () => setState(() => _currentIndex = _tabSettings),
      ),
      const CameraScreen(),
      const NotificationsScreen(),
      const SettingsScreen(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _currentIndex == _tabDashboard,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _currentIndex != _tabDashboard) {
          setState(() => _currentIndex = _tabDashboard);
        }
      },
      child: Scaffold(
        body: IndexedStack(
          index: _currentIndex,
          children: _buildScreens(),
        ),
        bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.camera_alt_outlined),
            selectedIcon: Icon(Icons.camera_alt),
            label: 'Camera',
          ),
          NavigationDestination(
            icon: Icon(Icons.notifications_outlined),
            selectedIcon: Icon(Icons.notifications),
            label: 'Notifications',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
        ),
      ),
    );
  }
}
