/// Dosya önizlemeleri: bir küçük resim ya da kısa bir metin. Arayüzden bağımsız;
/// platforma özgü kısım (PDF/resim çizimi) [PreviewSource] arkasındadır.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive_io.dart';

import 'file_kind.dart';
import 'library.dart';
import 'platform_bridge.dart' show nativePreview;

/// Küçük kartlar bu genişlikte (piksel) üretilir; "Önizle" penceresi büyüğünü ister.
const cardPreviewPx = 420;
const rowPreviewPx = 200;
const largePreviewPx = 1100;

/// [px] bu değerden büyükse metin önizlemesi uzun üretilir.
const _longTextFromPx = 800;

class Preview {
  const Preview.image(Uint8List this.bytes) : text = null;
  const Preview.text(String this.text) : bytes = null;

  final Uint8List? bytes;
  final String? text;

  bool get isImage => bytes != null;
}

abstract class PreviewSource {
  /// [px]: istenen en geniş kenar (piksel). Önizleme çıkarılamıyorsa null.
  Future<Preview?> load(String path, {required int px});
}

/// Hiç önizleme üretmez (testler ve önizlemesiz kullanım için).
class NoPreviewSource implements PreviewSource {
  const NoPreviewSource();

  @override
  Future<Preview?> load(String path, {required int px}) async => null;
}

const _textExts = {'txt', 'md', 'csv'};
const _zipExts = {
  'pptx', 'ppsx', 'pptm', 'docx', 'xlsx', //
  'odp', 'odt', 'ods',
};
const _imageExts = {'jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp', 'heic'};

class PlatformPreviewSource implements PreviewSource {
  const PlatformPreviewSource();

  @override
  Future<Preview?> load(String path, {required int px}) async {
    final ext = extensionOf(path);
    final long = px >= _longTextFromPx;
    try {
      if (_textExts.contains(ext)) {
        final t = await textHead(path, long: long);
        return t == null ? null : Preview.text(t);
      }
      if (_zipExts.contains(ext)) {
        // Zip açma işlemciyi tutmasın diye ayrı iş parçacığında.
        return await Isolate.run(
          () => zipDocumentPreview(path, ext, long: long),
        );
      }
      if (ext == 'pdf' || _imageExts.contains(ext)) {
        final bytes = await nativePreview(path, px);
        if (bytes != null) return Preview.image(bytes);
        // Android dışında (geliştirme) resimler doğrudan okunur; PDF çizilemez.
        if (ext != 'pdf' && !Platform.isAndroid) {
          final f = File(path);
          if (await f.length() <= 8 * 1024 * 1024) {
            return Preview.image(await f.readAsBytes());
          }
        }
      }
    } on Object {
      // Bozuk/okunamayan dosya: önizleme yok, tür simgesi gösterilir.
    }
    return null;
  }
}

// ----------------------------------------------------------- metin çıkarımı

String _clip(String s, {required bool long}) {
  final maxChars = long ? 1600 : 360;
  final maxLines = long ? 40 : 10;
  final lines = s
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .take(maxLines)
      .toList();
  var out = lines.join('\n');
  if (out.length > maxChars) out = '${out.substring(0, maxChars).trimRight()}…';
  return out;
}

/// Metin dosyasının ilk satırları; boşsa null.
Future<String?> textHead(String path, {bool long = false}) async {
  final f = await File(path).open();
  try {
    final bytes = await f.read(long ? 8192 : 3072);
    var s = utf8.decode(bytes, allowMalformed: true);
    if (s.startsWith('﻿')) s = s.substring(1);
    final out = _clip(s, long: long);
    return out.isEmpty ? null : out;
  } finally {
    await f.close();
  }
}

final _entity = RegExp(r'&(#x[0-9a-fA-F]+|#[0-9]+|amp|lt|gt|quot|apos);');

String unescapeXml(String s) => s.replaceAllMapped(_entity, (m) {
  final e = m[1]!;
  switch (e) {
    case 'amp':
      return '&';
    case 'lt':
      return '<';
    case 'gt':
      return '>';
    case 'quot':
      return '"';
    case 'apos':
      return "'";
  }
  try {
    final code = e.startsWith('#x')
        ? int.parse(e.substring(2), radix: 16)
        : int.parse(e.substring(1));
    return String.fromCharCode(code);
  } on Object {
    return '';
  }
});

final _tag = RegExp(r'<[^>]+>');

