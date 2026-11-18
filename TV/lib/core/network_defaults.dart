/// Valores de red compartidos entre la descarga de la lista y la
/// reproducción de los streams.
///
/// Muchos CDN de IPTV rechazan clientes desconocidos (User-Agent vacío o
/// nombres de reproductores) y solo entregan el manifiesto HLS cuando la
/// petición parece provenir de un navegador real.
abstract final class NetworkDefaults {
  /// User-Agent de navegador de escritorio.
  static const String browserUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36';

  /// Tipos aceptados por manifiestos HLS/DASH y segmentos de video.
  static const String accept =
      'application/vnd.apple.mpegurl, application/x-mpegURL, '
      'application/dash+xml, video/*, */*';

  /// Construye las cabeceras de un stream respetando el `User-Agent` y el
  /// `Referer` declarados por el canal. Si el canal no declara agente, se
  /// usa el navegador genérico para evitar bloqueos de CDN.
  static Map<String, String> streamHeaders({
    String? userAgent,
    String? referrer,
  }) {
    final agent = (userAgent ?? '').trim();
    final ref = (referrer ?? '').trim();
    return <String, String>{
      'User-Agent': agent.isEmpty ? browserUserAgent : agent,
      if (ref.isNotEmpty) 'Referer': ref,
      'Accept': accept,
    };
  }
}
