import 'package:flutter/material.dart';

import 'catalog.dart';
import 'design.dart';

typedef RowData = Map<String, dynamic>;

class StatsPage extends StatelessWidget {
  const StatsPage({
    super.key,
    required this.operations,
    required this.money,
    required this.categories,
  });

  final List<RowData> operations;
  final String Function(int) money;
  final List<String> categories;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month);
    final monthOps = operations
        .where((op) => (op['at'] as int) >= monthStart.millisecondsSinceEpoch)
        .toList();
    var income = 0;
    var expense = 0;
    final byCategory = <String, int>{};
    for (final op in monthOps) {
      if (op['transfer'] == true) continue;
      final delta = op['delta'] as int? ?? 0;
      if (delta > 0) {
        income += delta;
      } else if (delta < 0) {
        expense += -delta;
        final label = op['label'] as String? ?? 'Autre';
        byCategory.update(label, (value) => value - delta, ifAbsent: () => -delta);
      }
    }
    final maxCategory = byCategory.values.fold<int>(
      0,
      (max, value) => value > max ? value : max,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Statistiques')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SummaryPanel(
            label: 'Ce mois-ci',
            amount: money(income - expense),
            footer: 'Entrées ${money(income)} · Sorties ${money(expense)}',
          ),
          const Text(
            'Répartition des dépenses',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
          ),
          const SizedBox(height: 12),
          if (byCategory.isEmpty)
            const Card(
              child: ListTile(
                leading: IconPlate(Icons.bar_chart_outlined),
                title: Text('Pas encore de dépenses'),
                subtitle: Text('Les catégories apparaîtront ici.'),
              ),
            ),
          for (final (index, entry) in byCategory.entries.indexed)
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        IconPlate(
                          categoryIcon(entry.key),
                          color:
                              categoryColors[index % categoryColors.length],
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            entry.key,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        Text(
                          money(entry.value),
                          style: numberStyle.copyWith(fontSize: 12),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    PocheProgress(
                      value: maxCategory == 0
                          ? 0
                          : entry.value / maxCategory,
                      color: categoryColors[index % categoryColors.length],
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          const Text(
            'Catégories suivies',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final category in categories)
                Chip(
                  avatar: Icon(categoryIcon(category), size: 16, color: emerald),
                  label: Text(category),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
