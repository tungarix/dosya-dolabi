import 'package:flutter/material.dart';

import '../platform_bridge.dart';

/// İlk açılışta: dosyaları taşıyabilmek için neden izin gerektiğini anlatır.
class PermissionPage extends StatelessWidget {
  const PermissionPage({super.key, required this.onRetry});

  /// İzin ekranından dönünce durumu yeniden denetler.
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          // Kısa/yatay telefon ekranında içerik taşmasın, kaydırılsın.
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.folder_special_rounded,
                      size: 64,
                      color: cs.primary,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Dosya Dolabı\'na hoş geldin',
                      style: text.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'PDF ve slayt dosyalarını kategorilere ayırabilmem için '
                      'cihazındaki dosyalara erişmem gerekiyor. Her kategori '
                      'cihazında gerçek bir klasör olur; dosyalarını başka '
                      'uygulamalarda da bu klasörlerde görürsün.',
                      style: text.bodyLarge,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Bir sonraki ekranda "Tüm dosyalara erişime izin ver" '
                      'anahtarını aç, sonra geri dön. Dosyaların cihazdan '
                      'dışarı gönderilmez.',
                      style: text.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 28),
                    FilledButton.icon(
                      onPressed: () async {
                        await StorageAccess.request();
                        await onRetry();
                      },
                      icon: const Icon(Icons.lock_open_rounded),
                      label: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 10),
                        child: Text('İzin ver'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: StorageAccess.openSettings,
                      child: const Text('Uygulama ayarlarını aç'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
