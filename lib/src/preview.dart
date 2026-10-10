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

// XML taraması bilerek düzenli ifadeyle DEĞİL, indexOf ile yapılır. Neden:
// `<w:p[ >].*?</w:p>` gibi tembel desenler, kapanmayan açılış etiketleriyle
// dolu bir girdide her başlangıçtan sona kadar tarar (karesel). 600 KB'lık ve
// sıkıştırılmış hâli birkaç KB olan kötü niyetli bir belge, önizleme işçisini
// dakikalarca meşgul eder; üç tanesi bütün önizlemeleri durdurur. Aşağıdaki
// tarayıcılar her baytı en fazla birkaç kez okur: süre girdiyle doğrusal kalır.

/// [text] içinde [pattern]'i arar; bulunan yeri hatırlar ki aynı desen her
/// seferinde sona kadar yeniden taranmasın. [from] çağrıları hiç geriye
/// gitmeyen başlangıçlarla yapılmalı.
class _Finder {
  _Finder(this.text, this.pattern);

  final String text;
  final String pattern;
  var _at = -2; // -2: henüz aranmadı, -1: metinde artık yok

  int from(int start) {
    if (_at == -1 || _at >= start) return _at;
    return _at = text.indexOf(pattern, start);
  }
}

bool _endsName(String s, int i) {
  if (i >= s.length) return false;
  final c = s.codeUnitAt(i);
  // boşluk, sekme, satır sonu, '>' ya da '/'
  return c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D || c == 0x3E || c == 0x2F;
}

/// [opens]'tan biriyle başlayan her öğenin (ör. `<w:t` + boşluk ya da `>`)
/// açılış etiketinden sonraki ve [closes]'tan ilkine kadarki iç metni ile
/// öğenin tamamı. Kendi kendini kapatan `<x/>` öğeleri atlanır.
Iterable<({String inner, String whole})> _elements(
  String xml,
  List<String> opens,
  List<String> closes,
) sync* {
  final o = [for (final s in opens) _Finder(xml, s)];
  final c = [for (final s in closes) _Finder(xml, s)];
  final gt = _Finder(xml, '>');
  var pos = 0;
  while (true) {
    var s = -1;
    var sLen = 0;
    for (var i = 0; i < o.length; i++) {
      var at = o[i].from(pos);
      // `<w:tab/>` gibi aynı önekle başlayan başka adları atla.
      while (at >= 0) {
        final k = at + opens[i].length;
        if (_endsName(xml, k) && xml.codeUnitAt(k) != 0x2F) break;
        at = o[i].from(at + 1);
      }
      if (at >= 0 && (s < 0 || at < s)) {
        s = at;
        sLen = opens[i].length;
      }
    }
    if (s < 0) return;
    final g = gt.from(s + sLen);
    if (g < 0) return;
    var e = -1;
    var eLen = 0;
    for (var i = 0; i < c.length; i++) {
      final at = c[i].from(g + 1);
      if (at >= 0 && (e < 0 || at < e)) {
        e = at;
        eLen = closes[i].length;
      }
    }
    if (e < 0) return; // kapanış yok: sonraki hiçbir öğe de kapanamaz
    yield (inner: xml.substring(g + 1, e), whole: xml.substring(s, e + eLen));
    pos = e + eLen;
  }
}

/// `<...>` etiketlerini atar (`<[^>]+>` ile aynı sonuç, doğrusal zamanda).
String _stripTags(String s) {
  final out = StringBuffer();
  var i = 0;
  while (i < s.length) {
    final lt = s.indexOf('<', i);
    if (lt < 0) {
      out.write(s.substring(i));
      break;
    }
    out.write(s.substring(i, lt));
    if (lt + 1 < s.length && s.codeUnitAt(lt + 1) == 0x3E) {
      out.write('<'); // "<>" etiket değil
      i = lt + 1;
      continue;
    }
    final gt = s.indexOf('>', lt + 1);
    if (gt < 0) {
      out.write(s.substring(lt)); // kapanmayan '<': sonrasında etiket yok
      break;
    }
    i = gt + 1;
  }
  return out.toString();
}

/// Bir XML biçemi: paragraf öğeleri ve içlerindeki metin parçaları.
typedef _Shape = ({
  List<String> pOpen,
  List<String> pClose,
  List<String> rOpen,
  List<String> rClose,
});

