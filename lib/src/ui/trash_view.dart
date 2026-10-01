import 'package:flutter/material.dart';

import '../library.dart';
import '../state.dart';
import '../text.dart';
import 'dialogs.dart';

class TrashView extends StatelessWidget {
  const TrashView({super.key, required this.state});

  final DolapState state;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final items = state.snap?.trash ?? const <TrashItem>[];

    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.delete_outline_rounded, size: 72, color: cs.outline),
            const SizedBox(height: 12),
            Text('Çöp kutusu boş', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              'Sildiğin dosyalar burada 30 gün kalır, istersen geri alabilirsin.',
              style: TextStyle(color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, color: cs.onSurfaceVariant),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('Çöpteki dosyalar 30 gün sonra kalıcı olarak silinir.'),
              ),
              TextButton(
                onPressed: () async {
                  final ok = await confirm(
                    context,
                    title: 'Çöp kutusu boşaltılsın mı?',
                    body: '${fileCountLabel(items.length)} kalıcı olarak silinecek. '
                        'Bu geri alınamaz.',
                    confirmText: 'Boşalt',
                    destructive: true,
                  );
                  if (ok && context.mounted) {
                    runAndShow(context, state.emptyTrash());
                  }
                },
                child: const Text('Çöpü boşalt'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 24),
            itemCount: items.length,
            itemBuilder: (_, i) {
              final t = items[i];
              return ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                leading: Icon(t.kind.icon, color: t.kind.color, size: 32),
                title: Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  'Silindi: ${formatDate(t.deletedAt)} · Eski yeri: '
                  '${state.whereWasTrashed(t)} · ${formatSize(t.size)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: () async =>
                          runAndShow(context, state.restore([t])),
                      icon: const Icon(Icons.restore_rounded, size: 18),
                      label: const Text('Geri koy'),
                    ),
                    IconButton(
                      tooltip: 'Kalıcı olarak sil',
                      icon: const Icon(Icons.delete_forever_outlined),
                      onPressed: () async {
                        final ok = await confirm(
                          context,
                          title: '"${t.name}" kalıcı olarak silinsin mi?',
                          body: 'Bu geri alınamaz.',
                          confirmText: 'Sil',
                          destructive: true,
                        );
                        if (ok && context.mounted) {
                          runAndShow(context, state.deleteForever([t]));
                        }
                      },
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
