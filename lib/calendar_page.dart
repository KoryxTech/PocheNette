import 'package:flutter/material.dart';

import 'catalog.dart';
import 'design.dart';

typedef RowData = Map<String, dynamic>;

class ChargesCalendarPage extends StatefulWidget {
  const ChargesCalendarPage({
    super.key,
    required this.charges,
    required this.money,
  });

  final List<RowData> charges;
  final String Function(int) money;

  @override
  State<ChargesCalendarPage> createState() => _ChargesCalendarPageState();
}

class _ChargesCalendarPageState extends State<ChargesCalendarPage> {
  late DateTime month;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    month = DateTime(now.year, now.month);
  }

  List<RowData> forDay(DateTime day) => widget.charges.where((charge) {
    final date = DateTime.parse(charge['date'] as String);
    return date.year == day.year &&
        date.month == day.month &&
        date.day == day.day;
  }).toList();

  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final startWeekday = first.weekday % 7;
    final labels = ['D', 'L', 'M', 'M', 'J', 'V', 'S'];
    final monthNames = const [
      'Janvier',
      'Février',
      'Mars',
      'Avril',
      'Mai',
      'Juin',
      'Juillet',
      'Août',
      'Septembre',
      'Octobre',
      'Novembre',
      'Décembre',
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Calendrier des échéances')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => setState(
                  () => month = DateTime(month.year, month.month - 1),
                ),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  '${monthNames[month.month - 1]} ${month.year}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => setState(
                  () => month = DateTime(month.year, month.month + 1),
                ),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final label in labels)
                Expanded(
                  child: Center(
                    child: Text(
                      label,
                      style: const TextStyle(
                        color: muted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: startWeekday + daysInMonth,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
            ),
            itemBuilder: (context, index) {
              if (index < startWeekday) return const SizedBox.shrink();
              final day = index - startWeekday + 1;
              final date = DateTime(month.year, month.month, day);
              final items = forDay(date);
              final today = DateTime.now();
              final isToday =
                  date.year == today.year &&
                  date.month == today.month &&
                  date.day == today.day;
              return Container(
                decoration: BoxDecoration(
                  color: items.isEmpty ? Colors.white : const Color(0xffc5f6e3),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: isToday ? emerald : border),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '$day',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: isToday ? emerald : ink,
                      ),
                    ),
                    if (items.isNotEmpty)
                      Text(
                        '${items.length}',
                        style: const TextStyle(fontSize: 10, color: muted),
                      ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 18),
          const Text(
            'Échéances du mois',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
          ),
          const SizedBox(height: 10),
          if (widget.charges
              .where((charge) {
                final date = DateTime.parse(charge['date'] as String);
                return date.year == month.year && date.month == month.month;
              })
              .isEmpty)
            const Card(
              child: ListTile(
                leading: IconPlate(Icons.event_available_outlined),
                title: Text('Aucune échéance'),
                subtitle: Text('Ajoute une charge pour la voir ici.'),
              ),
            ),
          for (final charge
              in widget.charges.where((charge) {
                final date = DateTime.parse(charge['date'] as String);
                return date.year == month.year && date.month == month.month;
              }))
            Card(
              child: ListTile(
                leading: IconPlate(categoryIcon(charge['name'] as String?)),
                title: Text(
                  charge['name'] as String,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${DateTime.parse(charge['date'] as String).day}/${month.month}/${month.year} · ${charge['frequency']}',
                ),
                trailing: Text(
                  widget.money(charge['amount'] as int),
                  style: numberStyle.copyWith(fontSize: 12),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
