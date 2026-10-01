import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

/// Kullanıcının göreceği dosya türü grupları.
enum FileKind {
  pdf('PDF', Icons.picture_as_pdf_rounded, Color(0xFFD93A2B)),
  slides('Slayt', Icons.slideshow_rounded, Color(0xFFE8710A)),
  document('Belge', Icons.description_rounded, Color(0xFF2B6CD9)),
  sheet('Tablo', Icons.table_chart_rounded, Color(0xFF1E8E3E)),
  image('Görsel', Icons.image_rounded, Color(0xFF8E44AD)),
  archive('Arşiv', Icons.folder_zip_rounded, Color(0xFF6D6D6D)),
  other('Diğer', Icons.insert_drive_file_rounded, Color(0xFF607D8B));

  const FileKind(this.label, this.icon, this.color);

  final String label;
  final IconData icon;
  final Color color;

  static FileKind of(String path) => _kinds[extensionOf(path)] ?? other;
}

/// Noktasız, küçük harfli uzantı ("pdf"); uzantı yoksa boş.
String extensionOf(String path) {
  final e = p.extension(path);
  return e.isEmpty ? '' : e.substring(1).toLowerCase();
}

const _kinds = {
  'pdf': FileKind.pdf,
  'ppt': FileKind.slides, 'pptx': FileKind.slides, 'pps': FileKind.slides, //
  'ppsx': FileKind.slides, 'pptm': FileKind.slides, 'odp': FileKind.slides,
  'key': FileKind.slides,
  'doc': FileKind.document, 'docx': FileKind.document, 'odt': FileKind.document,
  'rtf': FileKind.document, 'txt': FileKind.document, 'md': FileKind.document,
  'epub': FileKind.document, 'pages': FileKind.document,
  'xls': FileKind.sheet, 'xlsx': FileKind.sheet, 'ods': FileKind.sheet,
  'csv': FileKind.sheet, 'numbers': FileKind.sheet,
  'jpg': FileKind.image, 'jpeg': FileKind.image, 'png': FileKind.image,
  'gif': FileKind.image, 'webp': FileKind.image, 'heic': FileKind.image,
  'bmp': FileKind.image,
  'zip': FileKind.archive, 'rar': FileKind.archive, '7z': FileKind.archive,
};

const _mimes = {
  'pdf': 'application/pdf',
  'ppt': 'application/vnd.ms-powerpoint',
  'pps': 'application/vnd.ms-powerpoint',
  'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  'ppsx':
      'application/vnd.openxmlformats-officedocument.presentationml.slideshow',
  'pptm': 'application/vnd.ms-powerpoint.presentation.macroEnabled.12',
  'odp': 'application/vnd.oasis.opendocument.presentation',
  'key': 'application/vnd.apple.keynote',
  'doc': 'application/msword',
  'docx':
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'odt': 'application/vnd.oasis.opendocument.text',
  'rtf': 'application/rtf',
  'txt': 'text/plain',
  'md': 'text/markdown',
  'epub': 'application/epub+zip',
  'xls': 'application/vnd.ms-excel',
  'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'ods': 'application/vnd.oasis.opendocument.spreadsheet',
  'csv': 'text/csv',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'gif': 'image/gif',
  'webp': 'image/webp',
  'heic': 'image/heic',
  'bmp': 'image/bmp',
  'zip': 'application/zip',
  'rar': 'application/vnd.rar',
  '7z': 'application/x-7z-compressed',
  'mp4': 'video/mp4',
  'mp3': 'audio/mpeg',
};

/// Android'e "bunu hangi uygulama açar" diye sorarken kullanılan MIME türü.
String mimeOf(String path) => _mimes[extensionOf(path)] ?? '*/*';
