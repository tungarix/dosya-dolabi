import 'package:flutter/material.dart';

import '../file_kind.dart';
import '../library.dart';
import '../preview.dart';
import '../state.dart';
import '../text.dart';
import 'file_actions.dart';
import 'layout.dart';

/// Dosyanın önizlemesi: küçük resim, kısa metin ya da (önizleme yoksa) tür
/// simgesi. Önizleme arka planda üretilirken tür simgesi gösterilir.
class FilePreview extends StatefulWidget {
  const FilePreview({
    super.key,
    required this.cache,
    required this.file,
    this.px = cardPreviewPx,
    this.large = false,
    this.iconSize = 40,
  });

  final PreviewCache cache;
  final DocFile file;

  /// İstenen en geniş kenar (piksel); önbellek anahtarının parçasıdır.
  final int px;

  /// Büyük pencere: resim sığdırılıp yakınlaştırılabilir, metin kaydırılabilir,
  /// yüklenirken ilerleme çubuğu gösterilir.
  final bool large;
  final double iconSize;

  @override
  State<FilePreview> createState() => _FilePreviewState();
}

class _FilePreviewState extends State<FilePreview> {
  Preview? _preview;
  var _loading = false;
  var _key = '';

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(FilePreview old) {
    super.didUpdateWidget(old);
    if (PreviewCache.keyOf(widget.file, widget.px) != _key) _resolve();
  }

  void _resolve() {
    final key = PreviewCache.keyOf(widget.file, widget.px);
    _key = key;
    final hit = widget.cache.lookup(key);
    if (hit.cached) {
      _preview = hit.value;
      _loading = false;
      return;
    }
    _preview = null;
    _loading = true;
    widget.cache
        .load(
          widget.file,
          px: widget.px,
          // Kaydırılıp ekrandan çıkan (ya da başka dosyaya dönüşen) öğe için
          // sıradaki iş atlanır.
          wanted: () => mounted && _key == key,
        )
        .then((p) {
          if (!mounted || _key != key) return;
          setState(() {
            _preview = p;
            _loading = false;
          });
        });
  }

  @override
  Widget build(BuildContext context) {
    final p = _preview;
    final kind = widget.file.kind;
    final large = widget.large;
    final Widget child;
    if (p != null && p.isImage) {
      final image = Image.memory(
        p.bytes!,
        fit: large ? BoxFit.contain : BoxFit.cover,
        alignment: Alignment.topCenter,
        gaplessPlayback: true,
        width: double.infinity,
        height: large ? null : double.infinity,
        errorBuilder: (_, _, _) => KindTile(kind, iconSize: widget.iconSize),
      );
      child = KeyedSubtree(
        key: const ValueKey('resim'),
        child: large ? InteractiveViewer(maxScale: 5, child: image) : image,
      );
    } else if (p != null && p.text != null) {
      child = KeyedSubtree(
        key: const ValueKey('metin'),
        child: _PaperText(text: p.text!, large: large),
      );
    } else if (_loading && large) {
      child = const Center(
        key: ValueKey('yukleniyor'),
        child: CircularProgressIndicator(),
      );
    } else {
      child = KindTile(
        kind,
        key: const ValueKey('simge'),
        iconSize: widget.iconSize,
        label: large ? 'Bu dosya için önizleme yok' : null,
      );
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 150),
      child: child,
    );
  }
}

/// Önizlemesi olmayan dosya için tür simgesi (renkli zemin üzerinde).
class KindTile extends StatelessWidget {
  const KindTile(this.kind, {super.key, this.iconSize = 40, this.label});

  final FileKind kind;
  final double iconSize;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: kind.color.withValues(alpha: 0.10),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(kind.icon, size: iconSize, color: kind.color),
          if (label != null) ...[
            const SizedBox(height: 8),
            Text(
              label!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Belgenin ilk satırlarını "kâğıt" üzerinde gösterir. Kâğıt her temada beyaz
/// kalır (PDF küçük resimleri gibi), bu yüzden yazı rengi de sabittir.
class _PaperText extends StatelessWidget {
  const _PaperText({required this.text, required this.large});

  final String text;
  final bool large;

  static const _paper = Color(0xFFFBFBF8);
  static const _ink = Color(0xFF2B2B2B);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: _paper,
      // Küçükken alt boşluk, üstüne binen tür etiketinin metni örtmemesi için.
      padding: large
          ? const EdgeInsets.all(20)
          : const EdgeInsets.fromLTRB(10, 10, 10, 32),
      alignment: Alignment.topLeft,
      child: large
          ? SingleChildScrollView(
              child: SelectableText(
                text,
                style: const TextStyle(color: _ink, height: 1.4, fontSize: 15),
              ),
            )
          : Text(
              text,
              maxLines: 8,
              overflow: TextOverflow.fade,
              style: const TextStyle(color: _ink, height: 1.3, fontSize: 10.5),
            ),
    );
  }
}

/// Büyük önizleme penceresi: sayfa/slayt başı okunabilir boyutta, yakınlaştırılabilir.
Future<void> showFilePreviewDialog(
  BuildContext context,
  DolapState state,
  DocFile file,
) {
  return showDialog<void>(
    context: context,
    builder: (ctx) =>
        _PreviewDialog(state: state, file: file, ownerContext: context),
  );
}

class _PreviewDialog extends StatelessWidget {
  const _PreviewDialog({
    required this.state,
    required this.file,
    required this.ownerContext,
  });

  final DolapState state;
  final DocFile file;

  /// Dosyanın kartının bağlamı: kapanınca "Aç"/"Kategoriye koy" onunla çalışır.
  final BuildContext ownerContext;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final compact = isCompact(context);
    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 32,
        vertical: 24,
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 760,
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 4, 8),
              child: Row(
                children: [
                  Icon(file.kind.icon, color: file.kind.color),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          file.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          '${file.kind.label} · ${formatSize(file.size)} · '
                          '${formatDate(file.modified)}',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Kapat',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Flexible(
              child: Container(
                width: double.infinity,
                constraints: const BoxConstraints(minHeight: 220),
                color: cs.surfaceContainerHighest,
                child: FilePreview(
                  cache: state.previews,
                  file: file,
                  px: largePreviewPx,
                  large: true,
                  iconSize: 56,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              // Dar ekranda iki düğme yan yana sığmazsa alt alta dizilir.
              child: OverflowBar(
                alignment: MainAxisAlignment.end,
                spacing: 8,
                overflowSpacing: 4,
                overflowAlignment: OverflowBarAlignment.end,
                children: [
                  if (!file.inLibrary)
                    TextButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        if (ownerContext.mounted) {
                          moveDocs(ownerContext, state, [file]);
                        }
                      },
                      icon: const Icon(Icons.drive_file_move_rounded, size: 18),
                      label: const Text('Kategoriye koy'),
                    ),
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      if (ownerContext.mounted) openDoc(ownerContext, file);
                    },
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: const Text('Aç'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
