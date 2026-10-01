/// Dolabın dosya sistemi katmanı: kategoriler gerçek klasörlerdir, dosyalar
/// gerçekten taşınır. Arayüzden bağımsızdır, testlerde geçici klasörle çalışır.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'file_kind.dart';
import 'text.dart';

/// Kullanıcıya olduğu gibi gösterilebilecek hata.
class LibraryException implements Exception {
  const LibraryException(this.message);
  final String message;
  @override
  String toString() => message;
}

class DocFile {
  const DocFile({
    required this.path,
    required this.size,
    required this.modified,
    this.category,
  });

  final String path;
  final int size;
  final DateTime modified;

  /// Dolaptaki kategorinin göreli yolu ('' = kategorisiz).
  /// Gelen Kutusu dosyalarında null.
  final String? category;

  String get name => p.basename(path);
  FileKind get kind => FileKind.of(path);
  bool get inLibrary => category != null;
}

class CategoryNode {
  CategoryNode(this.path, this.dir);

  /// Kökten göreli, '/' ile ayrılmış yol ("Dersler/Matematik"); kök için ''.
  final String path;

  /// Mutlak klasör yolu.
  final String dir;
  final children = <CategoryNode>[];
  final files = <DocFile>[];

  String get name => path.isEmpty ? '' : path.split('/').last;

  /// Üst kategorinin yolu; üst seviye kategoriler için ''.
  String get parent => parentOf(path);

  int get totalFiles =>
      files.length + children.fold(0, (s, c) => s + c.totalFiles);

  Iterable<CategoryNode> get descendants sync* {
    for (final c in children) {
      yield c;
      yield* c.descendants;
    }
  }

  Iterable<DocFile> get allFiles sync* {
    yield* files;
    for (final c in children) {
      yield* c.allFiles;
    }
  }
}

String parentOf(String categoryPath) {
  final i = categoryPath.lastIndexOf('/');
  return i < 0 ? '' : categoryPath.substring(0, i);
}

class TrashItem {
  const TrashItem({
    required this.path,
    required this.originalPath,
    required this.deletedAt,
    required this.size,
  });

  /// Çöp kutusundaki mutlak yol.
  final String path;
  final String originalPath;
  final DateTime deletedAt;
  final int size;

  String get name => p.basename(originalPath);
  FileKind get kind => FileKind.of(originalPath);
}

class LibrarySnapshot {
  LibrarySnapshot(this.root, this.inbox, this.trash);

  final CategoryNode root;
  final List<DocFile> inbox;
  final List<TrashItem> trash;

  CategoryNode? find(String path) {
    if (path.isEmpty) return root;
    for (final c in root.descendants) {
      if (c.path == path) return c;
    }
    return null;
  }

  List<CategoryNode> get categories => root.descendants.toList();
}

/// Bir taşımanın kaydı; geri almak için tersine çevrilir.
class Moved {
  const Moved(this.from, this.to);
  final String from;
  final String to;
}

class BatchResult {
  const BatchResult(this.moved, this.failed);
  final List<Moved> moved;
  final List<String> failed;
}

class Library {
  Library({required this.root, required this.inboxDirs, this.trashDays = 30});

  final String root;
  final List<String> inboxDirs;
  final int trashDays;

  static const trashFolder = '.cop-kutusu';
  static const _indexName = '.index.json';
  static const _skipInboxDirs = {'Sent', 'Private'};

  String get trashDir => p.join(root, trashFolder);

  String dirOf(String category) =>
      category.isEmpty ? root : p.joinAll([root, ...category.split('/')]);

  // ---------------------------------------------------------------- tarama

  Future<LibrarySnapshot> scan() async {
    await Directory(root).create(recursive: true);
    final top = CategoryNode('', root);
    await _scanCategory(top);
    final inbox = await _scanInbox();
    final trash = await _loadTrash();
    return LibrarySnapshot(top, inbox, trash);
  }

