import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:dosya_dolabi/src/library.dart';
import 'package:dosya_dolabi/src/preview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Gerçek bir zip dosyası (OOXML/ODF taklidi) üretir.
Uint8List makeZip(Map<String, Object> files) {
  final a = Archive();
  files.forEach((name, content) {
    final bytes = content is String
        ? utf8.encode(content)
        : content as List<int>;
    a.addFile(ArchiveFile(name, bytes.length, bytes));
  });
  return Uint8List.fromList(ZipEncoder().encode(a));
}

final jpegBytes = Uint8List.fromList([
  0xFF, 0xD8, 0xFF, 0xE0, 0, 0x10, 0x4A, 0x46, 0x49, 0x46, 0, 1, //
  ...List.filled(64, 7),
]);

String slide(List<String> paragraphs) =>
    '<p:sld><p:cSld><p:spTree>${paragraphs.map((t) => '<a:p><a:r><a:t>$t</a:t></a:r></a:p>').join()}</p:spTree></p:cSld></p:sld>';

/// Gerçek bir zip girdisini sarar; içeriği TAMAMEN açan her yol (content,
/// readBytes, getContent) patlar. Önizleme yollarının yalnızca sınırlı okuma
/// kullandığını (çıktı aynı kalsa bile) kanıtlamak için.
class TamAcmaYasak extends ArchiveFile {
  TamAcmaYasak(ArchiveFile f) : super.file(f.name, f.size, f.rawContent!) {
    compression = f.compression;
  }

  @override
  Uint8List get content => throw StateError('girdi tamamen açıldı: $name');

  @override
  Uint8List? readBytes() => throw StateError('girdi tamamen açıldı: $name');

  @override
  InputStream? getContent() => throw StateError('girdi tamamen açıldı: $name');
}

DocFile doc(String path, {int size = 10, int ms = 1}) => DocFile(
  path: path,
  size: size,
  modified: DateTime.fromMillisecondsSinceEpoch(ms),
);

class FakeSource implements PreviewSource {
  final calls = <String>[];
  final pending = <String, Completer<Preview?>>{};
  var running = 0;
  var maxRunning = 0;
  var failWith = false;

  @override
  Future<Preview?> load(String path, {required int px}) {
    calls.add(path);
    running++;
    if (running > maxRunning) maxRunning = running;
    final c = pending[path] = Completer<Preview?>();
    return c.future.whenComplete(() => running--);
  }

  void finish(String path, [Preview? value]) => pending[path]!.complete(value);
  void fail(String path) => pending[path]!.completeError(StateError('bozuk'));
}

Future<void> tick() => Future<void>.delayed(Duration.zero);

