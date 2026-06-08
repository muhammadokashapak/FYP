import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../widgets/alert_card.dart';
import 'notifications_provider.dart';

/// Notifications screen: list of dummy alerts (motion, object, person).
/// Structure ready for real-time alerts from AI/ESP32 later.
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
      ),
      body: Consumer<NotificationsProvider>(
        builder: (context, provider, _) {
          if (provider.items.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.notifications_none,
                    size: 64,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No alerts yet',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Alerts will appear here when detections occur.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: provider.items.length,
            itemBuilder: (context, index) {
              final alert = provider.items[index];
              return AlertCard(
                alert: alert,
                onTap: () => provider.markAsRead(alert.id),
              );
            },
          );
        },
      ),
    );
  }
}
