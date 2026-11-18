import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:openvpn_flutter/openvpn_flutter.dart';

/// Estado resumido de la VPN para la interfaz.
enum VpnPhase { unavailable, idle, connecting, connected, denied, failed }

/// Perfil `.ovpn` incluido en los assets de la app.
class VpnProfile {
  const VpnProfile({required this.asset, required this.name});

  final String asset;
  final String name;
}

/// Gestor de la VPN nativa para Android y Android TV usando OpenVPN.
///
/// Carga los perfiles `.ovpn` desde los assets y usa el servicio VPN del
/// sistema. No aplica en Windows/iOS: allí se usa el proxy HTTP de
/// `ProxySettings`.
///
/// El perfil principal es Netxxus (`config.ovpn`). Si el servidor no responde,
/// se intenta automáticamente el perfil de respaldo (`vpnok.ovpn`).
class VpnService extends ChangeNotifier {
  VpnService._();

  static final VpnService instance = VpnService._();

  /// Perfiles en orden de preferencia.
  static const List<VpnProfile> profiles = [
    VpnProfile(asset: 'assets/vpn/config.ovpn', name: 'Netxxus VPN'),
    VpnProfile(asset: 'assets/vpn/vpnok.ovpn', name: 'Netxxus VPN (respaldo)'),
  ];

  /// Tiempo máximo que se espera a que un perfil complete la conexión.
  static const Duration _connectTimeout = Duration(seconds: 22);

  OpenVPN? _engine;
  bool _initialized = false;
  VPNStage _stage = VPNStage.disconnected;
  VpnProfile? _activeProfile;
  VpnProfile? _attemptingProfile;
  String? _lastError;
  bool _connecting = false;
  bool _cancelRequested = false;
  Future<bool>? _pendingConnect;

  bool get isInitialized => _initialized;

  bool get isConnected => _stage.isConnected;

  bool get isConnecting => _connecting || _stage.isConnecting;

  VpnProfile? get activeProfile => _activeProfile;

  String? get lastError => _lastError;

  /// Perfil en uso (o el que se está intentando conectar).
  String get profileLabel =>
      (_activeProfile ?? _attemptingProfile)?.name ?? profiles.first.name;

  /// Verifica si el soporte de VPN está disponible (solo Android).
  bool get isAvailable => !kIsWeb && Platform.isAndroid;

  VpnPhase get phase {
    if (!isAvailable) return VpnPhase.unavailable;
    if (isConnected) return VpnPhase.connected;
    if (_stage == VPNStage.denied) return VpnPhase.denied;
    if (_stage == VPNStage.error || _stage == VPNStage.auth_failed) {
      return VpnPhase.failed;
    }
    if (isConnecting) return VpnPhase.connecting;
    return VpnPhase.idle;
  }

  /// Texto listo para mostrar en Ajustes.
  String get statusLabel {
    switch (phase) {
      case VpnPhase.unavailable:
        return 'Solo disponible en Android y Android TV';
      case VpnPhase.connected:
        return 'Conectado · $profileLabel';
      case VpnPhase.connecting:
        return 'Conectando con $profileLabel…';
      case VpnPhase.denied:
        return 'Permiso de VPN denegado. Actívala de nuevo y acepta el '
            'aviso de Android.';
      case VpnPhase.failed:
        return _lastError ?? 'No se pudo conectar';
      case VpnPhase.idle:
        return 'Desconectada';
    }
  }

  /// Inicializa el motor de OpenVPN una sola vez.
  Future<void> initVPN() async {
    if (!isAvailable) {
      debugPrint('[VPN] No disponible en esta plataforma');
      return;
    }
    if (_initialized) return;

    final engine = OpenVPN(
      onVpnStageChanged: (stage, rawStage) {
        debugPrint('[VPN] Etapa: $stage ($rawStage)');
        _stage = stage;
        if (stage.isConnected) {
          _lastError = null;
        } else if (stage == VPNStage.denied) {
          _lastError = 'Permiso de VPN denegado';
        } else if (stage == VPNStage.error) {
          _lastError ??= 'La conexión se interrumpió';
        }
        notifyListeners();
      },
    );

    try {
      await engine.initialize(
        localizedDescription: 'NexusStream VPN',
        disconnectOnTaskRemoved: false,
        lastStage: (stage) {
          _stage = stage;
          notifyListeners();
        },
      );
      _engine = engine;
      _initialized = true;
      debugPrint('[VPN] Motor inicializado');
    } on MissingPluginException {
      debugPrint('[VPN] El plugin nativo no está disponible');
      _stage = VPNStage.error;
      _lastError = 'El motor de VPN no está disponible en esta compilación.';
      notifyListeners();
    } on PlatformException catch (error) {
      debugPrint('[VPN] Error al inicializar: ${error.code} ${error.message}');
      _stage = VPNStage.error;
      _lastError = _describe(error);
      notifyListeners();
    }
  }

