/// Arayüzün tek durum kaynağı: hangi yerin açık olduğu, seçim, arama, sıralama
/// ve dosya işlemleri. Her işlem kullanıcıya gösterilecek bir [Outcome] döner.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'library.dart';
import 'preview.dart';
import 'text.dart';

enum Section { inbox, all, category, trash }

class Place {
  const Place(this.section, [this.category = '']);
  const Place.inbox() : this(Section.inbox);
  const Place.all() : this(Section.all);
  const Place.trash() : this(Section.trash);
  const Place.category(String path) : this(Section.category, path);

  final Section section;
  final String category;

  @override
  bool operator ==(Object other) =>
      other is Place && other.section == section && other.category == category;

  @override
  int get hashCode => Object.hash(section, category);
}

enum SortBy {
  name('Ada göre'),
  newest('En yeni'),
  size('Boyuta göre'),
  type('Türe göre');

  const SortBy(this.label);
  final String label;
}

/// Bir işlemin kullanıcıya gösterilecek sonucu; [undo] varsa "Geri al" çıkar.
class Outcome {
  const Outcome(this.message, {this.undo, this.isError = false});
  final String message;
  final Future<void> Function()? undo;
  final bool isError;
}

class DolapState extends ChangeNotifier {
  DolapState(this.lib, [this._prefs, PreviewCache? previews])
    : previews = previews ?? PreviewCache(const PlatformPreviewSource()) {
    sort = SortBy.values.firstWhere(
      (s) => s.name == _prefs?.getString('sort'),
      orElse: () => SortBy.name,
    );
    grid = _prefs?.getBool('grid') ?? true;
    expanded.addAll(_prefs?.getStringList('expanded') ?? const []);
  }

  final Library lib;

  /// Dosya önizlemeleri (küçük resim/metin); ekran kaydırılırken tembel üretilir.
  final PreviewCache previews;
  final SharedPreferences? _prefs;

  LibrarySnapshot? snap;
  bool loading = true;
  String? loadError;

  Place place = const Place.inbox();
  String query = '';
  late SortBy sort;
  late bool grid;
  final selected = <String>{};
  final expanded = <String>{};

  bool get selecting => selected.isNotEmpty;

  // ------------------------------------------------------------ yükleme

  Future<void> refresh({bool first = false}) async {
    try {
      snap = await lib.scan();
      loadError = null;
    } on FileSystemException catch (e) {
      loadError = 'Dosyalar okunamadı: ${e.osError?.message ?? e.message}';
    }
    final s = snap;
    if (s != null) {
      if (first && s.inbox.isEmpty && s.root.totalFiles > 0) {
        place = const Place.all();
      }
      if (place.section == Section.category && s.find(place.category) == null) {
        place = const Place.all();
      }
      final exist = {
        ...s.inbox.map((f) => f.path),
        ...s.root.allFiles.map((f) => f.path),
      };
      selected.removeWhere((path) => !exist.contains(path));
    }
    loading = false;
    notifyListeners();
  }

  // ------------------------------------------------------------ görünüm

  void go(Place target) {
    place = target;
    query = '';
    selected.clear();
    notifyListeners();
  }

  void setQuery(String q) {
    query = q;
    notifyListeners();
  }

  void setSort(SortBy s) {
    sort = s;
    _prefs?.setString('sort', s.name);
    notifyListeners();
  }

  void toggleGrid() {
    grid = !grid;
    _prefs?.setBool('grid', grid);
    notifyListeners();
  }

  void toggleExpanded(String path) {
    if (!expanded.remove(path)) expanded.add(path);
    _prefs?.setStringList('expanded', expanded.toList());
    notifyListeners();
  }

  /// Sidebar'da bir kategoriyi görünür kılmak için üstlerini açar.
  void reveal(String path) {
    var parent = parentOf(path);
    while (parent.isNotEmpty) {
      expanded.add(parent);
      parent = parentOf(parent);
    }
    _prefs?.setStringList('expanded', expanded.toList());
  }

  // ------------------------------------------------------------- seçim

