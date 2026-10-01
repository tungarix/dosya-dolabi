import 'dart:io';

import 'package:dosya_dolabi/src/app.dart';
import 'package:dosya_dolabi/src/library.dart';
import 'package:dosya_dolabi/src/preview.dart';
import 'package:dosya_dolabi/src/ui/permission_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Gerçek dosya G/Ç'si sahte zaman bölgesinde adım adım ilerler (bkz.
/// app_flow_test.dart); her etkileşimden sonra kısa bir bekleme döngüsü gerekir.
Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 40; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 15)),
    );
    await t.pump(const Duration(milliseconds: 60));
  }
  await t.pump(const Duration(seconds: 1));
}

void main() {
  // Taşma, Flutter testlerinde istisna olarak yakalanır: takeException boş olmalı.
  for (final width in [360.0, 393.0]) {
    group('telefon ${width.toInt()} dp', () {
      late Directory tmp;
      late Library lib;
      late String inbox;

      setUp(() {
        tmp = Directory.systemTemp.createTempSync('dolap_tel_');
        inbox = p.join(tmp.path, 'Download');
        Directory(inbox).createSync();
        File(p.join(inbox, 'Fizik notları.pdf')).writeAsStringSync('pdf');
        File(p.join(inbox, 'Sunum.pptx')).writeAsStringSync('ppt');
        lib = Library(root: p.join(tmp.path, 'Dolap'), inboxDirs: [inbox]);
      });

      tearDown(() => tmp.deleteSync(recursive: true));

      Future<void> start(WidgetTester t) async {
        t.view.physicalSize = Size(width, 800);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        await t.pumpWidget(
          DolapApp(library: lib, previewSource: const NoPreviewSource()),
        );
        await settle(t);
        expect(t.takeException(), isNull);
      }

      testWidgets('açılışta taşma yok, arama simgeye iner', (t) async {
        await start(t);
        expect(find.text('Gelen Kutusu'), findsWidgets);
        expect(find.byTooltip('Ara'), findsOneWidget);
        expect(find.byType(TextField), findsNothing);
        expect(
          find.byTooltip('Yenile'),
          findsNothing,
        ); // aşağı çekerek yenilenir
        expect(find.text('Fizik notları.pdf'), findsOneWidget);
      });

      testWidgets('arama çubuğu kaplar, filtreler, geri oku kapatır', (
        t,
      ) async {
        await start(t);
        await t.tap(find.byTooltip('Ara'));
        await settle(t);
        expect(find.byType(TextField), findsOneWidget);
        expect(find.byTooltip('Aramayı kapat'), findsOneWidget);

        await t.enterText(find.byType(TextField), 'notlari');
        await settle(t);
        expect(find.text('Fizik notları.pdf'), findsOneWidget);
        expect(find.text('Sunum.pptx'), findsNothing);
        expect(t.takeException(), isNull);

        await t.tap(find.byTooltip('Aramayı kapat'));
        await settle(t);
        expect(find.byType(TextField), findsNothing);
        expect(find.text('Sunum.pptx'), findsOneWidget);
      });

      testWidgets('sistem geri tuşu önce açık aramayı kapatır', (t) async {
        await start(t);
        await t.tap(find.byTooltip('Ara'));
        await settle(t);
        expect(find.byType(TextField), findsOneWidget);
        await t.binding.handlePopRoute();
        await settle(t);
        expect(find.byType(TextField), findsNothing);
        expect(find.byTooltip('Ara'), findsOneWidget);
      });

      testWidgets('seçim çubuğu simgelerle sığar', (t) async {
        await start(t);
        await t.longPress(find.text('Fizik notları.pdf'));
        await settle(t);
        expect(find.text('1 seçili'), findsOneWidget);
        expect(find.byTooltip('Hepsini seç'), findsOneWidget);
        expect(find.byTooltip('Kategoriye koy'), findsOneWidget);
        expect(find.byTooltip('Çöp kutusuna at'), findsOneWidget);
        expect(t.takeException(), isNull);

        await t.tap(find.byTooltip('Hepsini seç'));
        await settle(t);
        expect(find.text('2 seçili'), findsOneWidget);
      });

      testWidgets('liste görünümü taşmaz, taşıma simgesi var', (t) async {
        await start(t);
        await t.tap(find.byTooltip('Liste görünümü'));
        await settle(t);
        expect(find.byTooltip('Kategoriye koy'), findsNWidgets(2));
        expect(find.text('Fizik notları.pdf'), findsOneWidget);
        expect(t.takeException(), isNull);
      });

      testWidgets('kategori seçici diyaloğu taşmaz', (t) async {
        await start(t);
        await t.tap(find.text('Kategoriye koy').first);
        await settle(t);
        expect(find.text('Hangi kategoriye koyalım?'), findsOneWidget);
        expect(t.takeException(), isNull);

        // Yeni kategori adı diyaloğu da dar ekrana sığmalı.
        await t.tap(find.text('Yeni kategori…'));
        await settle(t);
        expect(find.text('Yeni kategori'), findsOneWidget);
        expect(t.takeException(), isNull);
      });

      testWidgets('çekmece ekranı tamamen kaplamaz, çöp kutusu sığar', (
        t,
      ) async {
        await start(t);
        await t.tap(find.byTooltip('Kategoriler'));
        await t.pumpAndSettle();
        final drawer = t.getSize(find.byType(Drawer)).width;
        expect(drawer, lessThanOrEqualTo(width - 56));

        // Bir dosyayı çöpe atıp çöp kutusunu aç.
        await t.tap(find.text('Çöp Kutusu'));
        await settle(t);
        expect(find.text('Çöp kutusu boş'), findsOneWidget);
        expect(t.takeException(), isNull);
      });

      testWidgets('çöpteki dosya satırı telefonda taşmaz', (t) async {
        await start(t);
        await t.tap(find.byTooltip('Dosya işlemleri').first);
        await t.pumpAndSettle();
        await t.tap(find.text('Çöp kutusuna at'));
        await settle(t);

        await t.tap(find.byTooltip('Kategoriler'));
        await t.pumpAndSettle();
        await t.tap(find.text('Çöp Kutusu'));
        await settle(t);
        expect(find.byTooltip('Geri koy'), findsOneWidget);
        expect(find.byTooltip('Kalıcı olarak sil'), findsOneWidget);
        expect(t.takeException(), isNull);
      });
    });
  }

  testWidgets('izin ekranı kısa yatay telefonda taşmaz, kaydırılır', (t) async {
    t.view.physicalSize = const Size(640, 320);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(home: PermissionPage(onRetry: () async {})));
    await t.pump();
    expect(t.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(find.textContaining('cihazındaki'), findsOneWidget);
  });

  testWidgets('izin ekranı dar dikey telefonda taşmaz', (t) async {
    t.view.physicalSize = const Size(360, 640);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(home: PermissionPage(onRetry: () async {})));
    await t.pump();
    expect(t.takeException(), isNull);
  });
}
