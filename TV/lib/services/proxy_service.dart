import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'vpn_service.dart';

/// Proxy/VPN opcional que la app usa como «VPN».
///
/// En Android y Android TV usa OpenVPN nativo (Netxxus).
/// En Windows usa proxy HTTP tradicional.
///
/// Cuando está activo, el portal, el catálogo, las listas M3U y los posters
/// salen por el proxy/VPN; la reproducción lo hace a través de libmpv. Se guarda
/// en preferencias para recordar el estado entre arranques y viene desactivado
/// de fábrica.
class ProxySettings {
  ProxySettings._();

  static final ProxySettings instance = ProxySettings._();

  /// Proxy por defecto para Windows (se puede cambiar desde Ajustes).
  static const String defaultHost = '154.62.127.162';
  static const int defaultPort = 999;

  static const String _enabledKey = 'nexus.proxy.enabled.v1';
  static const String _hostKey = 'nexus.proxy.host.v1';
  static const String _portKey = 'nexus.proxy.port.v1';

  String _host = defaultHost;
  int _port = defaultPort;
  bool _enabled = false;

  String get host => _host;
  int get port => _port;
  bool get enabled => _enabled;
  String get authority => '$_host:$_port';

  /// Texto corto para la interfaz.
  String get label {
    if (kIsWeb) return 'No disponible';
    if (Platform.isAndroid) {
      return _enabled ? VpnService.instance.profileLabel : 'Desactivada';
    }
    return _enabled ? '$_host:$_port' : 'Desactivada';
  }

  /// Lee las preferencias y aplica el proxy/VPN a `dart:io` antes de crear
  /// cualquier cliente HTTP. Se llama una vez en `main()`.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(_enabledKey) ?? false;
      _host = prefs.getString(_hostKey) ?? defaultHost;
      _port = prefs.getInt(_portKey) ?? defaultPort;
    } catch (_) {
      // Sin preferencias: valores por defecto (desactivado).
    }

    // En Android, inicializar VPN; en Windows, aplicar proxy HTTP
    if (!kIsWeb && Platform.isAndroid) {
      await VpnService.instance.initVPN();
      if (_enabled) {
        // No se bloquea el arranque: Android puede tardar en mostrar el
        // diálogo de permiso y en levantar el túnel.
        unawaited(VpnService.instance.connect());
      }
    } else {
      _applyToDartIo();
    }
  }

  Future<void> setEnabled(bool value) async {
    if (_enabled == value) return;
    _enabled = value;

    // En Android, conectar/desconectar VPN; en Windows, aplicar proxy HTTP
    if (!kIsWeb && Platform.isAndroid) {
      if (value) {
        await VpnService.instance.connect();
      } else {
        await VpnService.instance.disconnect();
      }
    } else {
      _applyToDartIo();
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_enabledKey, value);
    } catch (_) {
      // El cambio sigue activo en memoria.
    }
  }

  Future<void> setEndpoint(String host, int port) async {
    // En Android, la VPN usa el perfil .ovpn, no endpoint configurable
    if (Platform.isAndroid) {
      debugPrint(
        '[Proxy] En Android se usa el perfil .ovpn, no endpoint configurable',
      );
      return;
    }

    final cleanHost = host.trim();
    if (cleanHost.isEmpty || port <= 0 || port > 65535) return;
    _host = cleanHost;
    _port = port;
    _applyToDartIo();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_hostKey, _host);
      await prefs.setInt(_portKey, _port);
    } catch (_) {
      // El cambio sigue activo en memoria.
    }
  }

  /// Cliente `http` que usa el proxy si está activo.
  /// En Android, la VPN maneja todo el tráfico, no se usa proxy HTTP.
  http.Client createClient() {
    final inner = HttpClient();
    if (_enabled && !Platform.isAndroid) {
      inner.findProxy = (uri) => 'PROXY $authority';
    }
    return IOClient(inner);
  }

  /// Comprueba el proxy/VPN (o la conexión directa si está desactivado) y
  /// devuelve la IP de salida, para verificar el país.
  Future<ProxyTestResult> test({
    Duration timeout = const Duration(seconds: 12),
  }) async {
    // En Android, la VPN maneja todo el tráfico, no se usa proxy HTTP
    if (!kIsWeb && Platform.isAndroid) {
      if (!_enabled) {
        return const ProxyTestResult(ok: true, ip: null, country: null);
      }
      final vpn = VpnService.instance;
      if (vpn.isConnected) {
        return ProxyTestResult(
          ok: true,
          ip: null,
          country: null,
          error: vpn.statusLabel,
        );
      }
      return ProxyTestResult(ok: false, error: vpn.statusLabel);
    }

    final client = createClient();
    try {
      final response = await client
          .get(Uri.parse('https://api.ipify.org?format=json'))
          .timeout(timeout);
      if (response.statusCode != 200) {
        return ProxyTestResult(ok: false, error: 'HTTP ${response.statusCode}');
      }
      final data = jsonDecode(response.body);
      final ip = data is Map ? '${data['ip'] ?? ''}'.trim() : '';
      String? country;
      if (ip.isNotEmpty) {
        try {
          final geo = await client
              .get(
                Uri.parse('http://ip-api.com/json/$ip?fields=status,country'),
              )
              .timeout(timeout);
          if (geo.statusCode == 200) {
            final info = jsonDecode(geo.body);
            if (info is Map && info['status'] == 'success') {
              final name = '${info['country'] ?? ''}'.trim();
              if (name.isNotEmpty) country = name;
            }
          }
        } catch (_) {
          // La geolocalización es opcional; la IP ya confirma la salida.
        }
      }
      return ProxyTestResult(
        ok: true,
        ip: ip.isEmpty ? null : ip,
        country: country,
      );
    } on TimeoutException {
      return const ProxyTestResult(
        ok: false,
        error: 'tiempo de espera agotado',
      );
    } catch (error) {
      return ProxyTestResult(ok: false, error: _describe(error));
    } finally {
      client.close();
    }
  }

  /// Hace que los `HttpClient` creados a partir de ahora (imágenes incluidas)
  /// usen el proxy.
  void _applyToDartIo() {
    HttpOverrides.global = _enabled ? _ProxyOverrides(authority) : null;
  }

  String _describe(Object error) {
    if (error is SocketException) {
      return error.osError?.message ?? error.message;
    }
    return '$error';
  }
}

class ProxyTestResult {
  const ProxyTestResult({required this.ok, this.ip, this.country, this.error});

  final bool ok;
  final String? ip;
  final String? country;
  final String? error;

  String get summary {
    if (!ok) return 'Sin respuesta · ${error ?? 'error desconocido'}';
    if (ip == null) return 'Conexión verificada';
    return country == null ? 'Salida: $ip' : 'Salida: $ip · $country';
  }
}

class _ProxyOverrides extends HttpOverrides {
  _ProxyOverrides(this.authority);

  final String authority;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.findProxy = (uri) => 'PROXY $authority';
    return client;
  }
}