  void toggleSelected(String path) {
    if (!selected.remove(path)) selected.add(path);
    notifyListeners();
  }

  void clearSelection() {
    if (selected.isEmpty) return;
    selected.clear();
    notifyListeners();
  }

  void selectAll(Iterable<DocFile> files) {
    selected
      ..clear()
      ..addAll(files.map((f) => f.path));
    notifyListeners();
  }

  // ---------------------------------------------------- görünen dosyalar

  int get inboxCount => snap?.inbox.length ?? 0;
  int get totalCount => snap?.root.totalFiles ?? 0;
  int get trashCount => snap?.trash.length ?? 0;

  Iterable<DocFile> get _everything sync* {
    final s = snap;
    if (s == null) return;
    yield* s.inbox;
    yield* s.root.allFiles;
  }

  /// Arama açıksa tüm dosyalarda, değilse açık yerdeki dosyalar.
  List<DocFile> get visibleFiles {
    final s = snap;
    if (s == null) return const [];
    final Iterable<DocFile> base;
    if (query.trim().isNotEmpty) {
      final q = fold(query.trim());
      base = _everything.where((f) => fold(f.name).contains(q));
    } else {
      base = switch (place.section) {
        Section.inbox => s.inbox,
        Section.all => s.root.allFiles,
        Section.category => s.find(place.category)?.files ?? const <DocFile>[],
        Section.trash => const <DocFile>[],
      };
    }
    final list = base.toList();
    switch (sort) {
      case SortBy.name:
        list.sort((a, b) => naturalCompare(a.name, b.name));
      case SortBy.newest:
        list.sort((a, b) => b.modified.compareTo(a.modified));
      case SortBy.size:
        list.sort((a, b) => b.size.compareTo(a.size));
      case SortBy.type:
        list.sort((a, b) {
          final c = a.kind.index.compareTo(b.kind.index);
          return c != 0 ? c : naturalCompare(a.name, b.name);
        });
    }
    return list;
  }

  /// Açık kategorinin alt kategorileri (arama açıkken yok).
  List<CategoryNode> get subcategories {
    if (query.trim().isNotEmpty || place.section != Section.category) {
      return const [];
    }
    return snap?.find(place.category)?.children ?? const [];
  }

  /// Dosyanın bulunduğu yerin kullanıcıya gösterilen adı.
  String whereIs(DocFile f) {
    if (f.inLibrary) {
      return f.category!.isEmpty
          ? 'Kategorisiz'
          : f.category!.replaceAll('/', ' › ');
    }
    return p.basename(p.dirname(f.path));
  }

  String whereWasTrashed(TrashItem t) {
    final dir = p.dirname(t.originalPath);
    if (p.isWithin(lib.root, t.originalPath)) {
      final rel = p.relative(dir, from: lib.root);
      return rel == '.' ? 'Kategorisiz' : rel.replaceAll(p.separator, ' › ');
    }
    return p.basename(dir);
  }

  // ------------------------------------------------------------ işlemler

  Future<Outcome> _run(Future<Outcome> Function() body) async {
    try {
      return await body();
    } on LibraryException catch (e) {
      return Outcome(e.message, isError: true);
    } on FileSystemException catch (e) {
      return Outcome(
        'İşlem yapılamadı: ${e.osError?.message ?? e.message}',
        isError: true,
      );
    }
  }

  Future<Outcome> _undoable(String message, List<Moved> moves) async {
    await refresh();
    return Outcome(
      message,
      undo: () async {
        await lib.undo(moves);
        await refresh();
      },
    );
  }

  String _label(String category) => category.split('/').last;

  Future<Outcome> moveFiles(Iterable<DocFile> files, String category) =>
      _run(() async {
        final r = await lib.moveFiles(files.map((f) => f.path), category);
        selected.clear();
        if (r.moved.isEmpty && r.failed.isEmpty) {
          await refresh();
          return Outcome('Dosya zaten "${_label(category)}" kategorisinde');
        }
        final n = r.moved.length;
        final msg = r.failed.isEmpty
            ? (n == 1
                  ? '"${p.basename(r.moved.single.to)}" → ${_label(category)}'
                  : '$n dosya "${_label(category)}" kategorisine taşındı')
            : '$n dosya taşındı, ${r.failed.length} dosya taşınamadı';
        final o = await _undoable(msg, r.moved);
        return r.failed.isEmpty
            ? o
            : Outcome(o.message, undo: o.undo, isError: true);
      });