const _Shape _word = (
  pOpen: ['<w:p'],
  pClose: ['</w:p>'],
  rOpen: ['<w:t'],
  rClose: ['</w:t>'],
);
const _Shape _slide = (
  pOpen: ['<a:p'],
  pClose: ['</a:p>'],
  rOpen: ['<a:t'],
  rClose: ['</a:t>'],
);
const _Shape _sharedStrings = (
  pOpen: ['<si'],
  pClose: ['</si>'],
  rOpen: ['<t'],
  rClose: ['</t>'],
);
const _Shape _odf = (
  pOpen: ['<text:p', '<text:h'],
  pClose: ['</text:p>', '</text:h>'],
  rOpen: [],
  rClose: [],
);

/// XML'den paragraf paragraf metin toplar: her paragrafın içindeki metin
/// parçaları birleştirilir ([stripTags] ise etiketler atılıp kalanı alınır).
String _paragraphs(
  String xml,
  _Shape shape, {
  bool stripTags = false,
  int? maxChars,
  required bool long,
}) {
  final out = <String>[];
  var total = 0;
  final limit = maxChars ?? (long ? 1600 : 360);
  for (final p in _elements(xml, shape.pOpen, shape.pClose)) {
    final text = stripTags
        ? unescapeXml(_stripTags(p.whole))
        : _elements(
            p.whole,
            shape.rOpen,
            shape.rClose,
          ).map((r) => unescapeXml(r.inner)).join();
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

/// [xml]'deki her `<name ...>` açılış etiketinin tamamı (doğrusal zaman).
Iterable<String> _tags(String xml, String name) sync* {
  final open = '<$name';
  var pos = 0;
  while (true) {
    final s = xml.indexOf(open, pos);
    if (s < 0) return;
    final k = s + open.length;
    if (!_endsName(xml, k)) {
      pos = k; // `<p:sldIdLst` gibi daha uzun bir ad
      continue;
    }
    final g = xml.indexOf('>', k);
    if (g < 0) return;
    yield xml.substring(s, g + 1);
    pos = g + 1;
  }
}

/// Etiketteki `name="..."` özniteliğinin değeri (adın önünde boşluk olmalı).
String? _attr(String tag, String name) {
  final key = '$name="';
  var i = tag.indexOf(key);
  while (i > 0 && !_endsName(tag, i - 1)) {
    i = tag.indexOf(key, i + 1);
  }
  if (i <= 0) return null;
  final start = i + key.length;
  final end = tag.indexOf('"', start);
  return end < 0 ? null : tag.substring(start, end);
}

/// Sunumdaki ilk slaytların (sunum sırasıyla) dosya yolları.
List<String> _slidePaths(Archive a) {
  final pres = _readText(a, 'ppt/presentation.xml');
  final rels = _readText(a, 'ppt/_rels/presentation.xml.rels');
  final paths = <String>[];
  if (pres != null && rels != null) {
    // İlişkiler bir kez tabloya dökülür; her slayt için yeniden taranmaz.
    final targets = <String, String>{};
    for (final tag in _tags(rels, 'Relationship')) {
      final id = _attr(tag, 'Id');
      final target = _attr(tag, 'Target');
      if (id != null && target != null) targets.putIfAbsent(id, () => target);
    }
    for (final tag in _tags(pres, 'p:sldId')) {
      final rid = _attr(tag, 'r:id');
      final target = rid == null ? null : targets[rid];
      if (target == null) continue;
      paths.add(target.startsWith('/') ? target.substring(1) : 'ppt/$target');
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
    final t = _paragraphs(xml, _slide, long: long);
    if (t.isNotEmpty) return t;
  }
  return null;
}

String? _docxText(Archive a, {required bool long}) {
  final xml = _readText(a, 'word/document.xml');
  if (xml == null) return null;
  final t = _paragraphs(xml, _word, long: long);
  return t.isEmpty ? null : t;
}

String? _xlsxText(Archive a, {required bool long}) {
  final xml = _readText(a, 'xl/sharedStrings.xml');
  if (xml == null) return null;
  // Tabloda karakter değil yalnızca satır sınırı vardır (her hücre kısa).
  final t = _paragraphs(xml, _sharedStrings, maxChars: 1 << 30, long: long);
  return t.isEmpty ? null : t;
}

String? _odfText(Archive a, {required bool long}) {
  final xml = _readText(a, 'content.xml');
  if (xml == null) return null;
  final t = _paragraphs(xml, _odf, stripTags: true, long: long);
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

/// Zip dizininin üst sınırları. Gerçek Office/ODF belgeleri bunların çok
/// altında kalır (yüzlerce girdi, girdi başına onlarca baytlık ad).
const _maxZipEntries = 10000;
const _maxCentralDirBytes = 4 * 1024 * 1024;
const _maxLocalNameExtraBytes = 2 * 1024 * 1024;

int _u16(Uint8List b, int o) => b[o] | (b[o + 1] << 8);
int _u32(Uint8List b, int o) => _u16(b, o) | (_u16(b, o + 2) << 16);

Uint8List _readAt(RandomAccessFile f, int pos, int n) {
  f.setPositionSync(pos);
  final b = f.readSync(n);
  if (b.length != n) throw const FormatException('kısa okuma');
  return b;
}

/// `archive` paketine vermeden önce zip'in dizinini kendimiz, sınırlı bellekle
/// okuyup makul olup olmadığına bakar.
///
/// Neden: [readBoundedEntry] girdi İÇERİĞİNİ sınırlar ama `ZipDecoder` ondan
/// önce dizini ayrıştırır. archive 4.3.0 merkezi dizindeki HER kayıt için o
/// kaydın gösterdiği yerel başlığın adını (64 KB'a kadar) ve ek alanını (64
/// KB'a kadar) kopyalayıp tutar; kayıt sayısına sınır koymaz ve binlerce
/// kaydın aynı dev başlığı göstermesine izin verir. 46 baytlık her kayıt
/// ~128 KB bellek tutar: ~1 MB'lık bir `.docx` gigabaytlar ister. Gelen
/// Kutusu belgeleri kendiliğinden önizlendiği için bu, dosya kalana kadar
/// her açılışta bellek taşması olurdu.
///
/// Burada archive'ın okuyacağı dizin (sondan geriye ilk EOCD imzası) aynı
/// biçimde bulunur; kayıt sayısı, dizin boyutu ve yerel başlıklardaki ad + ek
/// alan toplamı tavanları aşarsa false döner. Zip64 belgeler önizlenmez.
bool zipDirectoryIsBounded(String path) {
  RandomAccessFile? f;
  try {
    f = File(path).openSync();
    return _checkZipDirectory(f);
  } on Object {
    return false;
  } finally {
    f?.closeSync();
  }
}

bool _checkZipDirectory(RandomAccessFile f) {
  final len = f.lengthSync();
  if (len < 22) return false;
  // Yorum en çok 65535 bayt: geçerli zip'te EOCD son 22+65535 bayttadır.
  final tailLen = math.min(len, 22 + 0xFFFF);
  final tail = _readAt(f, len - tailLen, tailLen);
  var e = -1;
  for (var i = tailLen - 22; i >= 0; i--) {
    if (tail[i] == 0x50 &&
        tail[i + 1] == 0x4B &&
        tail[i + 2] == 0x05 &&
        tail[i + 3] == 0x06) {
      e = i;
      break;
    }
  }
  if (e < 0) return false;
  final eocd = len - tailLen + e;
  if (eocd >= 20 && _u32(_readAt(f, eocd - 20, 4), 0) == 0x07064b50) {
    return false; // Zip64: archive dizini başka yerden okur
  }
  final cdSize = _u32(tail, e + 12);
  final cdOffset = _u32(tail, e + 16);
  if (cdSize > _maxCentralDirBytes || cdOffset + cdSize > eocd) return false;
  final cd = _readAt(f, cdOffset, cdSize);
  var p = 0;
  var entries = 0;
  var localBytes = 0;
  while (p + 4 <= cd.length && _u32(cd, p) == 0x02014b50) {
    if (p + 46 > cd.length || ++entries > _maxZipEntries) return false;
    // Unix'te yazılmış sembolik bağlantı girdisini archive, ayrıştırırken
    // sınırsız açar (readBytes): Office/ODF belgesinde bulunmaz, reddedilir.
    if (_u16(cd, p + 4) >> 8 == 3 &&
        (_u32(cd, p + 38) >> 16) & 0xF000 == 0xA000) {
      return false;
    }
    final local = _u32(cd, p + 42);
    p += 46 + _u16(cd, p + 28) + _u16(cd, p + 30) + _u16(cd, p + 32);
    if (p > cd.length || local == 0xFFFFFFFF || local + 30 > len) return false;
    final h = _readAt(f, local, 30);
    if (_u32(h, 0) != 0x04034b50) return false;
    localBytes += _u16(h, 26) + _u16(h, 28);
    if (localBytes > _maxLocalNameExtraBytes) return false;
  }
  // 1-3 baytlık artıkta archive imzayı dizin sınırının ötesinden okur ve
  // denetlenmemiş bir kayıt daha üretir.
  final rest = cd.length - p;
  return rest == 0 || rest >= 4;
}

/// Dosyadan okuyarak [archivePreview] üretir (bozuk dosyada null). Ayrı iş
/// parçacığında çalışacak şekilde üst düzey bir işlevdir.
Preview? zipDocumentPreview(String path, String ext, {bool long = false}) {
  if (!zipDirectoryIsBounded(path)) return null;
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
