import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../state.dart';
import '../text.dart';

/// Kullanıcıdan bir ad alır; iptalde null döner.
Future<String?> promptName(
  BuildContext context, {
  required String title,
  required String confirmText,
  String initial = '',
  String? hint,
  bool selectBaseName = false,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _NameDialog(
      title: title,
      confirmText: confirmText,
      initial: initial,
      hint: hint,
      selectBaseName: selectBaseName,
    ),
  );
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.title,
    required this.confirmText,
    required this.initial,
    required this.hint,
    required this.selectBaseName,
  });

  final String title;
  final String confirmText;
  final String initial;
  final String? hint;
  final bool selectBaseName;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _c;
  String? _error;

  @override
  void initState() {
    super.initState();
    _c = TextEditingController(text: widget.initial);
    // Dosya adını değiştirirken uzantı seçili gelmesin.
    final dot = widget.initial.lastIndexOf('.');
    _c.selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.selectBaseName && dot > 0
          ? dot
          : widget.initial.length,
    );
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _submit() {
    final err = validateName(_c.text);
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    Navigator.pop(context, _c.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 420,
        child: TextField(
          controller: _c,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText: widget.hint,
            errorText: _error,
            border: const OutlineInputBorder(),
          ),
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
          onSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Vazgeç'),
        ),
        FilledButton(onPressed: _submit, child: Text(widget.confirmText)),
      ],
    );
  }
}

Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmText,
  bool destructive = false,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error,
                  foregroundColor: Theme.of(ctx).colorScheme.onError,
                )
              : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmText),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// Kategori seçtirir. Seçilen kategorinin yolunu döner ('' = ana seviye,
/// yalnızca [allowRoot] açıkken); vazgeçilirse null.
/// [exclude] ve altındaki kategoriler listelenmez (kategori taşırken).
Future<String?> pickCategory(
  BuildContext context,
  DolapState state, {
  required String title,
  String? exclude,
  bool allowRoot = false,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _PickerDialog(
      state: state,
      title: title,
      exclude: exclude,
      allowRoot: allowRoot,
    ),
  );
}

class _PickerDialog extends StatefulWidget {
  const _PickerDialog({
    required this.state,
    required this.title,
    required this.exclude,
    required this.allowRoot,
  });

  final DolapState state;
  final String title;
  final String? exclude;
  final bool allowRoot;

  @override
  State<_PickerDialog> createState() => _PickerDialogState();
}

class _PickerDialogState extends State<_PickerDialog> {
  String _filter = '';

  Future<void> _create(String parent) async {
    final name = await promptName(
      context,
      title: parent.isEmpty
          ? 'Yeni kategori'
          : '"${parent.split('/').last}" içine yeni kategori',
      confirmText: 'Oluştur',
      hint: 'Örn. Matematik',
    );
    if (name == null || !mounted) return;
    final s = widget.state;
    final before = s.snap?.categories.map((c) => c.path).toSet() ?? {};
    final o = await s.createCategory(parent, name);
    if (!mounted) return;
    if (o.isError) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(o.message)));
      return;
    }
    final created = s.snap!.categories
        .map((c) => c.path)
        .toSet()
        .difference(before);
    // Yeni kategoriyi doğrudan seçilmiş say: kullanıcı zaten onu istiyordu.
    if (created.isNotEmpty) Navigator.pop(context, created.first);
  }

  @override
  Widget build(BuildContext context) {
    final snap = widget.state.snap!;
    final q = fold(_filter.trim());
    final all = snap.categories.where((c) {
      final ex = widget.exclude;
      if (ex != null && (c.path == ex || c.path.startsWith('$ex/'))) {
        return false;
      }
      return q.isEmpty || fold(c.path).contains(q);
    }).toList();
    final cs = Theme.of(context).colorScheme;

    return AlertDialog(
      title: Text(widget.title),
      contentPadding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
      content: SizedBox(
        width: 460,
        height: 460,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Kategori ara',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => _filter = v),
              ),
            ),
            const SizedBox(height: 8),
            if (widget.allowRoot && q.isEmpty)
              ListTile(
                leading: const Icon(Icons.home_outlined),
                title: const Text('Ana seviye'),
                onTap: () => Navigator.pop(context, ''),
              ),
            ListTile(
              leading: Icon(
                Icons.create_new_folder_outlined,
                color: cs.primary,
              ),
              title: Text(
                'Yeni kategori…',
                style: TextStyle(color: cs.primary),
              ),
              onTap: () => _create(''),
            ),
            const Divider(height: 1),
            Expanded(
              child: all.isEmpty
                  ? Center(
                      child: Text(
                        q.isEmpty
                            ? 'Henüz kategori yok'
                            : 'Eşleşen kategori yok',
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    )
                  : ListView.builder(
                      itemCount: all.length,
                      itemBuilder: (_, i) {
                        final c = all[i];
                        final depth = c.path.split('/').length - 1;
                        return ListTile(
                          contentPadding: EdgeInsets.only(
                            left: 24.0 + depth * 20,
                            right: 8,
                          ),
                          leading: const Icon(Icons.folder_outlined),
                          title: Text(c.name),
                          subtitle: depth > 0 && q.isNotEmpty
                              ? Text(c.parent.replaceAll('/', ' › '))
                              : null,
                          trailing: IconButton(
                            tooltip: 'Bunun içine yeni kategori',
                            icon: const Icon(Icons.add),
                            onPressed: () => _create(c.path),
                          ),
                          onTap: () => Navigator.pop(context, c.path),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Vazgeç'),
        ),
      ],
    );
  }
}

/// [Outcome]'u alt çubukta gösterir; geri alınabiliyorsa "GERİ AL" düğmesi koyar.
void showOutcome(BuildContext context, Outcome o) {
  final m = ScaffoldMessenger.of(context);
  final cs = Theme.of(context).colorScheme;
  m.hideCurrentSnackBar();
  m.showSnackBar(
    SnackBar(
      content: Text(
        o.message,
        style: o.isError ? TextStyle(color: cs.onErrorContainer) : null,
      ),
      backgroundColor: o.isError ? cs.errorContainer : null,
      behavior: SnackBarBehavior.floating,
      width: _snackWidth(context),
      duration: const Duration(seconds: 7),
      action: o.undo == null
          ? null
          : SnackBarAction(
              label: 'GERİ AL',
              onPressed: () async {
                await o.undo!();
                if (context.mounted) {
                  m.hideCurrentSnackBar();
                  m.showSnackBar(
                    SnackBar(
                      content: const Text('Geri alındı'),
                      behavior: SnackBarBehavior.floating,
                      width: _snackWidth(context),
                    ),
                  );
                }
              },
            ),
    ),
  );
}

double _snackWidth(BuildContext context) =>
    math.min(560, MediaQuery.sizeOf(context).width - 32);

/// İşlemi bekler, sonra (ekran hâlâ açıksa) sonucunu gösterir.
Future<void> runAndShow(BuildContext context, Future<Outcome> action) async {
  final o = await action;
  if (context.mounted) showOutcome(context, o);
}

String fileCountLabel(int n) => n == 1 ? '1 dosya' : '$n dosya';
