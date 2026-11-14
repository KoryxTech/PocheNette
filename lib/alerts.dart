import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

final notifications = FlutterLocalNotificationsPlugin();

bool notificationsReady = false;

Future<void> setupNotifications({bool requestPermission = false}) async {
  if (!notificationsReady) {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await notifications.initialize(
      const InitializationSettings(android: android),
    );
    notificationsReady = true;
  }
  if (requestPermission) {
    await notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
  }
}

Future<void> notifyThreshold(int amount) async {
  const details = NotificationDetails(
    android: AndroidNotificationDetails(
      'thresholds',
      'Seuils de solde',
      channelDescription: 'Alertes quand le solde passe sous ton seuil',
      importance: Importance.high,
      priority: Priority.high,
    ),
  );
  await notifications.show(
    41,
    'Solde bas',
    'Ton solde total est sous ${amount.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ' ')} FCFA.',
    details,
  );
}

Future<void> notifyChargeDue(String name, int amount) async {
  const details = NotificationDetails(
    android: AndroidNotificationDetails(
      'charges',
      'Échéances',
      channelDescription: 'Rappels de charges à régler',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    ),
  );
  await notifications.show(
    42,
    'Échéance du jour',
    '$name · ${amount.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ' ')} FCFA',
    details,
  );
}

class ThresholdBanner extends StatelessWidget {
  const ThresholdBanner({
    super.key,
    required this.total,
    required this.threshold,
  });

  final int total;
  final int threshold;

  @override
  Widget build(BuildContext context) {
    if (total >= threshold) return const SizedBox.shrink();
    return Card(
      color: const Color(0xffffe4e8),
      child: ListTile(
        leading: const Icon(
          Icons.warning_amber_rounded,
          color: Color(0xffd81c50),
        ),
        title: const Text(
          'Solde sous ton seuil',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          'Total ${total.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ' ')} FCFA · seuil ${threshold.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ' ')} FCFA',
        ),
      ),
    );
  }
}
