import 'package:flutter/material.dart';

import '../file_kind.dart';
import '../library.dart';
import '../platform_bridge.dart';
import '../state.dart';
import 'dialogs.dart';

Future<void> openDoc(
  BuildContext context,
  DocFile f, {
  bool chooser = false,
}) async {
  final r = await openFile(f.path, mimeOf(f.path), chooser: chooser);
  if (!context.mounted) return;
  switch (r) {
    case OpenResult.ok:
      break;
    case OpenResult.noApp:
      showOutcome(
        context,
        Outcome(
          'Bu ${f.kind.label.toLowerCase()} dosyasını açabilen bir uygulama yok. '
          'Play Store\'dan bir ${f.kind == FileKind.slides ? 'sunum' : f.kind.label.toLowerCase()} '
          'uygulaması yükleyebilirsin.',
          isError: true,
        ),
      );
    case OpenResult.failed:
      showOutcome(context, const Outcome('Dosya açılamadı', isError: true));
  }
}

Future<void> moveDocs(
  BuildContext context,
  DolapState state,
  List<DocFile> files,
) async {
  final to = await pickCategory(
    context,
    state,
    title: files.length == 1
        ? 'Hangi kategoriye koyalım?'
        : '${files.length} dosya hangi kategoriye koyulsun?',
  );
  if (to == null || !context.mounted) return;
  runAndShow(context, state.moveFiles(files, to));
}

Future<void> trashDocs(
  BuildContext context,
  DolapState state,
  List<DocFile> files,
) async {
  runAndShow(context, state.trashFiles(files));
}

Future<void> renameDoc(
  BuildContext context,
  DolapState state,
  DocFile f,
) async {
  final name = await promptName(
    context,
    title: 'Dosyanın adını değiştir',
    confirmText: 'Kaydet',
    initial: f.name,
    selectBaseName: true,
  );
  if (name == null || !context.mounted) return;
  runAndShow(context, state.renameFile(f, name));
}
