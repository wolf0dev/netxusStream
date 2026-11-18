import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/vod_resume.dart';

/// Persistencia de «Continuar viendo».
///
/// Guarda como máximo [maxEntries] títulos, ordenados por actividad reciente y
/// sin duplicados (una película/serie = una entrada, con su episodio actual).
class ResumeService {
  static const String storageKey = 'nexus.vodResume.v1';
  static const int maxEntries = 16;

  /// No guardamos los primeros segundos: al abrir un vídeo el reproductor
  /// emite posiciones transitorias que sobrescribirían el progreso real.
  static const Duration minPosition = Duration(seconds: 5);

  /// Margen para considerar un título terminado (los `.ts` del portal no
  /// siempre emiten el evento `completed`).
  static const Duration finishMargin = Duration(seconds: 15);

  /// Margen de seguridad al reanudar: no volver a abrir casi al final.
  static const Duration seekMargin = Duration(seconds: 3);

  /// Cadencia de guardado mientras se reproduce (el evento `position` llega
  /// varias veces por segundo).
  static const Duration saveInterval = Duration(seconds: 5);

  /// Serializa las escrituras: el reproductor guarda cada pocos segundos y dos
  /// `save` a la vez podrían leer el mismo estado y pisarse entre sí.
  Future<void> _tail = Future.value();

  Future<T> _enqueue<T>(Future<T> Function() action) {
    final next = _tail.then((_) => action());
    _tail = next.then((_) {}, onError: (_) {});
    return next;
  }

  Future<List<VodResume>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(storageKey) ?? const <String>[];
      final items = <VodResume>[];
      for (final entry in raw) {
        try {
          final parsed = VodResume.fromJson(
            jsonDecode(entry) as Map<String, dynamic>,
          );
          if (parsed != null) items.add(parsed);
        } catch (_) {
          // Una entrada corrupta no debe romper el resto del historial.
        }
      }
      return organize(items);
    } catch (_) {
      return const <VodResume>[];
    }
  }

  /// Añade o sustituye el progreso de un título y devuelve la lista resultante.
  Future<List<VodResume>> save(VodResume resume) => _enqueue(() async {
    final items = await load();
    final organized = organize(items, replacement: resume);
    await _write(organized);
    return organized;
  });

  /// Borra el progreso de un título (normalmente porque se terminó).
  Future<List<VodResume>> remove(String key) => _enqueue(() async {
    final items = await load();
    final organized = organize(items, removeKey: key);
    await _write(organized);
    return organized;
  });

  Future<void> _write(List<VodResume> items) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        storageKey,
        items.map((item) => jsonEncode(item.toJson())).toList(growable: false),
      );
    } catch (_) {
      // Silencioso: el progreso es una comodidad, no debe romper la app.
    }
  }

  /// Ordena por actividad, elimina duplicados y aplica el límite.
  ///
  /// Se expone para poder probar las reglas sin depender de SharedPreferences.
  static List<VodResume> organize(
    Iterable<VodResume> entries, {
    VodResume? replacement,
    String? removeKey,
  }) {
    final byKey = <String, VodResume>{};
    for (final entry in entries) {
      if (entry.key.isEmpty || entry.key == removeKey) continue;
      final previous = byKey[entry.key];
      if (previous == null || !entry.updatedAt.isBefore(previous.updatedAt)) {
        byKey[entry.key] = entry;
      }
    }
    if (replacement != null && replacement.key.isNotEmpty) {
      byKey[replacement.key] = replacement;
    }
    final items = byKey.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    if (items.length > maxEntries) {
      return items.sublist(0, maxEntries);
    }
    return List<VodResume>.unmodifiable(items);
  }

  /// `true` cuando merece la pena recordar esta posición.
  static bool shouldSave(Duration position, Duration duration) {
    if (position < minPosition) return false;
    return !isFinished(position, duration);
  }

  static bool isFinished(Duration position, Duration duration) {
    if (duration <= Duration.zero) return false;
    return position >= duration - finishMargin;
  }

  /// Posición desde la que se reanudará la reproducción.
  static Duration seekTarget(Duration position, Duration duration) {
    if (position <= Duration.zero) return Duration.zero;
    if (isFinished(position, duration)) return Duration.zero;
    if (duration <= Duration.zero) return position;
    final latest = duration - seekMargin;
    return position > latest ? latest : position;
  }
}
