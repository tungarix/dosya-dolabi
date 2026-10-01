import 'package:flutter/material.dart';

import '../library.dart';
import '../state.dart';
import 'dialogs.dart';

/// Sol panel: Gelen Kutusu, Tüm dosyalar, kategori ağacı ve Çöp Kutusu.
class Sidebar extends StatelessWidget {
  const Sidebar({super.key, required this.state, this.onNavigate});

  final DolapState state;

  /// Dar ekranda (çekmece) bir yere gidince çekmeceyi kapatmak için.
  final VoidCallback? onNavigate;

  void _go(Place p) {
    state.go(p);
    onNavigate?.call();
  }

  Future<void> _newCategory(BuildContext context, String parent) async {
    final name = await promptName(
      context,
      title: parent.isEmpty
          ? 'Yeni kategori'
          : '"${parent.split('/').last}" içine yeni kategori',
      confirmText: 'Oluştur',
      hint: 'Örn. Matematik',
    );
    if (name == null || !context.mounted) return;
    runAndShow(context, state.createCategory(parent, name));
  }

  Future<void> _rename(BuildContext context, CategoryNode c) async {
    final name = await promptName(
      context,
      title: 'Kategoriyi yeniden adlandır',
      confirmText: 'Kaydet',
      initial: c.name,
    );
    if (name == null || !context.mounted) return;
    runAndShow(context, state.renameCategory(c.path, name));
  }

  Future<void> _move(BuildContext context, CategoryNode c) async {
    final to = await pickCategory(
      context,
      state,
      title: '"${c.name}" nereye taşınsın?',
      exclude: c.path,
      allowRoot: true,
    );
    if (to == null || !context.mounted) return;
    runAndShow(context, state.moveCategory(c.path, to));
  }

  Future<void> _delete(BuildContext context, CategoryNode c) async {
    final ok = await confirm(
      context,
      title: '"${c.name}" kategorisi silinsin mi?',
      body: c.totalFiles == 0 && c.children.isEmpty
          ? 'Bu kategori boş.'
          : 'İçindeki dosyalar ve alt kategoriler silinmez; bir üst kategoriye '
                'taşınır.',
      confirmText: 'Sil',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    runAndShow(context, state.deleteCategory(c.path));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final snap = state.snap;
    final cats = snap?.root.children ?? const <CategoryNode>[];

    return Material(
      color: cs.surfaceContainerLow,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 12, 8),
              child: Row(
                children: [
                  Icon(
                    Icons.folder_special_rounded,
                    color: cs.primary,
                    size: 28,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Dosya Dolabı',
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            _NavTile(
              icon: Icons.inbox_rounded,
              label: 'Gelen Kutusu',
              count: state.inboxCount,
              highlight: state.inboxCount > 0,
              selected: state.place == const Place.inbox(),
              onTap: () => _go(const Place.inbox()),
            ),
            _NavTile(
              icon: Icons.folder_copy_rounded,
              label: 'Tüm dosyalar',
              count: state.totalCount,
              selected: state.place == const Place.all(),
              onTap: () => _go(const Place.all()),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'KATEGORİLER',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Yeni kategori',
                    icon: const Icon(Icons.add),
                    onPressed: () => _newCategory(context, ''),
                  ),
                ],
              ),
            ),
            Expanded(
              child: cats.isEmpty
                  ? _EmptyTree(state: state)
                  : ListView(
                      padding: const EdgeInsets.only(bottom: 8),
                      children: [for (final c in cats) ..._rows(context, c, 0)],
                    ),
            ),
            const Divider(height: 1),
            _NavTile(
              icon: Icons.delete_outline_rounded,
              label: 'Çöp Kutusu',
              count: state.trashCount,
              selected: state.place == const Place.trash(),
              onTap: () => _go(const Place.trash()),
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  Iterable<Widget> _rows(
    BuildContext context,
    CategoryNode c,
    int depth,
  ) sync* {
    final open = state.expanded.contains(c.path);
    yield _CategoryRow(
      category: c,
      depth: depth,
      expanded: open,
      selected: state.place == Place.category(c.path),
      onTap: () => _go(Place.category(c.path)),
      onToggle: c.children.isEmpty ? null : () => state.toggleExpanded(c.path),
      onMenu: (action) {
        switch (action) {
          case _CatAction.addChild:
            _newCategory(context, c.path);
          case _CatAction.rename:
            _rename(context, c);
          case _CatAction.move:
            _move(context, c);
          case _CatAction.delete:
            _delete(context, c);
        }
      },
    );
    if (open) {
      for (final child in c.children) {
        yield* _rows(context, child, depth + 1);
      }
    }
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.icon,
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
    this.highlight = false,
  });

  final IconData icon;
  final String label;
  final int count;
  final bool selected;
  final bool highlight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: ListTile(
        dense: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        selected: selected,
        selectedTileColor: cs.secondaryContainer,
        selectedColor: cs.onSecondaryContainer,
        leading: Icon(icon),
        title: Text(label),
        trailing: count == 0
            ? null
            : highlight
            ? Badge(label: Text('$count'), backgroundColor: cs.primary)
            : Text('$count', style: TextStyle(color: cs.onSurfaceVariant)),
        onTap: onTap,
      ),
    );
  }
}

