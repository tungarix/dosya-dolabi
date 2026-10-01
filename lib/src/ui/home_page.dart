import 'package:flutter/material.dart';

import '../state.dart';
import 'dialogs.dart';
import 'file_view.dart';
import 'sidebar.dart';
import 'trash_view.dart';

const _wideBreakpoint = 900.0;

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.state});

  final DolapState state;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _scaffold = GlobalKey<ScaffoldState>();
  final _search = TextEditingController();

  DolapState get state => widget.state;

  @override
  void initState() {
    super.initState();
    state.addListener(_syncSearchBox);
  }

  @override
  void dispose() {
    state.removeListener(_syncSearchBox);
    _search.dispose();
    super.dispose();
  }

  /// Başka yere gidince (durum aramayı sıfırlayınca) arama kutusunu da temizle.
  void _syncSearchBox() {
    if (state.query.isEmpty && _search.text.isNotEmpty) _search.clear();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final wide = MediaQuery.sizeOf(context).width >= _wideBreakpoint;
        final content = _Content(
          state: state,
          search: _search,
          showMenuButton: !wide,
          onMenu: () => _scaffold.currentState?.openDrawer(),
        );
        return PopScope(
          // Seçim açıkken geri tuşu önce seçimi kapatsın.
          canPop: !state.selecting,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) state.clearSelection();
          },
          child: Scaffold(
            key: _scaffold,
            drawer: wide
                ? null
                : Drawer(
                    width: 320,
                    child: Sidebar(
                      state: state,
                      onNavigate: () => Navigator.of(context).maybePop(),
                    ),
                  ),
            body: wide
                ? Row(
                    children: [
                      SizedBox(width: 320, child: Sidebar(state: state)),
                      const VerticalDivider(width: 1),
                      Expanded(child: content),
                    ],
                  )
                : content,
          ),
        );
      },
    );
  }
}

class _Content extends StatelessWidget {
  const _Content({
    required this.state,
    required this.search,
    required this.showMenuButton,
    required this.onMenu,
  });

  final DolapState state;
  final TextEditingController search;
  final bool showMenuButton;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final Widget body;
    if (state.loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (state.loadError != null && state.snap == null) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(state.loadError!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: state.refresh, child: const Text('Tekrar dene')),
            ],
          ),
        ),
      );
    } else if (state.place.section == Section.trash && state.query.trim().isEmpty) {
      body = TrashView(state: state);
    } else {
      body = FileView(state: state);
    }

    return SafeArea(
      child: Column(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 150),
            child: state.selecting
                ? _SelectionBar(key: const ValueKey('sel'), state: state)
                : _TopBar(
                    key: const ValueKey('top'),
                    state: state,
                    search: search,
                    showMenuButton: showMenuButton,
                    onMenu: onMenu,
                  ),
          ),
          Expanded(child: body),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    super.key,
    required this.state,
    required this.search,
    required this.showMenuButton,
    required this.onMenu,
  });

  final DolapState state;
  final TextEditingController search;
  final bool showMenuButton;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final trash = state.place.section == Section.trash;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Row(
        children: [
          if (showMenuButton)
            IconButton(
              tooltip: 'Kategoriler',
              icon: const Icon(Icons.menu),
              onPressed: onMenu,
            ),
          Expanded(child: _Title(state: state)),
          const SizedBox(width: 8),
          SizedBox(
            width: 260,
            child: TextField(
              controller: search,
              onChanged: state.setQuery,
              decoration: InputDecoration(
                hintText: 'Dosya ara',
                isDense: true,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: state.query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Aramayı temizle',
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          search.clear();
                          state.setQuery('');
                        },
                      ),
                filled: true,
                fillColor: cs.surfaceContainerHigh,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(28),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          if (!trash || state.query.isNotEmpty) ...[
            PopupMenuButton<SortBy>(
              tooltip: 'Sırala',
              icon: const Icon(Icons.sort_rounded),
              initialValue: state.sort,
              onSelected: state.setSort,
              itemBuilder: (_) => [
                for (final s in SortBy.values)
                  CheckedPopupMenuItem(
                    value: s,
                    checked: s == state.sort,
                    child: Text(s.label),
                  ),
              ],
            ),
            IconButton(
              tooltip: state.grid ? 'Liste görünümü' : 'Kart görünümü',
              icon: Icon(state.grid ? Icons.view_list_rounded : Icons.grid_view_rounded),
              onPressed: state.toggleGrid,
            ),
          ],
          IconButton(
            tooltip: 'Yenile',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: state.refresh,
          ),
        ],
      ),
    );
  }
}

/// "Gelen Kutusu" ya da tıklanabilir "Dersler › Matematik" yolu.
class _Title extends StatelessWidget {
  const _Title({required this.state});
  final DolapState state;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w600,
        );
    if (state.query.trim().isNotEmpty) {
      return Text('Arama sonuçları', style: style, maxLines: 1, overflow: TextOverflow.ellipsis);
    }
    switch (state.place.section) {
      case Section.inbox:
        return Text('Gelen Kutusu', style: style);
      case Section.all:
        return Text('Tüm dosyalar', style: style);
      case Section.trash:
        return Text('Çöp Kutusu', style: style);
      case Section.category:
        final parts = state.place.category.split('/');
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var i = 0; i < parts.length; i++) ...[
                if (i > 0)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 2),
                    child: Icon(Icons.chevron_right, size: 22),
                  ),
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: i == parts.length - 1
                      ? null
                      : () => state.go(Place.category(parts.sublist(0, i + 1).join('/'))),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    child: Text(parts[i], style: style),
                  ),
                ),
              ],
            ],
          ),
        );
    }
  }
}

class _SelectionBar extends StatelessWidget {
  const _SelectionBar({super.key, required this.state});
  final DolapState state;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final all = state.visibleFiles;
    final chosen = all.where((f) => state.selected.contains(f.path)).toList();
    final inLibraryOnly = chosen.isNotEmpty && chosen.every((f) => f.inLibrary);
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: cs.secondaryContainer,
        borderRadius: BorderRadius.circular(28),
      ),
      height: 56,
      child: Row(
        children: [
          IconButton(
            tooltip: 'Seçimi kapat',
            icon: const Icon(Icons.close),
            onPressed: state.clearSelection,
          ),
          Expanded(
            child: Text(
              '${state.selected.length} dosya seçildi',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          TextButton.icon(
            onPressed: chosen.length == all.length ? null : () => state.selectAll(all),
            icon: const Icon(Icons.select_all),
            label: const Text('Hepsini seç'),
          ),
          FilledButton.icon(
            onPressed: chosen.isEmpty ? null : () => moveDocs(context, state, chosen),
            icon: const Icon(Icons.drive_file_move_rounded),
            label: Text(inLibraryOnly ? 'Taşı' : 'Kategoriye koy'),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Çöp kutusuna at',
            icon: const Icon(Icons.delete_outline),
            onPressed: chosen.isEmpty
                ? null
                : () async {
                    final ok = chosen.length < 2 ||
                        await confirm(
                          context,
                          title: '${fileCountLabel(chosen.length)} çöp kutusuna atılsın mı?',
                          body: 'Çöp kutusundan 30 gün içinde geri alabilirsin.',
                          confirmText: 'Çöpe at',
                        );
                    if (ok && context.mounted) trashDocs(context, state, chosen);
                  },
          ),
        ],
      ),
    );
  }
}