  Future<void> _scanCategory(CategoryNode c) async {
    try {
      await for (final e in Directory(c.dir).list(followLinks: false)) {
        final name = p.basename(e.path);
        if (name.startsWith('.')) continue;
        if (e is Directory) {
          final child =
              CategoryNode(c.path.isEmpty ? name : '${c.path}/$name', e.path);
          await _scanCategory(child);
          c.children.add(child);
        } else if (e is File) {
          final f = await _docFile(e, c.path);
          if (f != null) c.files.add(f);
        }
      }
    } on FileSystemException {
      // Okunamayan klasörü boş say.
    }
    c.children.sort((a, b) => naturalCompare(a.name, b.name));
  }

  Future<DocFile?> _docFile(File f, String? category) async {
    try {
      final st = await f.stat();
      return DocFile(
        path: f.path,
        size: st.size,
        modified: st.modified,
        category: category,
      );
    } on FileSystemException {
      return null;
    }
  }

  Future<List<DocFile>> _scanInbox() async {
    final out = <DocFile>[];
    final seen = <String>{};
    for (final d in inboxDirs) {
      await _scanInboxDir(Directory(d), 0, out, seen);
    }
    return out;
  }

  Future<void> _scanInboxDir(
    Directory d,
    int depth,
    List<DocFile> out,
    Set<String> seen,
  ) async {
    if (p.equals(d.path, root) || !await d.exists()) return;
    try {
      await for (final e in d.list(followLinks: false)) {
        final name = p.basename(e.path);
        if (name.startsWith('.')) continue;
        if (e is Directory) {
          if (depth < 2 && !_skipInboxDirs.contains(name)) {
            await _scanInboxDir(e, depth + 1, out, seen);
          }
        } else if (e is File) {
          // Gelen Kutusu yalnızca belge türlerini gösterir; indirilen
          // video, .apk, yarım kalmış indirme vb. kalabalık yapmasın.
          if (FileKind.of(name) == FileKind.other) continue;
          if (!seen.add(p.canonicalize(e.path))) continue;
          final f = await _docFile(e, null);
          if (f != null) out.add(f);
        }
      }
    } on FileSystemException {
      // Erişilemeyen klasörü atla.
    }
  }

  // ------------------------------------------------------------ kategoriler

  Future<String> createCategory(String parent, String name) async {
    final n = _checkedName(name);
    final dir = p.join(dirOf(parent), n);
    if (_exists(dir)) {
      throw LibraryException('"$n" adında bir kategori zaten var');
    }
    await Directory(dir).create(recursive: true);
    return parent.isEmpty ? n : '$parent/$n';
  }

  Future<String> renameCategory(String path, String newName) async {
    if (path.isEmpty) {
      throw const LibraryException('Ana klasör yeniden adlandırılamaz');
    }
    final n = _checkedName(newName);
    final from = dirOf(path);
    final oldName = p.basename(from);
    final parent = parentOf(path);
    final result = parent.isEmpty ? n : '$parent/$n';
    if (oldName == n) return path;
    final to = p.join(p.dirname(from), n);
    final caseOnly = oldName.toLowerCase() == n.toLowerCase();
    if (!caseOnly && _exists(to)) {
      throw LibraryException('"$n" adında bir kategori zaten var');
    }
    if (caseOnly) {
      // Büyük/küçük harf duyarsız dosya sistemlerinde ara adla iki adımda.
      final tmp = await Directory(from).rename('$from.__ad');
      await tmp.rename(to);
    } else {
      await Directory(from).rename(to);
    }
    return result;
  }

  /// Kategoriyi başka bir kategorinin içine (ya da en üste) taşır.
  Future<String> moveCategory(String path, String newParent) async {
    if (path.isEmpty) throw const LibraryException('Ana klasör taşınamaz');
    if (newParent == path || newParent.startsWith('$path/')) {
      throw const LibraryException('Kategori kendi içine taşınamaz');
    }
    if (parentOf(path) == newParent) return path;
    final from = dirOf(path);
    final name = p.basename(from);
    final to = p.join(dirOf(newParent), name);
    if (_exists(to)) {
      throw LibraryException('Orada zaten "$name" adında bir kategori var');
    }
    await Directory(from).rename(to);
    return newParent.isEmpty ? name : '$newParent/$name';
  }

