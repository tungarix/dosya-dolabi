import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'src/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SharedPreferences? prefs;
  try {
    prefs = await SharedPreferences.getInstance();
  } catch (_) {
    // Tercihler okunamazsa varsayılanlarla açılır; uygulama yine çalışır.
  }
  runApp(DolapApp(prefs: prefs));
}