/// XML'den paragraf paragraf metin toplar: her [paragraph] eşleşmesinin
/// içindeki [run] eşleşmeleri birleştirilir.
String _paragraphs(
  String xml, {
  required RegExp paragraph,
  required RegExp run,
  bool stripTags = false,
  required bool long,
}) {
  final out = <String>[];
  var total = 0;
  final limit = long ? 1600 : 360;
  for (final p in paragraph.allMatches(xml)) {
    final body = p[0]!;
    final text = stripTags
        ? unescapeXml(body.replaceAll(_tag, ''))
        : run.allMatches(body).map((m) => unescapeXml(m[1]!)).join();
    final t = text.trim();
    if (t.isEmpty) continue;
    out.add(t);
    total += t.length;
    if (total >= limit || out.length >= (long ? 40 : 10)) break;
  }
  return out.join('\n');
}

String? _readText(Archive a, String name) {
  final f = a.findFile(name);
  if (f == null || !f.isFile) return null;
  // Çok büyük XML'in yalnızca başına bakmak yeter; zaten o kadarı açılıyor.
  final b = readBoundedEntry(f, _xmlHeadBytes, truncate: true);
  if (b == null) return null;
  return utf8.decode(b, allowMalformed: true);
}

/// XML'den okunan baş kısım; sonrasına bakılmaz.
const _xmlHeadBytes = 600 * 1024;

/// Gömülü küçük resmin açılmış boyut tavanı.
const _thumbMaxBytes = 3 * 1024 * 1024;

/// Zip girdisinin açılmış baytlarından en çok [max] tanesini okur; girdiyi
/// ASLA tamamen belleğe açmaz. Testlerde doğrudan sınanır.
///
/// Neden: `ArchiveFile.content` girdinin tamamını açar ve `size` yalnızca zip
/// başlığındaki iddiadır; paket VM'de açılımı başlığa bakmadan yapıyor. Sıkıştırılmış
/// birkaç KB'lık kötü niyetli (ya da bozuk) bir `.docx`/`.pptx` gigabaytlarca bellek
/// ister ve uygulamayı çökertir. Gelen Kutusu WhatsApp ve İndirilenler'deki her
/// belgeyi açılışta kendiliğinden önizlediği için bu, dosya silinene kadar her
/// açılışta çökme demek olurdu. Burada `dart:io`nun parçalı zlib çözücüsü küçük
/// parçalarla beslenir ve [max] bayt dolunca DURULUR: bellek ve süre, başlıkta ne
/// yazarsa yazsın sınırlı kalır.
///
/// [truncate] doğruysa [max]'tan uzun girdinin ilk [max] baytı döner (metin
/// önizlemesi başı yeter); yanlışsa tamamı gerekir ve [max]'ı aşan girdide null
/// döner (gömülü resim yarım olamaz). Deflate ve depolanmış (sıkıştırmasız)
/// girdiler desteklenir; bzip2 gibi diğerleri null döner (Office/ODF belgeleri
/// bunları yazmaz, bzip2 ise açılım oranı sınırsız bir bomba yüzeyi).
Uint8List? readBoundedEntry(ArchiveFile f, int max, {required bool truncate}) {
  final raw = f.rawContent;
  if (raw == null) {
    // Bellekte kurulmuş girdi (testler): içerik zaten açık, ek bellek yok.
    final b = f.content;
    if (b.length <= max) return b;
    return truncate ? Uint8List.sublistView(b, 0, max) : null;
  }

  final stream = raw.getStream(decompress: false);
  final savePos = stream.position;
  try {
    final head = _HeadSink(max);
    switch (f.compression) {
      case CompressionType.deflate:
        final conv = ZLibCodec(raw: true).decoder.startChunkedConversion(head);
        while (!stream.isEOS && !head.overflowed) {
          // 1 KB sıkıştırılmış veri en fazla ~1 MB açılır: tek adımda sınır
          // belirgin biçimde aşılamaz.
          conv.add(
            stream.readBytes(math.min(1024, stream.length)).toUint8List(),
          );
        }
        try {
          conv.close(); // yerel zlib kaynağını bırak (kesik akışta hata verebilir)
        } on Object {
          // Yeterince okundu ya da akış yarım: önemli değil.
        }
      case CompressionType.none:
        final n = math.min(stream.length, max + 1);
        head.add(stream.readBytes(n).toUint8List());
      default:
        return null;
    }
    if (head.overflowed && !truncate) return null;
    return head.bytes(max);
  } finally {
    stream.setPosition(savePos);
  }
}

/// [max] bayta kadar toplar, bir bayt fazlasını tutup taşmayı bildirir.
class _HeadSink implements Sink<List<int>> {
  _HeadSink(this.max);

  final int max;
  final _buf = BytesBuilder(copy: false);

  bool get overflowed => _buf.length > max;

  @override
  void add(List<int> chunk) {
    final room = max + 1 - _buf.length;
    if (room <= 0) return;
    _buf.add(chunk.length <= room ? chunk : chunk.sublist(0, room));
  }

