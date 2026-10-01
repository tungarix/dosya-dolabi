import 'package:flutter/material.dart';

import '../file_kind.dart';
import '../library.dart';
import '../preview.dart';
import '../state.dart';
import '../text.dart';
import 'file_actions.dart';
import 'file_preview.dart';
import 'layout.dart';

/// Açık yerdeki dosyalar (ve alt kategoriler): ızgara ya da liste.
class FileView extends StatelessWidget {
  const FileView({super.key, required this.state});

  final DolapState state;

  @override
  Widget build(BuildContext context) {
    final files = state.visibleFiles;
    final subs = state.subcategories;
    final searching = state.query.trim().isNotEmpty;
    final inInbox = state.place.section == Section.inbox && !searching;
    final showWhere = searching || state.place.section != Section.category;

    if (files.isEmpty && subs.isEmpty) {
      return _Empty(state: state, searching: searching);
    }

    return RefreshIndicator(
      onRefresh: state.refresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (inInbox)
            const SliverToBoxAdapter(
              child: _Hint(
                'Henüz düzenlenmemiş dosyaların. Bir dosyanın yanındaki '
                '"Kategoriye koy" düğmesine bas; dosya o kategorinin klasörüne '
                'taşınır.',
              ),
            ),
          if (subs.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              sliver: SliverToBoxAdapter(
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final c in subs)
                      ActionChip(
                        avatar: const Icon(Icons.folder_rounded, size: 20),
                        label: Text(
                          c.totalFiles == 0
                              ? c.name
                              : '${c.name}  ·  ${c.totalFiles}',
                        ),
                        onPressed: () => state.go(Place.category(c.path)),
                      ),
                  ],
                ),
              ),
            ),
          if (files.isEmpty && subs.isNotEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    'Bu kategorinin kendisinde dosya yok; dosyalar alt '
                    'kategorilerinde.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
          if (state.grid)
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverGrid.builder(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 240,
                  mainAxisExtent: 256,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                ),
                itemCount: files.length,
                itemBuilder: (_, i) => _FileCard(
                  state: state,
                  file: files[i],
                  showWhere: showWhere,
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
              sliver: SliverList.builder(
                itemCount: files.length,
                itemBuilder: (_, i) => _FileRow(
                  state: state,
                  file: files[i],
                  showWhere: showWhere,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(Icons.lightbulb_outline, color: cs.onPrimaryContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: TextStyle(color: cs.onPrimaryContainer)),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.state, required this.searching});
  final DolapState state;
  final bool searching;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (IconData icon, String title, String body) = searching
        ? (
            Icons.search_off_rounded,
            'Sonuç yok',
            '"${state.query.trim()}" ile eşleşen dosya bulunamadı.',
          )
        : switch (state.place.section) {
            Section.inbox => (
              Icons.inbox_rounded,
              'Gelen Kutusu boş',
              'İndirdiğin ya da aldığın yeni PDF ve sunum dosyaları burada '
                  'görünür. Hepsini düzenledin!',
            ),
            Section.all => (
              Icons.folder_open_rounded,
              'Dolap henüz boş',
              'Gelen Kutusu\'ndaki dosyaları bir kategoriye koyduğunda '
                  'burada görünür.',
            ),
            _ => (
              Icons.folder_open_rounded,
              'Bu kategori boş',
              'Gelen Kutusu\'ndan dosya taşıyabilirsin.',
            ),
          };
    return RefreshIndicator(
      onRefresh: state.refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: 360,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 72, color: cs.outline),
                  const SizedBox(height: 12),
                  Text(title, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      body,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _FileAction { preview, open, openWith, move, rename, trash }

class _FileMenu extends StatelessWidget {
  const _FileMenu({required this.state, required this.file});
  final DolapState state;
  final DocFile file;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_FileAction>(
      tooltip: 'Dosya işlemleri',
      icon: const Icon(Icons.more_vert, size: 20),
      onSelected: (a) {
        switch (a) {
          case _FileAction.preview:
            showFilePreviewDialog(context, state, file);
          case _FileAction.open:
            openDoc(context, file);
          case _FileAction.openWith:
            openDoc(context, file, chooser: true);
          case _FileAction.move:
            moveDocs(context, state, [file]);
          case _FileAction.rename:
            renameDoc(context, state, file);
          case _FileAction.trash:
            trashDocs(context, state, [file]);
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: _FileAction.preview,
          child: ListTile(
            leading: Icon(Icons.visibility_outlined),
            title: Text('Önizle'),
          ),
        ),
        const PopupMenuItem(
          value: _FileAction.open,
          child: ListTile(leading: Icon(Icons.open_in_new), title: Text('Aç')),
        ),
        const PopupMenuItem(
          value: _FileAction.openWith,
          child: ListTile(
            leading: Icon(Icons.apps_rounded),
            title: Text('Şununla aç…'),
          ),
        ),
        PopupMenuItem(
          value: _FileAction.move,
          child: ListTile(
            leading: const Icon(Icons.drive_file_move_outlined),
            title: Text(
              file.inLibrary ? 'Başka kategoriye taşı…' : 'Kategoriye koy…',
            ),
          ),
        ),
        const PopupMenuItem(
          value: _FileAction.rename,
          child: ListTile(
            leading: Icon(Icons.drive_file_rename_outline),
            title: Text('Adını değiştir'),
          ),
        ),
        const PopupMenuItem(
          value: _FileAction.trash,
          child: ListTile(
            leading: Icon(Icons.delete_outline),
            title: Text('Çöp kutusuna at'),
          ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------ kart/satır

/// Önizlemenin üstüne binen küçük tür etiketi ("PDF", "Slayt"...).
class _KindChip extends StatelessWidget {
  const _KindChip(this.kind);
  final FileKind kind;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: kind.color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(kind.icon, size: 14, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            kind.label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Önizlemenin üstünde okunur kalması için yarı saydam yuvarlak zemin.
class _OnPreview extends StatelessWidget {
  const _OnPreview({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.88),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(width: 36, height: 36, child: Center(child: child)),
    );
  }
}

class _FileCard extends StatelessWidget {
  const _FileCard({
    required this.state,
    required this.file,
    required this.showWhere,
  });

  static const previewHeight = 120.0;

  final DolapState state;
  final DocFile file;
  final bool showWhere;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final selected = state.selected.contains(file.path);
    final sub = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: cs.onSurfaceVariant);
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: selected ? cs.secondaryContainer : cs.surfaceContainerHigh,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: selected
            ? BorderSide(color: cs.primary, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: () => state.selecting
            ? state.toggleSelected(file.path)
            : openDoc(context, file),
        onLongPress: () => state.toggleSelected(file.path),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: previewHeight,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  FilePreview(
                    cache: state.previews,
                    file: file,
                    px: cardPreviewPx,
                    iconSize: 44,
                  ),
                  Positioned(left: 8, bottom: 8, child: _KindChip(file.kind)),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: _OnPreview(
                      child: state.selecting
                          ? Icon(
                              selected
                                  ? Icons.check_circle_rounded
                                  : Icons.radio_button_unchecked,
                              color: selected ? cs.primary : cs.outline,
                            )
                          : _FileMenu(state: state, file: file),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        file.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    Text(
                      '${formatSize(file.size)} · ${formatDate(file.modified)}',
                      style: sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (showWhere)
                      Text(
                        state.whereIs(file),
                        style: sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    if (!file.inLibrary && !state.selecting)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                          ),
                          onPressed: () => moveDocs(context, state, [file]),
                          icon: const Icon(
                            Icons.drive_file_move_rounded,
                            size: 18,
                          ),
                          label: const Text('Kategoriye koy'),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({
    required this.state,
    required this.file,
    required this.showWhere,
  });

  final DolapState state;
  final DocFile file;
  final bool showWhere;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final compact = isCompact(context);
    final selected = state.selected.contains(file.path);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        tileColor: selected ? cs.secondaryContainer : null,
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 48,
            height: 60,
            child: FilePreview(
              cache: state.previews,
              file: file,
              px: rowPreviewPx,
              iconSize: 26,
            ),
          ),
        ),
        title: Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          [
            file.kind.label,
            formatSize(file.size),
            if (showWhere) state.whereIs(file),
            formatDate(file.modified),
          ].join(' · '),
          // Telefonda tarih ve konum kesilmesin diye iki satıra izin ver.
          maxLines: compact ? 2 : 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: state.selecting
            ? Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked,
                color: selected ? cs.primary : cs.outline,
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!file.inLibrary && compact)
                    IconButton.filledTonal(
                      tooltip: 'Kategoriye koy',
                      icon: const Icon(Icons.drive_file_move_rounded),
                      onPressed: () => moveDocs(context, state, [file]),
                    )
                  else if (!file.inLibrary)
                    FilledButton.tonalIcon(
                      onPressed: () => moveDocs(context, state, [file]),
                      icon: const Icon(Icons.drive_file_move_rounded, size: 18),
                      label: const Text('Kategoriye koy'),
                    ),
                  _FileMenu(state: state, file: file),
                ],
              ),
        onTap: () => state.selecting
            ? state.toggleSelected(file.path)
            : openDoc(context, file),
        onLongPress: () => state.toggleSelected(file.path),
      ),
    );
  }
}
