import '../wiwy/wiwy_vod.dart';

/// Progreso guardado de una película o de un capítulo de serie.
///
/// Solo se conserva una entrada por título: cuando el usuario ve otro
/// capítulo, se sustituye la anterior. Así «Continuar viendo» siempre retoma
/// la última sesión, incluido el episodio exacto.
class VodResume {
  const VodResume({
    required this.asset,
    required this.kind,
    required this.positionMs,
    required this.durationMs,
    required this.updatedAt,
    this.episode,
  });

  final WiwyVodAsset asset;
  final WiwyVodEpisode? episode;
  final WiwyVodKind kind;
  final int positionMs;
  final int durationMs;
  final DateTime updatedAt;

  /// Identidad del título (un registro por película/serie).
  String get key => asset.contentId;

  Duration get position => Duration(milliseconds: positionMs);
  Duration get duration => Duration(milliseconds: durationMs);

  /// Fracción reproducida, entre 0 y 1.
  double get progress {
    if (durationMs <= 0 || positionMs <= 0) return 0;
    final value = positionMs / durationMs;
    return value < 0 ? 0 : (value > 1 ? 1 : value);
  }

  VodResume copyWith({
    WiwyVodAsset? asset,
    WiwyVodKind? kind,
    int? positionMs,
    int? durationMs,
    DateTime? updatedAt,
    bool clearEpisode = false,
    WiwyVodEpisode? episode,
  }) {
    return VodResume(
      asset: asset ?? this.asset,
      episode: clearEpisode ? null : (episode ?? this.episode),
      kind: kind ?? this.kind,
      positionMs: positionMs ?? this.positionMs,
      durationMs: durationMs ?? this.durationMs,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'asset': asset.toResumeJson(),
    'episode': episode?.toResumeJson(),
    'kind': kind.name,
    'positionMs': positionMs,
    'durationMs': durationMs,
    'updatedAt': updatedAt.toIso8601String(),
  };

  static VodResume? fromJson(Map<String, dynamic> json) {
    final assetJson = json['asset'];
    if (assetJson is! Map) return null;
    final asset = WiwyVodAsset.fromResumeJson(assetJson.cast<String, dynamic>());
    if (asset == null) return null;

    final kindName = '${json['kind'] ?? ''}';
    final kind = WiwyVodKind.values.firstWhere(
      (value) => value.name == kindName,
      orElse: () => WiwyVodKind.movies,
    );

    WiwyVodEpisode? episode;
    final episodeJson = json['episode'];
    if (episodeJson is Map) {
      episode = WiwyVodEpisode.fromResumeJson(
        episodeJson.cast<String, dynamic>(),
      );
    }

    final updatedAt = DateTime.tryParse('${json['updatedAt'] ?? ''}') ??
        DateTime.fromMillisecondsSinceEpoch(0);
    return VodResume(
      asset: asset,
      episode: episode,
      kind: kind,
      positionMs: (json['positionMs'] as num?)?.toInt() ?? 0,
      durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
      updatedAt: updatedAt,
    );
  }
}
