import 'package:flutter/widgets.dart';

/// Bu genişliğin altı "telefon" sayılır: üst çubuk, seçim çubuğu ve satırlar
/// yazılı düğmeler yerine simgeli düğmelerle yerleşir.
const compactWidth = 600.0;

/// Kalıcı kenar çubuğu için gereken en dar genişlik (altında çekmece kullanılır).
const wideWidth = 900.0;

bool isCompact(BuildContext context) =>
    MediaQuery.sizeOf(context).width < compactWidth;