enum _CatAction { addChild, rename, move, delete }

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.category,
    required this.depth,
    required this.expanded,
    required this.selected,
    required this.onTap,
    required this.onToggle,
    required this.onMenu,
  });

  final CategoryNode category;
  final int depth;
  final bool expanded;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onToggle;
  final void Function(_CatAction) onMenu;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = selected ? cs.onSecondaryContainer : null;
    return Padding(
      padding: EdgeInsets.fromLTRB(8 + depth * 16.0, 1, 4, 1),
      child: Material(
        color: selected ? cs.secondaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          onLongPress: () {},
          child: SizedBox(
            height: 44,
            child: Row(
              children: [
                SizedBox(
                  width: 36,
                  child: onToggle == null
                      ? null
                      : IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: expanded ? 'Daralt' : 'Genişlet',
                          icon: Icon(
                            expanded
                                ? Icons.keyboard_arrow_down_rounded
                                : Icons.keyboard_arrow_right_rounded,
                            color: fg,
                          ),
                          onPressed: onToggle,
                        ),
                ),
                Icon(
                  selected ? Icons.folder_open_rounded : Icons.folder_rounded,
                  size: 22,
                  color: selected ? fg : cs.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    category.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: fg),
                  ),
                ),
                if (category.totalFiles > 0)
                  Padding(
                    padding: const EdgeInsets.only(right: 2),
                    child: Text(
                      '${category.totalFiles}',
                      style: TextStyle(color: fg ?? cs.onSurfaceVariant),
                    ),
                  ),
                PopupMenuButton<_CatAction>(
                  tooltip: 'Kategori işlemleri',
                  icon: Icon(Icons.more_vert, size: 20, color: fg),
                  onSelected: onMenu,
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: _CatAction.addChild,
                      child: ListTile(
                        leading: Icon(Icons.create_new_folder_outlined),
                        title: Text('Alt kategori ekle'),
                      ),
                    ),
                    PopupMenuItem(
                      value: _CatAction.rename,
                      child: ListTile(
                        leading: Icon(Icons.drive_file_rename_outline),
                        title: Text('Adını değiştir'),
                      ),
                    ),
                    PopupMenuItem(
                      value: _CatAction.move,
                      child: ListTile(
                        leading: Icon(Icons.drive_file_move_outlined),
                        title: Text('Taşı…'),
                      ),
                    ),
                    PopupMenuItem(
                      value: _CatAction.delete,
                      child: ListTile(
                        leading: Icon(Icons.delete_outline),
                        title: Text('Sil'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Hiç kategori yokken: boş ağaç yerine hazır başlangıç önerileri.
class _EmptyTree extends StatelessWidget {
  const _EmptyTree({required this.state});
  final DolapState state;

  static const _starters = [
    'Dersler',
    'İş',
    'Kişisel',
    'Faturalar',
    'Sunumlar',
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Henüz kategori yok. Hazır bir tanesiyle başla ya da yukarıdaki + '
            'ile kendin oluştur:',
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final n in _starters)
                ActionChip(
                  label: Text(n),
                  avatar: const Icon(Icons.add, size: 18),
                  onPressed: () async =>
                      runAndShow(context, state.createCategory('', n)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
