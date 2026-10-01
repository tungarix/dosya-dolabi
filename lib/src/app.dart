import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'library.dart';
import 'platform_bridge.dart';
import 'state.dart';
import 'ui/home_page.dart';
import 'ui/permission_page.dart';

class DolapApp extends StatelessWidget {
  const DolapApp({super.key, this.prefs, this.library});

  final SharedPreferences? prefs;

  /// Testlerde geçici klasörle çalışan bir dolap vermek için.
  final Library? library;

  static const _seed = Color(0xFF2F5D8A);

  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness b) => ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: _seed, brightness: b),
          snackBarTheme: const SnackBarThemeData(showCloseIcon: false),
        );
    return MaterialApp(
      title: 'Dosya Dolabı',
      debugShowCheckedModeBanner: false,
      locale: const Locale('tr'),
      supportedLocales: const [Locale('tr')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      home: Gate(prefs: prefs, library: library),
    );
  }
}

/// İzin varsa dolabı, yoksa izin ekranını gösterir. Uygulamaya geri
/// dönülünce (ayarlardan ya da başka uygulamadan) izni ve dosyaları yeniler.
class Gate extends StatefulWidget {
  const Gate({super.key, this.prefs, this.library});

  final SharedPreferences? prefs;
  final Library? library;

  @override
  State<Gate> createState() => _GateState();
}

class _GateState extends State<Gate> with WidgetsBindingObserver {
  bool? _granted;
  DolapState? _state;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _state?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    final ok = await StorageAccess.granted();
    if (!mounted) return;
    if (ok) {
      final first = _state == null;
      _state ??= DolapState(
        widget.library ??
            Library(root: defaultRoot(), inboxDirs: defaultInboxDirs()),
        widget.prefs,
      );
      setState(() => _granted = true);
      await _state!.refresh(first: first);
    } else {
      setState(() => _granted = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return switch (_granted) {
      null => const Scaffold(body: Center(child: CircularProgressIndicator())),
      false => PermissionPage(onRetry: _check),
      true => HomePage(state: _state!),
    };
  }
}
