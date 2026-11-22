import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../services/proxy_service.dart';

/// Configuración de reproducción orientada a IPTV en vivo.
///
/// Android y Windows usan un búfer amplio (15 s) para absorber microcortes;
/// Android TV usa un perfil más ligero (ver las constantes `tv*`) porque con
/// los valores de escritorio se queda atrapada en «Estabilizando señal…».
/// * El perfil de TV solo se aplica a Android TV real. La distribución puede
///   forzarse a «Android TV» en Windows desde Ajustes, pero mpv con `vo=gpu`
///   abre una ventana externa; en escritorio se mantiene `libmpv` incrustado.
/// * En Android TV se usa MediaCodec sobre Vulkan/OpenGL con degradación
///   automática a software solo si el dispositivo no entrega fotogramas.
/// * Reintentos silenciosos antes de avisar al usuario.
abstract final class PlayerTuning {
  /// Segundos de adelanto del demuxer/caché de red.
  static const int bufferSeconds = 15;

  /// Caché máxima del demuxer (192 MiB).
  static const int demuxerMaxBytes = 192 * 1024 * 1024;

  /// Caché de retroceso para cambios de canal (64 MiB).
  static const int demuxerBackBytes = 64 * 1024 * 1024;

  /// Búfer del socket de red (4 MiB).
  static const int streamBufferBytes = 4 * 1024 * 1024;

  /// Segundos antes de considerar que la red se cayó.
  static const int networkTimeoutSeconds = 12;

  // -- perfil Android TV -------------------------------------------------------
  //
  // Los televisores (especialmente los Leanback económicos) tienen menos RAM y
  // un decodificador más lento que un móvil o un PC. Los valores de escritorio
  // (15 s y 192 MiB de demuxer, HLS a la máxima calidad) los dejan en un bucle
  // permanente de «Estabilizando señal…». Este perfil prioriza arranque rápido
  // y consumo contenido frente a absorber microcortes.

  /// Segundos de caché en TV (la mitad que en el resto).
  static const int tvBufferSeconds = 6;

  /// Caché máxima del demuxer en TV (48 MiB).
  static const int tvDemuxerMaxBytes = 48 * 1024 * 1024;

  /// Caché de retroceso en TV (16 MiB).
  static const int tvDemuxerBackBytes = 16 * 1024 * 1024;

  /// Búfer del socket en TV (1 MiB).
  static const int tvStreamBufferBytes = 1024 * 1024;

  /// Reintentos silenciosos antes de notificar al usuario.
  static const int maxRetries = 3;

  /// Espera entre reintentos automáticos.
  static const Duration retryDelay = Duration(seconds: 3);

  /// `true` solo para Android TV real.
  ///
  /// [isTv] refleja la distribución elegida en Ajustes; en Windows se puede
  /// forzar a «Android TV» sin que el dispositivo lo sea. Aplicar el perfil de
  /// TV ahí cambiaría `vo` a `gpu` y mpv abriría una segunda ventana.
  static bool useTvProfile(bool isTv) =>
      isTv && !kIsWeb && Platform.isAndroid;

  /// Configuración del [Player]. El tamaño del búfer del demuxer se aplica
  /// también como `demuxer-max-bytes` dentro de libmpv.
  static PlayerConfiguration playerConfiguration({bool isTv = false}) {
    final tv = useTvProfile(isTv);
    return PlayerConfiguration(
      title: 'NexusStream',
      bufferSize: tv ? tvDemuxerMaxBytes : demuxerMaxBytes,
      logLevel: MPVLogLevel.error,
      protocolWhitelist: const [
        'udp',
        'rtp',
        'tcp',
        'tls',
        'data',
        'file',
        'http',
        'https',
        'crypto',
        'rtmp',
        'rtmps',
        'rtsp',
      ],
    );
  }

  /// Configuración del [VideoController].
  ///
  /// En móvil/Windows `auto-safe` usa MediaCodec o D3D11/DXVA cuando el códec
  /// es compatible y cae a software si no lo es. En Android TV usamos
  /// `mediacodec-copy` con `vo=gpu`: MediaCodec descodifica en el SoC y mpv
  /// elige Vulkan/OpenGL según el firmware del televisor.
  static VideoControllerConfiguration videoConfiguration({bool isTv = false}) {
    final tv = useTvProfile(isTv);
    return VideoControllerConfiguration(
      vo: tv ? 'gpu' : null,
      hwdec: tv ? 'mediacodec-copy' : 'auto-safe',
      enableHardwareAcceleration: true,
    );
  }

