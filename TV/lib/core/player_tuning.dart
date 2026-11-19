import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../services/proxy_service.dart';

/// Configuración de reproducción orientada a IPTV en vivo.
///
/// Android y Windows usan un búfer amplio (15 s) para absorber microcortes;
/// Android TV usa un perfil más ligero (ver las constantes `tv*`) porque con
/// los valores de escritorio se queda atrapada en «Estabilizando señal…».
/// * Decodificación por hardware (`hwdec` + `enableHardwareAcceleration`).
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

  /// Configuración del [Player]. El tamaño del búfer del demuxer se aplica
  /// también como `demuxer-max-bytes` dentro de libmpv.
  static PlayerConfiguration playerConfiguration({bool isTv = false}) {
    return PlayerConfiguration(
      title: 'NexusStream',
      bufferSize: isTv ? tvDemuxerMaxBytes : demuxerMaxBytes,
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

  /// Configuración del [VideoController] con aceleración por hardware.
  ///
  /// `auto-safe` usa MediaCodec en Android y D3D11/DXVA en Windows cuando el
  /// códec es compatible; si no lo es, cae a decodificación por software en
  /// lugar de mostrar una pantalla negra.
  static VideoControllerConfiguration videoConfiguration() {
    return const VideoControllerConfiguration(
      hwdec: 'auto-safe',
      enableHardwareAcceleration: true,
    );
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

    final bufferSeconds = isTv ? tvBufferSeconds : PlayerTuning.bufferSeconds;
    final maxBytes = isTv ? tvDemuxerMaxBytes : demuxerMaxBytes;
    final backBytes = isTv ? tvDemuxerBackBytes : demuxerBackBytes;
    final socketBytes = isTv ? tvStreamBufferBytes : streamBufferBytes;

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
      // Pausa la reproducción mientras se rellena el búfer, en lugar de
      // congelar la imagen con audio cortado.
      'cache-pause': 'yes',
      'cache-pause-wait': isTv ? '1' : '3',
      // En TV no esperamos a llenar 15 s antes del primer fotograma: el
      // spinner desaparece en cuanto llegan los primeros datos.
      'cache-pause-initial': isTv ? 'no' : 'yes',
      // En TV limitamos la variante HLS para no saturar decodificador y red.
      'hls-bitrate': isTv ? '2500' : 'max',
    };

    for (final entry in properties.entries) {
      try {
        await platform.setProperty(entry.key, entry.value);
      } catch (error) {
        debugPrint('No se pudo aplicar ${entry.key}: $error');
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