  Uint8List bytes(int limit) {
    final all = _buf.toBytes();
    return all.length <= limit ? all : Uint8List.sublistView(all, 0, limit);
  }

  @override
  void close() {}
}

final _wP = RegExp(r'<w:p[ >].*?</w:p>', dotAll: true);
final _wT = RegExp(r'<w:t(?: [^>]*)?>(.*?)</w:t>', dotAll: true);
final _aP = RegExp(r'<a:p[ >].*?</a:p>', dotAll: true);
final _aT = RegExp(r'<a:t(?: [^>]*)?>(.*?)</a:t>', dotAll: true);
final _odfP = RegExp(r'<text:(?:p|h)[ >].*?</text:(?:p|h)>', dotAll: true);
final _si = RegExp(r'<si>.*?</si>', dotAll: true);
final _t = RegExp(r'<t(?: [^>]*)?>(.*?)</t>', dotAll: true);

/// Sunumdaki ilk slaytların (sunum sırasıyla) dosya yolları.
List<String> _slidePaths(Archive a) {
  final pres = _readText(a, 'ppt/presentation.xml');
  final rels = _readText(a, 'ppt/_rels/presentation.xml.rels');
  final paths = <String>[];
  if (pres != null && rels != null) {
    for (final m in RegExp(
      r'<p:sldId\b[^>]*\br:id="([^"]+)"',
    ).allMatches(pres)) {
      final rid = m[1]!;
      for (final r in RegExp(r'<Relationship\b[^>]*>').allMatches(rels)) {
        final tag = r[0]!;
        if (!RegExp('\\bId="${RegExp.escape(rid)}"').hasMatch(tag)) continue;
        final target = RegExp(r'\bTarget="([^"]+)"').firstMatch(tag)?[1];
        if (target != null) {
          paths.add(
            target.startsWith('/') ? target.substring(1) : 'ppt/$target',
          );
        }
        break;
      }
      if (paths.length >= 3) break;
    }
  }
  if (paths.isEmpty) {
    final fallback =
        a.files
            .map((f) => f.name)
            .where((n) => RegExp(r'^ppt/slides/slide\d+\.xml$').hasMatch(n))
            .toList()
          ..sort(
            (x, y) =>
                x.length != y.length ? x.length - y.length : x.compareTo(y),
          );
    paths.addAll(fallback.take(3));
  }
  return paths;
}

String? _pptxText(Archive a, {required bool long}) {
  for (final path in _slidePaths(a)) {
    final xml = _readText(a, path);
    if (xml == null) continue;
    final t = _paragraphs(xml, paragraph: _aP, run: _aT, long: long);
    if (t.isNotEmpty) return t;
  }
  return null;
}

String? _docxText(Archive a, {required bool long}) {
  final xml = _readText(a, 'word/document.xml');
  if (xml == null) return null;
  final t = _paragraphs(xml, paragraph: _wP, run: _wT, long: long);
  return t.isEmpty ? null : t;
}

String? _xlsxText(Archive a, {required bool long}) {
  final xml = _readText(a, 'xl/sharedStrings.xml');
  if (xml == null) return null;
  final out = <String>[];
  for (final si in _si.allMatches(xml)) {
    final s = _t
        .allMatches(si[0]!)
        .map((m) => unescapeXml(m[1]!))
        .join()
        .trim();
    if (s.isNotEmpty) out.add(s);
    if (out.length >= (long ? 40 : 10)) break;
  }
  return out.isEmpty ? null : out.join('\n');
}

String? _odfText(Archive a, {required bool long}) {
  final xml = _readText(a, 'content.xml');
  if (xml == null) return null;
  final t = _paragraphs(
    xml,
    paragraph: _odfP,
    run: _t, // kullanılmaz (stripTags)
    stripTags: true,
    long: long,
  );
  return t.isEmpty ? null : t;
}

bool _looksLikeImage(Uint8List b) =>
    b.length > 8 &&
    ((b[0] == 0xFF && b[1] == 0xD8) || // JPEG
        (b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47)); // PNG

const _thumbNames = {
  'docprops/thumbnail.jpeg',
  'docprops/thumbnail.jpg',
  'docprops/thumbnail.png',
  'thumbnails/thumbnail.png', // OpenDocument
};

Uint8List? _embeddedThumbnail(Archive a) {
  for (final f in a.files) {
    if (!f.isFile || !_thumbNames.contains(f.name.toLowerCase())) continue;
    if (f.size > _thumbMaxBytes) continue;
    // Başlıktaki boyuta güvenmeden sınırlı oku; aşarsa resim yok.
    final b = readBoundedEntry(f, _thumbMaxBytes, truncate: false);
    if (b != null && _looksLikeImage(b)) return b;
  }
  return null;
}

