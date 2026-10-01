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
