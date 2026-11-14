import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'l10n/l10n.dart';

final notifications = FlutterLocalNotificationsPlugin();

bool notificationsReady = false;

Future<void> setupNotifications({bool requestPermission = false}) async {
  try {
    if (!notificationsReady) {
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const darwin = DarwinInitializationSettings();
      await notifications.initialize(
        const InitializationSettings(android: android, iOS: darwin),
      );
      notificationsReady = true;
    }
    if (!requestPermission) return;
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      await notifications
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    } else {
      await notifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    }
  } catch (_) {
    // Plugin absent en tests / plateformes non supportées.
  }
}

String _groupFcfa(int amount) => amount.toString().replaceAllMapped(
  RegExp(r'\B(?=(\d{3})+(?!\d))'),
  (_) => ' ',
);

Future<void> notifyThreshold(int amount, {L10n? l10n}) async {
  try {
    final english = l10n?.isEnglish ?? false;
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        'thresholds',
        english ? 'Balance thresholds' : 'Seuils de solde',
        channelDescription: english
            ? 'Alerts when balance goes under your threshold'
            : 'Alertes quand le solde passe sous ton seuil',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: const DarwinNotificationDetails(),
    );
    final body = english
        ? 'Your total balance is under ${_groupFcfa(amount)} FCFA.'
        : 'Ton solde total est sous ${_groupFcfa(amount)} FCFA.';
    await notifications.show(
      41,
      english ? 'Low balance' : 'Solde bas',
      body,
      details,
    );
  } catch (_) {}
}

Future<void> notifyChargeDue(String name, int amount, {L10n? l10n}) async {
  try {
    final english = l10n?.isEnglish ?? false;
    final label = l10n?.t(name) ?? name;
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        'charges',
        english ? 'Due dates' : 'Échéances',
        channelDescription: english
            ? 'Reminders for bills due'
            : 'Rappels de charges à régler',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      ),
      iOS: const DarwinNotificationDetails(),
    );
    await notifications.show(
      42,
      english ? 'Due today' : 'Échéance du jour',
      '$label · ${_groupFcfa(amount)} FCFA',
      details,
    );
  } catch (_) {}
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
    final l10n = context.l10n;
    return Card(
      color: const Color(0xffffe4e8),
      child: ListTile(
        leading: const Icon(
          Icons.warning_amber_rounded,
          color: Color(0xffd81c50),
        ),
        title: Text(
          l10n.t('Solde sous ton seuil'),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          l10n.isEnglish
              ? 'Total ${_groupFcfa(total)} FCFA · threshold ${_groupFcfa(threshold)} FCFA'
              : 'Total ${_groupFcfa(total)} FCFA · seuil ${_groupFcfa(threshold)} FCFA',
        ),
      ),
    );
  }
}