  /// Propiedades base que mejoran la estabilidad del streaming.
  ///
  /// Extraídas para poder comprobarlas sin crear un [Player] nativo.
  static Map<String, String> nativeProperties({required bool tv}) {
    final bufferSeconds = tv ? tvBufferSeconds : PlayerTuning.bufferSeconds;
    final maxBytes = tv ? tvDemuxerMaxBytes : demuxerMaxBytes;
    final backBytes = tv ? tvDemuxerBackBytes : demuxerBackBytes;
    final socketBytes = tv ? tvStreamBufferBytes : streamBufferBytes;

    final properties = <String, String>{
      // Caché en memoria (no en disco) para streams en vivo.
      'cache': 'yes',
      'cache-on-disk': 'no',
      'cache-secs': '$bufferSeconds',
      'demuxer-readahead-secs': '$bufferSeconds',
      'demuxer-max-bytes': '$maxBytes',
      'demuxer-max-back-bytes': '$backBytes',
      'stream-buffer-size': '$socketBytes',
      'network-timeout': '$networkTimeoutSeconds',
      // En TV NO pausamos al agotar el búfer: `paused-for-cache` mantiene
      // `playing=false` y el overlay de «Estabilizando…» se queda pegado.
      // Preferimos un microcorte ocasional a un canal congelado.
      'cache-pause': tv ? 'no' : 'yes',
      'cache-pause-wait': tv ? '1' : '3',
      // En TV no esperamos a llenar 15 s antes del primer fotograma: el
      // spinner desaparece en cuanto llegan los primeros datos.
      'cache-pause-initial': tv ? 'no' : 'yes',
      // En TV limitamos la variante HLS para no saturar decodificador y red.
      'hls-bitrate': tv ? '2500' : 'max',
    };

    if (tv) {
      properties.addAll({
        // Vulkan es la ruta más rápida en los SoC recientes; si el firmware no
        // lo soporta, mpv cae a OpenGL. Nunca forzamos software: MediaCodec es
        // la única forma de que un televisor económico mantenga 1080p sin lag.
        'gpu-api': 'vulkan',
        'gpu-context': 'android',
        'hwdec': 'mediacodec-copy',
        'vd-lavc-threads': '4',
        'video-sync': 'display-resample',
        'framedrop': 'vo',
      });
    }

    return properties;
  }

  static Future<void> _setProperty(
    NativePlayer platform,
    String key,
    String value,
  ) async {
    try {
      await platform.setProperty(key, value);
    } catch (error) {
      debugPrint('No se pudo aplicar $key=$value: $error');
    }
  }

  /// Aplica propiedades de libmpv que mejoran la estabilidad del streaming.
  ///
  /// Debe invocarse una sola vez por [Player], antes o durante la primera
  /// reproducción. En la web no hay backend nativo y se omite.
  static Future<void> applyNativeTuning(
    Player player, {
    bool isTv = false,
  }) async {
    final platform = player.platform;
    if (platform is! NativePlayer) return;

    final tv = useTvProfile(isTv);
    final properties = nativeProperties(tv: tv);

    for (final entry in properties.entries) {
      final fallback = switch (entry.key) {
        'gpu-api' => 'opengl',
        'hwdec' => 'auto-safe',
        _ => null,
      };
      if (fallback == null) {
        await _setProperty(platform, entry.key, entry.value);
        continue;
      }
      try {
        await platform.setProperty(entry.key, entry.value);
      } catch (error) {
        debugPrint('No se pudo aplicar ${entry.key}=${entry.value}: $error');
        await _setProperty(platform, entry.key, fallback);
      }
    }

    // VPN/proxy opcional: libmpv sale por el mismo proxy que el portal.
    if (ProxySettings.instance.enabled) {
      final proxy = 'http://${ProxySettings.instance.authority}';
      for (final key in const ['http-proxy', 'https-proxy']) {
        try {
          await platform.setProperty(key, proxy);
        } catch (error) {
          debugPrint('No se pudo aplicar $key: $error');
        }
      }
    }
  }
}
