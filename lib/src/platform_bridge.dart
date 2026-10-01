/// Platforma özgü işler: dolabın konumu, Gelen Kutusu klasörleri, depolama
/// izni ve dosyayı başka uygulamada açma.
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

const _channel = MethodChannel('com.aktenak.dosya_dolabi/files');

const _androidBase = '/storage/emulated/0';

/// Geliştirirken gerçek belgelerine dokunmamak için ortam değişkeniyle
/// değiştirilebilir.
String defaultRoot() {
  final env = Platform.environment['DOSYA_DOLABI_KOK'];
  if (env != null && env.isNotEmpty) return env;
  if (Platform.isAndroid) return '$_androidBase/Dosya Dolabı';
  final home =
      Platform.environment['USERPROFILE'] ??
      Platform.environment['HOME'] ??
      Directory.systemTemp.path;
  return p.join(home, 'Documents', 'Dosya Dolabı');
}

/// Yeni dosyaların genelde düştüğü yerler; olmayanlar sessizce atlanır.
List<String> defaultInboxDirs() {
  final env = Platform.environment['DOSYA_DOLABI_GELEN'];
  if (env != null && env.isNotEmpty) {
    return env.split(Platform.isWindows ? ';' : ':');
  }
  if (Platform.isAndroid) {
    final dirs = <String>[
      for (final d in const [
        'Download',
        'Documents',
        'Bluetooth',
        'Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Documents',
        'Android/media/com.whatsapp.w4b/WhatsApp Business/Media/WhatsApp Business Documents',
        'WhatsApp/Media/WhatsApp Documents',
      ])
        '$_androidBase/$d',
    ];
    // SD kart: /storage/XXXX-XXXX
    try {
      for (final e in Directory('/storage').listSync()) {
        final name = p.basename(e.path);
        if (e is Directory && name != 'emulated' && name != 'self') {
          dirs
            ..add('${e.path}/Download')
            ..add('${e.path}/Documents');
        }
      }
    } on FileSystemException {
      // /storage okunamıyorsa yalnızca dahili depolama taranır.
    }
    return dirs;
  }
  final home =
      Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? '';
  return home.isEmpty ? [] : [p.join(home, 'Downloads')];
}

/// Dosyalar uygulamasındaki gibi tüm klasörleri görebilmek için Android 11+
/// "Tüm dosyalara erişim" izni gerekir (10 ve eskisinde normal depolama izni).
class StorageAccess {
  static Future<bool> granted() async {
    if (!Platform.isAndroid) return true;
    try {
      return await _channel.invokeMethod<bool>('storageGranted') ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Android 11+: izin sayfasını açar. Sonuç beklenmez; kullanıcı uygulamaya
  /// dönünce izin yeniden denetlenir (bkz. `Gate`).
  static Future<void> request() => _call('requestStorage');

  static Future<void> openSettings() => _call('openSettings');

  static Future<void> _call(String method) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>(method);
    } on PlatformException {
      // Ayarlar açılamazsa kullanıcı elle açabilir; uygulama çökmesin.
    }
  }
}

/// Android'in kendi PdfRenderer/BitmapFactory'siyle küçük resim üretir (JPEG
/// baytları); başka platformda ya da çizilemeyen dosyada null.
Future<Uint8List?> nativePreview(String path, int px) async {
  if (!Platform.isAndroid) return null;
  try {
    return await _channel.invokeMethod<Uint8List>('preview', {
      'path': path,
      'px': px,
    });
  } on PlatformException {
    return null;
  } on MissingPluginException {
    return null;
  }
}

enum OpenResult { ok, noApp, failed }

Future<OpenResult> openFile(
  String path,
  String mime, {
  bool chooser = false,
}) async {
  try {
    if (Platform.isAndroid) {
      final r = await _channel.invokeMethod<String>('open', {
        'path': path,
        'mime': mime,
        'chooser': chooser,
      });
      return r == 'no_app' ? OpenResult.noApp : OpenResult.ok;
    }
    if (Platform.isWindows) {
      await Process.start('explorer.exe', [path]);
      return OpenResult.ok;
    }
    return OpenResult.failed;
  } on PlatformException {
    return OpenResult.failed;
  } on ProcessException {
    return OpenResult.failed;
  }
}