  /// Kategoriyi siler; içindeki dosya ve alt kategoriler bir üst kategoriye
  /// taşınır, böylece hiçbir dosya kaybolmaz. Geri almak için taşımaları
  /// döndürür.
  Future<List<Moved>> deleteCategory(String path) async {
    if (path.isEmpty) throw const LibraryException('Ana klasör silinemez');
    final dir = dirOf(path);
    final parentDir = p.dirname(dir);
    final moved = <Moved>[];
    final entries = await Directory(dir).list(followLinks: false).toList();
    for (final e in entries) {
      final name = p.basename(e.path);
      if (name.startsWith('.')) continue;
      final to = _uniquePath(parentDir, name, isDir: e is Directory);
      await e.rename(to);
      moved.add(Moved(e.path, to));
    }
    await Directory(dir).delete(recursive: true);
    return moved;
  }

  // --------------------------------------------------------------- dosyalar

  Future<BatchResult> moveFiles(Iterable<String> paths, String category) async {
    final dir = dirOf(category);
    await Directory(dir).create(recursive: true);
    final moved = <Moved>[];
    final failed = <String>[];
    for (final from in paths) {
      if (p.equals(p.dirname(from), dir)) continue;
      try {
        final to = _uniquePath(dir, p.basename(from));
        await _moveFile(from, to);
        moved.add(Moved(from, to));
      } on FileSystemException {
        failed.add(from);
      }
    }
    return BatchResult(moved, failed);
  }

  /// [newName] uzantıyla birlikte tam addır.
  Future<String> renameFile(String path, String newName) async {
    final n = _checkedName(newName);
    final oldName = p.basename(path);
    if (oldName == n) return path;
    final to = p.join(p.dirname(path), n);
    final caseOnly = oldName.toLowerCase() == n.toLowerCase();
    if (!caseOnly && _exists(to)) {
      throw LibraryException('Burada "$n" adında bir dosya zaten var');
    }
    if (caseOnly) {
      final tmp = await File(path).rename('$path.__ad');
      await tmp.rename(to);
    } else {
      await File(path).rename(to);
    }
    return to;
  }

  /// Taşımaları tersine çevirir (en son yapılandan başlayarak).
  Future<BatchResult> undo(List<Moved> moves) async {
    final back = <Moved>[];
    final failed = <String>[];
    Map<String, dynamic>? index;
    for (final m in moves.reversed) {
      try {
        final isDir = FileSystemEntity.isDirectorySync(m.to);
        final to =
            _uniquePath(p.dirname(m.from), p.basename(m.from), isDir: isDir);
        if (isDir) {
          await Directory(p.dirname(to)).create(recursive: true);
          await Directory(m.to).rename(to);
        } else {
          await _moveFile(m.to, to);
        }
        back.add(Moved(m.to, to));
        if (p.isWithin(trashDir, m.to)) {
          index ??= await _readIndex();
          index.remove(p.basename(m.to));
        }
      } on FileSystemException {
        failed.add(m.to);
      }
    }
    if (index != null) await _writeIndex(index);
    return BatchResult(back, failed);
  }

  Future<void> _moveFile(String from, String to) async {
    await Directory(p.dirname(to)).create(recursive: true);
    try {
      await File(from).rename(to);
    } on FileSystemException {
      // Farklı depolama birimleri (ör. SD kart) arasında rename çalışmaz.
      if (!File(from).existsSync()) rethrow;
      await File(from).copy(to);
      await File(from).delete();
    }
  }

  // ------------------------------------------------------------ çöp kutusu

