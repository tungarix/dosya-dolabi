import 'dart:io';

import 'package:dosya_dolabi/src/app.dart';
import 'package:dosya_dolabi/src/library.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Gerçek dosya G/Ç'sinin her adımı, sahte zaman bölgesinde ayrı bir
/// "gerçek bekleme + kare çizimi" turu ister; tarama onlarca adımdan oluşur.
Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 40; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 15)),
    );
    await t.pump(const Duration(milliseconds: 60));
  }
  await t.pump(const Duration(seconds: 1)); // animasyonlar (snackbar, sayfa)
}

void main() {
  late Directory tmp;
  late Library lib;
  late String inbox;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('dolap_ui_');
    inbox = p.join(tmp.path, 'Download')..let(Directory.new).createSync();
    File(p.join(inbox, 'Fizik notları.pdf')).writeAsStringSync('pdf');
    File(p.join(inbox, 'Sunum.pptx')).writeAsStringSync('ppt');
    lib = Library(root: p.join(tmp.path, 'Dolap'), inboxDirs: [inbox]);
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  Future<void> start(
    WidgetTester t, {
    Size size = const Size(1280, 800),
  }) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(DolapApp(library: lib));
    await settle(t);
  }

  testWidgets('Gelen Kutusu\'ndaki dosya kategoriye taşınır ve geri alınır', (
    t,
  ) async {
    await start(t);

    // Açılışta yeni dosyalar Gelen Kutusu'nda, kategori yok.
    expect(find.text('Fizik notları.pdf'), findsOneWidget);
    expect(find.text('Sunum.pptx'), findsOneWidget);
    expect(find.text('Kategoriye koy'), findsNWidgets(2));

    // Hazır öneriden kategori oluştur.
    await t.tap(find.widgetWithText(ActionChip, 'Dersler'));
    await settle(t);
    expect(Directory(p.join(lib.root, 'Dersler')).existsSync(), isTrue);

    // İlk dosyayı o kategoriye koy.
    await t.tap(find.text('Kategoriye koy').first);
    await settle(t);
    expect(find.text('Hangi kategoriye koyalım?'), findsOneWidget);
    await t.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Dersler'),
      ),
    );
    await settle(t);

    final moved = File(p.join(lib.root, 'Dersler', 'Fizik notları.pdf'));
    expect(moved.existsSync(), isTrue);
    expect(File(p.join(inbox, 'Fizik notları.pdf')).existsSync(), isFalse);
    expect(
      find.text('Fizik notları.pdf'),
      findsNothing,
    ); // Gelen Kutusu'ndan çıktı
    expect(find.text('GERİ AL'), findsOneWidget);

    // Geri al.
    await t.tap(find.text('GERİ AL'));
    await settle(t);
    expect(File(p.join(inbox, 'Fizik notları.pdf')).existsSync(), isTrue);
    expect(moved.existsSync(), isFalse);
    expect(find.text('Fizik notları.pdf'), findsOneWidget);
  });

  testWidgets('dosya çöp kutusuna atılır ve oradan geri konur', (t) async {
    await start(t);
    await t.tap(find.byTooltip('Dosya işlemleri').first);
    await t.pumpAndSettle();
    await t.tap(find.text('Çöp kutusuna at'));
    await settle(t);
    expect(File(p.join(inbox, 'Fizik notları.pdf')).existsSync(), isFalse);

    await t.tap(find.text('Çöp Kutusu'));
    await settle(t);
    expect(find.text('Fizik notları.pdf'), findsOneWidget);
    await t.tap(find.text('Geri koy'));
    await settle(t);
    expect(File(p.join(inbox, 'Fizik notları.pdf')).existsSync(), isTrue);
    expect(find.text('Çöp kutusu boş'), findsOneWidget);
  });

  testWidgets('arama Türkçe harfleri ayırt etmez', (t) async {
    await start(t);
    await t.enterText(find.byType(TextField), 'notlari');
    await settle(t);
    expect(find.text('Fizik notları.pdf'), findsOneWidget);
    expect(find.text('Sunum.pptx'), findsNothing);
  });

  testWidgets('başka yere gidince arama kutusu temizlenir', (t) async {
    await start(t);
    await t.enterText(find.byType(TextField), 'notlari');
    await settle(t);
    await t.tap(find.text('Tüm dosyalar'));
    await settle(t);
    expect(
      t.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
  });

  testWidgets('dar ekranda kategoriler çekmecede açılır', (t) async {
    await start(t, size: const Size(600, 900));
    expect(find.text('Dosya Dolabı'), findsNothing); // çekmece kapalı
    await t.tap(find.byTooltip('Kategoriler'));
    await t.pumpAndSettle();
    expect(find.text('Dosya Dolabı'), findsOneWidget);
    expect(find.text('Çöp Kutusu'), findsOneWidget);
  });
}

extension<T> on T {
  R let<R>(R Function(T) f) => f(this);
}
