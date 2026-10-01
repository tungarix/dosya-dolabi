/// Türkçe metin yardımcıları: arama için harf katlama, doğal sıralama,
/// boyut ve tarih biçimleme.
library;

const _foldMap = {
  'İ': 'i', 'I': 'i', 'ı': 'i', //
  'Ş': 's', 'ş': 's',
  'Ğ': 'g', 'ğ': 'g',
  'Ü': 'u', 'ü': 'u',
  'Ö': 'o', 'ö': 'o',
  'Ç': 'c', 'ç': 'c',
};

/// "Sınav" ile "sinav" aynı sonucu versin diye harfleri sadeleştirir.
String fold(String s) {
  final b = StringBuffer();
  for (final ch in s.split('')) {
    b.write(_foldMap[ch] ?? ch.toLowerCase());
  }
  return b.toString();
}

final _chunk = RegExp(r'\d+|\D+');

/// "Hafta 2" "Hafta 10"dan önce gelsin diye sayıları sayı olarak karşılaştırır.
int naturalCompare(String a, String b) {
  final ca = _chunk.allMatches(fold(a)).map((m) => m[0]!).toList();
  final cb = _chunk.allMatches(fold(b)).map((m) => m[0]!).toList();
  for (var i = 0; i < ca.length && i < cb.length; i++) {
    final x = ca[i], y = cb[i];
    final nx = int.tryParse(x), ny = int.tryParse(y);
    final c = (nx != null && ny != null)
        ? (nx != ny ? nx.compareTo(ny) : x.length.compareTo(y.length))
        : x.compareTo(y);
    if (c != 0) return c;
  }
  return ca.length.compareTo(cb.length);
}

String formatSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB'];
  var v = bytes / 1024;
  var u = 0;
  while (v >= 1024 && u < units.length - 1) {
    v /= 1024;
    u++;
  }
  final s = v >= 100 ? v.round().toString() : v.toStringAsFixed(1);
  return '${s.replaceAll('.', ',')} ${units[u]}';
}

const _months = [
  'Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz', //
  'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara',
];

String _two(int n) => n.toString().padLeft(2, '0');

/// "Bugün 14:05", "Dün 09:12", "3 Eyl", "3 Eyl 2025".
String formatDate(DateTime d, [DateTime? now]) {
  now ??= DateTime.now();
  final day = DateTime(d.year, d.month, d.day);
  final today = DateTime(now.year, now.month, now.day);
  final diff = today.difference(day).inDays;
  final time = '${_two(d.hour)}:${_two(d.minute)}';
  if (diff == 0) return 'Bugün $time';
  if (diff == 1) return 'Dün $time';
  final base = '${d.day} ${_months[d.month - 1]}';
  return d.year == now.year ? base : '$base ${d.year}';
}

/// Dosya/kategori adı için hata mesajı döndürür; ad geçerliyse null.
String? validateName(String name) {
  final n = name.trim();
  if (n.isEmpty) return 'Bir ad yaz';
  if (n == '.' || n == '..') return 'Bu ad kullanılamaz';
  if (n.startsWith('.')) return 'Ad nokta ile başlayamaz';
  if (RegExp(r'[\\/:*?"<>|]').hasMatch(n)) {
    return r'Şu işaretler kullanılamaz: \ / : * ? " < > |';
  }
  if (n.length > 120) return 'Ad çok uzun';
  return null;
}
