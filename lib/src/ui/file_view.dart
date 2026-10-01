import 'package:flutter/material.dart';

import '../file_kind.dart';
import '../library.dart';
import '../platform_bridge.dart';
import '../state.dart';
import '../text.dart';
import 'dialogs.dart';
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
                  mainAxisExtent: 196,
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

// ------------------------------------------------------------ dosya işlemleri

Future<void> openDoc(
  BuildContext context,
  DocFile f, {
  bool chooser = false,
}) async {
  final r = await openFile(f.path, mimeOf(f.path), chooser: chooser);
  if (!context.mounted) return;
  switch (r) {
    case OpenResult.ok:
      break;
    case OpenResult.noApp:
      showOutcome(
        context,
        Outcome(
          'Bu ${f.kind.label.toLowerCase()} dosyasını açabilen bir uygulama yok. '
          'Play Store\'dan bir ${f.kind == FileKind.slides ? 'sunum' : f.kind.label.toLowerCase()} '
          'uygulaması yükleyebilirsin.',
          isError: true,
        ),
      );
    case OpenResult.failed:
      showOutcome(context, const Outcome('Dosya açılamadı', isError: true));
  }
}

Future<void> moveDocs(
  BuildContext context,
  DolapState state,
  List<DocFile> files,
) async {
  final to = await pickCategory(
    context,
    state,
    title: files.length == 1
        ? 'Hangi kategoriye koyalım?'
        : '${files.length} dosya hangi kategoriye koyulsun?',
  );
  if (to == null || !context.mounted) return;
  runAndShow(context, state.moveFiles(files, to));
}

Future<void> trashDocs(
  BuildContext context,
  DolapState state,
  List<DocFile> files,
) async {
  runAndShow(context, state.trashFiles(files));
}

Future<void> renameDoc(
  BuildContext context,
  DolapState state,
  DocFile f,
) async {
  final name = await promptName(
    context,
    title: 'Dosyanın adını değiştir',
    confirmText: 'Kaydet',
    initial: f.name,
    selectBaseName: true,
  );
  if (name == null || !context.mounted) return;
  runAndShow(context, state.renameFile(f, name));
}

enum _FileAction { open, openWith, move, rename, trash }

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

class _KindBadge extends StatelessWidget {
  const _KindBadge(this.kind, {this.size = 44});
  final FileKind kind;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: kind.color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      child: Icon(kind.icon, color: kind.color, size: size * 0.56),
    );
  }
}

class _FileCard extends StatelessWidget {
  const _FileCard({
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
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 4, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _KindBadge(file.kind),
                  const Spacer(),
                  if (state.selecting)
                    Padding(
                      padding: const EdgeInsets.only(right: 10, top: 4),
                      child: Icon(
                        selected
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked,
                        color: selected ? cs.primary : cs.outline,
                      ),
                    )
                  else
                    _FileMenu(state: state, file: file),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Text(
                    file.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Text(
                  '${file.kind.label} · ${formatSize(file.size)}',
                  style: sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 10, bottom: 2),
                child: Text(
                  showWhere
                      ? '${state.whereIs(file)} · ${formatDate(file.modified)}'
                      : formatDate(file.modified),
                  style: sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
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
                    icon: const Icon(Icons.drive_file_move_rounded, size: 18),
                    label: const Text('Kategoriye koy'),
                  ),
                ),
            ],
          ),
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
        leading: _KindBadge(file.kind, size: 42),
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