void main() {
  group('metin çıkarımı', () {
    test('XML kaçışlarını çözer', () {
      expect(
        unescapeXml('A &amp; B &lt;c&gt; &quot;d&quot; &apos;e&apos;'),
        'A & B <c> "d" \'e\'',
      );
      expect(unescapeXml('&#350;&#x131;k'), 'Şık');
      expect(
        unescapeXml('&#zzz;'),
        '&#zzz;',
      ); // geçersiz kaçış olduğu gibi kalır
    });

    test(
      'pptx: sunum sırasındaki ilk slaytın metni (dosya adı sırası değil)',
      () {
        final zip = makeZip({
          'ppt/presentation.xml': '<p:presentation><p:sldIdLst><p:sldId id="256" r:id="rId9"/><p:sldId id="257" r:id="rId3"/></p:sldIdLst></p:presentation>',
          'ppt/_rels/presentation.xml.rels': '<Relationships><Relationship Id="rId3" Type="x" Target="slides/slide1.xml"/><Relationship Target="slides/slide2.xml" Id="rId9" Type="x"/></Relationships>',
          'ppt/slides/slide1.xml': slide(['Eski ilk slayt']),
          'ppt/slides/slide2.xml': slide(['Fizik 2 &amp; Dinamik', 'Hafta 3']),
        });
        final pr = archivePreview(ZipDecoder().decodeBytes(zip), 'pptx')!;
        expect(pr.text, 'Fizik 2 & Dinamik\nHafta 3');
      },
    );

    test('pptx: ilk slaytta metin yoksa sıradakine bakar', () {
      final zip = makeZip({
        'ppt/presentation.xml': '<p:sldIdLst><p:sldId id="1" r:id="rId1"/><p:sldId id="2" r:id="rId2"/></p:sldIdLst>',
        'ppt/_rels/presentation.xml.rels': '<Relationships><Relationship Id="rId1" Target="slides/slide1.xml"/><Relationship Id="rId2" Target="slides/slide2.xml"/></Relationships>',
        'ppt/slides/slide1.xml': '<p:sld><p:pic/></p:sld>',
        'ppt/slides/slide2.xml': slide(['Gündem']),
      });
      expect(
        archivePreview(ZipDecoder().decodeBytes(zip), 'pptx')!.text,
        'Gündem',
      );
    });

    test('pptx: presentation.xml yoksa slaytları adına göre sıralar', () {
      final zip = makeZip({
        'ppt/slides/slide10.xml': slide(['onuncu']),
        'ppt/slides/slide2.xml': slide(['ikinci']),
      });
      expect(
        archivePreview(ZipDecoder().decodeBytes(zip), 'pptx')!.text,
        'ikinci',
      );
    });

    test('docx: paragrafları ve bölünmüş metin parçalarını birleştirir', () {
      final zip = makeZip({
        'word/document.xml': '<w:document><w:body><w:p><w:r><w:t>Staj </w:t></w:r><w:r><w:t xml:space="preserve">başvuru</w:t></w:r></w:p><w:p></w:p><w:p><w:r><w:t>Sayın yetkili,</w:t></w:r></w:p></w:body></w:document>',
      });
      expect(
        archivePreview(ZipDecoder().decodeBytes(zip), 'docx')!.text,
        'Staj başvuru\nSayın yetkili,',
      );
    });

    test('xlsx: ilk paylaşılan metinler', () {
      final zip = makeZip({
        'xl/sharedStrings.xml': '<sst><si><t>Ad</t></si><si><r><t>So</t></r><r><t>yad</t></r></si><si><t>Not</t></si></sst>',
      });
      expect(
        archivePreview(ZipDecoder().decodeBytes(zip), 'xlsx')!.text,
        'Ad\nSoyad\nNot',
      );
    });

    test('odt: içerik metni (etiketler temizlenir)', () {
      final zip = makeZip({
        'content.xml': '<office:text><text:h>Başlık</text:h><text:p>Ders <text:span>notu</text:span> &amp; özet</text:p></office:text>',
      });
      expect(
        archivePreview(ZipDecoder().decodeBytes(zip), 'odt')!.text,
        'Başlık\nDers notu & özet',
      );
    });

    test('gömülü küçük resim metinden önce gelir (OOXML ve ODF)', () {
      final ooxml = makeZip({
        'docProps/thumbnail.jpeg': jpegBytes,
        'ppt/slides/slide1.xml': slide(['metin']),
      });
      final pr = archivePreview(ZipDecoder().decodeBytes(ooxml), 'pptx')!;
      expect(pr.isImage, isTrue);
      expect(pr.bytes, jpegBytes);

      final odf = makeZip({
        'Thumbnails/thumbnail.png': Uint8List.fromList([
          0x89,
          0x50,
          0x4E,
          0x47,
          1,
          2,
          3,
          4,
          5,
          6,
        ]),
      });
      expect(
        archivePreview(ZipDecoder().decodeBytes(odf), 'odp')!.isImage,
        isTrue,
      );
    });

    test('resim olmayan "küçük resim" yok sayılır, metne düşer', () {
      final zip = makeZip({
        'docProps/thumbnail.jpeg':
            'bu bir resim değil, yeterince uzun bir metin',
        'word/document.xml': '<w:p><w:r><w:t>Gerçek içerik</w:t></w:r></w:p>',
      });
      final pr = archivePreview(ZipDecoder().decodeBytes(zip), 'docx')!;
      expect(pr.isImage, isFalse);
      expect(pr.text, 'Gerçek içerik');
    });

    test('uzun metin kırpılır; uzun istekte daha çok gösterilir', () {
      final text = List.generate(
        30,
        (i) => 'Satır numara ${i + 1} ve biraz uzun açıklama',
      ).join('\n');
      final zip = makeZip({
        'word/document.xml': text
            .split('\n')
            .map((l) => '<w:p><w:r><w:t>$l</w:t></w:r></w:p>')
            .join(),
      });
      final short = archivePreview(
        ZipDecoder().decodeBytes(zip),
        'docx',
      )!.text!;
      final long = archivePreview(
        ZipDecoder().decodeBytes(zip),
        'docx',
        long: true,
      )!.text!;
      expect(short.split('\n').length, lessThanOrEqualTo(10));
      expect(long.length, greaterThan(short.length));
    });

    test('içeriksiz belge için önizleme yok', () {
      expect(
        archivePreview(
          ZipDecoder().decodeBytes(makeZip({'word/document.xml': '<w:p/>'})),
          'docx',
        ),
        isNull,
      );
      expect(
        archivePreview(
          ZipDecoder().decodeBytes(makeZip({'a.txt': 'x'})),
          'xyz',
        ),
        isNull,
      );
    });
  });

  group('dosyadan okuma', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('onizleme_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    String write(String name, List<int> bytes) {
      final f = File(p.join(tmp.path, name))..writeAsBytesSync(bytes);
      return f.path;
    }

    test('zipDocumentPreview gerçek dosyayı okur', () {
      final path = write(
        'a.docx',
        makeZip({
          'word/document.xml': '<w:p><w:r><w:t>Merhaba</w:t></w:r></w:p>',
        }),
      );
      expect(zipDocumentPreview(path, 'docx')!.text, 'Merhaba');
    });

    test('bozuk ya da zip olmayan dosyada null döner, çökmez', () {
      expect(
        zipDocumentPreview(write('b.pptx', utf8.encode('zip değil')), 'pptx'),
        isNull,
      );
      expect(zipDocumentPreview(write('c.docx', []), 'docx'), isNull);
      expect(zipDocumentPreview(p.join(tmp.path, 'yok.pptx'), 'pptx'), isNull);
    });

    test('textHead: BOM ve boş satırları atar, ilk satırları verir', () async {
      final path = write('n.txt', [
        0xEF,
        0xBB,
        0xBF,
        ...utf8.encode('\n\nBaşlık\r\n\r\nİkinci satır\n'),
      ]);
      expect(await textHead(path), 'Başlık\nİkinci satır');
    });

    test('textHead: boş dosyada null; uzun dosyada kırpar', () async {
      expect(await textHead(write('e.txt', [])), isNull);
      expect(await textHead(write('f.txt', utf8.encode('   \n \n'))), isNull);
      final long = (await textHead(write('g.md', utf8.encode('a' * 5000))))!;
      expect(long.length, lessThanOrEqualTo(361));
      expect(long.endsWith('…'), isTrue);
    });

    test('PlatformPreviewSource: metin, zip belge ve tanımsız tür', () async {
      const src = PlatformPreviewSource();
      expect(
        (await src.load(write('x.txt', utf8.encode('selam')), px: 400))!.text,
        'selam',
      );
      expect(
        (await src.load(
          write(
            'y.pptx',
            makeZip({
              'ppt/slides/slide1.xml': slide(['Giriş']),
            }),
          ),
          px: 400,
        ))!.text,
        'Giriş',
      );
      expect(await src.load(write('z.xyz', [1, 2, 3]), px: 400), isNull);
      expect(
        await src.load(write('w.pdf', [1, 2, 3]), px: 400),
        isNull,
      ); // masaüstünde PDF çizilemez
    });
  });

  group('zip girdisi sınırlı okunur (zip bombası)', () {
    const cap = 600 * 1024;
    const bomba = 8 * 1024 * 1024; // sıkıştırılınca birkaç KB, açılınca 8 MiB

    /// "<a:t>merhaba</a:t>" ile başlayan, ardından boşluk dolu bir slayt XML'i.
    List<int> bombaXml() {
      final bas = utf8.encode('<a:p><a:r><a:t>merhaba</a:t></a:r></a:p>');
      return [...bas, ...List.filled(bomba - bas.length, 0x20)];
    }

    /// Zip'teki TÜM girdilerin başlıktaki "açılmış boyut" alanlarını [yalan]
    /// yapar (yerel başlık: ofset 22, merkezi dizin: ofset 24).
    Uint8List basligiYalanlat(Uint8List zip, int yalan) {
      final b = ByteData.sublistView(zip);
      for (var i = 0; i + 30 < zip.length; i++) {
        if (zip[i] != 0x50 || zip[i + 1] != 0x4B) continue;
        if (zip[i + 2] == 3 && zip[i + 3] == 4) {
          b.setUint32(i + 22, yalan, Endian.little);
        } else if (zip[i + 2] == 1 && zip[i + 3] == 2) {
          b.setUint32(i + 24, yalan, Endian.little);
        }
      }
      return zip;
    }

    ArchiveFile girdi(Uint8List zip, String ad) =>
        ZipDecoder().decodeBytes(zip).findFile(ad)!;

    test(
      'sıkıştırılmış dev girdi yalnızca baştan okunur, belleğe tamamen açılmaz',
      () {
        final zip = makeZip({'ppt/slides/slide1.xml': bombaXml()});
        final f = girdi(zip, 'ppt/slides/slide1.xml');
        final b = readBoundedEntry(f, cap, truncate: true)!;
        expect(
          b.length,
          cap,
          reason: '8 MiB açılmamalı, ilk $cap bayt alınmalı',
        );
        expect(utf8.decode(b.sublist(0, 18)), startsWith('<a:p><a:r><a:t>mer'));
        // Tamamı gerekiyorsa (gömülü resim gibi) tavanı aşan girdi reddedilir.
        expect(readBoundedEntry(f, 3 * 1024 * 1024, truncate: false), isNull);
      },
    );

    test(
      'başlığı yalan söyleyen (küçük boyut iddia eden) bomba da sınırlı kalır',
      () {
        final zip = basligiYalanlat(
          makeZip({'ppt/slides/slide1.xml': bombaXml()}),
          100,
        );
        final f = girdi(zip, 'ppt/slides/slide1.xml');
        expect(f.size, 100, reason: 'başlık gerçekten yalanlatılmış olmalı');
        expect(readBoundedEntry(f, cap, truncate: true)!.length, cap);
        expect(readBoundedEntry(f, 3 * 1024 * 1024, truncate: false), isNull);
      },
    );

    test('tavan altındaki girdi aynen döner (sıkıştırılmış ve depolanmış)', () {
      final veri = List<int>.generate(50000, (i) => 65 + i % 26);
      final a = Archive()
        ..addFile(ArchiveFile('sikisik.xml', veri.length, veri))
        ..addFile(ArchiveFile.noCompress('depolanan.xml', veri.length, veri));
      final zip = Uint8List.fromList(ZipEncoder().encode(a));
      final okunan = ZipDecoder().decodeBytes(zip);
      for (final ad in ['sikisik.xml', 'depolanan.xml']) {
        final f = okunan.findFile(ad)!;
        expect(readBoundedEntry(f, cap, truncate: true), veri, reason: ad);
        expect(readBoundedEntry(f, cap, truncate: false), veri, reason: ad);
      }
      expect(
        okunan.findFile('depolanan.xml')!.compression,
        CompressionType.none,
        reason: 'depolanan yol gerçekten sınanıyor olmalı',
      );
    });

    test('depolanmış (sıkıştırmasız) dev girdi de sınırlı okunur', () {
      final veri = List<int>.filled(bomba, 0x41);
      final a = Archive()
        ..addFile(ArchiveFile.noCompress('dev.xml', veri.length, veri));
      final f = ZipDecoder()
          .decodeBytes(Uint8List.fromList(ZipEncoder().encode(a)))
          .findFile('dev.xml')!;
      expect(readBoundedEntry(f, cap, truncate: true)!.length, cap);
      expect(readBoundedEntry(f, cap, truncate: false), isNull);
    });

    test('aynı girdi iki kez okunabilir (akış konumu geri alınır)', () {
      final zip = makeZip({'a.xml': bombaXml()});
      final f = girdi(zip, 'a.xml');
      final ilk = readBoundedEntry(f, cap, truncate: true)!;
      final ikinci = readBoundedEntry(f, cap, truncate: true)!;
      expect(ikinci, ilk);
    });

    test('bomba içeren sunumun önizlemesi yine de çıkar ve hızlı biter', () {
      final tmp = Directory.systemTemp.createTempSync('bomba_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final zip = basligiYalanlat(
        makeZip({
          'ppt/presentation.xml': '<p:presentation><p:sldId id="256" r:id="rId1"/></p:presentation>',
          'ppt/_rels/presentation.xml.rels': '<Relationships><Relationship Id="rId1" Target="slides/slide1.xml"/></Relationships>',
          'ppt/slides/slide1.xml': bombaXml(),
        }),
        100,
      );
      final path = (File(
        p.join(tmp.path, 'b.pptx'),
      )..writeAsBytesSync(zip)).path;
      final sw = Stopwatch()..start();
      final pv = zipDocumentPreview(path, 'pptx');
      sw.stop();
      expect(pv, isNotNull);
      expect(pv!.text, contains('merhaba'));
      expect(sw.elapsedMilliseconds, lessThan(2000));
    });

    test('önizleme yolları girdiyi content/readBytes ile TAMAMEN açmaz', () {
      // Çıktı sınırlı okumayla da aynı çıkar; bu yüzden yalnızca "tam açan yol
      // çağrıldı mı" bakışı, kodun yeniden `f.content`e dönmesini yakalar.
      Archive korumali(Map<String, Object> dosyalar) {
        final a = Archive();
        for (final f in ZipDecoder().decodeBytes(makeZip(dosyalar)).files) {
          a.addFile(TamAcmaYasak(f));
        }
        return a;
      }

      final metinli = archivePreview(
        korumali({
          'word/document.xml': '<w:p><w:r><w:t>Metin</w:t></w:r></w:p>',
        }),
        'docx',
      );
      expect(metinli!.text, contains('Metin'));

      final resimli = archivePreview(
        korumali({
          'docProps/thumbnail.jpeg': jpegBytes,
          'word/document.xml': '<w:p><w:r><w:t>Metin</w:t></w:r></w:p>',
        }),
        'docx',
      );
      expect(resimli!.isImage, isTrue);
    });

    test('tavanı aşan gömülü küçük resim yok sayılır, metne düşülür', () {
      final dev = Uint8List.fromList([
        0xFF, 0xD8, 0xFF, 0xE0, //
        ...List.filled(4 * 1024 * 1024, 7),
      ]);
      final zip = basligiYalanlat(
        makeZip({
          'docProps/thumbnail.jpeg': dev,
          'word/document.xml': '<w:p><w:r><w:t>Metin</w:t></w:r></w:p>',
        }),
        100, // başlık tavan altı görünüyor: yalnızca sınırlı okuma yakalar
      );
      final pv = archivePreview(ZipDecoder().decodeBytes(zip), 'docx');
      expect(pv, isNotNull);
      expect(pv!.isImage, isFalse, reason: '4 MiB resim tavanı aşıyor');
      expect(pv.text, contains('Metin'));
    });
  });

  group('zip dizini ve metin taraması sınırlı', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('sinir_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    String write(String name, List<int> bytes) =>
        (File(p.join(tmp.path, name))..writeAsBytesSync(bytes)).path;

    /// [ms] milisaniyeden kısa sürmeli; eski karesel tarama dakikalar sürerdi.
    T hizli<T>(T Function() f, {int ms = 3000}) {
      final sw = Stopwatch()..start();
      final r = f();
      expect(sw.elapsedMilliseconds, lessThan(ms));
      return r;
    }

    test('normal belgenin dizini sınır içinde', () {
      final path = write(
        'a.docx',
        makeZip({'word/document.xml': '<w:p><w:r><w:t>Merhaba</w:t></w:r></w:p>'}),
      );
      expect(zipDirectoryIsBounded(path), isTrue);
    });

    test('aynı dev yerel başlığı gösteren binlerce kayıt reddedilir', () {
      // Tek yerel başlık: 64 KB ad + 64 KB ek alan. 2000 merkezi kayıt hepsi
      // onu gösterir; archive 4.3.0 bunu ~260 MB belleğe çevirirdi.
      final b = BytesBuilder();
      void u16(int v) => b.add([v & 0xFF, (v >> 8) & 0xFF]);
      void u32(int v) {
        u16(v & 0xFFFF);
        u16((v >> 16) & 0xFFFF);
      }

      u32(0x04034b50);
      u16(20); u16(0); u16(0); u16(0); u16(0); // sürüm, bayrak, yöntem, saat, tarih
      u32(0); u32(0); u32(0); // crc, boyutlar
      u16(0xFFFF); u16(0xFFFF);
      b.add(List.filled(0xFFFF, 0x61));
      b.add(List.filled(0xFFFF, 0));
      final cdOffset = b.length;
      const n = 2000;
      for (var i = 0; i < n; i++) {
        u32(0x02014b50);
        u16(20); u16(20); u16(0); u16(0); u16(0); u16(0);
        u32(0); u32(0); u32(0);
        u16(0); u16(0); u16(0); u16(0); u16(0);
        u32(0);
        u32(0); // yerel başlık konumu: hepsi 0
      }
      final cdSize = b.length - cdOffset;
      u32(0x06054b50);
      u16(0); u16(0); u16(n); u16(n);
      u32(cdSize); u32(cdOffset);
      u16(0);
      final path = write('bomba.docx', b.toBytes());

      expect(zipDirectoryIsBounded(path), isFalse);
      expect(hizli(() => zipDocumentPreview(path, 'docx')), isNull);
    });

    /// [zip]'teki ilk merkezi dizin kaydının konumu.
    int ilkKayit(Uint8List zip) {
      for (var i = 0; i + 4 <= zip.length; i++) {
        if (zip[i] == 0x50 && zip[i + 1] == 0x4B && zip[i + 2] == 1 && zip[i + 3] == 2) {
          return i;
        }
      }
      throw StateError('merkezi dizin yok');
    }

    test('Unix sembolik bağlantı girdisi reddedilir (archive onu sınırsız açar)', () {
      final zip = makeZip({
        'word/document.xml': '<w:p><w:r><w:t>Merhaba</w:t></w:r></w:p>',
      });
      final k = ilkKayit(zip);
      ByteData.sublistView(zip)
        ..setUint16(k + 4, 0x031E, Endian.little) // Unix'te yazıldı
        ..setUint32(k + 38, 0xA1FF0000, Endian.little); // tür: sembolik bağlantı
      final path = write('baglanti.docx', zip);
      expect(zipDirectoryIsBounded(path), isFalse);
      expect(zipDocumentPreview(path, 'docx'), isNull);
    });

    test('dizin sonunda 1-3 baytlık artık reddedilir', () {
      final zip = makeZip({
        'word/document.xml': '<w:p><w:r><w:t>Merhaba</w:t></w:r></w:p>',
      });
      // Dizinle EOCD arasına 2 bayt ekle ve dizin boyutunu 2 büyüt: son
      // kayıttan sonra dizinin içinde 2 baytlık artık kalır.
      final e = zip.length - 22;
      final eocd = Uint8List.fromList(zip.sublist(e));
      final bd = ByteData.sublistView(eocd);
      bd.setUint32(12, bd.getUint32(12, Endian.little) + 2, Endian.little);
      final path = write('artik.docx', [...zip.sublist(0, e), 0x50, 0x4B, ...eocd]);
      expect(zipDirectoryIsBounded(path), isFalse);
      // Artıksız aynı dosya geçer (testin doğru yeri sınadığını gösterir).
      expect(zipDirectoryIsBounded(write('temiz.docx', zip)), isTrue);
    });

    test('kapanmayan paragraf etiketleri doğrusal sürede biter (docx)', () {
      final path = write(
        'b.docx',
        makeZip({'word/document.xml': '<w:p ' * 122880}), // 600 KB
      );
      expect(hizli(() => zipDocumentPreview(path, 'docx')), isNull);
    });

    test('eşleşmeyen slayt kimlikleri çapraz taranmaz (pptx)', () {
      final path = write(
        'c.pptx',
        makeZip({
          'ppt/presentation.xml': '<p:sldId r:id="a"/>' * 30000,
          'ppt/_rels/presentation.xml.rels':
              '<Relationship Id="b" Target="x"/>' * 40000,
        }),
      );
      expect(hizli(() => zipDocumentPreview(path, 'pptx')), isNull);
    });

    test('kapanmayan "<" ile dolu ODF ve xlsx de doğrusal', () {
      final odt = write(
        'd.odt',
        makeZip({'content.xml': '<text:p >${'<' * 300000}</text:p>'}),
      );
      expect(hizli(() => zipDocumentPreview(odt, 'odt')), isNull);
      final xlsx = write(
        'e.xlsx',
        makeZip({'xl/sharedStrings.xml': '<si>' * 150000}),
      );
      expect(hizli(() => zipDocumentPreview(xlsx, 'xlsx')), isNull);
    });

    test('yeni tarayıcı eski biçemleri aynen okur', () {
      final pv = archivePreview(
        ZipDecoder().decodeBytes(
          makeZip({
            'word/document.xml':
                '<w:body><w:p w:rsidR="1"><w:r><w:tab/><w:t xml:space="preserve">Bir </w:t></w:r>'
                '<w:r><w:t>iki</w:t></w:r></w:p><w:p/><w:p><w:r><w:t>&amp; üç</w:t></w:r></w:p></w:body>',
          }),
        ),
        'docx',
      );
      expect(pv!.text, 'Bir iki\n& üç');
    });
  });

  group('önbellek', () {
    test('aynı önizlemeyi aynı anda iki kez üretmez', () async {
      final src = FakeSource();
      final cache = PreviewCache(src);
      final f1 = cache.load(doc('/a.pdf'));
      final f2 = cache.load(doc('/a.pdf'));
      await tick();
      expect(src.calls, ['/a.pdf']);
      src.finish('/a.pdf', const Preview.text('merhaba'));
      expect((await f1)!.text, 'merhaba');
      expect((await f2)!.text, 'merhaba');
      // Sonra da önbellekten gelir.
      expect((await cache.load(doc('/a.pdf')))!.text, 'merhaba');
      expect(src.calls, hasLength(1));
    });

    test('dosya değişince (tarih ya da boyut) yeniden üretir', () async {
      final src = FakeSource();
      final cache = PreviewCache(src);
      final a = cache.load(doc('/a.pdf', ms: 1));
      await tick();
      src.finish('/a.pdf', const Preview.text('eski'));
      await a;
      final b = cache.load(doc('/a.pdf', ms: 2));
      await tick();
      expect(src.calls, hasLength(2));
      src.finish('/a.pdf', const Preview.text('yeni'));
      expect((await b)!.text, 'yeni');
    });

    test('önizleme yok (null) ve hata hatırlanır, tekrar denenmez', () async {
      final src = FakeSource();
      final cache = PreviewCache(src);
      final a = cache.load(doc('/a.pdf'));
      await tick();
      src.fail('/a.pdf');
      expect(await a, isNull);
      final hit = cache.lookup(
        PreviewCache.keyOf(doc('/a.pdf'), cardPreviewPx),
      );
      expect(hit.cached, isTrue);
      expect(hit.value, isNull);
      expect(await cache.load(doc('/a.pdf')), isNull);
      expect(src.calls, hasLength(1));
    });

    test('aynı anda en fazla "concurrency" iş çalışır', () async {
      final src = FakeSource();
      final cache = PreviewCache(src, concurrency: 2);
      for (final n in ['a', 'b', 'c', 'd']) {
        cache.load(doc('/$n.pdf'));
      }
      await tick();
      expect(src.running, 2);
      expect(src.maxRunning, 2);
      src.finish('/a.pdf');
      await tick();
      expect(src.calls, [
        '/a.pdf',
        '/b.pdf',
        '/d.pdf',
      ]); // sıradakilerden en yenisi başladı
      expect(src.running, 2);
      expect(src.maxRunning, 2);
    });

    test('ekrana en son gelen (en son istenen) önce işlenir', () async {
      final src = FakeSource();
      final cache = PreviewCache(src, concurrency: 1);
      cache.load(doc('/a.pdf'));
      cache.load(doc('/b.pdf'));
      cache.load(doc('/c.pdf'));
      await tick();
      expect(src.calls, ['/a.pdf']);
      src.finish('/a.pdf');
      await tick();
      expect(src.calls, ['/a.pdf', '/c.pdf']); // b değil, c
    });

    test(
      'artık gerekmeyen (kaydırılıp geçilen) iş atlanır, önbelleğe yazılmaz',
      () async {
        final src = FakeSource();
        final cache = PreviewCache(src, concurrency: 1);
        cache.load(doc('/a.pdf'));
        final b = cache.load(doc('/b.pdf'), wanted: () => false);
        final c = cache.load(doc('/c.pdf'));
        await tick();
        src.finish('/a.pdf');
        await tick();
        expect(src.calls, ['/a.pdf', '/c.pdf']);
        src.finish('/c.pdf', const Preview.text('c'));
        expect((await c)!.text, 'c');
        expect(await b, isNull);
        expect(
          cache.lookup(PreviewCache.keyOf(doc('/b.pdf'), cardPreviewPx)).cached,
          isFalse,
        );
      },
    );

    test('ikinci bir isteyen katılırsa iş atlanmaz', () async {
      final src = FakeSource();
      final cache = PreviewCache(src, concurrency: 1);
      cache.load(doc('/a.pdf'));
      cache.load(doc('/b.pdf'), wanted: () => false);
      final b2 = cache.load(doc('/b.pdf')); // başka bir ekran da istiyor
      await tick();
      src.finish('/a.pdf');
      await tick();
      expect(src.calls, ['/a.pdf', '/b.pdf']);
      src.finish('/b.pdf', const Preview.text('b'));
      expect((await b2)!.text, 'b');
    });

    test('kapasite aşılınca en az kullanılan atılır (LRU)', () async {
      final src = FakeSource();
      final cache = PreviewCache(src, capacity: 2, concurrency: 5);
      Future<void> fill(String n) async {
        final f = cache.load(doc('/$n.pdf'));
        await tick();
        src.finish('/$n.pdf', Preview.text(n));
        await f;
      }

      await fill('a');
      await fill('b');
      cache.lookup(
        PreviewCache.keyOf(doc('/a.pdf'), cardPreviewPx),
      ); // a'ya dokun
      await fill('c'); // b atılmalı
      bool cached(String n) => cache
          .lookup(PreviewCache.keyOf(doc('/$n.pdf'), cardPreviewPx))
          .cached;
      expect(cached('a'), isTrue);
      expect(cached('b'), isFalse);
      expect(cached('c'), isTrue);
    });

    test('farklı boyut isteği ayrı önizlemedir', () async {
      final src = FakeSource();
      final cache = PreviewCache(src);
      cache.load(doc('/a.pdf'), px: cardPreviewPx);
      cache.load(doc('/a.pdf'), px: largePreviewPx);
      await tick();
      expect(src.calls, hasLength(2));
    });
  });
}