  /// Conecta la VPN. Reutiliza la conexión en curso si ya hay una.
  ///
  /// Devuelve `true` cuando el túnel está arriba. Prueba primero Netxxus y,
  /// si falla, el perfil de respaldo.
  Future<bool> connect() {
    final pending = _pendingConnect;
    if (pending != null) return pending;

    final future = _connect();
    _pendingConnect = future;
    return future.whenComplete(() {
      if (identical(_pendingConnect, future)) _pendingConnect = null;
    });
  }

  Future<bool> _connect() async {
    _cancelRequested = false;
    if (!isAvailable) return false;

    await initVPN();
    final engine = _engine;
    if (!_initialized || engine == null) return false;
    if (_stage.isConnected) return true;

    _connecting = true;
    _lastError = null;
    notifyListeners();

    try {
      for (final profile in profiles) {
        if (_cancelRequested) return false;
        final connected = await _tryProfile(engine, profile);
        if (_cancelRequested) {
          if (connected) await engine.disconnect();
          return false;
        }
        if (connected) return true;
        // Si el usuario rechazó el permiso, no tiene sentido probar otro
        // servidor: Android no volverá a mostrar el diálogo.
        if (_stage == VPNStage.denied) return false;
      }
      return false;
    } finally {
      _connecting = false;
      _attemptingProfile = null;
      notifyListeners();
    }
  }

  Future<bool> _tryProfile(OpenVPN engine, VpnProfile profile) async {
    _attemptingProfile = profile;
    notifyListeners();

    final completer = Completer<VPNStage>();
    final subscription = engine.stageStream.listen((stage) {
      if ((stage.isConnected || stage.isDisconnected) &&
          !completer.isCompleted) {
        completer.complete(stage);
      }
    });

    try {
      final config = await rootBundle.loadString(profile.asset);
      final started = await engine.connect(
        config,
        profile.name,
        certIsRequired: true,
      );
      if (!started) {
        _stage = VPNStage.denied;
        _lastError = 'Permiso de VPN denegado';
        debugPrint('[VPN] Permiso denegado por el usuario');
        return false;
      }

      final stage = await completer.future.timeout(
        _connectTimeout,
        onTimeout: () => engine.currentStage,
      );

      if (stage.isConnected && !_cancelRequested) {
        _stage = stage;
        _activeProfile = profile;
        _lastError = null;
        debugPrint('[VPN] Conectado con ${profile.name}');
        return true;
      }

      _lastError = await _describeFailure(engine, profile);
      debugPrint('[VPN] Falló ${profile.name}: $_lastError');
    } on PlatformException catch (error) {
      _lastError = _describe(error);
      debugPrint('[VPN] Error con ${profile.name}: ${error.code}');
    } catch (error) {
      _lastError = _describe(error);
      debugPrint('[VPN] Error con ${profile.name}: $error');
    } finally {
      if (!completer.isCompleted) completer.complete(_stage);
      await subscription.cancel();
    }

    // Deja limpio el intento fallido antes de probar el siguiente perfil.
    try {
      await engine.disconnect();
    } catch (_) {
      // El motor ya puede estar detenido.
    }
    return false;
  }

  Future<String> _describeFailure(OpenVPN engine, VpnProfile profile) async {
    try {
      final reason = (await engine.lastError())?.trim();
      if (reason != null && reason.isNotEmpty) return reason;
    } catch (_) {
      // Sin detalle del motor; se usa la etapa actual.
    }

    switch (_stage) {
      case VPNStage.auth_failed:
        return 'El servidor rechazó las credenciales de ${profile.name}.';
      case VPNStage.denied:
        return 'Permiso de VPN denegado.';
      case VPNStage.no_network:
        return 'Sin conexión de red.';
      case VPNStage.paused:
        return 'Conexión pausada por el sistema.';
      case VPNStage.error:
        return 'El túnel se cerró con ${profile.name}.';
      default:
        return 'Tiempo de espera agotado con ${profile.name}.';
    }
  }

  String _describe(Object error) {
    if (error is PlatformException) {
      final message = (error.message ?? '').trim();
      final code = error.code.toLowerCase();
      if (code == 'native_libraries_not_extracted' ||
          message.toLowerCase().contains('native librar')) {
        return 'OpenVPN necesita extraer sus librerías nativas: '
            'recompila la app con useLegacyPackaging activado.';
      }
      if (message.isNotEmpty) return message;
      return error.code;
    }
    return error.toString();
  }

  /// Detiene la VPN.
  Future<void> disconnect() async {
    if (!isAvailable) return;

    _cancelRequested = true;
    _connecting = false;
    try {
      await _engine?.disconnect();
    } catch (error) {
      debugPrint('[VPN] Error al desconectar: $error');
    }
    _stage = VPNStage.disconnected;
    _activeProfile = null;
    _attemptingProfile = null;
    notifyListeners();
    debugPrint('[VPN] Desconectada');
  }
}