/// Açılmış bir zip tabanlı belgeden (OOXML/ODF) önizleme çıkarır: önce dosyanın
/// içindeki gömülü küçük resim, yoksa ilk slayt/sayfanın metni.
Preview? archivePreview(Archive a, String ext, {bool long = false}) {
  final thumb = _embeddedThumbnail(a);
  // Uzun (büyük pencere) istekte de gömülü resim, düşük çözünürlüğüne rağmen
  // gerçek ilk slayt/sayfayı gösterdiği için tercih edilir.
  if (thumb != null) return Preview.image(thumb);
  final text = switch (ext) {
    'pptx' || 'ppsx' || 'pptm' => _pptxText(a, long: long),
    'docx' => _docxText(a, long: long),
    'xlsx' => _xlsxText(a, long: long),
    'odt' || 'odp' || 'ods' => _odfText(a, long: long),
    _ => null,
  };
  return text == null ? null : Preview.text(text);
}

/// Dosyadan okuyarak [archivePreview] üretir (bozuk dosyada null). Ayrı iş
/// parçacığında çalışacak şekilde üst düzey bir işlevdir.
Preview? zipDocumentPreview(String path, String ext, {bool long = false}) {
  InputFileStream? input;
  try {
    input = InputFileStream(path); // dosya yoksa burada da atar
    return archivePreview(ZipDecoder().decodeStream(input), ext, long: long);
  } on Object {
    return null;
  } finally {
    input?.closeSync();
  }
}

// ------------------------------------------------------------------ önbellek

class _Job {
  _Job(this.key, this.path, this.px, this.wanted);

  final String key;
  final String path;
  final int px;

  /// Sıradayken artık gerekmiyorsa (kaydırılıp gidildi) iş atlanır.
  bool Function()? wanted;
  final completer = Completer<Preview?>();
}

/// Önizlemeleri bellekte tutar (en son kullanılan [capacity] tanesi), aynı
/// önizlemeyi iki kez üretmez, aynı anda en fazla [concurrency] iş çalıştırır
/// ve ekranda en son görünen öğeyi önce işler.
class PreviewCache {
  PreviewCache(this.source, {this.capacity = 160, this.concurrency = 3});

  final PreviewSource source;
  final int capacity;
  final int concurrency;

  // Map literali eklenme sırasını korur; en son kullanılan sona taşınır.
  final _done = <String, Preview?>{};
  final _jobs = <String, _Job>{};
  final _queue = Queue<_Job>();
  var _running = 0;

  /// Dosya değişince (tarih/boyut) anahtar da değişir; eski önizleme kullanılmaz.
  static String keyOf(DocFile f, int px) =>
      '${f.path}|${f.modified.millisecondsSinceEpoch}|${f.size}|$px';

  /// Önbellekte varsa `(cached: true, value)`; değer null ise "önizleme yok"
  /// olarak hatırlanmıştır (tekrar denenmez).
  ({bool cached, Preview? value}) lookup(String key) {
    if (!_done.containsKey(key)) return (cached: false, value: null);
    final v = _done.remove(key);
    _done[key] = v; // en son kullanılan sona
    return (cached: true, value: v);
  }

  Future<Preview?> load(
    DocFile f, {
    int px = cardPreviewPx,
    bool Function()? wanted,
  }) {
    final key = keyOf(f, px);
    final hit = lookup(key);
    if (hit.cached) return Future.value(hit.value);
    final running = _jobs[key];
    if (running != null) {
      running.wanted = null; // ikinci bir isteyen var: iş artık atlanamaz
      return running.completer.future;
    }
    final job = _Job(key, f.path, px, wanted);
    _jobs[key] = job;
    _queue.addLast(job);
    _pump();
    return job.completer.future;
  }

  void _pump() {
    while (_running < concurrency && _queue.isNotEmpty) {
      final job = _queue.removeLast(); // en son istenen (ekrandaki) önce
      final stillWanted = job.wanted;
      if (stillWanted != null && !stillWanted()) {
        _jobs.remove(job.key);
        job.completer.complete(null); // önbelleğe yazılmaz
        continue;
      }
      _running++;
      source
          .load(job.path, px: job.px)
          .then<Preview?>((p) => p, onError: (Object _) => null)
          .then((p) {
            _done[job.key] = p;
            while (_done.length > capacity) {
              _done.remove(_done.keys.first);
            }
            job.completer.complete(p);
          })
          .whenComplete(() {
            _jobs.remove(job.key);
            _running--;
            _pump();
          });
    }
  }

  void clear() => _done.clear();
}
