import 'dart:convert';
import 'dart:io';

import 'package:dosya_dolabi/src/library.dart';
import 'package:dosya_dolabi/src/text.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;
  late Library lib;
  late String inbox;

  File touch(String path, [String content = 'x']) {
    final f = File(path)..createSync(recursive: true);
    f.writeAsStringSync(content);
    return f;
  }

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('dolap_test_');
    inbox = p.join(tmp.path, 'Download');
    Directory(inbox).createSync();
    lib = Library(root: p.join(tmp.path, 'Dolap'), inboxDirs: [inbox]);
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  group('tarama', () {
    test('kategorileri ve dosyaları ağaç olarak bulur', () async {
      touch(p.join(lib.root, 'Dersler', 'Matematik', 'vize.pdf'));
      touch(p.join(lib.root, 'Dersler', 'fizik.pptx'));
      touch(p.join(lib.root, 'kök.pdf'));
      final s = await lib.scan();
      expect(s.root.children.map((c) => c.path), ['Dersler']);
      expect(s.find('Dersler/Matematik')!.files.single.name, 'vize.pdf');
      expect(s.find('Dersler')!.totalFiles, 2);
      expect(s.root.files.single.category, '');
    });

    test(
      'kategorileri doğal sırada dizer (Hafta 2, Hafta 10\'dan önce)',
      () async {
        for (final n in ['Hafta 10', 'Hafta 2', 'Hafta 1']) {
          Directory(p.join(lib.root, n)).createSync(recursive: true);
        }
        final s = await lib.scan();
        expect(s.root.children.map((c) => c.name), [
          'Hafta 1',
          'Hafta 2',
          'Hafta 10',
        ]);
      },
    );

    test('gizli dosyaları ve çöp kutusunu göstermez', () async {
      touch(p.join(lib.root, '.nomedia'));
      touch(p.join(lib.root, 'a.pdf'));
      final s = await lib.scan();
      expect(s.root.files.map((f) => f.name), ['a.pdf']);
      expect(s.root.children, isEmpty);
    });

    test('Gelen Kutusu yalnızca belge türlerini listeler', () async {
      touch(p.join(inbox, 'ders.pdf'));
      touch(p.join(inbox, 'sunum.pptx'));
      touch(p.join(inbox, 'film.mp4'));
      touch(p.join(inbox, 'oyun.apk'));
      touch(p.join(inbox, 'yarim.pdf.crdownload'));
      touch(p.join(inbox, 'alt', 'not.docx'));
      final s = await lib.scan();
      expect(
        s.inbox.map((f) => f.name),
        unorderedEquals(['ders.pdf', 'sunum.pptx', 'not.docx']),
      );
      expect(s.inbox.every((f) => !f.inLibrary), isTrue);
    });

    test(
      'dolap klasörü Gelen Kutusu içindeyse dolaptakiler tekrar görünmez',
      () async {
        final inside = Library(
          root: p.join(inbox, 'Dolap'),
          inboxDirs: [inbox],
        );
        touch(p.join(inside.root, 'Ders', 'a.pdf'));
        touch(p.join(inbox, 'b.pdf'));
        final s = await inside.scan();
        expect(s.inbox.map((f) => f.name), ['b.pdf']);
      },
    );
  });

  group('kategori işlemleri', () {
    test('oluşturur, çakışmayı ve geçersiz adı reddeder', () async {
      expect(await lib.createCategory('', 'Dersler'), 'Dersler');
      expect(await lib.createCategory('Dersler', 'Fizik'), 'Dersler/Fizik');
      expect(
        Directory(p.join(lib.root, 'Dersler', 'Fizik')).existsSync(),
        isTrue,
      );
      expect(
        lib.createCategory('', 'Dersler'),
        throwsA(isA<LibraryException>()),
      );
      expect(lib.createCategory('', 'a/b'), throwsA(isA<LibraryException>()));
      expect(lib.createCategory('', '  '), throwsA(isA<LibraryException>()));
    });

    test(
      'yeniden adlandırır; yalnızca harf boyu değişince de çalışır',
      () async {
        await lib.createCategory('', 'dersler');
        touch(p.join(lib.root, 'dersler', 'a.pdf'));
        expect(await lib.renameCategory('dersler', 'Dersler'), 'Dersler');
        expect(await lib.renameCategory('Dersler', 'Okul'), 'Okul');
        final s = await lib.scan();
        expect(s.root.children.single.name, 'Okul');
        expect(s.find('Okul')!.files.single.name, 'a.pdf');
      },
    );

    test(
      'başka kategorinin içine taşır; kendi içine taşımayı reddeder',
      () async {
        await lib.createCategory('', 'A');
        await lib.createCategory('A', 'B');
        await lib.createCategory('', 'C');
        expect(await lib.moveCategory('C', 'A/B'), 'A/B/C');
        expect(lib.moveCategory('A', 'A/B'), throwsA(isA<LibraryException>()));
        expect(lib.moveCategory('A', 'A'), throwsA(isA<LibraryException>()));
      },
    );

    test('silince içindekiler bir üste taşınır, dosya kaybolmaz', () async {
      touch(p.join(lib.root, 'A', 'B', 'x.pdf'));
      touch(p.join(lib.root, 'A', 'B', 'alt', 'y.pdf'));
      final moved = await lib.deleteCategory('A/B');
      expect(moved, hasLength(2));
      final s = await lib.scan();
      expect(s.find('A/B'), isNull);
      expect(s.find('A')!.files.single.name, 'x.pdf');
      expect(s.find('A/alt')!.files.single.name, 'y.pdf');
    });

    test('silmeyi geri alır', () async {
      touch(p.join(lib.root, 'A', 'B', 'x.pdf'));
      touch(p.join(lib.root, 'A', 'B', 'alt', 'y.pdf'));
      final moved = await lib.deleteCategory('A/B');
      await lib.undo(moved);
      final s = await lib.scan();
      expect(s.find('A/B')!.files.single.name, 'x.pdf');
      expect(s.find('A/B/alt')!.files.single.name, 'y.pdf');
    });

    /// A/B kategorisinde gizli öğeler (Android sistem çöpü, küçük resim
    /// klasörü, .nomedia) ve görünür bir dosya hazırlar.
    void gizliliBKategorisi() {
      final b = p.join(lib.root, 'A', 'B');
      touch(p.join(b, '.nomedia'), '');
      touch(p.join(b, '.gizli.txt'), 'gizli');
      touch(p.join(b, '.trashed-1-x.pdf'), 'sistem çöpü');
      touch(p.join(b, '.thumbnails', 't1.jpg'), 'küçük resim');
      touch(p.join(b, 'x.pdf'), 'görünür');
    }

    test(
      'silince gizli öğeler de bir üste taşınır (.nomedia hariç, o silinir)',
      () async {
        gizliliBKategorisi();
        final moved = await lib.deleteCategory('A/B');
        final a = p.join(lib.root, 'A');
        expect(File(p.join(a, 'x.pdf')).readAsStringSync(), 'görünür');
        expect(File(p.join(a, '.gizli.txt')).readAsStringSync(), 'gizli');
        expect(
          File(p.join(a, '.trashed-1-x.pdf')).readAsStringSync(),
          'sistem çöpü',
        );
        expect(
          File(p.join(a, '.thumbnails', 't1.jpg')).readAsStringSync(),
          'küçük resim',
        );
        // .nomedia üst klasöre gitseydi galeriler onu da gizlerdi.
        expect(File(p.join(a, '.nomedia')).existsSync(), isFalse);
        expect(Directory(p.join(a, 'B')).existsSync(), isFalse);
        // Üç gizli öğe + görünür dosya; silinen .nomedia sayılmaz.
        expect(moved, hasLength(4));
      },
    );

    test('silmeyi geri alınca gizli öğeler de yerine döner', () async {
      gizliliBKategorisi();
      final moved = await lib.deleteCategory('A/B');
      final r = await lib.undo(moved);
      expect(r.failed, isEmpty);
      final b = p.join(lib.root, 'A', 'B');
      expect(File(p.join(b, 'x.pdf')).readAsStringSync(), 'görünür');
      expect(File(p.join(b, '.gizli.txt')).readAsStringSync(), 'gizli');
      expect(
        File(p.join(b, '.trashed-1-x.pdf')).readAsStringSync(),
        'sistem çöpü',
      );
      expect(
        File(p.join(b, '.thumbnails', 't1.jpg')).readAsStringSync(),
        'küçük resim',
      );
      // Üst klasörde artık bunların kopyası kalmaz.
      final a = p.join(lib.root, 'A');
      expect(File(p.join(a, '.gizli.txt')).existsSync(), isFalse);
      expect(Directory(p.join(a, '.thumbnails')).existsSync(), isFalse);
    });

    test(
      'üst klasörde aynı adlı gizli dosya varsa ezmez, "(2)" ekler',
      () async {
        touch(p.join(lib.root, 'A', '.gizli.txt'), 'üsttekiler');
        touch(p.join(lib.root, 'A', 'B', '.gizli.txt'), 'içteki');
        await lib.deleteCategory('A/B');
        final a = p.join(lib.root, 'A');
        expect(File(p.join(a, '.gizli.txt')).readAsStringSync(), 'üsttekiler');
        expect(File(p.join(a, '.gizli (2).txt')).readAsStringSync(), 'içteki');
      },
    );

    test('".nomedia" bir KLASÖRSE dosya sayılmaz: diğer gizliler gibi taşınır, içi korunur', () async {
      // Yalnızca ".nomedia" DOSYASI taşınmadan silinir (üst klasörü galeriden
      // gizlemesin diye). Aynı adlı bir klasörün içindeki veri ise kullanıcı
      // verisi olabilir: sessizce silinmemeli.
      final b = p.join(lib.root, 'A', 'B');
      touch(p.join(b, 'x.pdf'), 'görünür');
      touch(p.join(b, '.nomedia', 'k.txt'), 'kalmalı');
      final moved = await lib.deleteCategory('A/B');
      expect(moved.map((m) => p.basename(m.to)).toSet(), {'x.pdf', '.nomedia'});
      final a = p.join(lib.root, 'A');
      expect(File(p.join(a, 'x.pdf')).existsSync(), isTrue);
      expect(
        File(p.join(a, '.nomedia', 'k.txt')).readAsStringSync(),
        'kalmalı',
      );
      expect(Directory(b).existsSync(), isFalse);
    });
  });

  group('dosya işlemleri', () {
    test('Gelen Kutusu\'ndan kategoriye gerçekten taşır', () async {
      final f = touch(p.join(inbox, 'ders.pdf'), 'içerik');
      final r = await lib.moveFiles([f.path], 'Dersler/Mat');
      expect(r.failed, isEmpty);
      expect(f.existsSync(), isFalse);
      expect(
        File(p.join(lib.root, 'Dersler', 'Mat', 'ders.pdf')).readAsStringSync(),
        'içerik',
      );
    });

    test('aynı adlı dosya varsa ezmez, "(2)" ekler', () async {
      touch(p.join(lib.root, 'K', 'ders.pdf'), 'eski');
      final f = touch(p.join(inbox, 'ders.pdf'), 'yeni');
      final r = await lib.moveFiles([f.path], 'K');
      expect(p.basename(r.moved.single.to), 'ders (2).pdf');
      expect(
        File(p.join(lib.root, 'K', 'ders.pdf')).readAsStringSync(),
        'eski',
      );
      expect(
        File(p.join(lib.root, 'K', 'ders (2).pdf')).readAsStringSync(),
        'yeni',
      );
    });

    test('zaten o kategorideki dosyayı atlar', () async {
      final f = touch(p.join(lib.root, 'K', 'a.pdf'));
      final r = await lib.moveFiles([f.path], 'K');
      expect(r.moved, isEmpty);
      expect(f.existsSync(), isTrue);
    });

    test('bulunmayan dosya hata olarak döner, diğerleri taşınır', () async {
      final ok = touch(p.join(inbox, 'a.pdf'));
      final r = await lib.moveFiles([p.join(inbox, 'yok.pdf'), ok.path], 'K');
      expect(r.failed, [p.join(inbox, 'yok.pdf')]);
      expect(r.moved, hasLength(1));
    });

    test('taşımayı geri alır', () async {
      final f = touch(p.join(inbox, 'ders.pdf'));
      final r = await lib.moveFiles([f.path], 'K');
      await lib.undo(r.moved);
      expect(f.existsSync(), isTrue);
      expect(File(r.moved.single.to).existsSync(), isFalse);
    });

    test('yeniden adlandırır, çakışmayı reddeder', () async {
      final a = touch(p.join(lib.root, 'K', 'a.pdf'));
      touch(p.join(lib.root, 'K', 'b.pdf'));
      expect(p.basename(await lib.renameFile(a.path, 'vize.pdf')), 'vize.pdf');
      expect(
        lib.renameFile(p.join(lib.root, 'K', 'vize.pdf'), 'b.pdf'),
        throwsA(isA<LibraryException>()),
      );
    });
  });

  group('çöp kutusu', () {
    test('sil → çöpte görünür → geri koy', () async {
      final f = touch(p.join(lib.root, 'K', 'a.pdf'), 'veri');
      await lib.trashFiles([f.path]);
      var s = await lib.scan();
      expect(f.existsSync(), isFalse);
      expect(s.root.descendants.expand((c) => c.files), isEmpty);
      expect(s.trash.single.name, 'a.pdf');
      expect(s.trash.single.originalPath, f.path);

      final r = await lib.restore(s.trash);
      expect(r.failed, isEmpty);
      expect(f.readAsStringSync(), 'veri');
      s = await lib.scan();
      expect(s.trash, isEmpty);
    });

    test('silmeyi geri alır (Geri al düğmesi)', () async {
      final f = touch(p.join(lib.root, 'K', 'a.pdf'));
      final r = await lib.trashFiles([f.path]);
      await lib.undo(r.moved);
      expect(f.existsSync(), isTrue);
      expect((await lib.scan()).trash, isEmpty);
    });

    test('özgün klasör silinmişse geri koyarken yeniden oluşturur', () async {
      final f = touch(p.join(lib.root, 'K', 'a.pdf'));
      await lib.trashFiles([f.path]);
      Directory(p.join(lib.root, 'K')).deleteSync(recursive: true);
      final s = await lib.scan();
      await lib.restore(s.trash);
      expect(f.existsSync(), isTrue);
    });

    test('aynı adlı iki dosyayı çöpte ayrı tutar', () async {
      final a = touch(p.join(lib.root, 'A', 'x.pdf'), 'bir');
      final b = touch(p.join(lib.root, 'B', 'x.pdf'), 'iki');
      await lib.trashFiles([a.path, b.path]);
      final s = await lib.scan();
      expect(s.trash, hasLength(2));
      await lib.restore(s.trash);
      expect(a.readAsStringSync(), 'bir');
      expect(b.readAsStringSync(), 'iki');
    });

    test('kalıcı siler ve çöpü boşaltır', () async {
      final a = touch(p.join(lib.root, 'a.pdf'));
      final b = touch(p.join(lib.root, 'b.pdf'));
      await lib.trashFiles([a.path, b.path]);
      var s = await lib.scan();
      await lib.deleteForever([s.trash.first]);
      s = await lib.scan();
      expect(s.trash, hasLength(1));
      await lib.emptyTrash();
      expect((await lib.scan()).trash, isEmpty);
    });

    test('30 günden eski çöp dosyaları temizlenir', () async {
      final old = Library(root: lib.root, inboxDirs: [inbox], trashDays: 0);
      final f = touch(p.join(lib.root, 'a.pdf'));
      await old.trashFiles([f.path]);
      expect((await old.scan()).trash, isEmpty);
    });

    test('bozuk dizin dosyasına rağmen çöp listelenir', () async {
      final f = touch(p.join(lib.root, 'a.pdf'));
      await lib.trashFiles([f.path]);
      File(p.join(lib.trashDir, '.index.json')).writeAsStringSync('{bozuk');
      final s = await lib.scan();
      expect(s.trash.single.name, 'a.pdf');
    });

    // Taşıma (rename) değişme tarihini korur: çöpe yeni atılmış eski bir
    // indirme, silinme zamanı bilinmiyorsa "eski" görünüp kalıcı silinmesin.
    String dizinYolu() => p.join(lib.trashDir, '.index.json');
    Map<String, dynamic> dizinOku() =>
        jsonDecode(File(dizinYolu()).readAsStringSync())
            as Map<String, dynamic>;
    String gunOnce(int gun) =>
        DateTime.now().subtract(Duration(days: gun)).toIso8601String();

    /// Çöp klasörüne doğrudan bırakılmış, değişme tarihi [gun] gün öncesine
    /// ayarlı dosya (dizin kaydı yok).
    File copteEski(String ad, {int gun = 100}) {
      final f = touch(p.join(lib.trashDir, ad), 'veri');
      f.setLastModifiedSync(DateTime.now().subtract(Duration(days: gun)));
      return f;
    }

    test('dizin kaydı yoksa eski tarihli çöp dosyası silinmez, sayaç şimdi '
        'başlar', () async {
      final f = copteEski('eski.pdf');
      final once = DateTime.now();
      final s = await lib.scan();
      expect(f.existsSync(), isTrue);
      expect(s.trash.single.name, 'eski.pdf');
      expect(
        s.trash.single.deletedAt.isBefore(
          once.subtract(const Duration(seconds: 1)),
        ),
        isFalse,
        reason:
            'silinme zamanı dosya tarihi (100 gün önce) değil, şimdi olmalı',
      );
      // Kayıt dizine KALICI yazıldı.
      final at = DateTime.parse(dizinOku()['eski.pdf']['at'] as String);
      expect(at.difference(once).abs(), lessThan(const Duration(seconds: 5)));
      // Sonraki taramada da duruyor; sayaç yeniden başlamıyor.
      final s2 = await lib.scan();
      expect(f.existsSync(), isTrue);
      expect(
        s2.trash.single.deletedAt.difference(s.trash.single.deletedAt).abs(),
        lessThan(const Duration(seconds: 1)),
      );
    });

    test('bozuk dizinle de eski tarihli çöp dosyası silinmez', () async {
      final f = touch(p.join(lib.root, 'K', 'a.pdf'), 'veri');
      f.setLastModifiedSync(DateTime.now().subtract(const Duration(days: 100)));
      await lib.trashFiles([f.path]);
      final cop = File(p.join(lib.trashDir, 'a.pdf'));
      // Ön koşul: taşıma değişme tarihini korumuş olmalı.
      expect(DateTime.now().difference(cop.lastModifiedSync()).inDays, 100);
      File(dizinYolu()).writeAsStringSync('{bozuk');
      final s = await lib.scan();
      expect(cop.existsSync(), isTrue);
      expect(s.trash.single.name, 'a.pdf');
      expect(dizinOku()['a.pdf']['at'], isA<String>()); // dizin onarıldı
    });

    test('geçerli "at" ile 30 günden eskiyse hâlâ kalıcı silinir, tazeyse '
        'dosya tarihine bakılmaz', () async {
      final eski = copteEski('eski.pdf');
      final taze = copteEski('taze.pdf');
      File(dizinYolu()).writeAsStringSync(
        jsonEncode({
          'eski.pdf': {'from': '/y/eski.pdf', 'at': gunOnce(40)},
          'taze.pdf': {'from': '/y/taze.pdf', 'at': gunOnce(10)},
        }),
      );
      final s = await lib.scan();
      expect(eski.existsSync(), isFalse);
      expect(dizinOku().containsKey('eski.pdf'), isFalse);
      expect(taze.existsSync(), isTrue);
      expect(s.trash.map((t) => t.name), ['taze.pdf']);
      expect(DateTime.now().difference(s.trash.single.deletedAt).inDays, 10);
      expect(s.trash.single.originalPath, '/y/taze.pdf');
    });

    test(
      'ayrıştırılamayan ya da eksik "at" şimdi sayılır, "from" korunur',
      () async {
        final f = <String, File>{
          for (final ad in ['a.pdf', 'b.pdf', 'c.pdf']) ad: copteEski(ad),
        };
        File(dizinYolu()).writeAsStringSync(
          jsonEncode({
            'a.pdf': {'from': 'C:/yer/a.pdf', 'at': 'dün akşam'},
            'b.pdf': 'tamamen bozuk kayıt',
            'c.pdf': {'from': 'C:/yer/c.pdf'}, // "at" hiç yok
          }),
        );
        final s = await lib.scan();
        expect(f.values.every((e) => e.existsSync()), isTrue);
        final byName = {for (final t in s.trash) t.name: t};
        expect(byName.keys, unorderedEquals(['a.pdf', 'b.pdf', 'c.pdf']));
        expect(byName['a.pdf']!.originalPath, 'C:/yer/a.pdf');
        expect(byName['c.pdf']!.originalPath, 'C:/yer/c.pdf');
        expect(byName['b.pdf']!.originalPath, p.join(lib.root, 'b.pdf'));
        for (final t in s.trash) {
          expect(
            DateTime.now().difference(t.deletedAt),
            lessThan(const Duration(seconds: 5)),
          );
        }
        // Mevcut kayıt (from) korunarak "at" dizine yazıldı.
        final d = dizinOku();
        expect(d['a.pdf']['from'], 'C:/yer/a.pdf');
        expect(DateTime.tryParse(d['a.pdf']['at'] as String), isNotNull);
        expect(d['c.pdf']['from'], 'C:/yer/c.pdf');
        expect(DateTime.tryParse(d['c.pdf']['at'] as String), isNotNull);
        expect(DateTime.tryParse(d['b.pdf']['at'] as String), isNotNull);
      },
    );

    test('dizin yazımı geçici dosya bırakmaz', () async {
      final f = touch(p.join(lib.root, 'a.pdf'));
      await lib.trashFiles([f.path]);
      expect(
        File(p.join(lib.trashDir, '.index.json.tmp')).existsSync(),
        isFalse,
      );
      expect(dizinOku().keys, ['a.pdf']);
      await lib.deleteForever((await lib.scan()).trash);
      expect(
        File(p.join(lib.trashDir, '.index.json.tmp')).existsSync(),
        isFalse,
      );
    });

    test('önceden kalmış yarım geçici dosya listede çıkmaz, dizini bozmaz ve '
        'sonraki yazımda ezilir', () async {
      final f = touch(p.join(lib.root, 'K', 'a.pdf'), 'veri');
      await lib.trashFiles([f.path]);
      final tmp = File(p.join(lib.trashDir, '.index.json.tmp'))
        ..writeAsStringSync('{"a.pdf": {"from": "yarım');
      // Taramada görünmez; gerçek dizin okunmaya devam eder.
      var s = await lib.scan();
      expect(s.trash.map((t) => t.name), ['a.pdf']);
      expect(s.trash.single.originalPath, f.path);
      expect(tmp.existsSync(), isTrue);
      // Sonraki yazım artığı ezer: dizin geçerli, geçici dosya kalmaz.
      final g = touch(p.join(lib.root, 'K', 'b.pdf'));
      await lib.trashFiles([g.path]);
      expect(tmp.existsSync(), isFalse);
      expect(dizinOku().keys, unorderedEquals(['a.pdf', 'b.pdf']));
      s = await lib.scan();
      expect(s.trash, hasLength(2));
    });
  });

  group('metin yardımcıları', () {
    test('Türkçe harf katlama', () {
      expect(fold('ÇALIŞMA Sınav İş'), 'calisma sinav is');
      expect(fold('Işık'), fold('isik'));
    });

    test('doğal sıralama', () {
      final l = ['b10', 'b2', 'a', 'B1']..sort(naturalCompare);
      expect(l, ['a', 'B1', 'b2', 'b10']);
    });

    test('boyut biçimi', () {
      expect(formatSize(500), '500 B');
      expect(formatSize(1536), '1,5 KB');
      expect(formatSize(5 * 1024 * 1024), '5,0 MB');
      expect(formatSize(250 * 1024 * 1024), '250 MB');
    });

    test('tarih biçimi', () {
      final now = DateTime(2026, 10, 1, 12);
      expect(formatDate(DateTime(2026, 10, 1, 9, 5), now), 'Bugün 09:05');
      expect(formatDate(DateTime(2026, 9, 30, 23, 0), now), 'Dün 23:00');
      expect(formatDate(DateTime(2026, 9, 3), now), '3 Eyl');
      expect(formatDate(DateTime(2025, 9, 3), now), '3 Eyl 2025');
    });

    test('ad doğrulama', () {
      expect(validateName('Matematik'), isNull);
      expect(validateName(''), isNotNull);
      expect(validateName('.gizli'), isNotNull);
      expect(validateName('a:b'), isNotNull);
    });
  });
}