  Future<BatchResult> trashFiles(Iterable<String> paths) async {
    await Directory(trashDir).create(recursive: true);
    final index = await _readIndex();
    final now = DateTime.now().toIso8601String();
    final moved = <Moved>[];
    final failed = <String>[];
    for (final from in paths) {
      try {
        final to = _uniquePath(trashDir, p.basename(from));
        await _moveFile(from, to);
        index[p.basename(to)] = {'from': from, 'at': now};
        moved.add(Moved(from, to));
      } on FileSystemException {
        failed.add(from);
      }
    }
    await _writeIndex(index);
    return BatchResult(moved, failed);
  }

  /// Çöpteki dosyaları eski yerlerine geri koyar.
  Future<BatchResult> restore(Iterable<TrashItem> items) =>
      undo([for (final t in items) Moved(t.originalPath, t.path)]);

  Future<void> deleteForever(Iterable<TrashItem> items) async {
    final index = await _readIndex();
    for (final t in items) {
      try {
        await File(t.path).delete();
      } on FileSystemException {
        // Zaten yoksa sorun değil.
      }
      index.remove(p.basename(t.path));
    }
    await _writeIndex(index);
  }

  Future<void> emptyTrash() async {
    final dir = Directory(trashDir);
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  /// Çöpü listeler; [trashDays] günden eski dosyaları kalıcı olarak siler.
  Future<List<TrashItem>> _loadTrash() async {
    final dir = Directory(trashDir);
    if (!await dir.exists()) return [];
    final index = await _readIndex();
    final items = <TrashItem>[];
    final now = DateTime.now();
    var changed = false;
    await for (final e in dir.list(followLinks: false)) {
      final name = p.basename(e.path);
      if (e is! File || name.startsWith('.')) continue;
      final meta = index[name];
      final st = await e.stat();
      final at =
          (meta is Map ? DateTime.tryParse('${meta['at']}') : null) ??
              st.modified;
      final from = meta is Map && meta['from'] is String
          ? meta['from'] as String
          : p.join(root, name);
      if (now.difference(at).inDays >= trashDays) {
        await e.delete();
        index.remove(name);
        changed = true;
        continue;
      }
      items.add(TrashItem(
        path: e.path,
        originalPath: from,
        deletedAt: at,
        size: st.size,
      ));
    }
    final before = index.length;
    index.removeWhere((k, _) => !File(p.join(trashDir, k)).existsSync());
    if (changed || index.length != before) await _writeIndex(index);
    items.sort((a, b) => b.deletedAt.compareTo(a.deletedAt));
    return items;
  }

  Future<Map<String, dynamic>> _readIndex() async {
    final f = File(p.join(trashDir, _indexName));
    try {
      final data = jsonDecode(await f.readAsString());
      if (data is Map<String, dynamic>) return data;
    } on FileSystemException {
      // İlk kullanım.
    } on FormatException {
      // Bozuk dizin dosyası: sıfırdan başla, dosyalar yine listelenir.
    }
    return {};
  }

  Future<void> _writeIndex(Map<String, dynamic> index) async {
    await Directory(trashDir).create(recursive: true);
    await File(p.join(trashDir, _indexName)).writeAsString(jsonEncode(index));
  }

  // ------------------------------------------------------------ yardımcılar

  String _checkedName(String name) {
    final err = validateName(name);
    if (err != null) throw LibraryException(err);
    return name.trim();
  }

  bool _exists(String path) =>
      FileSystemEntity.typeSync(path, followLinks: false) !=
      FileSystemEntityType.notFound;

  /// [dir] içinde çakışmayan bir yol: "Ders.pdf" varsa "Ders (2).pdf".
  String _uniquePath(String dir, String name, {bool isDir = false}) {
    var candidate = p.join(dir, name);
    if (!_exists(candidate)) return candidate;
    final ext = isDir ? '' : p.extension(name);
    final base = (isDir ? name : p.basenameWithoutExtension(name))
        .replaceFirst(RegExp(r' \(\d+\)$'), '');
    for (var i = 2;; i++) {
      candidate = p.join(dir, '$base ($i)$ext');
      if (!_exists(candidate)) return candidate;
    }
  }
}
