import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dosya_dolabi/src/app.dart';
import 'package:dosya_dolabi/src/library.dart';
import 'package:dosya_dolabi/src/preview.dart';
import 'package:dosya_dolabi/src/ui/file_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Geçerli, tek pikselli bir PNG.
final pngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

/// Dosya adına göre sabit önizleme veren sahte kaynak.
class FakeSource implements PreviewSource {
  final calls = <String>[];

  @override
  Future<Preview?> load(String path, {required int px}) async {
    calls.add('${p.basename(path)}@$px');
    return switch (p.basename(path)) {
      'Rapor.pdf' => Preview.image(Uint8List.fromList(pngBytes)),
      'Slayt.pptx' => const Preview.text('Hafta 3 — Dinamik\nNewton yasaları'),
      _ => null,
    };
  }
}

Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 40; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 15)),
    );
    await t.pump(const Duration(milliseconds: 60));
  }
  await t.pump(const Duration(seconds: 1));
}

bool isMemoryImage(Widget w) => w is Image && w.image is MemoryImage;

void main() {
  late Directory tmp;
  late Library lib;
  late FakeSource source;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('dolap_onizleme_');
    final inbox = p.join(tmp.path, 'Download')..replaceAll('', '');
    Directory(inbox).createSync();
    for (final n in ['Rapor.pdf', 'Slayt.pptx', 'Belge.docx']) {
      File(p.join(inbox, n)).writeAsStringSync('x');
    }
    lib = Library(root: p.join(tmp.path, 'Dolap'), inboxDirs: [inbox]);
    source = FakeSource();
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  Future<void> start(WidgetTester t, {double width = 1280}) async {
    t.view.physicalSize = Size(width, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(DolapApp(library: lib, previewSource: source));
    await settle(t);
    expect(t.takeException(), isNull);
  }

  testWidgets('kartlarda resim, metin ve tür simgesi önizlemesi', (t) async {
    await start(t);
    expect(find.byWidgetPredicate(isMemoryImage), findsOneWidget); // Rapor.pdf
    expect(find.text('Hafta 3 — Dinamik\nNewton yasaları'), findsOneWidget);
    expect(find.byType(KindTile), findsOneWidget); // Belge.docx: önizleme yok
    // Tür etiketleri önizlemenin üstünde.
    expect(find.text('PDF'), findsOneWidget);
    expect(find.text('Slayt'), findsOneWidget);
    expect(find.text('Belge'), findsOneWidget);
    // Üç dosya için tek seferde birer önizleme istendi.
    expect(source.calls.map((c) => c.split('@').first).toSet(), {
      'Rapor.pdf',
      'Slayt.pptx',
      'Belge.docx',
    });
  });

  testWidgets('aynı önizleme tekrar çizimde yeniden üretilmez', (t) async {
    await start(t);
    final first = source.calls.length;
    await t.tap(find.byTooltip('Liste görünümü'));
    await settle(t);
    await t.tap(find.byTooltip('Kart görünümü'));
    await settle(t);
    // Liste farklı boyut ister (rowPreviewPx), kart boyutu önbellekten gelir.
    final cardCalls = source.calls.where((c) => c.endsWith('@$cardPreviewPx'));
    expect(cardCalls.length, 3);
    expect(source.calls.length, greaterThanOrEqualTo(first));
  });

  testWidgets('liste görünümünde de önizleme var', (t) async {
    await start(t);
    await t.tap(find.byTooltip('Liste görünümü'));
    await settle(t);
    expect(find.byWidgetPredicate(isMemoryImage), findsOneWidget);
    expect(find.text('Hafta 3 — Dinamik\nNewton yasaları'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('"Önizle" büyük pencereyi açar; Kapat kapatır', (t) async {
    await start(t);
    await t.tap(find.byTooltip('Dosya işlemleri').at(1)); // Rapor.pdf
    await t.pumpAndSettle();
    await t.tap(find.text('Önizle'));
    await settle(t);

    expect(find.byType(Dialog), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.text('Rapor.pdf'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.byType(InteractiveViewer),
      ),
      findsOneWidget,
    );
    expect(find.text('Aç'), findsWidgets);
    // Büyük pencere büyük boyut ister.
    expect(source.calls, contains('Rapor.pdf@$largePreviewPx'));

    await t.tap(find.byTooltip('Kapat'));
    await t.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('metin önizlemesi büyük pencerede seçilebilir metindir', (
    t,
  ) async {
    await start(t);
    await t.tap(find.byTooltip('Dosya işlemleri').at(2)); // Slayt.pptx
    await t.pumpAndSettle();
    await t.tap(find.text('Önizle'));
    await settle(t);
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.byType(SelectableText),
      ),
      findsOneWidget,
    );
  });

  testWidgets('önizlemesi olmayan dosyada açıklama gösterilir', (t) async {
    await start(t);
    await t.tap(find.byTooltip('Dosya işlemleri').at(0)); // Belge.docx
    await t.pumpAndSettle();
    await t.tap(find.text('Önizle'));
    await settle(t);
    expect(find.text('Bu dosya için önizleme yok'), findsOneWidget);
  });

  for (final width in [360.0, 393.0]) {
    testWidgets(
      'telefon ${width.toInt()} dp: önizlemeli kart ve satır taşmaz',
      (t) async {
        await start(t, width: width);
        expect(find.byWidgetPredicate(isMemoryImage), findsOneWidget);
        await t.tap(find.byTooltip('Liste görünümü'));
        await settle(t);
        expect(find.byWidgetPredicate(isMemoryImage), findsOneWidget);
        expect(t.takeException(), isNull);

        await t.tap(find.byTooltip('Dosya işlemleri').first);
        await t.pumpAndSettle();
        await t.tap(find.text('Önizle'));
        await settle(t);
        expect(find.byType(Dialog), findsOneWidget);
        expect(t.takeException(), isNull);
      },
    );
  }
}
