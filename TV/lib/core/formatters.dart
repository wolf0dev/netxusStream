import 'package:flutter/material.dart';

/// Utilidades de formato en español.
String formatNumber(int value) {
  final digits = value.abs().toString();
  final buffer = StringBuffer();
  for (var index = 0; index < digits.length; index++) {
    if (index > 0 && (digits.length - index) % 3 == 0) {
      buffer.write('.');
    }
    buffer.write(digits[index]);
  }
  return '${value < 0 ? '-' : ''}$buffer';
}

String formatRelative(DateTime? date) {
  if (date == null) return 'Sin datos';
  final difference = DateTime.now().difference(date);
  if (difference.inSeconds < 60) return 'Hace un momento';
  if (difference.inMinutes < 60) {
    final minutes = difference.inMinutes;
    return 'Hace $minutes ${minutes == 1 ? 'minuto' : 'minutos'}';
  }
  if (difference.inHours < 24) {
    final hours = difference.inHours;
    return 'Hace $hours ${hours == 1 ? 'hora' : 'horas'}';
  }
  final days = difference.inDays;
  return 'Hace $days ${days == 1 ? 'día' : 'días'}';
}

String formatClock(DateTime? date) {
  if (date == null) return '--:--';
  final local = date.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

/// Tiempo que falta hasta una fecha futura ("en 3 h", "caducadas").
String formatUntil(DateTime? date) {
  if (date == null) return 'sin datos';
  final remaining = date.difference(DateTime.now());
  if (remaining.isNegative || remaining.inSeconds < 30) return 'caducadas';
  if (remaining.inMinutes < 60) return 'en ${remaining.inMinutes} min';
  if (remaining.inHours < 48) return 'en ${remaining.inHours} h';
  return 'en ${remaining.inDays} días';
}

/// Muestra un mensaje breve con el estilo de la app.
void showAppSnackBar(
  BuildContext context,
  String message, {
  IconData icon = Icons.info_outline_rounded,
  SnackBarAction? action,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, size: 18, color: Colors.white70),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
        action: action,
      ),
    );
}