  Future<Outcome> trashFiles(Iterable<DocFile> files) => _run(() async {
    final r = await lib.trashFiles(files.map((f) => f.path));
    selected.clear();
    final n = r.moved.length;
    final msg = r.failed.isEmpty
        ? (n == 1
              ? 'Dosya çöp kutusuna taşındı'
              : '$n dosya çöp kutusuna taşındı')
        : '$n dosya silindi, ${r.failed.length} dosya silinemedi';
    final o = await _undoable(msg, r.moved);
    return r.failed.isEmpty
        ? o
        : Outcome(o.message, undo: o.undo, isError: true);
  });

  Future<Outcome> renameFile(DocFile f, String name) => _run(() async {
    final to = await lib.renameFile(f.path, name);
    selected.remove(f.path);
    await refresh();
    return Outcome('Adı "${p.basename(to)}" oldu');
  });

  Future<Outcome> createCategory(String parent, String name) => _run(() async {
    final path = await lib.createCategory(parent, name);
    reveal(path);
    await refresh();
    return Outcome('"${_label(path)}" kategorisi oluşturuldu');
  });

  /// Yol değişince açık yeri ve açık dalları yeni yola uyarlar.
  void _remap(String from, String to) {
    String? map(String path) {
      if (path == from) return to;
      if (path.startsWith('$from/')) return to + path.substring(from.length);
      return null;
    }

    if (place.section == Section.category) {
      final m = map(place.category);
      if (m != null) place = Place.category(m);
    }
    final moved = {for (final e in expanded) e: map(e)}
      ..removeWhere((_, v) => v == null);
    expanded
      ..removeAll(moved.keys)
      ..addAll(moved.values.cast<String>());
    _prefs?.setStringList('expanded', expanded.toList());
  }

  Future<Outcome> renameCategory(String path, String name) => _run(() async {
    final to = await lib.renameCategory(path, name);
    if (to == path) return Outcome('Ad değişmedi');
    _remap(path, to);
    await refresh();
    return Outcome('"${_label(to)}" olarak yeniden adlandırıldı');
  });

  Future<Outcome> moveCategory(String path, String newParent) => _run(() async {
    final to = await lib.moveCategory(path, newParent);
    if (to == path) return Outcome('Kategori zaten orada');
    _remap(path, to);
    reveal(to);
    await refresh();
    return Outcome('"${_label(to)}" taşındı');
  });

  Future<Outcome> deleteCategory(String path) => _run(() async {
    final moved = await lib.deleteCategory(path);
    final parent = parentOf(path);
    if (place.section == Section.category &&
        (place.category == path || place.category.startsWith('$path/'))) {
      place = parent.isEmpty ? const Place.all() : Place.category(parent);
    }
    return _undoable(
      moved.isEmpty
          ? '"${_label(path)}" kategorisi silindi'
          : '"${_label(path)}" silindi, içindekiler bir üste taşındı',
      moved,
    );
  });

  Future<Outcome> restore(Iterable<TrashItem> items) => _run(() async {
    final r = await lib.restore(items);
    await refresh();
    final n = r.moved.length;
    if (r.failed.isNotEmpty) {
      return Outcome(
        '$n dosya geri konuldu, ${r.failed.length} dosya konulamadı',
        isError: true,
      );
    }
    return Outcome(n == 1 ? 'Dosya geri konuldu' : '$n dosya geri konuldu');
  });

  Future<Outcome> deleteForever(Iterable<TrashItem> items) => _run(() async {
    await lib.deleteForever(items);
    await refresh();
    return const Outcome('Kalıcı olarak silindi');
  });

  Future<Outcome> emptyTrash() => _run(() async {
    await lib.emptyTrash();
    await refresh();
    return const Outcome('Çöp kutusu boşaltıldı');
  });
}
